/// Clips de audio del proyecto.
///
/// La app usa la voz grabada de "Jorge" (Loquendo) en vez del TTS del sistema:
/// el TTS cambia de acento segun el movil y suena distinto en cada dispositivo,
/// mientras que un MP3 incluido en la app suena SIEMPRE igual.
///
/// ## Por que antes no sonaba
///
/// `audioplayers` resuelve los assets con un prefijo `assets/` por defecto
/// (`AudioCache.prefix`) y busca `assets/Audio/no_entendi.mp3`. El MP3 esta en
/// `app/Audio/`, o sea en la RAIZ de los assets. La busqueda fallaba, la
/// excepcion se comia en silencio dentro de `playClip` y no se oia nada.
///
/// Por eso [ensureConfigured] deja el prefijo vacio. Si algun dia se mueve la
/// carpeta `Audio/` dentro de `app/assets/`, hay que deshacer esto o volver a
/// poner el prefijo `assets/`.
///
/// ## Como se anade un clip
///
/// 1. Poner el `.mp3` en `app/Audio/`.
/// 2. Declararlo en `pubspec.yaml` bajo `assets:`.
/// 3. Anadir la constante aqui y, si quieres un texto de respaldo, su entrada
///    en [textFor].
///
/// El texto de respaldo se usa solo si el clip no se puede reproducir, para
/// que un archivo roto nunca deje a la persona sin voz.
library;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class Clips {
  const Clips._();

  /// Clip real que hay en el repositorio.
  static const notUnderstood = 'Audio/no_entendi.mp3';

  /// False mientras no se haya configurado [AudioCache].
  static bool _configured = false;

  /// Apunta el cache de audio a la raiz de los assets. Idempotente.
  static void ensureConfigured() {
    if (_configured) return;
    _configured = true;
    AudioCache.instance = AudioCache(prefix: '');
    debugPrint('[clips] cache de audio en la raiz de los assets');
  }

  /// Texto que se dice si el clip no se puede reproducir.
  static String? textFor(String asset) {
    ensureConfigured();
    return switch (asset) {
      notUnderstood => 'No he entendido. Repite, por favor.',
      _ => null,
    };
  }
}