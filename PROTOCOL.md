# Contrato de comunicación — App ⇄ ESP32-S3

**Estado: CONGELADO.** Cualquier cambio requiere modificar este archivo, `firmware/include/protocol.h`
y `app/lib/data/protocol/protocol.dart` en el mismo commit.

- Transport: Bluetooth LE, perfil GATT, conexión punto a punto.
- Codificación: JSON UTF-8, un objeto por mensaje, sin saltos de línea.
- Tamaño máximo de carga: 240 bytes (MTU 247). Ningún mensaje del contrato se acerca a ese límite.

---

## 1. GATT

| Elemento | UUID | Propiedades | Dirección |
|---|---|---|---|
| Servicio | `0000ff00-0000-1000-8000-00805f9b34fb` | — | — |
| `RX` (comandos) | `0000ff01-0000-1000-8000-00805f9b34fb` | Write, WriteNR | app → device |
| `TX` (eventos) | `0000ff02-0000-1000-8000-00805f9b34fb` | Notify, Read | device → app |

Nombre Bluetooth: `PuertaVoz-XXXX`, donde `XXXX` son los 4 últimos dígitos del MAC.

### Reglas de transporte

1. La app **debe** re-descubrir los servicios tras **cada** reconexión. En Android los objetos
   `BluetoothService` / `BluetoothCharacteristic` de una conexión anterior quedan inválidos.
2. La app **debe** suscribirse a `TX` (notify) antes de escribir en `RX`.
3. El firmware notifica `eventos` a **todos** los clientes conectados. Solo se admite uno.
4. Distinción de errores de parseo, que la app registra de forma distinta:
   - `MALFORMED`: el payload no es JSON, no es un objeto, le falta `cmd`, o le falta un `seq`
     utilizable. No se puede correlacionar con nada.
   - `UNKNOWN_CMD`: el JSON parsea y el `seq` es válido, pero el `cmd` no existe en la tabla de la
     sección 2. Sí se puede correlacionar.

---

## 2. Comandos — app → ESP32 (escritura en `RX`)

```json
{"cmd":"open","seq":42}
{"cmd":"close","seq":43}
{"cmd":"estop","seq":44}
{"cmd":"ping","seq":45}
{"cmd":"get_config","seq":46}
{"cmd":"save_config","seq":47,"press_us":1800,"rest_us":1500,"min_us":950,"max_us":2050,"hold_ms":1500}
{"cmd":"calibrate","seq":48,"mode":"sweep"}
```

| `cmd` | Campos | Efecto |
|---|---|---|
| `open` | — | Presiona la manija, sostiene, vuelve a reposo |
| `close` | — | Vuelve a reposo. Idempotente. Efecto inmediato en la app, sin confirmación |
| `estop` | — | Aborta el movimiento en curso y vuelve a reposo a máxima velocidad |
| `ping` | — | Devuelve `pong`. También renueva el watchdog |
| `get_config` | — | Devuelve `config` |
| `save_config` | `press_us`, `rest_us`, `min_us`, `max_us`, `hold_ms` | Valida, acota y persiste en NVS |
| `calibrate` | `mode` | `sweep`: barre `min_us → max_us → min_us` para fijar límites reales |

### `seq`

- Entero monotónico creciente, empieza en 1.
- El firmware **descarta** cualquier comando con `seq` menor o igual al último aceptado
  (error `STALE_SEQ`). Esto descarta duplicados del stack BLE y comandos retrasados de una
  reconexión.
- Todo evento devuelto lleva el `seq` del comando que lo provocó, salvo `status`, que no lo lleva.
- **`estop` es la excepción a las guardas y sí conserva su `seq`.** No pasa por el control de orden
  (para que un e-stop repetido nunca se descarte y siempre llegue a `reposo`), pero el `ack` y el
  `done` que genera llevan el `seq` recibido, para que la app pueda correlacionarlos. La app cuenta
  los que no son cero y descarta el resto.
- El `seq` se consume **solo si el comando es aceptado**. Un comando rechazado por debounce no
  gasta un número de la secuencia.

---

## 3. Eventos — ESP32 → app (notify en `TX`)

