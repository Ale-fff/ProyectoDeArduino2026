import 'package:flutter_test/flutter_test.dart';
import 'package:puertavoz/core/voice_controller.dart';
import 'package:puertavoz/data/protocol/protocol.dart';
import 'package:puertavoz/speech/intent_lexer_es419.dart';

void main() {
  late VoiceController v;

  setUp(() {
    v = VoiceController(confirmWindow: const Duration(seconds: 8));
  });

  tearDown(() => v.dispose());

  AppCommand? issuedCommand() {
    final d = v.lastDecision;
    return d.outcome == VoiceOutcome.command ? d.command!.cmd : null;
  }

  group('abrir exige confirmacion', () {
    test('"abre la puerta" solo pregunta, no mueve el servo', () {
      v.beginListening();
      v.onSpeechResult(<String>['abre la puerta']);

      expect(v.phase, VoicePhase.pendingConfirm);
      expect(issuedCommand(), isNull,
          reason: 'NUNCA se debe mover el servo sin un "si" explicito');
      expect(v.lastDecision.outcome, VoiceOutcome.spoken);
      expect(v.lastDecision.message, VoiceStrings.askOpen);
    });

    test('"si" confirma y emite open', () {
      v.beginListening();
      v.onSpeechResult(<String>['abre la puerta']);
      v.onSpeechResult(<String>['si']);

      expect(v.phase, VoicePhase.executing);
      expect(issuedCommand(), AppCommand.open);
      expect(v.lastDecision.command!.seq, greaterThan(0));
    });

    test('variantes de "si" tambien confirman', () {
      for (final ok in <String>['si', 'dale', 'claro', 'vale', 'ok', 'adelante', 'hecho']) {
        final c = VoiceController();
        c.beginListening();
        c.onSpeechResult(<String>['abre la puerta']);
        c.onSpeechResult(<String>[ok]);
        expect(c.lastDecision.outcome, VoiceOutcome.command,
            reason: '"$ok" deberia confirmar');
        expect(c.lastDecision.command!.cmd, AppCommand.open);
        c.dispose();
      }
    });
  });

  group('cancelar', () {
    test('"no" cancela y no emite nada', () {
      v.beginListening();
      v.onSpeechResult(<String>['abre la puerta']);
      v.onSpeechResult(<String>['no']);

      expect(v.phase, VoicePhase.idle);
      expect(issuedCommand(), isNull);
      expect(v.lastDecision.message, VoiceStrings.cancelled);
    });

    test('"olvidalo" tambien cancela', () {
      v.beginListening();
      v.onSpeechResult(<String>['abre la puerta']);
      v.onSpeechResult(<String>['olvidalo']);
      expect(issuedCommand(), isNull);
    });

    test('una frase que no se entiende cancela la confirmacion', () {
      // Es lo correcto: si no entendemos, no asumimos que queria decir "si".
      v.beginListening();
      v.onSpeechResult(<String>['abre la puerta']);
      v.onSpeechResult(<String>['que tiempo hace']);
      expect(v.phase, VoicePhase.idle);
      expect(issuedCommand(), isNull);
    });

    test('el timeout cancela solo', () {
      v = VoiceController(confirmWindow: const Duration(milliseconds: 50));
      v.beginListening();
      v.onSpeechResult(<String>['abre la puerta']);
      expect(v.phase, VoicePhase.pendingConfirm);

      return Future<void>.delayed(const Duration(milliseconds: 120), () {
        expect(v.phase, VoicePhase.idle);
        expect(issuedCommand(), isNull);
        expect(v.lastDecision.message, VoiceStrings.timedOut);
      });
    });
  });

  group('lo que reduce el riesgo se ejecuta de inmediato', () {
    test('"cierra la puerta" no pide confirmacion', () {
      v.beginListening();
      v.onSpeechResult(<String>['cierra la puerta']);

      expect(issuedCommand(), AppCommand.close);
      expect(v.phase, VoicePhase.executing);
    });

    test('"para" no pide confirmacion', () {
      v.beginListening();
      v.onSpeechResult(<String>['para']);
      expect(issuedCommand(), AppCommand.estop);
    });

    test('"alto" corta una confirmacion pendiente y actua ya', () {
      v.beginListening();
      v.onSpeechResult(<String>['abre la puerta']);
      expect(v.phase, VoicePhase.pendingConfirm);

      v.onSpeechResult(<String>['alto']);
      expect(issuedCommand(), AppCommand.estop,
          reason: 'una parada nunca debe quedar trabada en una confirmacion');
    });
  });

  group('microfono bloqueado durante la ejecucion', () {
    test('una orden durante la ejecucion se ignora', () {
      v.beginListening();
      v.onSpeechResult(<String>['abre la puerta']);
      v.onSpeechResult(<String>['si']);
      expect(v.phase, VoicePhase.executing);

      // Ruido ambiente o voz involuntary: no puede pasar nada.
      v.onSpeechResult(<String>['abre la puerta']);
      v.onSpeechResult(<String>['no']);

      expect(v.phase, VoicePhase.executing,
          reason: 'el microfono tiene que seguir apagado hasta onSequenceFinished');
      expect(issuedCommand(), AppCommand.open,
          reason: 'no se puede emitir un segundo comando encima del primero');
    });

    test('el microfono vuelve a estar disponible al terminar', () {
      v.beginListening();
      v.onSpeechResult(<String>['abre la puerta']);
      v.onSpeechResult(<String>['si']);
      v.onSequenceFinished();

      expect(v.phase, VoicePhase.idle);
      expect(v.canListen, isTrue);
    });
  });

  group('la persona se impacienta', () {
    test('repetir la orden vuelve a preguntar, no ejecuta', () {
      v.beginListening();
      v.onSpeechResult(<String>['abre la puerta']);
      v.onSpeechResult(<String>['abre la puerta']);
      v.onSpeechResult(<String>['abre']);

      expect(v.phase, VoicePhase.pendingConfirm);
      expect(issuedCommand(), isNull,
          reason: 'repetir la orden no es consentir');
      expect(v.lastDecision.message, VoiceStrings.askOpen);
    });
  });

  group('lo que no se entiende', () {
    test('pide repetir en vez de adivinar', () {
      v.beginListening();
      v.onSpeechResult(<String>['pon la musica']);

      expect(v.lastDecision.outcome, VoiceOutcome.askToRepeat);
      expect(issuedCommand(), isNull);
      expect(v.phase, VoicePhase.listening,
          reason: 'se puede seguir escuchando sin haber tenido exito');
    });

    test('usa la mejor de varias hipotesis', () {
      v.beginListening();
      v.onSpeechResult(<String>[
        'hola a todos',
        'el tiempo',
        'abre la puerta por favor',
      ]);
      expect(v.phase, VoicePhase.pendingConfirm);
    });
  });

  group('errores de transporte', () {
    test('dejan el control en manos de la persona', () {
      v.beginListening();
      v.onSpeechResult(<String>['abre la puerta']);
      v.onSpeechResult(<String>['si']);
      expect(v.phase, VoicePhase.executing);

      v.onTransportError(VoiceStrings.notConnected);
      expect(v.phase, VoicePhase.idle);
      expect(v.canListen, isTrue);
      expect(v.lastDecision.outcome, VoiceOutcome.error);
    });
  });

  group('los numeros de seq nunca se repiten', () {
    test('dos abres seguidos usan seq distintos', () {
      v.beginListening();
      v.onSpeechResult(<String>['abre la puerta']);
      v.onSpeechResult(<String>['si']);
      final first = v.lastDecision.command!.seq;

      v.onSequenceFinished();
      v.beginListening();
      v.onSpeechResult(<String>['abre la puerta']);
      v.onSpeechResult(<String>['si']);
      final second = v.lastDecision.command!.seq;

      expect(second, greaterThan(first),
          reason: 'el firmware descarta los seq repetidos');
    });
  });

  group('regla de confirmacion declarada', () {
    test('solo open la exige', () {
      expect(IntentAction.open.needsVoiceConfirmation, isTrue);
      expect(IntentAction.close.needsVoiceConfirmation, isFalse);
      expect(IntentAction.stop.needsVoiceConfirmation, isFalse);
      expect(IntentAction.confirm.needsVoiceConfirmation, isFalse);
      expect(IntentAction.cancel.needsVoiceConfirmation, isFalse);
    });
  });
}
