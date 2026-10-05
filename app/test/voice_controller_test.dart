import 'package:flutter_test/flutter_test.dart';
import 'package:puertavoz/core/voice_controller.dart';
import 'package:puertavoz/data/protocol/protocol.dart';
import 'package:puertavoz/speech/intent_lexer_es419.dart';

/// Un turno completo de voz contra un controlador concreto.
void utterOn(VoiceController c, String phrase) {
  c.beginListening();
  c.onSpeechResult(<String>[phrase]);
}

/// Pruebas de la maquina de voz.
///
/// La confirmacion se retiro a proposito: `open` ya no pide un "si". Los
/// grupos que cubren la confirmacion antigua se reescribieron para fijar el
/// comportamiento NUEVO, no para borrarlos.
///
/// Nota sobre la cobertura que ya no existe: `VoicePhase.pendingConfirm` es
/// inalcanzable por la API publica mientras `needsVoiceConfirmation` sea
/// `false`, asi que sus ramas (`_handleConfirmation`, el timeout) no tienen
/// pruebas. Siguen escritas y compiladas; si se reactiva la confirmacion hay
/// que recuperar esos tests.
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

  /// Atajo de la forma que ahora usa la persona: un toque, una frase, y ya.
  void utter(String phrase) => utterOn(v, phrase);

  group('abrir se ejecuta de inmediato', () {
    test('"abre la puerta" mueve el servo sin preguntar nada', () {
      utter('abre la puerta');

      expect(issuedCommand(), AppCommand.open);
      expect(v.phase, VoicePhase.executing);
      expect(v.lastDecision.command!.seq, greaterThan(0));
    });

    test('no hace falta un "si" detras', () {
      utter('abre la puerta');
      expect(issuedCommand(), AppCommand.open);
      expect(v.phase, VoicePhase.executing,
          reason: 'tiene que ejecutar en el primer turno, no quedarse esperando');
    });

    test('variantes de "abre" tambien ejecutan solas', () {
      for (final phrase in <String>[
        'abre',
        'abreme la puerta',
        'abre la puerta por favor',
      ]) {
        final c = VoiceController();
        c.beginListening();
        c.onSpeechResult(<String>[phrase]);
        expect(c.lastDecision.outcome, VoiceOutcome.command, reason: '"$phrase"');
        expect(c.lastDecision.command!.cmd, AppCommand.open, reason: '"$phrase"');
        c.dispose();
      }
    });

    test('un "si" suelto NO abre la puerta', () {
      // Sin confirmacion ya no hay nada que confirmar. Tratar "si" como
      // "abre" seria abrir la puerta por una respuesta a nada.
      for (final phrase in <String>['si', 'dale', 'claro', 'vale', 'adelante', 'hecho']) {
        final c = VoiceController();
        utterOn(c, phrase);
        expect(c.lastDecision.outcome, isNot(VoiceOutcome.command),
            reason: '"$phrase" no debe emitir ningun comando');
        expect(c.lastDecision.command, isNull, reason: '"$phrase"');
        c.dispose();
      }
    });
  });

  group('lo que se dice y no es una orden', () {
    test('"no" no emite nada', () {
      utter('no');

      expect(issuedCommand(), isNull);
      expect(v.phase, VoicePhase.idle);
    });

    test('"olvidalo" no emite nada', () {
      utter('olvidalo');
      expect(issuedCommand(), isNull);
    });

    test('"pon la musica" no mueve el servo', () {
      utter('pon la musica');

      expect(issuedCommand(), isNull);
      expect(v.lastDecision.outcome, VoiceOutcome.askToRepeat);
    });
  });

  group('cerrar y parar siguen siendo directos', () {
    test('"cierra la puerta"', () {
      utter('cierra la puerta');
      expect(issuedCommand(), AppCommand.close);
      expect(v.phase, VoicePhase.executing);
    });

    test('"para"', () {
      utter('para');
      expect(issuedCommand(), AppCommand.estop);
    });

    test('"alto"', () {
      utter('alto');
      expect(issuedCommand(), AppCommand.estop);
    });
  });

  group('microfono bloqueado durante la ejecucion', () {
    test('una orden durante la ejecucion se ignora', () {
      utter('abre la puerta');
      expect(v.phase, VoicePhase.executing);
      final first = v.lastDecision.command!.seq;

      // Ruido ambiente o voz involuntary: no puede pasar nada.
      utter('abre la puerta');
      utter('cierra la puerta');

      expect(v.phase, VoicePhase.executing,
          reason: 'el microfono tiene que seguir apagado hasta onSequenceFinished');
      expect(issuedCommand(), AppCommand.open,
          reason: 'no se puede emitir un segundo comando encima del primero');
      expect(v.lastDecision.command!.seq, first,
          reason: 'el seq del primer comando no debe cambiar');
    });

    test('el microfono vuelve a estar disponible al terminar', () {
      utter('abre la puerta');
      v.onSequenceFinished();

      expect(v.phase, VoicePhase.idle);
      expect(v.canListen, isTrue);
    });
  });

  group('repetir la orden', () {
    test('insiste hasta que se entienda y ejecuta una sola vez', () {
      utter('pon la musica');
      expect(issuedCommand(), isNull);

      utter('abre la puerta');
      expect(issuedCommand(), AppCommand.open);
      expect(v.phase, VoicePhase.executing);
    });
  });

  group('lo que no se entiende', () {
    test('pide repetir en vez de adivinar', () {
      utter('pon la musica');

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

      expect(issuedCommand(), AppCommand.open);
      expect(v.phase, VoicePhase.executing);
    });
  });

  group('errores de transporte', () {
    test('dejan el control en manos de la persona', () {
      utter('abre la puerta');
      expect(v.phase, VoicePhase.executing);

      v.onTransportError(VoiceStrings.notConnected);
      expect(v.phase, VoicePhase.idle);
      expect(v.canListen, isTrue);
      expect(v.lastDecision.outcome, VoiceOutcome.error);
    });
  });

  group('los numeros de seq nunca se repiten', () {
    test('dos abres seguidos usan seq distintos', () {
      utter('abre la puerta');
      final first = v.lastDecision.command!.seq;

      v.onSequenceFinished();
      utter('abre la puerta');
      final second = v.lastDecision.command!.seq;

      expect(second, greaterThan(first),
          reason: 'el firmware descarta los seq repetidos');
    });
  });

  group('frases de la puerta', () {
    test('se habla solo de abrir y cerrar, sin mencionar el actuador', () {
      // El usuario quito "Actuador en reposo" por confuso: no dice nada que la
      // persona no sepa. Estas pruebas son el candado para que no vuelva.
      expect(VoiceStrings.doneOpen.toLowerCase(), 'puerta abierta.');
      expect(VoiceStrings.doneClose.toLowerCase(), 'puerta cerrada.');

      for (final s in <String>[
        VoiceStrings.doneOpen,
        VoiceStrings.doneClose,
        VoiceStrings.repeat,
        VoiceStrings.notConnected,
      ]) {
        expect(s.toLowerCase(), isNot(contains('actuador')),
            reason: '"$s" no debe hablar del actuador');
        expect(s.toLowerCase(), isNot(contains('reposo')),
            reason: '"$s" no debe hablar de reposo');
      }
    });

    test('ninguna frase se alarga con instrucciones de pulsar', () {
      for (final s in <String>[
        VoiceStrings.doneOpen,
        VoiceStrings.doneClose,
      ]) {
        expect(s.toLowerCase(), isNot(contains('presiona')),
            reason: '"$s" no debe pedir hacer nada mas');
      }
    });
  });

  group('regla de confirmacion declarada', () {
    test('ninguna accion exige confirmacion', () {
      for (final action in IntentAction.values) {
        expect(action.needsVoiceConfirmation, isFalse,
            reason: '$action no debe pedir confirmacion');
      }
    });

    test('la maquina de confirmacion sigue disponible por si se reactiva', () {
      // No se borro el soporte: solo se dejo de usar. Si algun dia vuelve,
      // basta cambiar `needsVoiceConfirmation` en el lexico.
      expect(VoicePhase.values, contains(VoicePhase.pendingConfirm));
    });
  });
}