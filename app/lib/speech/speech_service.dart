/// Reconocimiento de voz.
///
/// Envuelve `speech_to_text` y devuelve TODAS las hipotesis que da el
/// reconocedor, no solo la mejor. Android produce varias alternativas y
/// probarlas todas sube la tasa de acierto sin coste para la persona.
///
/// El idioma queda fijado a `es-ES` porque el lexicon esta escrito para
/// espanol de Espana. Ojo: en el lexicon hay una entrada para Mexico
/// ("abrir" con prenosis de 'j') que no viene del modelo sino de una
/// ortografia alternativa, no de un acento.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechService extends ChangeNotifier {
  SpeechService({SpeechToText? engine, this.localeId = 'es_ES'})
      : _engine = engine ?? SpeechToText();

  final SpeechToText _engine;
  final String localeId;

  bool _available = false;
  bool get isAvailable => _available;

  String _status = 'Sin inicializar';
  String get statusMessage => _status;

  /// `true` mientras el motor esta escuchando de verdad.
  bool _listening = false;
  bool get isListening => _listening;

  bool _initializing = false;
  bool get isInitializing => _initializing;

  final StreamController<List<String>> _results =
      StreamController<List<String>>.broadcast();

  /// Listas de hipotesis, de mejor a peor. Puede llegar mas de una por turno.
  Stream<List<String>> get results => _results.stream;

  /// Ultima lista de hipotesis, para mostrar el texto reconocido.
  List<String> _lastHypotheses = const <String>[];
  List<String> get lastHypotheses => _lastHypotheses;

  /// Error de la ultima invocacion, si hubo.
  String? _lastError;
  String? get lastError => _lastError;

  // -------------------------------------------------------------------------

  Future<bool> initialize() async {
    if (_available) return true;
    _initializing = true;
    _lastError = null;
    notifyListeners();

    try {
      _available = await _engine.initialize(
        onError: (e) {
          _lastError = e.errorMsg;
          _listening = false;
          notifyListeners();
        },
        onStatus: (s) {
          _status = s;
          _listening = s == 'listening';
          notifyListeners();
        },
      );
      _status = _available ? 'Listo' : 'No disponible';
      if (!_available) {
        _lastError = 'El motor de voz no se pudo iniciar en este dispositivo';
      }
    } catch (e) {
      _available = false;
      _lastError = 'Error al iniciar el reconocedor: $e';
      _status = 'Error';
    } finally {
      _initializing = false;
      notifyListeners();
    }
    return _available;
  }

  // -------------------------------------------------------------------------

  /// Empieza a escuchar. Devuelve `false` si no se pudo, para que la UI pueda
  /// avisar en vez de quedarse esperando en silencio.
  Future<bool> listen() async {
    _lastError = null;
    if (!_available && !await initialize()) return false;
    if (_listening) return true;

    try {
      final ok = await _engine.listen(
        onResult: _onResult,
        // Corto: la persona habla una orden corta. Escuchar mas tiempo solo
        // capta ruido y hace mas lenta la respuesta.
        listenFor: const Duration(seconds: 6),
        pauseFor: const Duration(seconds: 3),
        localeId: localeId,
        listenOptions: SpeechListenOptions(
          partialResults: false,
          // Con ondevice=false el motor usa la red. En un sitio sin datos la
          // app se queda muda, asi que se deja que el sistema decida.
          onDevice: false,
        ),
      );
      _listening = ok;
      if (!ok) {
        _lastError = 'No se pudo iniciar el microfono. Revisa el permiso.';
      }
      notifyListeners();
      return ok;
    } catch (e) {
      _lastError = 'No se pudo acceder al microfono: $e';
      _listening = false;
      notifyListeners();
      return false;
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!result.finalResult) return;
    stop();

    final hypotheses = result.recognitionResult
        .where((s) => s.trim().isNotEmpty)
        .toList(growable: false);
    if (hypotheses.isEmpty) {
      _lastHypotheses = const <String>[];
      _results.add(const <String>[]);
      notifyListeners();
      return;
    }

    _lastHypotheses = hypotheses;
    notifyListeners();
    _results.add(hypotheses);
  }

  Future<void> stop() async {
    if (!_listening) return;
    await _engine.stop();
    _listening = false;
    notifyListeners();
  }

  Future<void> cancel() async {
    await _engine.cancel();
    _listening = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _engine.cancel();
    _results.close();
    super.dispose();
  }
}
