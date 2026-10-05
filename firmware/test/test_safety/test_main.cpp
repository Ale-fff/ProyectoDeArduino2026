// Pruebas de la logica de servo_axis y safety, con reloj simulado.
// No requieren ESP32, MG995 ni fuente: se ejecutan en la PC.
//
//   pio test -e native
//
// Para compilar solo en nativo, estos modulos no deben depender de nada de
// Arduino fuera de timebase.h.

#include <unity.h>

#include "protocol.h"
#include "safety.h"
#include "servo_axis.h"
#include "timebase.h"

namespace {

ServoConfig testConfig() {
    ServoConfig c;
    c.minUs   = 1000;
    c.maxUs   = 2000;
    c.restUs  = 1500;
    c.pressUs = 1800;
    c.holdMs  = 1500;
    c.calibrated = true;
    return c;
}

// Recorre el reloj hasta que el eje termine el movimiento en curso, o hasta el
// limite dado.
//
// Usa moving() y NO busy() a proposito: desde que `open` deja el servo en
// HOLDING, busy() se queda en true indefinidamente (es lo correcto: el pestillo
// sigue presionado) y este helper no terminaria nunca.
void runUntilIdle(ServoAxis& axis, uint32_t maxMs = 12000) {
    uint32_t elapsed = 0;
    while (axis.moving() && elapsed < maxMs) {
        tb_advance(10);
        axis.task();
        elapsed += 10;
    }
    TEST_ASSERT_TRUE_MESSAGE(!axis.moving(), "el servo se quedo moviendo");
}

}  // namespace

// Unity declara setUp() y tearDown() como extern y las llama por su nombre.
// Por eso NO pueden vivir en el namespace anonimo de arriba: ahi tendrian
// enlace interno, Unity no las encontraria, y setUp() no se ejecutaria nunca.
// Con el reloj simulado sin resetear entre tests, el tiempo se acumula y los
// numeros de duracion salen de otro mundo.
void setUp(void) {
    tb_reset();
}

void tearDown(void) {}

// ---------------------------------------------------------------------------
// servo_axis
// ---------------------------------------------------------------------------

void test_begin_deja_el_servo_en_reposo() {
    ServoAxis axis;
    axis.setConfig(testConfig());
    axis.begin();
    TEST_ASSERT_EQUAL_UINT16(1500, axis.positionUs());
    TEST_ASSERT_EQUAL(AxisState::Idle, axis.state());
}

// Contrato actual: `open` termina la secuencia al LLEGAR a press_us y se queda
// presionando. No hay ninguna temporizacion que lo suelte.
void test_open_termina_la_secuencia_y_se_queda_presionando() {
    ServoAxis axis;
    axis.setConfig(testConfig());
    axis.begin();

    axis.requestOpen();
    TEST_ASSERT_EQUAL(AxisState::Presenting, axis.state());
    TEST_ASSERT_EQUAL_UINT16(1800, axis.positionUs());

    runUntilIdle(axis);

    TEST_ASSERT_TRUE(axis.sequenceComplete());
    TEST_ASSERT_FALSE(axis.wasAborted());
    TEST_ASSERT_EQUAL(ErrCode::None, axis.lastError());
    TEST_ASSERT_EQUAL(AxisState::Holding, axis.state());
    // Invariante central: tras un open el servo queda en press_us, NO en
    // rest_us. Antes este test afirmaba lo contrario.
    TEST_ASSERT_EQUAL_UINT16(1800, axis.positionUs());

    // La duracion es solo el viaje de ida: 276 ms = viaje(126) + asentar(150).
    const uint32_t travelMs = ServoAxis::estimateTravelMs(1500, 1800) + SETTLE_MS;
    TEST_ASSERT_TRUE_MESSAGE(axis.lastDurationMs() >= travelMs,
                             "la duracion deberia cubrir el viaje de ida");
    // Y la logica clave: hold_ms ya NO forma parte de nada. Si este test falla
    // porque la duracion se alarga, es que alguien ha vuelto a colgar un
    // temporizador de auto-soltado.
    TEST_ASSERT_TRUE_MESSAGE(axis.lastDurationMs() < travelMs + 100,
                             "hold_ms no deberia alargu la duracion de open");
}

