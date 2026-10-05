/// Interpreta el texto transcrito y decide que orden es.
///
/// Esta es la pieza donde fracasa la mayoria de los proyectos de voz: un
/// `if (texto == "abre")` no sobrevive ni una semana de uso real. La gente
/// dice "abrame la puerta por favor", "por favor abrir la puerta", "esta
/// abierta?", "abree"...
///
/// El algoritmo puntua cada grupo de sinonimos y gana el mejor:
///
///   1. Token exacto          -> 0.92
///   2. Prefijo compartido    -> 0.88  (abre / abriendo / abria)
///   3. Similitud difusa      -> 0.65 a 0.87, segun Levenshtein
///   +0.05 si aparece el objeto ('puerta')
///   Tope de 0.98
///
/// Por debajo de [threshold] el resultado es [IntentAction.none] y la app
/// pide repetir en vez de adivinar. Adivinar mal en un actuador de puerta no
/// es un bug de UX: es un problema de seguridad.
library;

import 'intent_lexer_es419.dart';
import 'levenshtein.dart';
import 'normalizer.dart';

/// Prefijo minimo compartido para dar por buena una coincidencia parcial.
/// Cuatro letras es el punto en que "abre" -> "abree" es claramente el mismo
/// verbo, y por encima del ruido de "si" -> "sino".
const int kMinPrefixLength = 4;

class IntentMatch {
  const IntentMatch.none()
      : action = IntentAction.none,
        score = 0,
        matchedOn = '';

  const IntentMatch({
    required this.action,
    required this.score,
    required this.matchedOn,
  });

  final IntentAction action;
  final double score;
  final String matchedOn;

  bool get isConfident => action != IntentAction.none;

  @override
  String toString() =>
      'IntentMatch(${action.label}, ${score.toStringAsFixed(2)}, "$matchedOn")';
}

class IntentMatcher {
  IntentMatcher({
    this.threshold = 0.65,
    this.stopCompetitionFloor = 0.85,
    List<PhraseGroup>? lexicon,
    this.normalizer = const TextNormalizer(),
  }) : _groups = lexicon ?? kEs419Lexicon;

  /// Piso de confianza. Bajo este valor preferimos no hacer nada.
  final double threshold;

  /// Si otra accion tambien apareció con al menos esta confianza, `stop` no
  /// gana. Resuelve "para abrir la puerta", donde `para` es preposicion: gana
  /// `open` (0.97) en lugar de `stop` (0.97). Con "para" a secas sigue
  /// ganndose `stop`, porque es un imperativo de parada legitimo.
  final double stopCompetitionFloor;

  final TextNormalizer normalizer;
  final List<PhraseGroup> _groups;

  /// Puntua un texto ya transcrito.
  IntentMatch match(String raw) {
    final tokens = normalizer.significantTokens(raw);
    if (tokens.isEmpty) return const IntentMatch.none();

    var best = const IntentMatch.none();
    var runnerUp = 0.0;

    for (final group in _groups) {
      final hit = _scoreGroup(group, tokens);
      if (hit.score > best.score) {
        runnerUp = best.score;
        best = hit;
      } else if (hit.score > runnerUp) {
        runnerUp = hit.score;
      }
    }

    if (best.action == IntentAction.stop &&
        runnerUp >= stopCompetitionFloor) {
      // Habia otra intencion real en la frase. Hay que reevaluar sin `stop`.
      return _bestExcluding(tokens, IntentAction.stop);
    }

    if (best.score < threshold) return const IntentMatch.none();
    return best;
  }

  IntentMatch _bestExcluding(List<String> tokens, IntentAction excluded) {
    var best = const IntentMatch.none();
    for (final group in _groups) {
      if (group.action == excluded) continue;
      final hit = _scoreGroup(group, tokens);
      if (hit.score > best.score) best = hit;
    }
    if (best.score < threshold) return const IntentMatch.none();
    return best;
  }

  /// Evalua TODAS las hipotesis que devuelve el reconocedor de voz y se
  /// queda con la mejor.
  ///
  /// Android entrega varias alternativas con su confianza. Probarlas todas es
  /// gratis y sube mucho la tasa de acierto: si la primera salio mal, la
  /// segunda puede ser exactamente "abre la puerta".
  IntentMatch matchBest(Iterable<String> hypotheses) {
    var best = const IntentMatch.none();
    for (final h in hypotheses) {
      final m = match(h);
      if (m.score > best.score) best = m;
    }
    return best;
  }

  // -------------------------------------------------------------------------

  IntentMatch _scoreGroup(PhraseGroup group, List<String> tokens) {
    var bestVerbScore = 0.0;
    var bestVerb = '';

    for (final verb in group.verbs) {
      final v = _cleanWord(verb);
      for (final token in tokens) {
        final s = _scoreToken(token, v);
        if (s > bestVerbScore) {
          bestVerbScore = s;
          bestVerb = token;
        }
      }
    }

    if (bestVerbScore <= 0) {
      return const IntentMatch.none();
    }

    // El objeto es una bonificacion, nunca un requisito: "abre" solo ya
    // significa "abre la puerta", porque solo hay una puerta.
    var score = bestVerbScore;
    final mentionsObject =
        group.objects.isNotEmpty && tokens.any(group.objects.contains);
    if (mentionsObject) score += 0.05;

    return IntentMatch(
      action: group.action,
      score: score.clamp(0.0, 0.98),
      matchedOn: bestVerb,
    );
  }

  double _scoreToken(String token, String verb) {
    if (token == verb) return 0.92;
    // Prefijo comun: "abre" contra "abree" o "abriendo", "cierra" contra
    // "cerrala".
    //
    // El verbo del lexico tiene que ser PREFIJO del token, no limitarse a
    // compartir los primeros caracteres. Compartir 4 letras hacia dos falsos
    // positivos muy molestos: "hace" contra "hacerlo" hacia que "que tiempo
    // hace" confirme, y "abrio" contra "abrir" hacia que "nadie me abrio" abra
    // la puerta. Los dos verbos existen en espanol y ninguno es una orden, asi
    // que la regla mira el final de la palabra, no su arranque.
    //
    // Sigue exigiendo al menos 4 caracteres. Sin ese minimo, "si" (2 letras)
    // emparejaria por prefijo con "sino", "silla" o "situado", y cualquier
    // palabra que empiece por 'no' o 'ya' se convertiria en una orden.
    if (verb.length >= kMinPrefixLength && token.startsWith(verb)) return 0.88;

    // Similitud difusa para el resto.
    final sim = similarity(token, verb);
    if (sim >= 0.82) {
      // 0.82 -> 0.65, 1.00 -> 0.87
      return 0.65 + ((sim - 0.82) / 0.18) * 0.22;
    }
    return 0;
  }

  /// Los verbos del lexico estan en minúsculas y sin tildes. Se limpian igual
  /// para que agregar "ciérrala" con tilde funcione sin THINK.
  String _cleanWord(String w) {
    final n = normalizer.clean(w);
    return n.isEmpty ? w : n;
  }
}
