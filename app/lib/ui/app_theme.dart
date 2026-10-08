import 'package:flutter/material.dart';

/// Tema de la app ManejIA - Edición Dashboard Domótico / Hardware IoT.
///
/// Combina alta accesibilidad para adultos mayores (tipografía grande >= 16px,
/// botones de 56 px táctiles) con una estética de panel de control domótico
/// de grado de ingeniería:
///
///   * [light] -> Panel de instrumentación técnico claro, alto contraste y legible.
///   * [dark]  -> Consola oscura IoT de alta fidelidad, con acentos neón y lectura tipo HUD.
class AppTheme {
  const AppTheme._();

  /// Rojo/naranja del modo claro.
  static const Color seedLight = Color(0xFFD9480F);

  /// Naranja de acento en modo oscuro.
  static const Color seedDark = Color(0xFFF97316);

  /// Acento cian tecnológico del modo oscuro (BLE / Telemetría).
  static const Color techCyan = Color(0xFF06B6D4);

  /// Azul de apoyo del modo oscuro.
  static const Color accentDark = Color(0xFF3B82F6);

  /// Acento ámbar para advertencias de hardware / calibración.
  static const Color amberAccent = Color(0xFFF59E0B);

  /// Indicadores de estado LED (compatibles con `const` en la UI).
  static const Color warn = Color(0xFFEF4444);
  static const Color ok = Color(0xFF10B981);

  static ThemeData light() => _base(_lightScheme(), Brightness.light);

  static ThemeData dark() => _base(_darkScheme(), Brightness.dark);

  static ColorScheme _lightScheme() {
    final scheme = ColorScheme.fromSeed(seedColor: seedLight);
    return scheme.copyWith(
      // Superficie limpia estilo instrumentación de laboratorio
      surface: const Color(0xFFF8FAFC),
      surfaceContainerLowest: const Color(0xFFFFFFFF),
      surfaceContainerLow: const Color(0xFFF1F5F9),
      surfaceContainer: const Color(0xFFE2E8F0),
      surfaceContainerHigh: const Color(0xFFCBD5E1),
      surfaceContainerHighest: const Color(0xFF94A3B8),
      primary: const Color(0xFFC2410C),
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFFFEDD5),
      onPrimaryContainer: const Color(0xFF7C2D12),
      secondary: const Color(0xFF0284C7),
      secondaryContainer: const Color(0xFFE0F2FE),
      onSecondaryContainer: const Color(0xFF0369A1),
      tertiary: const Color(0xFF0F766E),
      error: const Color(0xFFDC2626),
      outline: const Color(0xFF94A3B8),
      outlineVariant: const Color(0xFFE2E8F0),
    );
  }

  static ColorScheme _darkScheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedDark,
      brightness: Brightness.dark,
    );
    return scheme.copyWith(
      // Consola de operaciones IoT en negro grafito / obsidiana
      surface: const Color(0xFF060911),
      surfaceContainerLowest: const Color(0xFF030509),
      surfaceContainerLow: const Color(0xFF0D1424),
      surfaceContainer: const Color(0xFF131D33),
      surfaceContainerHigh: const Color(0xFF1B2844),
      surfaceContainerHighest: const Color(0xFF243456),
      primary: seedDark,
      onPrimary: const Color(0xFF2E0D00),
      primaryContainer: const Color(0xFF7C2D12),
      onPrimaryContainer: const Color(0xFFFFDCC4),
      secondary: techCyan,
      onSecondary: const Color(0xFF002029),
      secondaryContainer: const Color(0xFF0E3846),
      onSecondaryContainer: const Color(0xFFA5F3FC),
      tertiary: const Color(0xFF38BDF8),
      error: const Color(0xFFF87171),
      outline: const Color(0xFF334768),
      outlineVariant: const Color(0xFF1C273C),
    );
  }

  static ThemeData _base(ColorScheme scheme, Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      // Gran tamaño de fuente para máxima legibilidad y ergonomía
      textTheme: const TextTheme(
        displaySmall: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: -0.5),
        headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.3),
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        bodyLarge: TextStyle(fontSize: 18),
        bodyMedium: TextStyle(fontSize: 16),
        labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          color: scheme.onSurface,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          side: BorderSide(color: scheme.outline, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant, width: 1.2),
        ),
      ),
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant),
    );
  }
}