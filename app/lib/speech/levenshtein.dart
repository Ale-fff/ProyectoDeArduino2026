/// Distancia de Levenshtein y similitud normalizada.
///
/// Se usa para tolerar errores de transcripcion: "abrime" en vez de "abrirme",
/// "vrentan" en vez de "ventana", etc.
library;

int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var previous = List<int>.generate(b.length + 1, (i) => i, growable: false);
  var current = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    final ai = a.codeUnitAt(i - 1);

    for (var j = 1; j <= b.length; j++) {
      final cost = ai == b.codeUnitAt(j - 1) ? 0 : 1;
      final del = previous[j] + 1;
      final ins = current[j - 1] + 1;
      final sub = previous[j - 1] + cost;
      var best = del;
      if (ins < best) best = ins;
      if (sub < best) best = sub;
      current[j] = best;
    }

    final swap = previous;
    previous = current;
    current = swap;
  }

  return previous[b.length];
}

/// Similitud de 0.0 a 1.0. 1.0 es identico.
///
/// Se normaliza por la cadena mas larga, que es lo que corresponde cuando
/// comparamos un token contra un sinonimo de longitud parecida.
double similarity(String a, String b) {
  if (a == b) return 1.0;
  final maxLen = a.length > b.length ? a.length : b.length;
  if (maxLen == 0) return 1.0;
  return 1.0 - (levenshtein(a, b) / maxLen);
}
