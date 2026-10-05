import 'package:flutter/material.dart';

/// Tema de la app.
///
/// Pensado para una persona mayor: tipografia grande, contrastes altos y
/// botones de 56 px como minimo, que es el objetivo tactil recomendado.
///
/// Dos identidades bien distintas, porque la app se usa de dia en la puerta y
/// de noche en el pasillo:
///
///   * [light] -> calido. Fondo crema, primario rojo/naranja. Es el modo por
///     defecto: el color calido invita a tocar y el servo se ve "vivo".
///   * [dark]  -> negro azulado con acento azul. No cansa la vista de noche y
///     el acento se aparta del rojo de "parado" para no confundirse con una
///     alarma.
///
/// Se arranca en [light] porque un modo oscuro surprises en un boton que abre
/// una puerta real. El usuario puede cambiarlo con el boton de la barra.
class AppTheme {
  const AppTheme._();

  /// Rojo/naranja del modo claro.
  static const Color seedLight = Color(0xFFD9480F);

  /// Naranja de acento en modo oscuro.
  static const Color seedDark = Color(0xFFF97316);

  /// Azul de apoyo del modo oscuro.
  static const Color accentDark = Color(0xFF3B82F6);

  // Se mantienen como constantes porque hay varios `const` en la UI. El valor
  // es un punto medio que se lee en los dos modos.
  static const Color warn = Color(0xFFE5484D);
  static const Color ok = Color(0xFF2F9E63);

  static ThemeData light() => _base(_lightScheme(), Brightness.light);

  static ThemeData dark() => _base(_darkScheme(), Brightness.dark);

  static ColorScheme _lightScheme() {
    final scheme = ColorScheme.fromSeed(seedColor: seedLight);
    return scheme.copyWith(
      // Crema en vez de blanco puro: cansa menos la vista durante el dia.
      surface: const Color(0xFFFFF8F2),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFFFF1E6),
      surfaceContainer: const Color(0xFFFDEADC),
      surfaceContainerHigh: const Color(0xFFF8E3D3),
      primary: const Color(0xFFC2410C),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFFFE2CC),
      onPrimaryContainer: const Color(0xFF5A1B00),
      secondary: const Color(0xFFB45309),
      secondaryContainer: const Color(0xFFFFEBC7),
      onSecondaryContainer: const Color(0xFF4A2A00),
      tertiary: const Color(0xFF9A3412),
      error: const Color(0xFFB3261E),
      outline: const Color(0xFF9C7A66),
      outlineVariant: const Color(0xFFEBD5C6),
    );
  }

  static ColorScheme _darkScheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedDark,
      brightness: Brightness.dark,
    );
    return scheme.copyWith(
      // Negro azulado, no gris neutro.
      surface: const Color(0xFF0A0F1A),
      surfaceContainerLowest: const Color(0xFF05080F),
      surfaceContainerLow: const Color(0xFF0E1420),
      surfaceContainer: const Color(0xFF141B29),
      surfaceContainerHigh: const Color(0xFF1B2434),
      surfaceContainerHighest: const Color(0xFF222D40),
      primary: seedDark,
      onPrimary: const Color(0xFF3B1500),
      primaryContainer: const Color(0xFF6B2C0C),
      onPrimaryContainer: const Color(0xFFFFDCC4),
      secondary: accentDark,
      onSecondary: const Color(0xFF00214A),
      secondaryContainer: const Color(0xFF1E3A6B),
      onSecondaryContainer: const Color(0xFFD3E2FF),
      tertiary: const Color(0xFF60A5FA),
      error: const Color(0xFFFFB4AB),
      outline: const Color(0xFF44506B),
      outlineVariant: const Color(0xFF2A3446),
    );
  }

  static ThemeData _base(ColorScheme scheme, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      // Minimo 16 px de cuerpo: por debajo la app deja de ser legible.
      textTheme: const TextTheme(
        displaySmall: TextStyle(fontSize: 36, fontWeight: FontWeight.w600),
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(fontSize: 18),
        bodyMedium: TextStyle(fontSize: 16),
        labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        // La barra ya lleva el color del fondo: sin tinte, los bordes de las
        // tarjetas se ven sueltos.
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          side: BorderSide(color: scheme.outline, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
    );
  }
}