/// UUIDs del servicio GATT. Deben coincidir con `firmware/include/config.h`.
library;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleUuids {
  const BleUuids._();

  static final Guid service = Guid('0000ff00-0000-1000-8000-00805f9b34fb');

  /// Comandos app -> ESP32.
  static final Guid rx = Guid('0000ff01-0000-1000-8000-00805f9b34fb');

  /// Eventos ESP32 -> app.
  static final Guid tx = Guid('0000ff02-0000-1000-8000-00805f9b34fb');

  /// Prefijo del nombre Bluetooth. El sufijo son 4 digitos del MAC.
  static const String namePrefix = 'PuertaVoz';
}
