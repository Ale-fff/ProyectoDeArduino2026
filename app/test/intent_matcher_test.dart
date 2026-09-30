import 'package:flutter_test/flutter_test.dart';
import 'package:puertavoz/speech/intent_lexer_es419.dart';
import 'package:puertavoz/speech/intent_matcher.dart';

void main() {
  final m = IntentMatcher();

  IntentAction act(String text) => m.match(text).action;
  double score(String text) => m.match(text).score;

  group('abrir la puerta', () {
    test('orden directa', () {
      expect(act('abre'), IntentAction.open);
      expect(act('abre la puerta'), IntentAction.open);
      expect(act('abrir la puerta'), IntentAction.open);
    });

    test('con cortesia alrededor', () {
      expect(act('por favor abre la puerta'), IntentAction.open);
      expect(act('oye por favor puedes abrirme la puerta'), IntentAction.open);
      expect(act('hola, abre la puerta'), IntentAction.open);
    });

    test('con tildes, mayusculas y puntuacion', () {
      expect(act('¡ÁBREME LA PUERTA!'), IntentAction.open);
      expect(act('¿Puedes abrir la puerta?'), IntentAction.open);
    });

    test('modismos latinoamericanos', () {
      expect(act('abreme'), IntentAction.open);
      expect(act('dejame entrar'), IntentAction.open);
      expect(act('suelta la puerta'), IntentAction.open);
    });

    test('formas verbales', () {
      expect(act('abriendo la puerta'), IntentAction.open);
      expect(act('abierta'), IntentAction.open);
    });

    test('error tipico de transcripcion', () {
      // El prefijo compartido cubre "abree" -> "abre".
      expect(act('abree la puerta'), IntentAction.open);
    });
  });

  group('cerrar la puerta', () {
    test('orden directa', () {
      expect(act('cierra'), IntentAction.close);
      expect(act('cierra la puerta'), IntentAction.close);
      expect(act('cerrar la puerta'), IntentAction.close);
    });

    test('con cortesia', () {
      expect(act('por favor cierra la puerta'), IntentAction.close);
    });

    test('modismo: empujar y salir', () {
      expect(act('empuja la puerta'), IntentAction.close);
      expect(act('salir'), IntentAction.close);
    });
  });

  group('confirmar', () {
    test('si y variantes', () {
      expect(act('si'), IntentAction.confirm);
      expect(act('sí'), IntentAction.confirm);
      expect(act('dale'), IntentAction.confirm);
      expect(act('claro'), IntentAction.confirm);
      expect(act('vale'), IntentAction.confirm);
      expect(act('ok'), IntentAction.confirm);
      expect(act('adelante'), IntentAction.confirm);
      expect(act('hecho'), IntentAction.confirm);
    });

    test('"si" no se confunde con palabras que empiezan igual', () {
      // Este es el motivo de minTokenLength = 2 en el grupo confirm.
      expect(act('sino te aviso'), isNot(IntentAction.confirm));
    });
  });

  group('cancelar', () {
    test('no y variantes', () {
      expect(act('no'), IntentAction.cancel);
      expect(act('nop'), IntentAction.cancel);
      expect(act('cancela'), IntentAction.cancel);
      expect(act('olvidalo'), IntentAction.cancel);
    });
  });

  group('parada', () {
    test('imperativos claros', () {
      expect(act('para'), IntentAction.stop);
      expect(act('alto'), IntentAction.stop);
      expect(act('detente'), IntentAction.stop);
      expect(act('emergencia'), IntentAction.stop);
      expect(act('auxilio'), IntentAction.stop);
    });
  });

  group('desempate de "para"', () {
    test('"para abrir" es abrir, no parar', () {
      // "para" da 0.97 en stop y "abrir" da 0.97 en open. Gana open porque
      // la frase contiene otra intencion real.
      expect(act('para abrir la puerta'), IntentAction.open);
    });

    test('"para cerrar" es cerrar, no parar', () {
      expect(act('para cerrar la puerta'), IntentAction.close);
    });

    test('"para" a secas sigue siendo parar', () {
      expect(act('para'), IntentAction.stop);
    });
  });

  group('lo que NO debe disparar nada', () {
    test('silencio', () {
      expect(m.match('').action, IntentAction.none);
      expect(m.match('   ').action, IntentAction.none);
    });

    test('conversacion ajena al proyecto', () {
      expect(act('que tiempo hace'), IntentAction.none);
      expect(act('pon la musica'), IntentAction.none);
      expect(act('llama a mi mama'), IntentAction.none);
    });

    test('solo relleno', () {
      expect(act('hola'), IntentAction.none);
      expect(act('buenos dias'), IntentAction.none);
    });

    test('palabras que contienen un verbo sin ser el verbo', () {
      // "nadie" contiene "die" y "abrio" se parece a "abrir", pero ninguno
      // es una orden: la app tiene que pedir que repita.
      expect(act('nadie me abrio'), IntentAction.none);
    });
  });

  group('umbral de confianza', () {
    test('una frase con score bajo devuelve none, no adivina', () {
      // "xyzzy" no esta en el lexico y no se parece a nada.
      final r = m.match('xyzzy qwerty');
      expect(r.action, IntentAction.none);
      expect(r.score, 0);
    });

    test('el score de una orden clara supera el umbral', () {
      expect(score('abre la puerta'), greaterThan(m.threshold));
      expect(score('si'), greaterThan(m.threshold));
    });

    test('con umbral mas alto, una orden debil deja de matchear', () {
      final estricto = IntentMatcher(threshold: 0.95);
      // "abree" puntua 0.93 (0.88 por prefijo + 0.05 por objeto).
      expect(estricto.match('abree la puerta').action, IntentAction.none);
      // "abre la puerta" puntua 0.97 y sigue entrando.
      expect(estricto.match('abre la puerta').action, IntentAction.open);
    });
  });

  group('matchBest sobre varias hipotesis del reconocedor', () {
    test('gana la mejor hipotesis aunque no sea la primera', () {
      final r = m.matchBest(<String>[
        'hola a todos',
        'abril la puerta',
        'abre la puerta por favor',
      ]);
      expect(r.action, IntentAction.open);
      expect(r.score, greaterThan(0.95));
    });

    test('si ninguna hipotesis sirve, devuelve none', () {
      final r = m.matchBest(<String>['hola', 'que dia es hoy']);
      expect(r.action, IntentAction.none);
    });
  });

  group('regla de confirmacion de la app', () {
    test('solo open exige confirmacion por voz', () {
      // La regla es simetrica: se confirma lo que sube el riesgo.
      expect(IntentAction.open.needsVoiceConfirmation, isTrue);
      expect(IntentAction.close.needsVoiceConfirmation, isFalse);
      expect(IntentAction.stop.needsVoiceConfirmation, isFalse);
      expect(IntentAction.cancel.needsVoiceConfirmation, isFalse);
    });
  });
}
