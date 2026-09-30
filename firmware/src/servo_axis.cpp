#include "servo_axis.h"

#include "log.h"
#include "timebase.h"

#if !DRY_RUN
#include <ESP32Servo.h>
static Servo s_servo;
static bool  s_servoAttached = false;
#endif

// ---------------------------------------------------------------------------
// Cronograma
// ---------------------------------------------------------------------------

// MG995 a 6 V: ~0.14 s por 60 grados, o sea ~2.33 ms/grado.
// El pulso va de 1000 us (0 grados) a 2000 us (180 grados): 5.56 us/grado.
// => ms = deltaUs / 5.56 * 2.33 = deltaUs * 0.419
uint16_t ServoAxis::estimateTravelMs(uint16_t fromUs, uint16_t toUs) {
    const uint16_t deltaUs = (fromUs > toUs) ? static_cast<uint16_t>(fromUs - toUs)
                                             : static_cast<uint16_t>(toUs - fromUs);
    // 42/100 ~= 0.42 ms por microsegundo de desplazamiento.
    return static_cast<uint16_t>((static_cast<uint32_t>(deltaUs) * 42u) / 100u);
}

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

void ServoAxis::begin() {
    _simUs = clampUs(_cfg, _cfg.restUs);
    _state = AxisState::Idle;

#if !DRY_RUN
    s_servo.setPeriodHertz(SERVO_FREQ_HZ);
    s_servo.attach(PIN_SERVO_PWM, SERVO_ABS_MIN_US, SERVO_ABS_MAX_US);
    s_servoAttached = true;
    applyPulse(_simUs);
    PV_LOG_PRINTF("[servo] DRY_RUN=0  pin=%u  rest=%u us\n", PIN_SERVO_PWM, _simUs);
#else
    PV_LOG_PRINTF("[servo] DRY_RUN=1  sin salida PWM  rest=%u us\n", _simUs);
#endif
}

void ServoAxis::setConfig(const ServoConfig& cfg) {
    _cfg = cfg;
    setLimits(_cfg.minUs, _cfg.maxUs);
}

void ServoAxis::setLimits(uint16_t minUs, uint16_t maxUs) {
    if (minUs < SERVO_ABS_MIN_US) minUs = SERVO_ABS_MIN_US;
    if (maxUs > SERVO_ABS_MAX_US) maxUs = SERVO_ABS_MAX_US;
    if (minUs >= maxUs) {  // rango incoherente: ignora el pedido
        PV_LOG_PRINTLN("[servo] setLimits: rango incoherente, se conserva");
        return;
    }
    _cfg.minUs = minUs;
    _cfg.maxUs = maxUs;
    // Reacota los valores derivados de los limites.
    _cfg.restUs  = clampUs(_cfg, _cfg.restUs);
    _cfg.pressUs = clampUs(_cfg, _cfg.pressUs);
}

// ---------------------------------------------------------------------------
// Salida
// ---------------------------------------------------------------------------

void ServoAxis::applyPulse(uint16_t us) {
    _simUs = us;
#if !DRY_RUN
    if (s_servoAttached) s_servo.writeMicroseconds(us);
#endif
}

// ---------------------------------------------------------------------------
// Peticiones. No bloquean: solo mueven la maquina de estados.
// ---------------------------------------------------------------------------

void ServoAxis::requestOpen() {
    if (_moveActive || _state == AxisState::Holding) return;  // hay una secuencia en curso
    _seqComplete = false;
    _aborted     = false;
    _lastError   = ErrCode::None;
    _seqStartMs  = nowMs();
    beginMove(clampUs(_cfg, _cfg.pressUs), /*isReturn*/ false);
}

void ServoAxis::requestClose() {
    if (_moveActive || _state == AxisState::Holding) return;
    _seqComplete = false;
    _aborted     = false;
    _lastError   = ErrCode::None;
    _seqStartMs  = nowMs();

    if (_simUs == _cfg.restUs) {
        // Ya estaba en reposo: cerrar no requiere ninguna accion del servo.
        // La persona empuja la puerta y el pestillo se re-engancha solo.
        PV_LOG_PRINTLN("[servo] close: ya en reposo, dur_ms=0");
        finish(ErrCode::None);
        return;
    }
    beginMove(clampUs(_cfg, _cfg.restUs), /*isReturn*/ true);
}

