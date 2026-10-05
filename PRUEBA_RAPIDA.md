# Prueba rápida — ManejIA con ESP32-S3 y un servo MG995

Código completo listo para pegar en Arduino IDE: `firmware/prueba_rapida/ManejIA_prueba_rapida.ino`.

Este sketch habla el **mismo protocolo congelado** de `PROTOCOL.md` que la app ManejIA, así que no
hay que tocar la app: el móvil reconoce la voz, manda `{"cmd":"open","seq":N}` por BLE y el ESP32
mueve el servo. No hay calibración ni sensor de puerta: reporta `calibrated: true` siempre.

---

## 1. Conexiones

| MG995 | ESP32-S3-DevKitC-1 |
|---|---|
| Señal (naranja) | **GPIO 18** |
| Vcc (rojo) | **Fuente externa 5–6 V** — NO el pin 5V del devkit |
| GND (marrón) | **GND común con el ESP32** |

- El MG995 puede consumir más de 1 A en picos: alimentarlo del devkit reinicia el ESP32 o quema el
  regulador. Fuente separada, GND común.
- GPIO 18 está libre en el S3 (los prohibidos son 0/3/19/20/26-37/43/44, ver `firmware/include/config.h`).

## 2. Flasheo

1. Abre `ManejIA_prueba_rapida.ino` en Arduino IDE.
2. Placa: **ESP32S3 Dev Module** (o ESP32-S3-DevKitC-1).
3. Sube con el cable USB-C del devkit.

En el Monitor Serial a 115200 verás:

```
==============================================
  ManejIA - Prueba rapida BLE + MG995
==============================================
[servo] GPIO 18, reposo 1500 us, rango 1000-2000 us
[ble] anunciando como ManejIA
[ble] servicio 0000ff00-0000-1000-8000-00805f9b34fb
```

### Autoprueba del servo (sin la app)

En la parte de arriba del sketch: `#define SELFTEST_BOOT 1`. Barre 0°/90°/180° al arrancar, como tu
ejemplo verificado. Deja `0` cuando el servo esté enganchado a la puerta.

## 3. Probar con la app

1. Abre **ManejIA** en el móvil. Sale un **splash** con el logo mientras busca el actuador.
2. Concede permisos de Bluetooth y micrófono si los pide.
3. **No hace falta tocar el botón de conexión:** al arrancar la app busca sola y se conecta si
   encuentra **un** dispositivo compatible. Si hay varios, no elige por ti (podría ser el actuador
   de otra casa) y entonces sí toca el botón: aparece la **lista de dispositivos cercanos** con el
   RSSI, y los compatibles salen primero con su etiqueta.
4. Toca el micrófono. Aparece abajo una barra **"Escuchando…"** y el botón suelta dos anillos que
   se expanden mientras graba.
5. Di **"abre la puerta"** → el servo baja la manija a 180° y **se queda ahí**. **Sin preguntar
   nada y sin pedir un "sí".** La app habla: *"Puerta abierta."*
6. Di **"cierra la puerta"** → el servo suelta el pestillo y vuelve a 90°. La app dice
   *"Puerta cerrada."*

> El servo **no vuelve solo** tras abrir. El pestillo tiene resorte: se desbloquea al presionarlo
> y se re-engancha al soltar. Mantenerlo abajo solo dejaría la puerta cerrada sin motivo.
>
> Por eso el paso 5 tiene que devolver el control: al llegar a la posición, el firmware manda
> `done` de inmediato y la app vuelve a escuchar. Si tras abrir el micrófono siguiera bloqueado,
> es que el sketch subido es el anterior.

