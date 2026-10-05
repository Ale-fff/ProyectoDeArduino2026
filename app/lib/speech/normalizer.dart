/// Normalizacion de texto transcrito.
///
/// El reconocedor de voz devuelve cosas como
/// `"\u00bfAbrime la puerta, por favor!"`. Este archivo lo deja en tokens
/// limpios comparables: sin mayusculas, sin tildes, sin puntuacion y sin
/// las palabras de relleno que la gente mete al hablar.
library;

/// Mapa explicito en lugar de depender de NFD: asi el resultado es
/// identico en todas las plataformas y no hace falta ningun paquete extra.
const Map<int, int> _stripDiacritics = <int, int>{
  0x00E0: 0x0061, // a con acento grave
  0x00E1: 0x0061, // a con acento agudo
  0x00E2: 0x0061, // a circunflejo
  0x00E3: 0x0061, // a con tilde
  0x00E4: 0x0061, // a con dieresis
  0x00E5: 0x0061, // a con anillo
  0x00E7: 0x0063, // c cedilla
  0x00E8: 0x0065,
  0x00E9: 0x0065,
  0x00EA: 0x0065,
  0x00EB: 0x0065,
  0x00ED: 0x0069,
  0x00EE: 0x0069,
  0x00EF: 0x0069,
  0x00F1: 0x006E, // n con tilde
  0x00F2: 0x006F,
  0x00F3: 0x006F,
  0x00F4: 0x006F,
  0x00F5: 0x006F,
  0x00F6: 0x006F,
  0x00F8: 0x006F,
  0x00F9: 0x0075,
  0x00FA: 0x0075,
  0x00FB: 0x0075,
  0x00FC: 0x0075,
  0x00FD: 0x0079, // y con tilde
  0x00FF: 0x0079,
  0x00A1: 0x0021, // exclamacion inicial
  0x00BF: 0x003F, // interrogacion inicial
};

/// Palabras que no aportan al significado de una orden.
const Set<String> _fillerWords = <String>{
  // cortesia
  'por', 'favor', 'porfavor', 'favordemiquiera',
  'gracias',
  // llamado de atencion
  'oye', 'hey', 'eh', 'oiga', 'hola', 'buenos', 'buenas',
  'asista', 'atencion',
  // cortesia peticional
  'puedes', 'podrias', 'pudieras', 'quisieras', 'te', 'porfa',
  // relleno
  'me', 'mi', 'a', 'al', 'el', 'la', 'los', 'las', 'un', 'una', 'unos', 'unas',
  'de', 'del', 'y', 'o', 'u', 'e',
  // 'ok' y 'va' NO van aqui: 'ok' es sinonimo de confirmacion en el lexico y
  // 'va' forma parte de 'vamos'. Si se filtran antes de puntuar, nunca se
  // emparejan con su verbo.
  'ahora', 'ya', 'luego', 'entonces', 'bien',
  // saludos completos: "buenos dias", "buenas tardes"
  'dias', 'tardes', 'noches',
  'solito', 'solita',
};

/// Palabras que no deben eliminarse aunque esten en la lista de relleno.
///
/// La mayoria son ordenes: "no" cancela, "para" detiene. Las demas estan
/// porque la app se las muestra a la persona y quitarlas deja la pantalla
/// vacia: "ya" y "vamos" son las dos unicas palabras de la frase de
/// confirmacion que sobreviven, y son las que le dicen a la persona que si
/// la estamos escuchando.
const Set<String> _semanticTokens = <String>{
  'no',
  'para',
  'alto',
  'si',
  'vamos',
  'ya',
  'cierra',
  'abre',
  'abrir',
  'sube',
  'baja',
};

class TextNormalizer {
  const TextNormalizer();

  /// Texto completo en minusculas, sin tildes, sin puntuacion y con los
  /// espacios colapsados. NO elimina palabras de relleno.
  String clean(String raw) {
    var s = raw.toLowerCase();
    s = _removeDiacritics(s);
    // Cualquier cosa que no sea letra o digito se vuelve espacio: elimina
    // puntuacion, comillas, signos de exclamacion/interrogacion.
    s = s.replaceAll(RegExp('[^a-z0-9]+'), ' ');
    return s.replaceAll(RegExp('\\s+'), ' ').trim();
  }

  /// Tokens ya limpios, en minusculas y sin acentos.
  List<String> tokenize(String raw) {
    final cleaned = clean(raw);
    if (cleaned.isEmpty) return const <String>[];
    return cleaned.split(' ');
  }

  /// Texto limpio y ademas sin palabras de relleno.
  String stripFiller(String raw) {
    final tokens = tokenize(raw)
        .where((t) => !_fillerWords.contains(t) || _semanticTokens.contains(t))
        .toList();
    return tokens.join(' ');
  }

  /// Tokens de una orden util, sin relleno. Es lo que consume el matcher.
  List<String> significantTokens(String raw) {
    final cleaned = clean(raw);
    if (cleaned.isEmpty) return const <String>[];
    return cleaned
        .split(' ')
        .where((t) => t.isNotEmpty && (!_fillerWords.contains(t) || _semanticTokens.contains(t)))
        .toList();
  }

  String _removeDiacritics(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      buffer.writeCharCode(_stripDiacritics[rune] ?? rune);
    }
    return buffer.toString();
  }
}