// El `open` NO se auto-libera. Ni al doble de hold_ms, ni al triple.
void test_open_no_se_libera_solo_pase_lo_que_pase() {
    ServoAxis axis;
    axis.setConfig(testConfig());
    axis.begin();

    axis.requestOpen();
    runUntilIdle(axis);
    TEST_ASSERT_EQUAL(AxisState::Holding, axis.state());
    // sequenceComplete() es un latch que el router limpia al emitir el 'done'.
    // Aqui se limpia a mano para poder comprobar que el paso del tiempo NO
    // vuelve a ponerlo: si el servo se auto-libera, se abriria una secuencia.
    axis.clearSequenceComplete();

    // Muy por encima de hold_ms (1500). Antes de este cambio el servo ya
    // habria vuelto a reposo, y este test habria atrapado la regresion.
    tb_advance(testConfig().holdMs * 6u);
    axis.task();
    TEST_ASSERT_EQUAL(AxisState::Holding, axis.state());
    TEST_ASSERT_EQUAL_UINT16(1800, axis.positionUs());

    tb_advance(30000);
    axis.task();
    TEST_ASSERT_EQUAL(AxisState::Holding, axis.state());
    TEST_ASSERT_EQUAL_UINT16(1800, axis.positionUs());
    TEST_ASSERT_FALSE_MESSAGE(axis.sequenceComplete(),
                              "no debe reabrirse la secuencia sola");
}

// Este es el bug que motivo el cambio de contrato: `close` que llegaba desde
// HOLDING se ignoraba, y el pestillo se quedaba presionado para siempre.
void test_close_desde_holding_libera_el_pestillo() {
    ServoAxis axis;
    axis.setConfig(testConfig());
    axis.begin();

    axis.requestOpen();
    runUntilIdle(axis);
    TEST_ASSERT_EQUAL(AxisState::Holding, axis.state());
    axis.clearSequenceComplete();

    axis.requestClose();
    TEST_ASSERT_EQUAL(AxisState::Returning, axis.state());

    runUntilIdle(axis);
    TEST_ASSERT_EQUAL_UINT16(1500, axis.positionUs());
    TEST_ASSERT_EQUAL(AxisState::Idle, axis.state());
    TEST_ASSERT_TRUE(axis.sequenceComplete());
    TEST_ASSERT_FALSE(axis.wasAborted());
}

// HOLDING es un estado estable: no es un "movimiento en curso". El watchdog se
// apoya en moving() para no soltar el pestillo cuando el movil se desconecta,
// asi que esta distincion es la que sostiene el contrato.
void test_holding_no_cuenta_como_movimiento() {
    ServoAxis axis;
    axis.setConfig(testConfig());
    axis.begin();

    axis.requestOpen();
    TEST_ASSERT_TRUE(axis.moving());

    runUntilIdle(axis);
    TEST_ASSERT_FALSE_MESSAGE(axis.moving(), "HOLDING no es un movimiento");
    TEST_ASSERT_TRUE_MESSAGE(axis.busy(), "HOLDING si cuenta como ocupado");
}

// Un `open` repetido mientras ya se sostiene no debe relanzar la secuencia.
void test_open_mientras_sostiene_se_ignora() {
    ServoAxis axis;
    axis.setConfig(testConfig());
    axis.begin();

    axis.requestOpen();
    runUntilIdle(axis);
    axis.clearSequenceComplete();

    axis.requestOpen();
    TEST_ASSERT_EQUAL(AxisState::Holding, axis.state());
    TEST_ASSERT_FALSE_MESSAGE(axis.sequenceComplete(),
                              "un open repetido no debe abrir otra secuencia");
    TEST_ASSERT_EQUAL_UINT16(1800, axis.positionUs());
}

void test_stall_aborta_y_aunque_asu_retorna_a_reposo() {
    ServoAxis axis;
    axis.setConfig(testConfig());
    axis.begin();
    axis.requestOpen();

    // Simular un servo trabado: el reloj avanza mucho mas de lo previsto.
    tb_advance(2500);
    axis.task();
    TEST_ASSERT_EQUAL(ErrCode::Stall, axis.lastError());
    TEST_ASSERT_TRUE(axis.wasAborted());

    runUntilIdle(axis);
    TEST_ASSERT_EQUAL_UINT16(1500, axis.positionUs());
    TEST_ASSERT_EQUAL(AxisState::Idle, axis.state());
    // El codigo de STALL tiene que sobrevivir al retorno a reposo: es el
    // dato que la app necesita para avisarle a la persona.
    TEST_ASSERT_EQUAL(ErrCode::Stall, axis.lastError());
}

void test_estop_durante_el_sostenimiento_libera_la_manija() {
    ServoAxis axis;
    axis.setConfig(testConfig());
    axis.begin();
    axis.requestOpen();

    tb_advance(300);  // pasado el umbral de llegada
    axis.task();
    TEST_ASSERT_EQUAL(AxisState::Holding, axis.state());
    TEST_ASSERT_EQUAL_UINT16(1800, axis.positionUs());

    axis.abort();
    TEST_ASSERT_EQUAL(AxisState::Returning, axis.state());

    runUntilIdle(axis);
    TEST_ASSERT_EQUAL_UINT16(1500, axis.positionUs());
    TEST_ASSERT_TRUE(axis.wasAborted());
}

