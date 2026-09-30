#include <Arduino.h>

#include "log.h"
#include "ble_service.h"
#include "calibration.h"
#include "command_router.h"
#include "config.h"
#include "safety.h"
#include "servo_axis.h"

static Calibration    g_calib;
static ServoAxis     g_axis;
static SafetyManager g_safety;
static CommandRouter g_router(g_axis, g_safety, g_calib);

// Si se cae la conexion BLE a mitad de un movimiento, el servo tiene que
// volver a reposo igual. Es la misma politica que el watchdog: si nadie esta
// mirando, el servo no queda tocando la manija.
static void onBleDisconnect(void* /*user*/) {
    g_axis.abort();
    // OJO: aqui NO se marca fin de movimiento. abort() es asincrono: el servo
    // tardara lo que tarden los milisegundos del regreso en reposo. Marcarlo
    // como terminado aqui dejaria el watchdog desarmado mientras el brazo
    // sigue fuera de la posicion de reposo, que es justo el estado que el
    // watchdog existe para vigilar. El 'done' lo emite tick() cuando el
    // retorno termina, y ahi si se desarma.
    PV_LOG_PRINTLN("[main] BLE desconectado durante movimiento: retorno a reposo");
}

void setup() {
    Serial.begin(115200);
    const uint32_t t0 = millis();
    while (!Serial && millis() - t0 < 2000) { /* espera al monitor, max 2 s */ }

    PV_LOG_PRINTLN();
    PV_LOG_PRINTLN("==============================================");
    PV_LOG_PRINTLN("  PuertaVoz - Asistente domotico por voz");
    PV_LOG_PRINTF("  fw %s   DRY_RUN=%d\n", FW_VERSION, DRY_RUN);
    PV_LOG_PRINTLN("==============================================");

    // 1. Calibracion: define hasta donde puede llegar el brazo. Sin esto el
    //    servo se queda sin permiso para moverse.
    g_calib.begin();
    g_axis.begin();
    g_axis.setConfig(g_calib.load());

    // 2. Guardas.
    g_safety.reset();

    // 3. Anuncio BLE.
    BleService::begin(g_router, &onBleDisconnect, nullptr);

    if (!g_axis.config().calibrated) {
        PV_LOG_PRINTLN("[main] SIN CALIBRAR: open sera rechazado hasta calibrar");
    }
    PV_LOG_PRINTLN("[main] listo");
}

void loop() {
    g_router.pollWatchdog();
    g_router.tick();
    // El resto de la logica es reactiva: todo pasa por handleRaw() desde el
    // callback de escritura BLE, asi que loop() no hace trabajo periodico.
    delay(5);
}
