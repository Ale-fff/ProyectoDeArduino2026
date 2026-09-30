#include "safety.h"

#include "log.h"
#include "timebase.h"

void SafetyManager::reset() {
    _lastSeq   = 0;
    _haveSeq   = false;
    _lastCmd   = CmdId::None;
    _lastCmdMs = 0;
    _lastPingMs = nowMs();
    _movementInProgress = false;
    _vrailOk   = true;
}

bool SafetyManager::acceptCommand(CmdId cmd, uint16_t seq, ErrCode* reason) {
    const uint32_t t = nowMs();

    // El orden de los seq tiene prioridad sobre todo lo demas: un comando
    // retrasado no debe poder pisar un movimiento en curso.
    if (_haveSeq && seq <= _lastSeq) {
        if (reason) *reason = ErrCode::StaleSeq;
        return false;
    }

    // Anti-rebote: mismo comando repetido en muy poco tiempo.
    if (cmd == _lastCmd && (t - _lastCmdMs) < CMD_DEBOUNCE_MS) {
        if (reason) *reason = ErrCode::Debounced;
        return false;
    }

    // Aceptado. El seq se consume recien ahora, para que un comando rechazado
    // por debounce no gaste un numero de la secuencia.
    _lastSeq   = seq;
    _haveSeq   = true;
    _lastCmd   = cmd;
    _lastCmdMs = t;
    if (reason) *reason = ErrCode::None;
    return true;
}

bool SafetyManager::watchdogExpired() const {
    if (!_movementInProgress) return false;
    return (nowMs() - _lastPingMs) >= WATCHDOG_PING_MS;
}

void SafetyManager::notePing() { _lastPingMs = nowMs(); }

void SafetyManager::noteMovementStart() {
    _movementInProgress = true;
    _lastPingMs = nowMs();
}

void SafetyManager::noteMovementEnd() { _movementInProgress = false; }

void SafetyManager::setVrailMv(uint16_t mv) {
    if (mv == 0) {  // pin sin conectar o ADC no disponible
        _vrailOk = true;
        return;
    }
    _vrailOk = (mv >= VRAIL_MIN_MV);
}
