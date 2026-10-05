/// Maquina de estados de la interaccion por voz.
///
/// Es la pieza que sostiene la seguridad del sistema, asi que no depende de
/// BLE ni de Flutter mas alla de `ChangeNotifier`: se puede probar entera.
///
/// ## Confirmacion: retirada
///
/// Antes `open` exigia un "si" explicito (se confirmaba lo que AUMENTA el
/// riesgo, se ejecutaba de inmediato lo que lo REDUCE). El usuario lo pidio
/// cambiar: tener la app abierta en la mano ya es la intencion, y el turno de
/// "di si" hacia la puerta mas lenta y mas frustrante de usar.
///
/// `IntentAction.needsVoiceConfirmation` devuelve `false` para todas las
/// acciones, asi que hoy [VoicePhase.pendingConfirm] no se alcanza. La maquina
/// se conserva intacta y probada: recuperar el comportamiento viejo es cambiar
/// una linea en `intent_lexer_es419.dart`.
///
/// Durante [VoicePhase.executing] el microfono queda COMPLETAMENTE apagado:
/// el ruido ambiente no puede disparar nada mientras el servo se mueve.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/protocol/protocol.dart';
import '../speech/intent_lexer_es419.dart';
import '../speech/intent_matcher.dart';

enum VoicePhase {
  /// Esperando que la persona toque el microfono.
  idle,

  /// Escuchando. Va directo a la accion, sin confirmar.
  listening,

  /// Escuchando la confirmacion de una accion que requiere "si".
  pendingConfirm,

  /// El servo se esta moviendo. Microfono apagado.
  executing,
}

/// Que se acaba de decidir hacer. La UI lo escucha y reacciona.
class VoiceDecision {
  const VoiceDecision.command(this.command)
      : outcome = VoiceOutcome.command,
        match = null,
        message = '';

  const VoiceDecision.askToRepeat(this.message)
      : outcome = VoiceOutcome.askToRepeat,
        command = null,
        match = null;

  const VoiceDecision.spoken(this.message)
      : outcome = VoiceOutcome.spoken,
        command = null,
        match = null;

  const VoiceDecision.error(this.message)
      : outcome = VoiceOutcome.error,
        command = null,
        match = null;

  final VoiceOutcome outcome;
  final Command? command;
  final IntentMatch? match;
  final String message;
}

enum VoiceOutcome {
  /// Hay que enviar [command] al ESP32.
  command,

  /// No se entendio: pedir que repita.
  askToRepeat,

  /// Solo hablar, sin tocar el hardware.
  spoken,

  /// Falla: falta conexion, calibracion, etc.
  error,
}

/// Frases de la app.
///
/// El usuario pidio que se hable solo del ESTADO DE LA PUERTA, abierta o
/// cerrada, y nada mas. Se fue el "actuador en reposo": suena a averia y no
/// dice nada que la persona no sepa.
///
/// Ojo con el formato, porque hay una trampa: el MG995 no reporta posicion y
/// el ESP32 no tiene sensor de puerta. "Cerrada" aqui significa "el servo
/// solto el pestillo", no "sensor confirme que la puerta esta cerrada". Quien
/// quiera el matiz exacto, vuelve al texto anterior.
class VoiceStrings {
  const VoiceStrings._();

  static const askOpen = 'Voy a abrir la puerta. Di "si" para confirmar.';
  static const doneOpen = 'Puerta abierta.';
  static const doneClose = 'Puerta cerrada.';
  static const cancelled = 'Cancelado.';
  static const timedOut = 'No escuché respuesta. Cancelado.';
  static const repeat = 'No entendí. Repite, por favor.';
  static const notConnected = 'No hay dispositivo conectado.';
  static const notCalibrated =
      'El actuador no está calibrado. Hay que calibrarlo primero.';
  static const stall = 'El actuador no se movió. Revisa si algo está trabado.';
  static const lowBattery = 'La batería está baja. Recarga el actuador.';
  static const stopped = 'Actuador detenido.';
  static const listening = 'Te escucho.';
}

class VoiceController extends ChangeNotifier {
  VoiceController({
    IntentMatcher? matcher,
    this.confirmWindow = const Duration(seconds: 8),
  }) : matcher = matcher ?? IntentMatcher();

  final IntentMatcher matcher;

  /// Tiempo para responder "si" antes de que se cancele solo.
  final Duration confirmWindow;

  VoicePhase _phase = VoicePhase.idle;
  VoiceDecision _lastDecision = const VoiceDecision.spoken('');
  IntentAction? _pendingAction;
  Timer? _confirmTimer;
  int _seq = 0;

  VoicePhase get phase => _phase;
  VoiceDecision get lastDecision => _lastDecision;
  IntentAction? get pendingAction => _pendingAction;

  /// El microfono solo puede escuchar en estas fases.
  bool get canListen =>
      _phase == VoicePhase.idle || _phase == VoicePhase.pendingConfirm;

  /// Texto que la UI debe mostrar como transcrito.
  String _transcript = '';
  String get transcript => _transcript;
  set transcript(String value) {
    _transcript = value;
    notifyListeners();
  }

  void reset() {
    _confirmTimer?.cancel();
    _confirmTimer = null;
    _pendingAction = null;
    _phase = VoicePhase.idle;
    _lastDecision = const VoiceDecision.spoken('');
    notifyListeners();
  }

