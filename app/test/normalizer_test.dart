import 'package:flutter_test/flutter_test.dart';
import 'package:puertavoz/speech/levenshtein.dart';
import 'package:puertavoz/speech/normalizer.dart';

void main() {
  const n = TextNormalizer();

  group('clean', () {
    test('pasa a minusculas y quita tildes', () {
      expect(n.clean('ÁBREME'), 'abreme');
      expect(n.clean('CIÉRRA'), 'cierra');
      expect(n.clean('POR FAVOR'), 'por favor');
    });

    test('quita la enie: "ñ" se trata como "n"', () {
      expect(n.clean('mañana'), 'manana');
    });

    test('quita puntuacion, signos y comillas', () {
      expect(n.clean('¡Ábreme la puerta, por favor!'), 'abreme la puerta por favor');
      expect(n.clean('¿Cierras la puerta?'), 'cierras la puerta');
      expect(n.clean('"abre"'), 'abre');
    });

    test('colapsa espacios multiples', () {
      expect(n.clean('abre   la    puerta'), 'abre la puerta');
    });

    test('texto vacio o sin letras queda vacio', () {
      expect(n.clean(''), '');
      expect(n.clean('   '), '');
      expect(n.clean('¿¿¿...!!!'), '');
    });
  });

  group('tokenize', () {
    test('parte en palabras', () {
      expect(n.tokenize('Abre la puerta'), ['abre', 'la', 'puerta']);
    });

    test('texto vacio da lista vacia', () {
      expect(n.tokenize(''), isEmpty);
    });
  });

  group('stripFiller', () {
    test('quita las palabras de cortesia', () {
      expect(n.stripFiller('abre la puerta por favor'), 'abre puerta');
      expect(n.stripFiller('oye puedes abrir la puerta gracias'), 'abrir puerta');
    });

    test('conserva los tokens semanticos que tambien son relleno', () {
      // "no" y "para" estan en la lista de relleno pero son ordenes.
      expect(n.stripFiller('no por favor'), 'no');
      expect(n.stripFiller('para ya'), 'para ya');
    });
  });

  group('significantTokens', () {
    test('descarta relleno pero conserva el significado', () {
      expect(n.significantTokens('por favor abre la puerta'), ['abre', 'puerta']);
      expect(n.significantTokens('oye puedes abrirme la puerta por favor'),
          ['abrirme', 'puerta']);
    });

    test('una frase que es solo relleno no deja tokens', () {
      expect(n.significantTokens('hola'), isEmpty);
      expect(n.significantTokens('buenos dias'), isEmpty);
    });

    test('un saludo seguido de una orden conserva la orden', () {
      expect(n.significantTokens('hola abre la puerta'), ['abre', 'puerta']);
    });
  });

  group('levenshtein', () {
    test('cadenas identicas dan 0', () {
      expect(levenshtein('abre', 'abre'), 0);
    });

    test('cadenas vacias', () {
      expect(levenshtein('', ''), 0);
      expect(levenshtein('', 'abre'), 4);
      expect(levenshtein('abre', ''), 4);
    });

    test('una insercion', () {
      expect(levenshtein('abre', 'abree'), 1);
    });

    test('una sustitucion', () {
      expect(levenshtein('abre', 'abre'), 0);
      expect(levenshtein('abre', 'abru'), 1);
    });

    test('casos conocidos', () {
      expect(levenshtein('kitten', 'sitting'), 3);
      expect(levenshtein('puerta', 'puerta'), 0);
      expect(levenshtein('flaw', 'lawn'), 2);
    });
  });

  group('similarity', () {
    test('identicas da 1.0', () {
      expect(similarity('abre', 'abre'), 1.0);
    });

    test('vacias da 1.0', () {
      expect(similarity('', ''), 1.0);
    });

    test('muy distintas da un valor bajo', () {
      expect(similarity('abre', 'puerta'), lessThan(0.5));
    });

    test('casi iguales da un valor alto', () {
      // 1 error de edicion sobre la palabra mas larga: 1 - 1/5 = 0.8 exacto.
      expect(similarity('abre', 'abree'), greaterThanOrEqualTo(0.8));
    });
  });
}
