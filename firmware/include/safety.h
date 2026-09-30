#pragma once

#include <stdint.h>

#include "protocol.h"

// Guardas que se aplican ANTES de tocar el servo.
//
// Objetivo: que ningun paquete malicioso, corrupto, duplicado o retrasado
// pueda llevar el servo a una posicion arbitraria o dejarlo presionando la
// manija.

class SafetyManager {
public:
    void reset();

    // Valida un comando entrante. Devuelve true si se acepta.
    //
    // Rechazos:
    //   StaleSeq  -> seq <= ultimo aceptado (duplicado del stack BLE o
    //                comando retrasado de una reconexion)
    //   Debounced -> mismo cmd dentro de CMD_DEBOUNCE_MS
    bool acceptCommand(CmdId cmd, uint16_t seq, ErrCode* reason);

    // Watchdog. Si nadie manda ping durante WATCHDOG_PING_MS y hay una
    // secuencia en curso, hay que abortarla.
    bool watchdogExpired() const;
    void notePing();
    void noteMovementStart();
    void noteMovementEnd();
    bool movementInProgress() const { return _movementInProgress; }

    // Verificacion del riel de alimentacion del servo. Sin el divisor
    // resistivo en PIN_VRAIL_SENSE devuelve true (no se puede comprobar).
    bool vrailOk() const { return _vrailOk; }
    void setVrailMv(uint16_t mv);

    uint16_t lastSeq() const { return _lastSeq; }

private:
    uint16_t _lastSeq      = 0;
    bool     _haveSeq      = false;
    CmdId    _lastCmd      = CmdId::None;
    uint32_t _lastCmdMs    = 0;

    uint32_t _lastPingMs   = 0;
    bool     _movementInProgress = false;
    bool     _vrailOk      = true;
};
