#include "command_router.h"

#include "log.h"
#include "timebase.h"

#if defined(ARDUINO)
#include <ArduinoJson.h>
#endif

CommandRouter::CommandRouter(ServoAxis& axis, SafetyManager& safety, Calibration& calib)
    : _axis(axis), _safety(safety), _calib(calib) {}

// ---------------------------------------------------------------------------
// Emision
// ---------------------------------------------------------------------------

void CommandRouter::emit(const char* json) {
    if (_sink) {
        _sink(json, _sinkUser);
    } else {
        PV_LOG_PRINTLN(json);
    }
}

void CommandRouter::emitError(uint16_t seq, ErrCode code) {
    char buf[200];
    snprintf(buf, sizeof(buf),
             "{\"ev\":\"error\",\"seq\":%u,\"code\":\"%s\",\"msg\":\"%s\"}",
             static_cast<unsigned>(seq), errCodeName(code), errMsg(code));
    emit(buf);
}

void CommandRouter::emitAck(uint16_t seq, const char* action, AxisState st) {
    char buf[128];
    snprintf(buf, sizeof(buf),
             "{\"ev\":\"ack\",\"seq\":%u,\"action\":\"%s\",\"state\":\"%s\"}",
             static_cast<unsigned>(seq), action, axisStateName(st));
    emit(buf);
}

void CommandRouter::emitDone(uint16_t seq, const char* action, uint32_t durMs,
                             const char* note) {
    char buf[192];
    if (note && *note) {
        snprintf(buf, sizeof(buf),
                 "{\"ev\":\"done\",\"seq\":%u,\"action\":\"%s\",\"state\":\"REST\","
                 "\"dur_ms\":%lu,\"note\":\"%s\"}",
                 static_cast<unsigned>(seq), action,
                 static_cast<unsigned long>(durMs), note);
    } else {
        snprintf(buf, sizeof(buf),
                 "{\"ev\":\"done\",\"seq\":%u,\"action\":\"%s\",\"state\":\"REST\","
                 "\"dur_ms\":%lu}",
                 static_cast<unsigned>(seq), action,
                 static_cast<unsigned long>(durMs));
    }
    emit(buf);
}

void CommandRouter::emitConfig() {
    const ServoConfig c = _axis.config();
    char buf[216];
    snprintf(buf, sizeof(buf),
             "{\"ev\":\"config\",\"press_us\":%u,\"rest_us\":%u,\"min_us\":%u,"
             "\"max_us\":%u,\"hold_ms\":%u,\"calibrated\":%s,\"fw\":\"%s\"}",
             c.pressUs, c.restUs, c.minUs, c.maxUs, c.holdMs,
             c.calibrated ? "true" : "false", FW_VERSION);
    emit(buf);
}

void CommandRouter::emitStatus() {
    char buf[200];
    snprintf(buf, sizeof(buf),
             "{\"ev\":\"status\",\"state\":\"%s\",\"servo_us\":%u,"
             "\"vrail_ok\":%s,\"fw\":\"%s\"}",
             axisStateName(_axis.state()), _axis.positionUs(),
             _safety.vrailOk() ? "true" : "false", FW_VERSION);
    emit(buf);
}

void CommandRouter::emitPong(uint16_t seq) {
    char buf[48];
    snprintf(buf, sizeof(buf), "{\"ev\":\"pong\",\"seq\":%u}", static_cast<unsigned>(seq));
    emit(buf);
}

void CommandRouter::markPending(const char* action) {
    snprintf(_pendingAction, sizeof(_pendingAction), "%s", action);
    _pendingSeq    = _seq;
    _watchdogFired = false;
    _safety.noteMovementStart();
}

// ---------------------------------------------------------------------------
// Parseo
// ---------------------------------------------------------------------------

bool CommandRouter::parse(const char* payload, size_t len) {
    _cmd     = CmdId::None;
    _seq     = 0;
    _hasSave = false;
    _mode[0] = '\0';

#if defined(ARDUINO)
    JsonDocument doc;
    if (deserializeJson(doc, payload, len)) return false;

    const char* cmd = doc["cmd"] | "";
    if (*cmd == '\0') return false;  // sin "cmd": el payload esta roto

    // El seq se valida antes que el nombre del comando. Motivo: un comando
    // desconocido sin seq utilizable no se puede correlacionar con nada, y
    // para la app eso es un payload mal formado, no un nombre inventado.
    const int seq = doc["seq"] | 0;
    if (seq <= 0 || seq > 65535) return false;  // seq 0 no sirve para ordenar
    _seq = static_cast<uint16_t>(seq);

    if      (strcmp(cmd, "open")       == 0) { _cmd = CmdId::Open; }
    else if (strcmp(cmd, "close")      == 0) { _cmd = CmdId::Close; }
    else if (strcmp(cmd, "estop")      == 0) { _cmd = CmdId::Estop; }
    else if (strcmp(cmd, "ping")       == 0) { _cmd = CmdId::Ping; }
    else if (strcmp(cmd, "get_config") == 0) { _cmd = CmdId::GetConfig; }
    else if (strcmp(cmd, "calibrate")  == 0) {
        _cmd = CmdId::Calibrate;
        snprintf(_mode, sizeof(_mode), "%s", doc["mode"] | "sweep");
    } else if (strcmp(cmd, "save_config") == 0) {
        _cmd  = CmdId::SaveConfig;
        _save = _axis.config();
        _save.minUs   = doc["min_us"]   | _save.minUs;
        _save.maxUs   = doc["max_us"]   | _save.maxUs;
        _save.restUs  = doc["rest_us"]  | _save.restUs;
        _save.pressUs = doc["press_us"] | _save.pressUs;
        _save.holdMs  = doc["hold_ms"]  | _save.holdMs;
        _hasSave = true;
    } else {
        // JSON que parsea, seq valido, pero el comando no existe. Distinto de
        // MALFORMED a proposito, para que la app pueda differentiate.
        _cmd = CmdId::Unknown;
    }
    return true;
#else
    (void)payload; (void)len;
    return false;
#endif
}

