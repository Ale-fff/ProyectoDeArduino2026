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

// Si se cae la conexion BLE, el servo se queda donde esta.
//
// Antes esto llamaba a g_axis.abort() y devolvia el pestillo a reposo. Con el
// contrato actual eso ya no es correcto: si la persona abrio la puerta y solo
// se le cae el movil o se cierra la app, la puerta NO debe cerrarse sola a los
// 30 s. Cerrar es una decision suya, y para eso estan `close` y `estop`.
//
// Lo que no se hace aqui es NADA. El servo ya fue comandado a su destino en
// beginMove(), asi que sigue su curso fisicamente aunque el BLE se caiga, y
// el bookkeeping sigue avanzando en ServoAxis::task() desde loop(). Lo unico
// que se pierde es la confirmacion: el 'done' se emite igualmente, pero sin
// cliente al que notificar.
static void onBleDisconnect(void* /*user*/) {
    PV_LOG_PRINTLN("[main] BLE desconectado: el servo se queda donde esta");
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
    // Reanuda el anuncio BLE si el cliente se desconectó. Debe correr desde
    // loop(), no desde el callback: allí compite con el stack y falla.
    BleService::service();
    g_router.pollWatchdog();
    g_router.tick();
    // El resto de la logica es reactiva: todo pasa por handleRaw() desde el
    // callback de escritura BLE, asi que loop() no hace trabajo periodico.
    delay(5);
}
