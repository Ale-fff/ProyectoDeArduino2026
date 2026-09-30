/// Permisos de plataforma.
///
/// Android 12+ (API 31) ya no concede BLUETOOTH_SCAN/BLUETOOTH_CONNECT al
/// instalar: sin pedirlo en tiempo de ejecucion, `startScan` falla en
/// silencio y la app parece que no ve ningun dispositivo. Por eso esto va
/// antes de cualquier escaneo, no en el arranque.
///
/// iOS es al reves: el permiso de Bluetooth NO se puede pedir por codigo.
/// Hay que enviar a la persona a Ajustes, y la unica manera de detectinglo es
/// mirar si el sistema devuelve un estado de tipo "desautorizado" en vez de
/// "denegado". Por eso `BleFailure.bluetoothPermissionDenied` lleva a una
/// instruccion en pantalla en vez de a otro intento automatico.
library;

import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  const PermissionService();

  bool get _isAndroid => Platform.isAndroid;
  bool get _isIOS => Platform.isIOS;

  /// Lo que hay que pedir antes de poder escanear.
  ///
  /// Devuelve una lista de permisos FALTANTES. Vacia significa que se puede
  /// seguir. El llamante decide que hacer: reintentar, o explicar.
  Future<List<String>> missingForScan() async {
    final List<String> missing = <String>[];

    if (_isAndroid) {
      // El permiso de microfono NO hace falta para escanear. Se pide en
      // listen(), no aqui, para no pedir microfono a alguien que solo quiere
      // conectar el actuador.
      if (!await Permission.bluetoothScan.isGranted) {
        if (await Permission.bluetoothScan.request() != PermissionStatus.granted) {
          missing.add('bluetooth_scan');
        }
      }
      if (!await Permission.bluetoothConnect.isGranted) {
        if (await Permission.bluetoothConnect.request() != PermissionStatus.granted) {
          missing.add('bluetooth_connect');
        }
      }
      // Android 11 y menos: el escaneo BLE se considera un sensor de
      // ubicacion. En API 31+ no hace falta y pedirlo confunde a la persona.
      if (!await Permission.bluetoothScan.isGranted && !_isAndroid12OrNewer) {
        if (await Permission.locationWhenInUse.request() != PermissionStatus.granted) {
          missing.add('location');
        }
      }
    }

    if (_isIOS) {
      // No hay nada que pedir por codigo. El estado se consulta para poder
      // distinguir "todavia no lo ha decidido" de "lo ha denegado para
      // siempre", que es lo que obliga a ir a Ajustes.
      final status = await Permission.bluetooth.request();
      if (status.isPermanentlyDenied || status.isRestricted) {
        missing.add('bluetooth_settings');
      }
    }

    return missing;
  }

  /// Permiso de microfono. Se pide al tocar el boton, no antes: pedirlo de
  /// entrada y que la persona lo deniegue deja la app inservible desde el
  /// primer arranque, y ademas el boton de la manija sigue funcionando.
  Future<bool> requestMicrophone() async {
    if (!_isAndroid && !_isIOS) return true;
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Reconocimiento de voz: en Android 13+ el motor de Google pide su propio
  /// permiso de reconocimiento de voz ademas del microfono.
  Future<bool> requestSpeechRecognition() async {
    if (!_isAndroid) return true;
    if (await Permission.speech.isGranted) return true;
    final status = await Permission.speech.request();
    return status.isGranted;
  }

  bool get _isAndroid12OrNewer {
    // AndroidVersion.VERSION_CODES.S
    final result = Platform.operatingSystemVersion;
    if (!result.contains('Android')) return true;
    final match = RegExp(r'Android\s+(\d+)').firstMatch(result);
    if (match == null) return true;
    return int.tryParse(match.group(1)!) != null &&
        int.parse(match.group(1)!) >= 12;
  }

  /// Texto para la persona cuando un permiso hay que cambiarlo a mano.
  static String instructionsFor(String missing) => switch (missing) {
        'bluetooth_scan' || 'bluetooth_connect' =>
          'Activa el permiso de Bluetooth para esta app en Ajustes.',
        'bluetooth_settings' =>
          'iOS no permite pedir este permiso desde la app. Abre Ajustes > '
              'Privacidad > Bluetooth y activa el acceso para esta app.',
        'location' =>
          'En este Android, buscar dispositivos Bluetooth necesita el permiso '
              'de ubicacion mientras la app esta abierta.',
        'microphone' =>
          'Sin microfono no hay comandos de voz. Activalo en Ajustes.',
        _ => 'Falta un permiso. Revisa los ajustes de la app.',
      };
}