// Regresion: un e-stop con el servo ya en reposo tiene que cerrar la
// secuencia de todas formas. Antes abort() no llamaba a finish() en ese caso,
// asi que el router emitia un 'ack' sin 'done' y la app se quedaba con el
// microfono bloqueado para siempre.
void test_estop_en_reposo_cierra_la_secuencia_al_igual() {
    ServoAxis axis;
    axis.setConfig(testConfig());
    axis.begin();

    axis.abort();
    TEST_ASSERT_TRUE_MESSAGE(axis.sequenceComplete(),
                             "un ack sin done deja la app colgada");
    TEST_ASSERT_EQUAL_UINT16(0, axis.lastDurationMs());
    TEST_ASSERT_EQUAL_UINT16(1500, axis.positionUs());
    TEST_ASSERT_EQUAL(AxisState::Idle, axis.state());
}

// Regresion: abort() es asincrono y reinicia el temporizador del movimiento.
// Si se llamara cada tick, como haria el watchdog, el servo no llegaria nunca
// a reposo. El guardia esta en ServoAxis::abort() y no en el router, asi que
// este test golpea el eje directamente, sin pasar por CommandRouter.
void test_abort_repetido_no_impide_llegar_a_reposo() {
    ServoAxis axis;
    axis.setConfig(testConfig());
    axis.begin();
    axis.requestOpen();

    tb_advance(300);
    axis.task();
    TEST_ASSERT_EQUAL(AxisState::Holding, axis.state());

    axis.abort();
    TEST_ASSERT_EQUAL(AxisState::Returning, axis.state());

    // Simula el bucle de loop() llamando abort() cada 10 ms, como haria el
    // watchdog sin un guardia de un solo disparo.
    uint32_t elapsed = 0;
    while (axis.busy() && elapsed < 12000) {
        axis.abort();
        tb_advance(10);
        axis.task();
        elapsed += 10;
    }

    TEST_ASSERT_TRUE_MESSAGE(!axis.busy(), "el servo se quedo atascado en el retorno");
    TEST_ASSERT_EQUAL_UINT16(1500, axis.positionUs());
    TEST_ASSERT_TRUE(axis.sequenceComplete());
    TEST_ASSERT_TRUE_MESSAGE(elapsed < 1000,
                             "el retorno tardaria 276 ms si el guardia funcionase");
}

void test_close_con_el_servo_ya_en_reposo_no_mueve_nada() {
    ServoAxis axis;
    axis.setConfig(testConfig());
    axis.begin();

    axis.requestClose();
    TEST_ASSERT_TRUE(axis.sequenceComplete());
    TEST_ASSERT_EQUAL_UINT16(0, axis.lastDurationMs());
    TEST_ASSERT_EQUAL_UINT16(1500, axis.positionUs());
}

void test_los_limites_acotan_un_press_us_corrupto() {
    ServoAxis axis;
    ServoConfig c = testConfig();
    c.maxUs = 1600;      // limite muy bajo a proposito
    axis.setConfig(c);
    axis.begin();

    axis.requestOpen();
    // pressUs (1800) queda fuera de [1000, 1600]: debe acotarse a 1600.
    TEST_ASSERT_EQUAL_UINT16(1600, axis.positionUs());
    TEST_ASSERT_EQUAL_UINT16(1600, axis.config().pressUs);
}

void test_estado_de_reposo_siempre_dentro_de_los_limites() {
    ServoAxis axis;
    ServoConfig c = testConfig();
    c.restUs = 2500;     // corrupto, por encima del limite superior
    axis.setConfig(c);
    axis.begin();
    TEST_ASSERT_EQUAL_UINT16(2000, axis.positionUs());
}

// ---------------------------------------------------------------------------
// safety
// ---------------------------------------------------------------------------

void test_seq_fuera_de_orden_se_rechaza() {
    SafetyManager s;
    s.reset();
    ErrCode why = ErrCode::None;

    TEST_ASSERT_TRUE(s.acceptCommand(CmdId::Open, 10, &why));
    TEST_ASSERT_TRUE(s.acceptCommand(CmdId::Close, 11, &why));
    // Duplicado
    TEST_ASSERT_FALSE(s.acceptCommand(CmdId::Open, 11, &why));
    TEST_ASSERT_EQUAL(ErrCode::StaleSeq, why);
    // Retrocedido
    TEST_ASSERT_FALSE(s.acceptCommand(CmdId::Open, 3, &why));
    TEST_ASSERT_EQUAL(ErrCode::StaleSeq, why);
}

