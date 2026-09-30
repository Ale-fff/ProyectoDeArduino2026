/// Lexico de ordenes en espagnol latinoamericano (es-419).
///
/// Modismos incluidos a proposito: en Latinoamerica la gente dice "abreme" y
/// "cerrala" mucho mas que "abrirme" y "cierrala". Esta lista es el unico
/// lugar del proyecto donde se tocan las palabras: agregar un sinonimo aqui
/// no requiere tocar el matcher.
library;

/// Acciones que la app sabe interpretar.
enum IntentAction { none, open, close, confirm, cancel, stop }

extension IntentActionInfo on IntentAction {
  /// Nombre legible, para logs y tests.
  String get label => switch (this) {
        IntentAction.none => 'none',
        IntentAction.open => 'open',
        IntentAction.close => 'close',
        IntentAction.confirm => 'confirm',
        IntentAction.cancel => 'cancel',
        IntentAction.stop => 'stop',
      };

  /// La app solo pide confirmacion en voz para lo que lleva el servo a un
  /// estado NO seguro. `open` es la unica.
  ///
  /// La regla es simetrica: se confirma lo que AUMENTA el riesgo y se ejecuta
  /// de inmediato lo que lo REDUCE. Por eso `close` y `stop` no preguntan.
  bool get needsVoiceConfirmation => this == IntentAction.open;
}

/// Un grupo de sinonimos que comparten intencion.
class PhraseGroup {
  const PhraseGroup({
    required this.action,
    required this.verbs,
    this.objects = const <String>{},
  });

  final IntentAction action;

  /// Alternativas que identifican la accion. Al menos una tiene que aparecer.
  final List<String> verbs;

  /// Sustantivos que refinan la accion. Si alguno aparece sube el puntaje,
  /// pero su ausencia NO invalida el acierto: con una sola puerta, "abre"
  /// a secas ya significa "abre la puerta".
  final Set<String> objects;
}

/// Diccionario es-419.
///
/// Nota de diseno sobre 'para': es preposicion ("para abrir la puerta") y
/// tambien imperativo de parada ("para"). El matcher resuelve la ambiguedad
/// con una regla explicita y no con el orden de esta lista: `stop` solo gana
/// cuando ninguna otra accion tambien aparecio en la frase.
const List<PhraseGroup> kEs419Lexicon = <PhraseGroup>[
  PhraseGroup(
    action: IntentAction.open,
    verbs: <String>[
      'abre', 'abrir', 'abriendo', 'abierta', 'abierto',
      'abreme', 'abramos', 'abrirme', 'abriendome',
      'entra', 'entrar', 'entrando', 'dejame', 'dejarme',
      'suelta', 'suelte', 'libera', 'liberar',
    ],
    objects: <String>{'puerta', 'principal', 'entrada'},
  ),
  PhraseGroup(
    action: IntentAction.close,
    verbs: <String>[
      'cierra', 'cerrar', 'cerrando', 'cerrada', 'cerrado', 'cerrarla',
      'sal', 'salir', 'saliendo', 'fuera',
      'empuja', 'empujar', 'empujala',
    ],
    objects: <String>{'puerta', 'principal'},
  ),
  PhraseGroup(
    action: IntentAction.confirm,
    verbs: <String>[
      'si', 'dale', 'claro', 'correcto', 'exacto',
      'adelante', 'adelantate', 'vale', 'ok', 'okay',
      'hecho', 'hecha', 'confirmar', 'confirma', 'confirmo',
      'hazlo', 'hacerlo', 'vamos',
    ],
  ),
  PhraseGroup(
    action: IntentAction.cancel,
    verbs: <String>[
      'no', 'nop', 'nel', 'nunca', 'cancela', 'cancelar',
      'olvida', 'olvidalo', 'olvidar', 'deja', 'dejar', 'nanai',
    ],
  ),
  PhraseGroup(
    action: IntentAction.stop,
    verbs: <String>[
      'para', 'parar', 'parate', 'detente', 'detener', 'alto', 'stop',
      'emergencia', 'auxilio', 'urgente', 'basta', 'quieto', 'socorro',
    ],
  ),
];
