# ManejIA (Asistente Domótico Controlado por Voz)

Este proyecto consta de una aplicación móvil (Flutter) y un firmware (PlatformIO/ESP32-S3) para controlar la apertura de una puerta mediante un servomotor (MG995) usando comandos de voz a través de Bluetooth Low Energy (BLE).

## Estructura del Proyecto

- `/app`: Código fuente de la aplicación móvil desarrollada en Flutter.
- `/firmware`: Código fuente del firmware para el ESP32-S3, desarrollado utilizando PlatformIO y el framework de Arduino.
- `PROTOCOL.md`: Documento que define el contrato de comunicación BLE (GATT) entre la aplicación y el ESP32-S3.

## Funcionalidades Principales

- **Conexión BLE**: Conexión rápida y directa al dispositivo ESP32-S3.
- **Reconocimiento de Voz Offline**: Utiliza `speech_to_text` de manera local para interpretar intenciones ("abre la puerta", etc).
- **Control de Acceso Seguro**: El firmware garantiza que el servo nunca quede presionando la manija indefinidamente; incluye mecanismos de seguridad y un watchdog (temporizador de vigilancia) a prueba de desconexiones.
- **Feedback por Voz (TTS)**: La aplicación proporciona confirmaciones y alertas de estado por voz, haciendo que el sistema sea utilizable sin necesidad de mirar la pantalla.
- **Pantalla de Calibración y Ajustes**: Permite iniciar el modo barrido (`sweep`) para validar topes mecánicos y ajustar en tiempo real el tiempo de retención (`hold_ms`), el rango seguro de reposo (`rest_us`) y la posición de presión (`press_us`).
- **Diagnóstico y Alertas de Alimentación**: Alertas visuales y por voz ante estados de falla (STALL, descalibración o voltaje bajo en el riel de alimentación del servo).

## Requisitos de Desarrollo

### Aplicación Móvil (Flutter)
- Flutter SDK (>= 3.22.0)
- Dart SDK (>= 3.3.0 < 4.0.0)

Para compilar y probar la aplicación:
```bash
cd app
flutter pub get
flutter run
```

### Firmware (ESP32-S3)
- PlatformIO Core o extensión para VSCode

Para compilar y subir el firmware al microcontrolador:
```bash
cd firmware
pio run -e esp32s3_drive -t upload
```
*Nota: Revisa el archivo `platformio.ini` para conocer los distintos entornos de compilación (`esp32s3` para simulación, `esp32s3_drive` para accionar el servo físicamente).*

Para acceder desde el navegador: http://localhost:8080