void test_debounce_rechaza_el_mismo_comando_repetido() {
    SafetyManager s;
    s.reset();
    ErrCode why = ErrCode::None;

    TEST_ASSERT_TRUE(s.acceptCommand(CmdId::Open, 1, &why));
    // Mismo comando, seq creciente, pero dentro de la ventana.
    TEST_ASSERT_FALSE(s.acceptCommand(CmdId::Open, 2, &why));
    TEST_ASSERT_EQUAL(ErrCode::Debounced, why);

    tb_advance(CMD_DEBOUNCE_MS + 1);
    TEST_ASSERT_TRUE(s.acceptCommand(CmdId::Open, 3, &why));
}

void test_un_comando_rechazado_no_gasta_un_seq() {
    SafetyManager s;
    s.reset();
    ErrCode why = ErrCode::None;

    TEST_ASSERT_TRUE(s.acceptCommand(CmdId::Open, 5, &why));
    // Rechazado por debounce: el seq 6 NO debe consumirse.
    TEST_ASSERT_FALSE(s.acceptCommand(CmdId::Open, 6, &why));
    TEST_ASSERT_EQUAL_UINT16(5, s.lastSeq());
    // Por eso un comando legitimo con seq 7 entra sin problema.
    TEST_ASSERT_TRUE(s.acceptCommand(CmdId::Close, 7, &why));
}

void test_watchdog_solo_expira_con_movimiento_en_curso() {
    SafetyManager s;
    s.reset();

    tb_advance(WATCHDOG_PING_MS + 100);
    // Sin movimiento en curso no hay nada que abortar.
    TEST_ASSERT_FALSE(s.watchdogExpired());

    s.noteMovementStart();
    tb_advance(WATCHDOG_PING_MS + 1);
    TEST_ASSERT_TRUE(s.watchdogExpired());

    s.notePing();
    TEST_ASSERT_FALSE(s.watchdogExpired());
}

void test_riel_de_servo_demasiado_bajo() {
    SafetyManager s;
    s.reset();

    s.setVrailMv(0);      // pin sin conectar: no comprobable
    TEST_ASSERT_TRUE(s.vrailOk());

    s.setVrailMv(5200);
    TEST_ASSERT_TRUE(s.vrailOk());

    s.setVrailMv(4200);   // por debajo de VRAIL_MIN_MV
    TEST_ASSERT_FALSE(s.vrailOk());
}

// ---------------------------------------------------------------------------
// protocol
// ---------------------------------------------------------------------------

void test_clamp_usa_respeta_los_limites() {
    ServoConfig c = testConfig();
    TEST_ASSERT_EQUAL_UINT16(1000, clampUs(c, 500));
    TEST_ASSERT_EQUAL_UINT16(2000, clampUs(c, 2500));
    TEST_ASSERT_EQUAL_UINT16(1700, clampUs(c, 1700));
}

void test_nombres_de_la_maquina_de_estados() {
    TEST_ASSERT_EQUAL_STRING("PRESENTING", axisStateName(AxisState::Presenting));
    TEST_ASSERT_EQUAL_STRING("HOLDING",    axisStateName(AxisState::Holding));
    TEST_ASSERT_EQUAL_STRING("RETURNING",  axisStateName(AxisState::Returning));
    TEST_ASSERT_EQUAL_STRING("IDLE",       axisStateName(AxisState::Idle));
}

int main(int, char**) {
    UNITY_BEGIN();

    RUN_TEST(test_begin_deja_el_servo_en_reposo);
    RUN_TEST(test_open_termina_la_secuencia_y_se_queda_presionando);
    RUN_TEST(test_open_no_se_libera_solo_pase_lo_que_pase);
    RUN_TEST(test_close_desde_holding_libera_el_pestillo);
    RUN_TEST(test_holding_no_cuenta_como_movimiento);
    RUN_TEST(test_open_mientras_sostiene_se_ignora);
    RUN_TEST(test_stall_aborta_y_aunque_asu_retorna_a_reposo);
    RUN_TEST(test_estop_durante_el_sostenimiento_libera_la_manija);
    RUN_TEST(test_estop_en_reposo_cierra_la_secuencia_al_igual);
    RUN_TEST(test_abort_repetido_no_impide_llegar_a_reposo);
    RUN_TEST(test_close_con_el_servo_ya_en_reposo_no_mueve_nada);
    RUN_TEST(test_los_limites_acotan_un_press_us_corrupto);
    RUN_TEST(test_estado_de_reposo_siempre_dentro_de_los_limites);

    RUN_TEST(test_seq_fuera_de_orden_se_rechaza);
    RUN_TEST(test_debounce_rechaza_el_mismo_comando_repetido);
    RUN_TEST(test_un_comando_rechazado_no_gasta_un_seq);
    RUN_TEST(test_watchdog_solo_expira_con_movimiento_en_curso);
    RUN_TEST(test_riel_de_servo_demasiado_bajo);

    RUN_TEST(test_clamp_usa_respeta_los_limites);
    RUN_TEST(test_nombres_de_la_maquina_de_estados);

    return UNITY_END();
}
