// Log del firmware.
//
// Existe por una razon concreta: los tests nativos se compilan SIN Arduino,
// asi que `Serial` no existe ahi. En vez de llenar el codigo de
// `#if defined(ARDUINO)`, todo el log pasa por estas dos macros.
//
// En el ESP32 van al puerto serie de USB. En nativo callan, salvo que se
// defina PV_DEBUG_NATIVE, que es util cuando un test falla y hay que ver que
// estaba pasando dentro de la FSM.
#pragma once

#if defined(ARDUINO)
#include <Arduino.h>
#define PV_LOG_PRINTF(...) Serial.printf(__VA_ARGS__)
#define PV_LOG_PRINTLN(msg) Serial.println(msg)
#else
#if defined(PV_DEBUG_NATIVE)
#include <cstdio>
#define PV_LOG_PRINTF(...) std::fprintf(stderr, __VA_ARGS__)
#define PV_LOG_PRINTLN(msg) std::fprintf(stderr, "%s\n", msg)
#else
// Los argumentos NO se evaluan. Importa: asi los tests pueden pasar llamadas
// sin efecto colateral sin cambiar una linea de test.
#define PV_LOG_PRINTF(...) ((void)0)
#define PV_LOG_PRINTLN(msg) ((void)0)
#endif
#endif