void ServoAxis::abort() {
    // Si ya estamos volviendo a reposo, no hay nada que abortar. Y ESTE es el
    // guardia que de verdad importa: abort() reinicia el temporizador del
    // movimiento, asi que volver a llamarlo mientras el servo vuelve a reposo
    // haria que NUNCA llegue. Los llamantes que pueden pasar por aqui (el
    // watchdog en cada tick del loop, la desconexion BLE) no son idempotentes
    // por si mismos, asi que la garantia tiene que estar aqui y no alla.
    if (_state == AxisState::Returning) return;

    if (_moveActive || _state == AxisState::Holding) {
        _aborted    = true;
        _seqStartMs = nowMs();
        beginMove(clampUs(_cfg, _cfg.restUs), /*isReturn*/ true);
        return;
    }
    // No hay nada en curso. Si aun asi el servo quedo fuera de rango, hay que
    // devolverlo a reposo.
    if (_simUs != _cfg.restUs) {
        _aborted    = true;
        _seqStartMs = nowMs();
        beginMove(clampUs(_cfg, _cfg.restUs), /*isReturn*/ true);
        return;
    }
    // Ya estaba en reposo. Aun asi hay que cerrar la secuencia: el router
    // promete que todo 'ack' lleva detras un 'done', y sin esto un e-stop en
    // reposo dejaria a la app esperando con el microfono bloqueado para
    // siempre.
    //
    // _seqStartMs se pone a cero AHORA, y no se reutiliza el de una secuencia
    // anterior: finish() calcula la duracion como nowMs() - _seqStartMs, y si
    // se dejara el valor viejo la duracion de este e-stop instantaneo seria el
    // tiempo transcurrido desde el ultimo movimiento, en vez de 0.
    _aborted    = true;
    _seqStartMs = nowMs();
    finish(ErrCode::None);
}

// ---------------------------------------------------------------------------
// Movimiento
// ---------------------------------------------------------------------------

void ServoAxis::beginMove(uint16_t targetUs, bool isReturn) {
    _moveFromUs  = _simUs;
    _moveToUs    = clampUs(_cfg, targetUs);
    _moveStartMs = nowMs();
    _moveDoneMs  = _moveStartMs + estimateTravelMs(_moveFromUs, _moveToUs) + SETTLE_MS;
    _moveActive  = true;
    _state       = isReturn ? AxisState::Returning : AxisState::Presenting;
    applyPulse(_moveToUs);
}

void ServoAxis::arrive() {
    _moveActive = false;
    if (_state == AxisState::Returning) {
        // Volvimos a reposo: unico camino de salida normal del firmware.
        // Se preserva _lastError, que puede traer un STALL detectado durante
        // el PRESENTING que se acaba de abortar.
        finish(_lastError);
    } else {
        _state       = AxisState::Holding;
        _holdStartMs = nowMs();
    }
}

void ServoAxis::finish(ErrCode err) {
    _state          = AxisState::Idle;
    _moveActive     = false;
    _lastError      = err;
    _lastDurationMs = nowMs() - _seqStartMs;
    _seqComplete    = true;
    PV_LOG_PRINTF("[servo] fin err=%s dur_ms=%lu pos=%u us\n",
                  errCodeName(err),
                  static_cast<unsigned long>(_lastDurationMs), _simUs);
}

// ---------------------------------------------------------------------------
// Tarea periodica. Llamar desde loop().
// ---------------------------------------------------------------------------

void ServoAxis::task() {
    const uint32_t t = nowMs();

    // --- Sosteniendo la manija presionada ---
    if (_state == AxisState::Holding) {
        if (t - _holdStartMs >= _cfg.holdMs) {
            // Tiempo cumplido: soltar. El retorno es a velocidad maxima para
            // no estorbar el cierre de la puerta.
            beginMove(clampUs(_cfg, _cfg.restUs), /*isReturn*/ true);
        }
        return;
    }

    if (!_moveActive) return;

    // --- Corte duro por trabamiento ---
    if (t - _moveStartMs >= MAX_MOVE_MS) {
        PV_LOG_PRINTF("[servo] STALL tras %u ms, retorno a reposo\n", MAX_MOVE_MS);
        _lastError = ErrCode::Stall;
        _aborted   = true;
        beginMove(clampUs(_cfg, _cfg.restUs), /*isReturn*/ true);
        return;
    }

    if (t < _moveDoneMs) return;  // todavia en camino

    // Llegamos. En DRY_RUN el tiempo estimado se cumplio, que es justo lo que
    // hace que la app vea la misma duracion con y sin servo conectado.
    arrive();
}
