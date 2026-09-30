/// Respuesta hablada de la app.
///
/// Aislada en su propia clase porque la UI nunca habla por su cuenta: siempre
/// pasa por [TtsService], y asi el texto audible queda en un solo sitio
/// auditable.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  TtsService({FlutterTts? engine, this.localeId = 'es-ES'})
      : _engine = engine ?? FlutterTts();

  final FlutterTts _engine;
  final String localeId;

  bool _ready = false;
  bool get isReady => _ready;

  Future<void> initialize() async {
    if (_ready) return;
    try {
      await _engine.setLanguage(localeId);
      // En iOS, sin esto la primera frase se come casi entera mientras
      // "despierta" el motor.
      await _engine.awaitSpeakCompletion(false);
      _engine.setCompletionHandler(_noop);
      _ready = true;
    } catch (e) {
      debugPrint('[tts] no se pudo inicializar: $e');
      _ready = false;
    }
  }

  void _noop() {}

  /// Habla un texto. Si el motor falla, la app sigue funcionando: el mensaje
  /// tambien esta en pantalla. Un TTS caido nunca debe ser un error fatal.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await initialize();
    if (!_ready) return;
    try {
      await _engine.stop();
      await _engine.speak(text);
    } catch (e) {
      debugPrint('[tts] fallo al hablar: $e');
    }
  }

  /// Corta lo que estuviera diciendo. Se llama al tocar el microfono para que
  /// la app no se hable encima de la persona.
  Future<void> stop() async {
    if (!_ready) return;
    try {
      await _engine.stop();
    } catch (_) {
      // Ignorado.
    }
  }
}