```json
{"ev":"ack","seq":42,"action":"open","state":"PRESENTING"}
{"ev":"done","seq":42,"action":"open","state":"REST","dur_ms":2340}
{"ev":"done","seq":43,"action":"close","state":"REST","dur_ms":0,"note":"already_at_rest"}
{"ev":"error","seq":42,"code":"STALL","msg":"no alcanzo press_us en 2000 ms; retorno a reposo"}
{"ev":"config","press_us":1800,"rest_us":1500,"min_us":950,"max_us":2050,"hold_ms":1500,"calibrated":true,"fw":"1.0.0"}
{"ev":"status","state":"REST","servo_us":1500,"vrail_ok":true,"fw":"1.0.0"}
{"ev":"pong","seq":45}
```

| `ev` | Cuándo |
|---|---|
| `ack` | Inmediatamente al aceptar un comando válido |
| `done` | Al terminar la secuencia. **Todo `ack` de movimiento lleva detrás exactamente un `done`**, incluso si el servo ya estaba en reposo (`note=already_at_rest`) |
| `error` | Comando rechazado. Un movimiento abortado se reporta con `done` + `note=stall` / `note=watchdog`, no con `error` |
| `config` | Respuesta a `get_config` o a `save_config` |
| `status` | Periódico (cada 5 s) |
| `pong` | Respuesta a `ping` |

### `note` de `done`

| `note` | Significado |
|---|---|
| (ausente) | La secuencia terminó sola, sin incidencias |
| `already_at_rest` | El servo ya estaba en `rest_us`; `dur_ms` es 0 y no hubo movimiento |
| `stall` | No alcanzó el destino en `MAX_MOVE_MS`; ya está de vuelta en reposo |
| `watchdog` | Se cortó por falta de `ping`; ya está de vuelta en reposo |

### `state`

`IDLE` · `PRESENTING` · `HOLDING` · `RETURNING`

`REST` es un valor de `state` que solo aparece en el evento `done`, significando
"terminó y el servo está en `rest_us`".

### Campos de `status`

| Campo | Significado |
|---|---|
| `servo_us` | Pulso PWM que el firmware está aplicando ahora mismo |
| `vrail_ok` | Riel del servo por encima del mínimo. En V1.0 el pin no está cableado, así que siempre vale `true`: es un marcador de sitio para V1.1, no una medida |
| `fw` | Versión del firmware |

`status` no lleva `vbat_mv` ni `rssi_dbm`. En V1.0 el ESP32 no mide el riel y el RSSI leído por el
stack BLE no es fiable en todas las plataformas de móvil, así que publicar esos campos sería
publicar ruido. Si la app los necesita, tienen que venir de otro lado: RSSI de `flutter_blue_plus` y
un ADC de verdad.

### `code` de error

| `code` | Causa | La app debe |
|---|---|---|
| `MALFORMED` | JSON inválido, sin `cmd`, o sin `seq` utilizable | Log técnico. No hablar al usuario |
| `UNKNOWN_CMD` | `cmd` no reconocido | Log técnico. No hablar al usuario |
| `STALE_SEQ` | `seq` ≤ último aceptado | Ignorar en silencio. Reintentar con `seq` mayor |
| `DEBOUNCED` | Mismo `cmd` dentro de 500 ms | Ignorar en silencio |
| `NOT_CALIBRATED` | NVS vacío y el servo no puede moverse | Guiar a la app a la pantalla de calibración |
| `OUT_OF_RANGE` | `save_config` con valor fuera de límites duros | Mostrar el valor rechazado |
| `STALL` | No alcanzó `press_us` en `MAX_MOVE_MS` | Avisar "no se movió, algo está trabado" |
| `VOLTAGE_LOW` | Riel del servo < 5.0 V (V1.1) | Avisar "batería baja" |

---

## 4. Configuración persistida (NVS)

| Clave | Rango | Default | Significado |
|---|---|---|---|
| `min_us` | 900–2000 | 1000 | Límite mecánico duro inferior |
| `max_us` | 1100–2100 | 2000 | Límite mecánico duro superior |
| `rest_us` | `[min_us, max_us]` | 1500 | **Estado seguro.** El servo no toca la manija |
| `press_us` | `[min_us, max_us]` | 1800 | Manija presionada, pestillo retraído |
| `hold_ms` | 300–3000 | 1500 | Cuánto mantiene presionada la manija |

