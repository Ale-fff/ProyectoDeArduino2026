/// Salida de audio de la app.
///
/// Aislada en su propia clase porque la UI nunca habla por su cuenta: siempre
/// pasa por [TtsService], y asi lo audible queda en un solo sitio auditable.
///
/// Hay dos vias de sonido y conviene no confundirlas:
///
///   * [speak]   -> TTS, texto sintetizado.
///   * [playClip] -> MP3 grabado del propio proyecto.
///
/// Existe [playClip] por una razon concreta: `setLanguage('es-ES')` no garantiza
/// una voz espanola. Si el movil no tiene instalada ninguna voz `es-*`, Android
/// sintetiza el texto con su voz por defecto (inglesa) y el resultado es
/// castellano con acento inglesa. Para "no he entendido" el usuario pidio un
/// audio grabado, que ademas no depende de que haya voces instaladas.
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'clips.dart';

class TtsService {
  TtsService({
    FlutterTts? engine,
    AudioPlayer? clipPlayer,
    this.localeId = 'es-ES',
  })  : _engine = engine ?? FlutterTts(),
        _clips = clipPlayer ?? AudioPlayer();

  final FlutterTts _engine;
  final AudioPlayer _clips;
  final String localeId;

  bool _ready = false;
  bool get isReady => _ready;

  /// Voz que ha quedado seleccionada, solo para depurar.
  String? _voiceName;
  String? get voiceName => _voiceName;

  Future<void> initialize() async {
    if (_ready) return;
    try {
      await _engine.setLanguage(localeId);
      await _engine.awaitSpeakCompletion(false);
      _engine.setCompletionHandler(_noop);
      await _selectSpanishVoice();
      _ready = true;
    } catch (e) {
      debugPrint('[tts] no se pudo inicializar: $e');
      _ready = false;
    }
  }

  void _noop() {}

  /// Elige una voz realmente espanola entre las instaladas.
  ///
  /// Orden de preferencia:
  ///   1. region que coincide con la pedida (es-ES, es-ES...)
  ///   2. cualquier es-* (es-MX, es-US...)
  ///   3. la que ya tuviera el motor, si es espanola
  ///
  /// Si no hay ninguna voz espanola se deja `setLanguage` y se avisa: mejor un
  /// acento raro que quedarse sin voz.
  Future<void> _selectSpanishVoice() async {
    try {
      final dynamic raw = await _engine.getVoices;
      if (raw is! List) return;

      final voices = raw
          .whereType<Map>()
          .map((m) => <String, String>{
                'name': m['name']?.toString() ?? '',
                'locale': m['locale']?.toString() ?? '',
              })
          .where((v) => v['locale']!.toLowerCase().startsWith('es'))
          .toList();

      if (voices.isEmpty) {
        debugPrint('[tts] no hay voz es-* instalada: quedara el acento del '
            'idioma por defecto');
        return;
      }

      final wanted = localeId.toLowerCase().replaceAll('_', '-');
      voices.sort((a, b) => _score(b['locale']!, wanted) - _score(a['locale']!, wanted));

      final voice = voices.first;
      _voiceName = '${voice['name']} (${voice['locale']})';
      await _engine.setVoice(<String, String>{
        'name': voice['name']!,
        'locale': voice['locale']!,
      });
      debugPrint('[tts] voz seleccionada: $_voiceName');
    } catch (e) {
      debugPrint('[tts] no se pudo elegir voz espanola: $e');
    }
  }

  /// 2 si el idioma es exactamente el pedido, 1 si es otro es-*, 0 si no.
  static int _score(String locale, String wanted) {
    final l = locale.toLowerCase().replaceAll('_', '-');
    if (l == wanted) return 2;
    final language = l.split('-').first;
    if (language == wanted.split('-').first) return 1;
    return 0;
  }

  /// Habla un texto. Si el motor falla, la app sigue funcionando: el mensaje
  /// tambien esta en pantalla. Un TTS caido nunca debe ser un error fatal.
  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await initialize();
    if (!_ready) return;
    try {
      await _clips.stop();
      await _engine.stop();
      await _engine.speak(text);
    } catch (e) {
      debugPrint('[tts] fallo al hablar: $e');
    }
  }

  /// Reproduce un MP3 del proyecto. No depende del TTS ni de las voces
  /// instaladas, asi que es la via fiable para mensajes que siempre tienen que
  /// sonar bien.
  ///
  /// Si el clip falla (no existe, no se pudo leer) cae al TTS: es preferible
  /// sonar raro que no sonar nada.
  Future<void> playClip(String asset) async {
    Clips.ensureConfigured();
    try {
      await _engine.stop();
      await _clips.stop();
      await _clips.play(AssetSource(asset));
      debugPrint('[tts] clip: $asset');
    } catch (e) {
      debugPrint('[tts] fallo al reproducir $asset: $e');
      await speak(Clips.textFor(asset) ?? '');
    }
  }

  /// Atajo del mensaje de "no te he entendido".
  Future<void> speakNotUnderstood() => playClip(Clips.notUnderstood);

  Future<void> speakMessage(String clipAsset, String fallbackText) async {
    Clips.ensureConfigured();
    try {
      await _engine.stop();
      await _clips.stop();
      await _clips.play(AssetSource(clipAsset));
      debugPrint('[tts] clip: $clipAsset');
    } catch (e) {
      debugPrint('[tts] fallo al reproducir $clipAsset: $e');
      await speak(fallbackText);
    }
  }

  /// Corta lo que estuviera sonando, este o no TTS. Se llama al tocar el
  /// microfono para que la app no se hable encima de la persona.
  Future<void> stop() async {
    try {
      await _clips.stop();
    } catch (_) {
      // Ignorado.
    }
    if (!_ready) return;
    try {
      await _engine.stop();
    } catch (_) {
      // Ignorado.
    }
  }

  Future<void> dispose() async {
    try {
      await _clips.dispose();
    } catch (_) {
      // Ignorado.
    }
  }
}