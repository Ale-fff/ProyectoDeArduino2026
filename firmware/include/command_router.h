#pragma once

#include <stdint.h>

#include "calibration.h"
#include "protocol.h"
#include "safety.h"
#include "servo_axis.h"

class CommandRouter {
public:
    CommandRouter(ServoAxis& axis, SafetyManager& safety, Calibration& calib);

    // Procesa un payload crudo de BLE y emite el evento correspondiente.
    // handleRaw NUNCA emite 'done': esa emisson es responsabilidad exclusiva
    // de tick(), para no duplicar eventos cuando una accion termina de forma
    // sincrona (por ejemplo un close con el servo ya en reposo).
    bool handleRaw(const char* payload, size_t len);

    // Destino de los eventos. Por defecto se imprimen por Serial.
    using Sink = void (*)(const char* json, void* user);
    void setSink(Sink sink, void* user) { _sink = sink; _sinkUser = user; }

    // Llamar desde loop(). Emite 'done' al terminar una secuencia y 'status'
    // periodicamente. Devuelve true si emitio algo.
    bool tick();

    // Corta la secuencia en curso si nadie manda ping. El 'done' correspondiente
    // lo emite tick() con note="watchdog".
    bool pollWatchdog();

private:
    void emit(const char* json);
    void emitError(uint16_t seq, ErrCode code);
    void emitAck(uint16_t seq, const char* action, AxisState st);
    void emitDone(uint16_t seq, const char* action, uint32_t durMs, const char* note);
    void emitConfig();
    void emitStatus();
    void emitPong(uint16_t seq);

    void markPending(const char* action);

    bool parse(const char* payload, size_t len);

    ServoAxis&     _axis;
    SafetyManager& _safety;
    Calibration&   _calib;

    Sink  _sink     = nullptr;
    void* _sinkUser = nullptr;

    // Resultados de parse(), rellenados en handleRaw.
    CmdId       _cmd     = CmdId::None;
    uint16_t    _seq     = 0;
    ServoConfig _save    = defaultConfig();
    bool        _hasSave = false;
    char        _mode[16] = {0};

    // Accion de la secuencia en curso y su comando asociado, para poder
    // etiquetar el 'done'.
    char        _pendingAction[12] = {0};
    uint16_t    _pendingSeq        = 0;
    bool        _watchdogFired     = false;
    uint32_t    _lastStatusMs      = 0;
};