`rest_us` es simultáneamente el estado de reposo, el destino de todas las salidas de error y el
estado de apagado seguro. No existe ninguna ruta de ejecución en la que el servo termine
presionando la manija.

### Ajustes mecánicos que impone el firmware

1. **El retorno a `rest_us` es siempre a velocidad máxima.** El brazo no debe estorbar el cierre
   de la puerta ni interferir con un closer.
2. **`hold_ms` debe ser suficiente para que la persona empuje la puerta.** Si se suelta antes de
   tiempo, el pestillo se re-engancha y la puerta no abre. Se ajusta en pruebas de campo (Fase 6).
3. **`press_us` nunca puede cruzar `rest_us`** hacia un lado que exceda `max_us`: siempre se acota
   con `constrain()` contra `[min_us, max_us]`, sin importa qué envíe la app.

---

## 5. Semántica de `open` y `close`

Modelo mecánico: **manija de palanca con resorte**.

- `open` = bajar la manija (retraer el pestillo), sostener, soltar. La puerta queda desbloqueada.
- `close` = **no requiere acción del servo.** La persona empuja la puerta y el pestillo se
  re-engancha solo. El servo solo necesita estar en reposo para no estorbar.

Por lo tanto `close` es un alias de "ir a `rest_us`", y por diseño **no pide confirmación de voz**:
se ejecuta de inmediato. La regla de interacción es simétrica:

> Se confirma lo que **aumenta** el riesgo. Se ejecuta de inmediato lo que lo **reduce**.

`open` es la única acción que mueve el servo hacia un estado no-seguro, y es la única que exige
confirmación en dos pasos por voz.

### Honestidad del estado

El MG995 no reporta posición y el ESP32 no tiene sensor de puerta. La app **no puede afirmar que la
puerta está cerrada**; solo puede afirmar que el actuador está en reposo. Todo el feedback verbal
debe hablar del actuador, nunca de la puerta.

Frase obligatoria tras `open`: *"Puerta desbloqueada. Presiona la puerta para cerrarla."*
Frase obligatoria tras `close`: *"Actuador en reposo. Presiona la puerta para cerrarla."*

---

## 6. Límites y tiempos del firmware

| Parámetro | Valor | Constante |
|---|---|---|
| Timeout duro de movimiento | 2000 ms | `MAX_MOVE_MS` |
| Anti-rebote de comandos | 500 ms | `CMD_DEBOUNCE_MS` |
| Watchdog sin `ping` | 30 000 ms | `WATCHDOG_PING_MS` |
| Periodo PWM del servo | 50 Hz / 20 ms | `SERVO_FREQ_HZ` |
| `status` periódico | 5000 ms | — |

### El watchdog es de un solo disparo

`abort()` es **asíncrono**: el servo tarda lo que tarden los milisegundos del regreso a `rest_us`.
Si el watchdog volviera a llamar `abort()` en cada vuelta del `loop()`, reiniciaría el temporizador
de movimiento y el servo **nunca** llegaría a reposo. Por eso `pollWatchdog()` dispara una vez por
secuencia, igual que un lazo con su propia bandera.

La desconexión BLE aplica la misma política y, por el mismo motivo, **no** marca fin de movimiento:
mientras el brazo siga fuera de `rest_us` el watchdog tiene que seguir armado. Lo desarma el `done`
que emite `tick()` cuando el retorno termina.

---

## 7. Códigos de error

| `code` | `msg` |
|---|---|
| `MALFORMED` | `json invalido` |
| `UNKNOWN_CMD` | `comando desconocido` |
| `STALE_SEQ` | `seq fuera de orden` |
| `DEBOUNCED` | `comando duplicado` |
| `NOT_CALIBRATED` | `falta calibracion` |
| `OUT_OF_RANGE` | `valor fuera de rango` |
| `STALL` | `no alcanzo press_us; retorno a reposo` |
| `VOLTAGE_LOW` | `riel de servo por debajo de 5.0 V` |
