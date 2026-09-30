#pragma once

#include <stddef.h>
#include <stdint.h>

// ===========================================================================
// PLACA
// ESP32-S3-DevKitC-1  (variantes N8R2 y N16R8)
//
// PINES PROHIBIDOS — no usarlos bajo ninguna circunstancia:
//   GPIO0, 3, 45, 46  strapping (modo de boot, VDD_SPI, fuente JTAG, ROM log)
//   GPIO19, 20        USB nativo. Libres SOLO si flasheás por el UART por USB
//   GPIO26..32        bus interno de flash y PSRAM
//   GPIO33..37        ocupados por PSRAM octal en la variante N16R8.
//                     LIBRES en N8R2. No contés con ellos: el firmware debe
//                     compilar y comportarse igual en ambas variantes.
//   GPIO43, 44        consola UART0
// ===========================================================================

// ---------------------------------------------------------------------------
// Flags de compilacion
// ---------------------------------------------------------------------------

// DRY_RUN=1 -> servo_axis NO toca el pin PWM, solo registra por Serial y
//              simula los tiempos. Permite desarrollar y probar el protocolo
//              completo sin MG995 conectado y sin fuente de 6 V.
// DRY_RUN=0 -> acciona el servo de verdad.
#ifndef DRY_RUN
#define DRY_RUN 1
#endif

// UNIT_TEST=1 -> habilita el reloj simulado de timebase.h (tests en la PC).
#ifndef UNIT_TEST
#define UNIT_TEST 0
#endif

// ---------------------------------------------------------------------------
// Pines
// ---------------------------------------------------------------------------
static constexpr uint8_t PIN_SERVO_PWM   = 4;  // senal PWM hacia el MG995
static constexpr uint8_t PIN_BTN_ESTOP   = 5;  // boton de parada fisico (opcional)
static constexpr uint8_t PIN_VRAIL_SENSE = 6;  // divisor resistivo -> ADC (opcional, V1.1)

// ---------------------------------------------------------------------------
// Servo
// ---------------------------------------------------------------------------
static constexpr uint8_t  SERVO_FREQ_HZ    = 50;
static constexpr uint16_t SERVO_PERIOD_US = 20000;

// Limites mecanicos duros. La calibracion los ajusta hacia adentro, nunca hacia
// afuera de estos rangos.
static constexpr uint16_t SERVO_ABS_MIN_US  = 900;
static constexpr uint16_t SERVO_ABS_MAX_US  = 2100;

// ---------------------------------------------------------------------------
// Configuracion por defecto de la calibracion (se sobreescribe con save_config)
// ---------------------------------------------------------------------------
static constexpr uint16_t DEFAULT_MIN_US   = 1000;
static constexpr uint16_t DEFAULT_MAX_US   = 2000;
static constexpr uint16_t DEFAULT_REST_US  = 1500;  // estado seguro
static constexpr uint16_t DEFAULT_PRESS_US = 1800;  // manija presionada
static constexpr uint16_t DEFAULT_HOLD_MS  = 1500;

// Rango admitido para hold_ms. El piso es corto a proposito: el servo tiene que
// soltar la manija rapido para no estorbar el cierre de la puerta.
static constexpr uint16_t HOLD_MS_MIN = 300;
static constexpr uint16_t HOLD_MS_MAX = 3000;

// ---------------------------------------------------------------------------
// Tiempos de la maquina de estados
// ---------------------------------------------------------------------------
static constexpr uint16_t MAX_MOVE_MS   = 2000;  // corte duro de un movimiento
static constexpr uint16_t SETTLE_MS     = 150;   // asentar antes de dar por llegado
static constexpr uint16_t STATUS_PERIOD_MS = 5000;

// ---------------------------------------------------------------------------
// Seguridad
// ---------------------------------------------------------------------------
static constexpr uint32_t CMD_DEBOUNCE_MS  = 500;
static constexpr uint32_t WATCHDOG_PING_MS = 30000;
static constexpr uint16_t VRAIL_MIN_MV     = 5000;  // para V1.1 con ADC

// ---------------------------------------------------------------------------
// BLE
// ---------------------------------------------------------------------------
static constexpr const char* DEVICE_NAME_PREFIX = "PuertaVoz";
static constexpr const char* SERVICE_UUID = "0000ff00-0000-1000-8000-00805f9b34fb";
static constexpr const char* CHAR_RX_UUID = "0000ff01-0000-1000-8000-00805f9b34fb";
static constexpr const char* CHAR_TX_UUID = "0000ff02-0000-1000-8000-00805f9b34fb";
static constexpr uint16_t    BLE_MTU       = 247;

// Tope de un evento saliente. El contrato fija 240 bytes de carga util; los
// buffers del router se dimensionan con 216, asi que 240 es un techo comodo
// que no llega a recortar ningun evento posible pero si corta un buffer
// desbordado antes de mandarlo por el aire.
static constexpr size_t      MAX_EVENT_BYTES = 240;

static constexpr const char* FW_VERSION = "1.0.0";