> Si dices algo que no es ninguna orden suena el clip grabado **`Audio/no_entendi.mp3`** ("No he
> entendido eso, ¿podés repetirlo?"), no la voz sintética.

### Botones

**Abrir**, **Cerrar** y **Desconectar**. El tercero **no** es una parada de emergencia: cierra el
Bluetooth y **no mueve el servo**. La puerta se queda en el estado en que estuviera, y si estaba
abierta sigue abierta. La parada de emergencia sigue existiendo **por voz** ("para" / "alto"), que sí
llega al firmware y devuelve el pestillo a reposo.

### Fondos animados

El fondo no es estático:

- **Modo claro** → nubes que se desplazan hacia la derecha, muy despacio (unos 40 s de recorrido).
- **Modo oscuro** → estrellas que titilan con paralaje.

### Conmutador de tema

El icono de sol/luna en la barra superior alterna entre **modo claro** (crema con rojo y naranja)
y **modo oscuro** (negro azulado con acento azul). Arranca siempre en claro.

### Qué esperar en el Serial

```
[ble] cliente conectado
[ble] MTU negociado: 247 (244 bytes utiles)
[ble] cliente desconectado
[ble] reanunciando
```

Si en algún momento ves `[watchdog] sin ping durante el movimiento`, la app estuvo más de 30 s
sin mandar `ping` mientras el servo se movía. Con la app conectada no debería aparecer.

### Diagnóstico

| Síntoma | Causa | Qué hacer |
|---|---|---|
| La lista de la app sale vacía | El ESP32 no anuncia el UUID de servicio | Verifica que subiste el sketch con `adv->addServiceUUID(...)`. Con la lista "todos los cercanos" debería verse igualmente |
| Conecta pero el servo no se mueve | Comando rechazado o rango | Mira el Serial: `STALE_SEQ`/`DEBOUNCED` son normales; revisa que `PRESS_US` sea distinto de `REST_US` |
| El servo vibra en los extremos | Topes mecánicos | Sube `PULSE_MIN_US` / baja `PULSE_MAX_US` (1000–2000 es el rango seguro) |
| Se desconecta cada pocos segundos | Alimentación del servo | Fuente externa, GND común |
| El servo se mueve al azar al arrancar | GPIO en flotación durante el boot | Normal: el S3 deja el pin sin definir hasta `ledcAttach`. Se estabiliza al llegar a reposo |

## 4. Seguridad del servo

Los 500 µs / 2400 µs de tu ejemplo son rango completo. Con carga eso empuja contra los topes
mecánicos del MG995: sobrecalienta el motor y puede reventar la reductora. El sketch viene con
**1000–2000 µs** por defecto, que es el recorrido útil completo de un MG995 típico; las tres
constantes están arriba del todo del archivo para cambiarlas en un segundo.

Además el sketch acota **todo** lo que manda la app contra `[PULSE_MIN_US, PULSE_MAX_US]`, así que
aunque el firmware de producción envíe otro rango, el servo no lo pasa.

## 5. Comandos que entiende (contrato congelado)

| `cmd` | Efecto |
|---|---|
| `open` | Reposo → `press_us` y **se queda ahí** (estado `HOLDING`). Emite `done` al llegar |
| `close` | Vuelve a reposo desde donde esté, incluido `HOLDING`. Idempotente |
| `estop` | Aborta y vuelve a reposo ya (excepción a las guardas) |
| `ping` | `pong` + renueva el watchdog de 30 s (solo vigila movimientos en curso) |
| `get_config` | Evento `config` |
| `save_config` | Acepta los 5 campos y responde `config` |
| `calibrate` | Responde `config`; la prueba no barre límites reales |

Eventos: `ack`, `done` (exactamente uno por comando), `error` (`MALFORMED`, `UNKNOWN_CMD`,
`STALE_SEQ`, `DEBOUNCED`), `config`, `status` cada 5 s, `pong`.

## 6. Diferencias con el firmware de producción

Este sketch es una versión **reducida a propósito** para una prueba rápida:

- Sin calibración en NVS, sin máquina de estados con sensor de corriente, sin detección de stall.
- Sin watchdog de dos disparos ni detección de `vrail` (reporta `vrail_ok: true` fijo).
- Parseo de JSON a mano, sin ArduinoJson: cero librerías externas.
- Se anuncia como `ManejIA` en vez de `PuertaVoz-XXXX` para identificarlo a simple vista en la lista.

Cuando la prueba funcione, el firmware real es `firmware/` con PlatformIO
(`pio run -e esp32s3_drive -t upload`), que tiene calibración, watchdog y detección de stall.
