import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Logo de ManejIA, dibujado en codigo.
///
/// No hay archivo de imagen en el repositorio, y un PNG obligaria a mantener
/// varias resoluciones para el splash, el launcher y la pantalla. Con un
/// [CustomPainter] el mismo logo sirve para los tres y ademas se recolorea
/// con el tema.
///
/// Lo que representa: una puerta con la manija retraida y las ondas de radio
/// saliendo por el lado de la bisagra. Es literalmente lo que hace el servo.
class ManejIALogo extends StatelessWidget {
  const ManejIALogo({
    super.key,
    this.size = 96,
    this.tone,
    this.onTone,
    this.showBackground = true,
  });

  final double size;

  /// Color de la puerta. Por defecto, el primario del tema.
  final Color? tone;

  /// Color de las ondas. Por defecto, el color de la puerta.
  final Color? onTone;

  /// Sin fondo, para ponerlo sobre una barra.
  final bool showBackground;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LogoPainter(
          tone: tone ?? scheme.primary,
          onTone: onTone ?? (showBackground ? scheme.onPrimary : scheme.primary),
          showBackground: showBackground,
        ),
      ),
    );
  }
}

class _LogoPainter extends CustomPainter {
  const _LogoPainter({
    required this.tone,
    required this.onTone,
    required this.showBackground,
  });

  final Color tone;
  final Color onTone;
  final bool showBackground;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;

    if (showBackground) {
      final bg = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, s, s),
        Radius.circular(s * 0.24),
      );
      canvas.drawRRect(
        bg,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color.lerp(tone, Colors.white, 0.18)!,
              tone,
            ],
          ).createShader(Offset.zero & size),
      );
    }

    // --- puerta ---
    final door = Rect.fromLTWH(s * 0.28, s * 0.20, s * 0.30, s * 0.60);
    final doorPaint = Paint()..color = onTone;
    canvas.drawRRect(
      RRect.fromRectAndRadius(door, Radius.circular(s * 0.05)),
      doorPaint,
    );

    // --- manija retráida: un hueco en el canto derecho de la puerta ---
    final knob = Offset(s * 0.485, s * 0.52);
    canvas.drawCircle(knob, s * 0.038, Paint()..color = tone);

    // --- ondas de radio ---
    final wave = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.055
      ..strokeCap = StrokeCap.round
      ..color = onTone;

    // Dos ondas concéntricas alrededor de la manija, openness hacia la
    // derecha, que es por donde "sale" la orden.
    for (final (radius, alpha) in <(double, double)>[(0.11, 0.85), (0.19, 0.45)]) {
      wave.color = onTone.withValues(alpha: alpha);
      canvas.drawArc(
        Rect.fromCircle(center: knob, radius: s * radius),
        -0.85,
        1.70,
        false,
        wave,
      );
    }
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.tone != tone || old.onTone != onTone || old.showBackground != showBackground;
}

/// El mismo logo, pero como palabra: onda + nombre.
///
/// Se usa en el splash, donde el logo solo queda pequeno.
class ManejIAWordmark extends StatelessWidget {
  const ManejIAWordmark({
    super.key,
    this.logoSize = 72,
    this.fontSize = 34,
  });

  final double logoSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        ManejIALogo(size: logoSize, tone: AppTheme.seedLight, onTone: Colors.white),
        const SizedBox(width: 14),
        Text(
          'ManejIA',
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}