/// Cliente BLE de la app.
///
/// Aisle todo lo de `flutter_blue_plus` aca. El resto de la app solo ve
/// [BleLink] con [BleLinkStatus] y un stream de eventos, sin saber que
/// existe un plugin detras.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../protocol/protocol.dart';
import 'ble_uuids.dart';

enum BleLinkStatus {
  unknown,
  bluetoothOff,
  scanning,
  connecting,
  ready,
  disconnected,
  error,
}

/// Por que la conexion no se puede establecer. La app usa esto para dar
/// instrucciones concretas en vez de un error generico.
enum BleFailure {
  none,

  /// En iOS el permiso de Bluetooth NO se puede pedir por codigo: hay que
  /// enviar a la persona a Ajustes. Sin este caso la app se queda muda.
  bluetoothPermissionDenied,

  /// Android 12+ exige permiso de escaneo; Android 11 y menos, permiso de
  /// ubicacion.
  locationPermissionMissing,

  /// Android 12+ exige permiso de conexion.
  connectPermissionMissing,

  /// iOS necesita microfono para el reconocimiento de voz, y enbackground
  /// el reconocimiento offline necesita conexion.
  speechNotAvailable,

  other,
}

class BleLink extends ChangeNotifier {
  BleLink({this.scanDuration = const Duration(seconds: 8)});

  final Duration scanDuration;

  final List<BluetoothDevice> _found = <BluetoothDevice>[];
  List<BluetoothDevice> get foundDevices => List.unmodifiable(_found);

  BluetoothDevice? _device;
  BluetoothCharacteristic? _rx;
  BluetoothCharacteristic? _tx;

  BleLinkStatus _status = BleLinkStatus.unknown;
  BleLinkStatus get status => _status;

  BleFailure _failure = BleFailure.none;
  BleFailure get failure => _failure;

  String _lastError = '';
  String get lastError => _lastError;

  /// Eventos que llegan del ESP32 por notify.
  final StreamController<AppEvent> _events =
      StreamController<AppEvent>.broadcast();
  Stream<AppEvent> get events => _events.stream;

  int _seq = 0;

  bool get isReady => _status == BleLinkStatus.ready;

  // -------------------------------------------------------------------------

  Future<void> initialize() async {
    _setStatus(BleLinkStatus.unknown, failure: BleFailure.none);
    try {
      final supported = await FlutterBluePlus.isSupported;
      if (!supported) {
        _fail('Este dispositivo no tiene Bluetooth', BleFailure.other);
        return;
      }
      await FlutterBluePlus.initialize(logLevel: LogLevel.warn, showLogs: kDebugMode);
      await FlutterBluePlus.turnOn();
      _setStatus(BleLinkStatus.disconnected);
    } catch (e) {
      _fail('No se pudo iniciar el Bluetooth: $e', BleFailure.other);
    }
  }

  /// Verifica que el Bluetooth este encendido. En iOS devuelve
  /// [BleFailure.bluetoothPermissionDenied] si falta el permiso, que la app
  /// tiene que comunicar con una instruccion de ir a Ajustes.
  Future<bool> ensureBluetoothOn() async {
    try {
      final on = await FlutterBluePlus.isSupported ? FlutterBluePlus.turnOn() : false;
      if (on) {
        _setStatus(BleLinkStatus.disconnected, failure: BleFailure.none);
        return true;
      }
      _setStatus(BleLinkStatus.bluetoothOff, failure: _guessPermissionFailure());
      return false;
    } catch (e) {
      _fail('Bluetooth no disponible: $e', BleFailure.other);
      return false;
    }
  }

