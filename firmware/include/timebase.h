#pragma once

// Reloj del firmware.
//
// Los modulos de logica (servo_axis, safety) NUNCA llaman a millis() directo:
// usan nowMs(). Asi los mismos .cpp compilan para el ESP32 y para el entorno
// nativo de pruebas, donde el reloj es simulado y lo avanza tb_advance().

#include <stdint.h>

#if defined(ARDUINO)

#include <Arduino.h>

inline uint32_t nowMs() { return static_cast<uint32_t>(millis()); }

#else  // build nativo de pruebas

uint32_t nowMs();

// Valor del reloj simulado. Solo tiene sentido en el build nativo.
void tb_set(uint32_t ms);

// Avanza el reloj simulado.
void tb_advance(uint32_t deltaMs);

void tb_reset();

#endif
