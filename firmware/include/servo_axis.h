#pragma once

#include <stdint.h>

#include "protocol.h"

// Maquina de estados del unico eje (puerta).
//
// Reglas de diseno que no se negocian:
//
//  1. No bloquea. Ni un solo delay(). Todo el tiempo se mide con nowMs().
//  2. open  = PRESENTING -> HOLDING, y se QUEDA en HOLDING. La secuencia de
//     `open` termina (y emite su 'done') al llegar a press_us, no al soltar.
//     Los unicos comandos que devuelven el servo a rest_us son `close` y
//     `estop`.
//  3. HOLDING es un estado estable y deliberado: la puerta se queda abierta
//     porque la persona la abrio. NO hay ningun temporizador que la cierre.
//     Anadir un "soltar a los N ms" seria dejar la puerta sin decidir por la
//     persona, que es exactamente el fallo que este diseno evita.
//  4. El pulso de salida se acota SIEMPRE con clampUs(), sin importar que
//     mande la app. Un valor corrupto no puede mover el servo.
//  5. El retorno a reposo es siempre a velocidad maxima, para no estorbar el
//     cierre de la puerta ni interferir con un closer.
//
// En DRY_RUN=1 no se toca el pin PWM: se registra por Serial y se simula el
// mismo cronograma, de modo que la app se comporta igual con y sin servo.

class ServoAxis {
public:
    void begin();

    // Configuracion efectiva. Guardar con setConfig() no persiste en NVS:
    // eso lo hace calibration.cpp. Aqui solo cambia el comportamiento en RAM.
    void setConfig(const ServoConfig& cfg);
    ServoConfig config() const { return _cfg; }

    // Los limites duros acotan automaticamente los que envie la app.
    void setLimits(uint16_t minUs, uint16_t maxUs);

    // Resultado de la ultima secuencia terminada.
    bool         sequenceComplete() const { return _seqComplete; }
    void         clearSequenceComplete() { _seqComplete = false; }
    bool         wasAborted() const { return _aborted; }
    ErrCode      lastError() const { return _lastError; }
    uint32_t     lastDurationMs() const { return _lastDurationMs; }
    AxisState    state() const { return _state; }
    uint16_t     positionUs() const { return _simUs; }

    // Hay un movimiento EN CURSO (PRESENTING o RETURNING). No cuenta HOLDING:
    // en HOLDING el servo ya esta donde tiene que estar y no hay nada que
    // esperar. Lo usan el watchdog y los tests.
    bool moving() const { return _moveActive; }

    // El servo esta moviendose o sosteniendo la manija. Con el contrato actual
    // esto incluye HOLDING, asi que un open deja busy() en true a proposito.
    bool busy() const { return _moveActive || _state == AxisState::Holding; }

    // Peticiones. No bloquean: solo mueven la maquina de estados.
    void requestOpen();
    void requestClose();
    void abort();  // estop: corta y vuelve a reposo a maxima velocidad

    // Llamar desde loop(), periodicamente.
    void task();

    // Tiempo estimado de recorrido del MG995 a 6 V, sin contar el asentar.
    // 1000 us ~ 0 grados, 2000 us ~ 180 grados, ~2.33 ms/grado a 6 V.
    // Publico y estatico para que los tests puedan assertar sobre el cronograma.
    static uint16_t estimateTravelMs(uint16_t fromUs, uint16_t toUs);

private:
    // Inicia un movimiento hacia targetUs.
    void beginMove(uint16_t targetUs, bool isReturn);
    void arrive();

    // Cierra la secuencia y deja el estado en nextState. nextState casi siempre
    // es Idle; el unico caso en el que no lo es es `open`, que termina en
    // Holding. Antes esta funcion ponia siempre Idle y por eso era imposible
    // que un open acabara presionando.
    void finish(ErrCode err, AxisState nextState);

    void applyPulse(uint16_t us);

    ServoConfig _cfg;
    AxisState   _state      = AxisState::Idle;
    ErrCode     _lastError  = ErrCode::None;

    uint16_t _simUs        = 0;  // pulso actual (real o simulado)
    uint16_t _moveFromUs   = 0;
    uint16_t _moveToUs     = 0;
    uint32_t _moveStartMs  = 0;
    uint32_t _moveDoneMs   = 0;  // instante estimado de llegada
    bool     _moveActive   = false;

    uint32_t _seqStartMs   = 0;
    uint32_t _lastDurationMs = 0;

    bool _seqComplete     = false;
    bool _aborted         = false;
};