  void beginListening() {
    if (_phase == VoicePhase.executing) return;
    _phase = VoicePhase.listening;
    _transcript = '';
    notifyListeners();
  }

  /// La UI llama a esto cuando el servo termina, para devolver el control.
  void onSequenceFinished() {
    if (_phase != VoicePhase.executing) return;
    _phase = VoicePhase.idle;
    _pendingAction = null;
    notifyListeners();
  }

  /// Recibe TODAS las hipotesis que devolvio el reconocedor de voz.
  ///
  /// Android entrega varias alternativas: probar todas es gratis y sube la
  /// tasa de acierto. Si la primera salio mal, la segunda puede ser
  /// exactamente la orden.
  void onSpeechResult(List<String> hypotheses) {
    if (hypotheses.isEmpty) return;
    _transcript = hypotheses.first;
    final match = matcher.matchBest(hypotheses);
    _dispatch(match);
  }

  void onSpeechError() {
    if (_phase == VoicePhase.pendingConfirm) {
      _cancel(VoiceStrings.repeat);
    } else if (_phase == VoicePhase.listening) {
      _decide(const VoiceDecision.askToRepeat(VoiceStrings.repeat));
    }
  }

  // -------------------------------------------------------------------------

  void _dispatch(IntentMatch match) {
    if (_phase == VoicePhase.executing) {
      // Microfono apagado a proposito: no se procesa nada.
      return;
    }

    if (!match.isConfident) {
      if (_phase == VoicePhase.pendingConfirm) {
        _cancel(VoiceStrings.repeat);
      } else {
        _decide(const VoiceDecision.askToRepeat(VoiceStrings.repeat));
      }
      return;
    }

    if (_phase == VoicePhase.pendingConfirm) {
      _handleConfirmation(match);
      return;
    }

    final action = match.action;

    if (action.needsVoiceConfirmation) {
      _askConfirmation(action);
      return;
    }

    // close y stop: execution inmediata, sin preguntar.
    _issue(action);
  }

  void _handleConfirmation(IntentMatch match) {
    switch (match.action) {
      case IntentAction.confirm:
        final action = _pendingAction;
        _confirmTimer?.cancel();
        _confirmTimer = null;
        _pendingAction = null;
        if (action != null) _issue(action);
      case IntentAction.cancel:
        _cancel(VoiceStrings.cancelled);
      case IntentAction.open:
        // La persona se impacienta y repite la orden: se vuelve a preguntar.
        _askConfirmation(IntentAction.open);
      case IntentAction.stop:
        // "alto" tiene que poder cortar la confirmacion pendiente y actuar ya.
        _confirmTimer?.cancel();
        _confirmTimer = null;
        _pendingAction = null;
        _issue(IntentAction.stop);
      case IntentAction.close:
        _confirmTimer?.cancel();
        _confirmTimer = null;
        _pendingAction = null;
        _issue(IntentAction.close);
      case IntentAction.none:
        _cancel(VoiceStrings.repeat);
    }
  }

  void _askConfirmation(IntentAction action) {
    _pendingAction = action;
    _phase = VoicePhase.pendingConfirm;
    _decide(const VoiceDecision.spoken(VoiceStrings.askOpen));

    _confirmTimer?.cancel();
    _confirmTimer = Timer(confirmWindow, () {
      _confirmTimer = null;
      _pendingAction = null;
      _phase = VoicePhase.idle;
      _decide(const VoiceDecision.spoken(VoiceStrings.timedOut));
    });
  }

  void _cancel(String message) {
    _confirmTimer?.cancel();
    _confirmTimer = null;
    _pendingAction = null;
    _phase = VoicePhase.idle;
    _decide(VoiceDecision.spoken(message));
  }

  /// Traduce una intencion en un comando y pasa a fase de ejecucion.
  void _issue(IntentAction action) {
    final AppCommand? cmd = switch (action) {
      IntentAction.open => AppCommand.open,
      IntentAction.close => AppCommand.close,
      IntentAction.stop => AppCommand.estop,
      // Un "si" suelto NO abre. Antes solo aparecia como respuesta a una
      // confirmacion y por eso podia mapearse a `open`. Sin confirmacion ya no
      // hay nada que confirmar, y dejarlo como "abre" convertiria un "si"
      // dicho al azar en una puerta abierta.
      IntentAction.confirm => null,
      IntentAction.cancel => null,
      IntentAction.none => null,
    };

    if (cmd == null) {
      _cancel(VoiceStrings.repeat);
      return;
    }

    _phase = VoicePhase.executing;
    _seq = _seq >= 65535 ? 1 : _seq + 1;
    _decide(VoiceDecision.command(Command(cmd, _seq)));
  }

  /// Error reportado por la capa de transporte. Devuelve el control a la
  /// persona con un mensaje util en vez de dejarla colgada.
  void onTransportError(String message) {
    _confirmTimer?.cancel();
    _confirmTimer = null;
    _pendingAction = null;
    _phase = VoicePhase.idle;
    _decide(VoiceDecision.error(message));
  }

  void _decide(VoiceDecision d) {
    _lastDecision = d;
    notifyListeners();
  }

  @override
  void dispose() {
    _confirmTimer?.cancel();
    super.dispose();
  }
}