// ---------------------------------------------------------------------------
// Despacho
// ---------------------------------------------------------------------------

bool CommandRouter::handleRaw(const char* payload, size_t len) {
    if (!payload || len == 0) {
        emitError(0, ErrCode::Malformed);
        return false;
    }
    if (!parse(payload, len)) {
        emitError(_seq, ErrCode::Malformed);
        return false;
    }

    // --- E-stop: atraviesa todas las guardas ---
    // Es la unica orden que tiene que poder pasar siempre, incluso repetida
    // dentro de la ventana de debounce, porque su unico efecto es REDUCIR el
    // riesgo. Por eso NO consume el seq: no se llama a acceptCommand(), asi
    // que el control de orden sigue intacto para el siguiente comando legitimo
    // de la app. Lo que si hay que hacer es conservar el seq recibido, para
    // que el 'ack' y el 'done' se puedan correlacionar con lo que pidio la
    // persona. La app cuenta los que no soy cero y los descarta.
    if (_cmd == CmdId::Estop) {
        _safety.notePing();
        markPending("estop");
        _axis.abort();
        emitAck(_seq, "estop", _axis.state());
        return true;
    }

    ErrCode reason = ErrCode::None;
    if (!_safety.acceptCommand(_cmd, _seq, &reason)) {
        emitError(_seq, reason);
        return false;
    }
    _safety.notePing();

    switch (_cmd) {
        case CmdId::Ping:
            emitPong(_seq);
            return true;

        case CmdId::GetConfig:
            emitConfig();
            return true;

        case CmdId::SaveConfig:
            if (!_hasSave || !_calib.save(_save)) {
                emitError(_seq, ErrCode::OutOfRange);
                return false;
            }
            _axis.setConfig(_calib.load());
            emitConfig();
            return true;

        case CmdId::Calibrate:
            _calib.markCalibrated();
            _axis.setConfig(_calib.load());
            emitConfig();
            PV_LOG_PRINTF("[cal] calibrate mode=%s\n", _mode);
            return true;

        case CmdId::Open: {
            const ServoConfig c = _axis.config();
            if (!c.calibrated) {
                emitError(_seq, ErrCode::NotCalibrated);
                return false;
            }
            if (!_safety.vrailOk()) {
                emitError(_seq, ErrCode::VoltageLow);
                return false;
            }
            markPending("open");
            _axis.requestOpen();
            emitAck(_seq, "open", _axis.state());
            return true;
        }

        case CmdId::Close: {
            // No exige calibracion ni riel sano: close REDUCE el riesgo, asi
            // que tiene que poder ejecutarse siempre, incluso con la
            // configuracion sin calibrar.
            markPending("close");
            _axis.requestClose();
            emitAck(_seq, "close", _axis.state());
            return true;
        }

        case CmdId::Unknown:
            emitError(_seq, ErrCode::UnknownCmd);
            return false;

        case CmdId::None:
        default:
            emitError(_seq, ErrCode::Malformed);
            return false;
    }
}

// ---------------------------------------------------------------------------
// Tarea periodica
// ---------------------------------------------------------------------------

bool CommandRouter::pollWatchdog() {
    if (_watchdogFired) return false;          // un disparo por secuencia
    if (!_safety.watchdogExpired()) return false;

    PV_LOG_PRINTLN("[safety] watchdog: sin ping, retorno a reposo");
    // Ahora mismo el servo puede estar en medio de un PRESENTING. abort() lo
    // manda a reposo, pero esa vuelta tiene su propia duracion: si se
    // volviera a llamar abort() en cada tick, reiniciaria el temporizador de
    // movimiento y el servo NUNCA llegaria a reposo.
    _axis.abort();
    _watchdogFired = true;
    return true;
}

bool CommandRouter::tick() {
    _axis.task();
    bool emitted = false;

    // Cierre de la secuencia en curso. Unico lugar del firmware que emite
    // 'done', con lo que no hay riesgo de duplicados.
    if (_axis.sequenceComplete()) {
        _axis.clearSequenceComplete();

        const char* action = _pendingAction[0] ? _pendingAction : "abort";
        const char* note   = nullptr;
        if (_watchdogFired) {
            note = "watchdog";
        } else if (_axis.wasAborted() && _axis.lastError() == ErrCode::Stall) {
            note = "stall";
        } else if (_axis.lastDurationMs() == 0) {
            note = "already_at_rest";
        }

        emitDone(_pendingSeq, action, _axis.lastDurationMs(), note);
        _pendingAction[0] = '\0';
        _watchdogFired    = false;
        _safety.noteMovementEnd();
        emitted = true;
    }

    const uint32_t t = nowMs();
    if (t - _lastStatusMs >= STATUS_PERIOD_MS) {
        _lastStatusMs = t;
        emitStatus();
        emitted = true;
    }
    return emitted;
}
