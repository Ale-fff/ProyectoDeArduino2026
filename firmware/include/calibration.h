#pragma once

#include <stdint.h>

#include "protocol.h"

// Persistencia de la calibracion en NVS, via la API Preferences del core.
//
// La calibracion es lo unico que sobrevive al reinicio. Si NVS esta vacio el
// servo arranca en los defaults seguros y NO se puede mover hasta calibrar:
// el firmware no sabe hasta donde llega el brazo en la puerta real.

class Calibration {
public:
    // Lee de NVS. Si no hay nada, deja los defaults y calibrated=false.
    void begin();

    ServoConfig load() const { return _cfg; }

    // Valida y persiste. Devuelve false (y no escribe nada) si algun valor
    // esta fuera de rango o si la geometria es incoherente.
    bool save(const ServoConfig& in);

    // Marca la calibracion como completa y persiste el flag.
    void markCalibrated();

private:
    ServoConfig _cfg = defaultConfig();
};