  BleFailure _guessPermissionFailure() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return BleFailure.bluetoothPermissionDenied;
    }
    return BleFailure.connectPermissionMissing;
  }

  // -------------------------------------------------------------------------

  Future<void> scan() async {
    if (!await ensureBluetoothOn()) return;

    _found.clear();
    _setStatus(BleLinkStatus.scanning);

    final sub = FlutterBluePlus.onScanResults.listen(_onScanResult);
    try {
      await FlutterBluePlus.startScan(
        withServices: <Guid>[BleUuids.service],
        timeout: scanDuration,
      );
    } finally {
      await sub.cancel();
      if (_status == BleLinkStatus.scanning) {
        _setStatus(BleLinkStatus.disconnected);
      }
    }
  }

  void _onScanResult(List<ScanResult> results) {
    for (final r in results) {
      if (r.device.platform != BluetoothDevicePlatform.unknown &&
          r.advertisementData.advName.isNotEmpty &&
          !r.advertisementData.advName.startsWith(BleUuids.namePrefix)) {
        continue;
      }
      if (_found.any((d) => d.remoteId.str == r.device.remoteId.str)) continue;
      _found.add(r.device);
      notifyListeners();
    }
  }

  // -------------------------------------------------------------------------

  Future<void> connect(BluetoothDevice device) async {
    if (!await ensureBluetoothOn()) return;

    _device = device;
    _setStatus(BleLinkStatus.connecting);

    try {
      await device.connect(
        autoConnect: false,
        mtu: null,
        // Timeout corto: si no conecta en 10 s, mejor que la persona lo sepa
        // y reintente que quedarse mirando una pantalla de carga.
        connectionTimeout: const Duration(seconds: 10),
      );

      // CRITICO: hay que re-descubrir los servicios en CADA conexion. En
      // Android los objetos de la conexion anterior quedan invalidos.
      _rx = await _findCharacteristic(device, BleUuids.rx);
      _tx = await _findCharacteristic(device, BleUuids.tx);

      if (_rx == null || _tx == null) {
        _fail('El dispositivo no tiene el servicio esperado', BleFailure.other);
        await disconnect();
        return;
      }

      await _tx!.setNotifyValue(true);
      _txSub?.cancel();
      _txSub = _tx!.onValueReceived.listen(_onTxValue);

      _statusSub?.cancel();
      _statusSub = device.connectionState.listen(_onConnectionState);

      _setStatus(BleLinkStatus.ready);
    } catch (e) {
      _fail('No se pudo conectar: $e', BleFailure.other);
    }
  }

  Future<bool> requestConfig() => send(AppCommand.getConfig);

  /// Mantiene vivo el watchdog del firmware. Hay que llamarlo cada pocos
  /// segundos mientras haya una secuencia en curso.
  Future<bool> ping() => send(AppCommand.ping);

  Future<BluetoothCharacteristic?> _findCharacteristic(
    BluetoothDevice device,
    Guid uuid,
  ) async {
    final services = await device.discoverServices();
    for (final service in services) {
      if (service.uuid != BleUuids.service) continue;
      for (final c in service.characteristics) {
        if (c.uuid == uuid) return c;
      }
    }
    return null;
  }

  void _onConnectionState(BluetoothConnectionState state) {
    if (state == BluetoothConnectionState.connected) return;

    // Desconexion durante una secuencia: el firmware tambien aborta y vuelve
    // a reposo, pero la app tiene que enterarse para avisar.
    _txSub?.cancel();
    _txSub = null;
    _statusSub?.cancel();
    _statusSub = null;
    _rx = null;
    _tx = null;
    _setStatus(BleLinkStatus.disconnected, failure: BleFailure.none);
  }

  void _onTxValue(List<int> bytes) {
    final AppEvent? event = AppEvent.decode(utf8.decode(bytes, allowMalformed: true));
    if (event == null) {
      debugPrint('[ble] evento ilegible: ${utf8.decode(bytes, allowMalformed: true)}');
      return;
    }
    if (event.kind == AppEventKind.unknown) {
      debugPrint('[ble] evento desconocido: $event');
      return;
    }
    _events.add(event);
  }

  // -------------------------------------------------------------------------

  /// Envia un comando. Devuelve false si no hay conexion.
  ///
  /// El `seq` se incrementa aca y nunca se reenvia el mismo: el firmware
  /// descarta los duplicados.
  Future<bool> send(AppCommand cmd, {int? seqOverride}) async {
    final rx = _rx;
    if (rx == null || _status != BleLinkStatus.ready) return false;

    _seq = _seq >= 65535 ? 1 : _seq + 1;
    final command = Command(cmd, seqOverride ?? _seq);
    try {
      await rx.write(command.encode(), withoutResponse: false);
      return true;
    } catch (e) {
      _fail('No se pudo enviar la orden: $e', BleFailure.other);
      return false;
    }
  }

  /// Pide la configuracion actual. La respuesta llega por el stream de eventos.
  Future<bool> requestConfig() => send(AppCommand.getConfig);

  /// Mantiene vivo el watchdog del firmware. Hay que llamarlo cada pocos
  /// segundos mientras haya una secuencia en curso.
  Future<bool> ping() => send(AppCommand.ping);

  // -------------------------------------------------------------------------

  Future<void> disconnect() async {
    await _txSub?.cancel();
    _txSub = null;
    await _statusSub?.cancel();
    _statusSub = null;
    try {
      await _device?.disconnect();
    } catch (_) {
      // Ignorado: desconectar un dispositivo ya desconectado no es un error.
    }
    _device = null;
    _rx = null;
    _tx = null;
    _setStatus(BleLinkStatus.disconnected);
  }

  void _fail(String message, BleFailure failure) {
    _lastError = message;
    _status = BleLinkStatus.error;
    _failure = failure;
    notifyListeners();
  }

  void _setStatus(BleLinkStatus s, {BleFailure failure = BleFailure.none}) {
    _status = s;
    _failure = failure;
    if (s != BleLinkStatus.error) _lastError = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _txSub?.cancel();
    _statusSub?.cancel();
    _events.close();
    super.dispose();
  }
}
