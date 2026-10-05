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

/// MTU que se pide al ESP32.
///
/// Android arranca en 23 (solo 20 bytes utiles) y NO negocia solo. El
/// contrato de PROTOCOL.md fija 240 bytes de carga con MTU 247, asi que hay
/// que pedirlo explicitamente o el enlace se rompe en el primer comando.
const int kPreferredMtu = 247;

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

class DiscoveredDevice {
  const DiscoveredDevice({
    required this.device,
    required this.rssi,
    required this.compatible,
  });

  final BluetoothDevice device;
  final int rssi;
  final bool compatible;
}

class BleLink extends ChangeNotifier {
  BleLink({this.scanDuration = const Duration(seconds: 10)});

  final Duration scanDuration;

  final List<DiscoveredDevice> _found = <DiscoveredDevice>[];

  /// Todo lo que se ve al escanear, los compatibles primero y ordenado por
  /// senal. Incluye dispositivos ajenos a proposito: si el ESP32 no anuncia
  /// bien su UUID de servicio, seguiria apareciendo y se puede diagnosticar.
  List<DiscoveredDevice> get foundDevices {
    final sorted = List<DiscoveredDevice>.of(_found);
    sorted.sort((a, b) {
      if (a.compatible != b.compatible) return a.compatible ? -1 : 1;
      return b.rssi.compareTo(a.rssi);
    });
    return List.unmodifiable(sorted);
  }

  BluetoothDevice? _device;
  BluetoothCharacteristic? _rx;
  BluetoothCharacteristic? _tx;

  StreamSubscription<List<int>>? _txSub;
  StreamSubscription<BluetoothConnectionState>? _statusSub;

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
      await FlutterBluePlus.setLogLevel(LogLevel.warning, color: false);
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
      final supported = await FlutterBluePlus.isSupported;
      if (supported) {
        await FlutterBluePlus.turnOn();
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

  /// Un dispositivo sirve si anuncia nuestro servicio o si se llama como
  /// cualquiera de los dos prefijos que ha usado el proyecto.
  static bool isCompatible(ScanResult r) {
    if (r.advertisementData.serviceUuids.contains(BleUuids.service)) return true;
    final name = r.advertisementData.advName;
    return name.startsWith(BleUuids.namePrefix) ||
        name.startsWith('ManejIA');
  }

  Future<void> scan() async {
    if (!await ensureBluetoothOn()) return;

    _found.clear();
    _setStatus(BleLinkStatus.scanning);

    final sub = FlutterBluePlus.onScanResults.listen(_onScanResult);
    try {
      // Sin filtro de servicio a proposito: el firmware de produccion no
      // anuncia el UUID y con withServices la lista salia vacia sin decir
      // por que. El filtrado compatible lo hace isCompatible() en cliente.
      await FlutterBluePlus.startScan(timeout: scanDuration);
    } finally {
      await sub.cancel();
      if (_status == BleLinkStatus.scanning) {
        _setStatus(BleLinkStatus.disconnected);
      }
    }
  }

  void _onScanResult(List<ScanResult> results) {
    for (final r in results) {
      if (_found.any((d) => d.device.remoteId.str == r.device.remoteId.str)) {
        continue;
      }
      _found.add(DiscoveredDevice(
        device: r.device,
        rssi: r.rssi,
        compatible: isCompatible(r),
      ));
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
        timeout: const Duration(seconds: 10),
        // Obligatorio desde flutter_blue_plus 2.3.13. Este proyecto es personal
        // y sin animo de lucro, asi que declara nonprofit. Cambiar a
        // License.commercial si algun dia se usa en una empresa.
        license: License.nonprofit,
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

      // CRITICO: negociar el MTU. Sin esto Android se queda en el MTU por
      // defecto de 23 bytes, que solo admite 20 bytes de carga util: cualquier
      // comando del contrato ({"cmd":"get_config","seq":1} son 28) se rechaza
      // con "data longer than allowed", y el firmware trunca en silencio los
      // notify a 20 bytes. Pasar mtu en connect() tambien funciona, pero se
      // hace aparte para que un fallo de negociacion no tumbe la conexion.
      await _negotiateMtu(device);

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


  /// Pide un MTU grande y comprueba lo que quedo realmente negociado.
  ///
  /// Android NO negocia MTU por su cuenta: el valor se queda en 23 hasta que
  /// la app lo pide explicitamente. Un fallo aqui degrada el enlace pero no lo
  /// rompe, asi que se avisa por consola y se sigue.
  Future<void> _negotiateMtu(BluetoothDevice device) async {
    try {
      await device.requestMtu(kPreferredMtu);
      final negotiated = device.mtuNow;
      debugPrint('[ble] MTU negociado: $negotiated '
          '(${negotiated - 3} bytes de carga util)');
      if (negotiated < 64) {
        debugPrint('[ble] ATENCION: MTU bajo ($negotiated). Los comandos de más '
            'de ${negotiated - 3} bytes fallaran y el firmware truncara los '
            'eventos grandes.');
      }
    } catch (e) {
      debugPrint('[ble] no se pudo negociar el MTU: $e');
    }
  }

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

  /// Envia un comando basico por [cmd]. Devuelve false si no hay conexion.
  Future<bool> send(AppCommand cmd, {int? seqOverride}) {
    return sendCommand(
      Command(
        cmd,
        seqOverride ?? (_seq >= 65535 ? 1 : _seq + 1),
      ),
      incrementSeq: seqOverride == null,
    );
  }

  /// Envia un [Command] completo (incluyendo posibles parametros como pressUs, etc).
  Future<bool> sendCommand(Command command, {bool incrementSeq = true}) async {
    final rx = _rx;
    if (rx == null || _status != BleLinkStatus.ready) return false;

    if (incrementSeq) {
      _seq = command.seq;
    }

    try {
      await rx.write(utf8.encode(command.encode()), withoutResponse: false);
      return true;
    } catch (e) {
      _fail('No se pudo enviar la orden: $e', BleFailure.other);
      return false;
    }
  }

  /// Pide la configuracion actual. La respuesta llega por el stream de eventos.
  Future<bool> requestConfig() => send(AppCommand.getConfig);

  /// Guarda una nueva configuracion en la NVS del dispositivo.
  Future<bool> saveConfig({
    required int pressUs,
    required int restUs,
    int? minUs,
    int? maxUs,
    int? holdMs,
  }) {
    final nextSeq = _seq >= 65535 ? 1 : _seq + 1;
    return sendCommand(
      Command(
        AppCommand.saveConfig,
        nextSeq,
        pressUs: pressUs,
        restUs: restUs,
        minUs: minUs,
        maxUs: maxUs,
        holdMs: holdMs,
      ),
    );
  }

  /// Inicia el modo de calibracion/barrido en el servo.
  Future<bool> calibrate({String mode = 'sweep'}) {
    final nextSeq = _seq >= 65535 ? 1 : _seq + 1;
    return sendCommand(
      Command(
        AppCommand.calibrate,
        nextSeq,
        mode: mode,
      ),
    );
  }

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
