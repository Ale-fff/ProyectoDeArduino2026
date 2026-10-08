import 'package:flutter/material.dart';

import '../app_theme.dart';

/// Logo de ManejIA - Estilo Nodo Domótico IoT / Actuador BLE.
///
/// Dibujado en código vectorial mediante [CustomPainter] para nitidez perfecta
/// en cualquier resolución y adaptación automática al esquema de color activo.
///
/// Representa el mecanismo de la cerradura inteligente:
/// el módulo del actuador, la manija de puerta y las ondas de radiofrecuencia BLE 5.0.
class ManejIALogo extends StatelessWidget {
  const ManejIALogo({
    super.key,
    this.size = 96,
    this.tone,
    this.onTone,
    this.showBackground = true,
  });

  final double size;

  /// Color primario del actuador. Por defecto, el primario del tema.
  final Color? tone;

  /// Color de contraste de los componentes. Por defecto, blanco o primario según el fondo.
  final Color? onTone;

  /// Si incluye el chasis de fondo o solo el glifo.
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
      // Chasis externo del módulo IoT con bisel redondeado
      final bg = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, s, s),
        Radius.circular(s * 0.26),
      );

      // Degradado sutil con iluminación superior
      final bgPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color.lerp(tone, Colors.white, 0.28)!,
            tone,
            Color.lerp(tone, Colors.black, 0.22)!,
          ],
        ).createShader(Offset.zero & size);
      canvas.drawRRect(bg, bgPaint);

      // Borde exterior reflectante
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.02
        ..color = Colors.white.withValues(alpha: 0.35);
      canvas.drawRRect(bg, borderPaint);
    }

    // --- Puerta y bastidor del actuador ---
    final doorRect = Rect.fromLTWH(s * 0.24, s * 0.18, s * 0.32, s * 0.64);
    final doorPaint = Paint()..color = onTone;
    canvas.drawRRect(
      RRect.fromRectAndRadius(doorRect, Radius.circular(s * 0.06)),
      doorPaint,
    );

    // Ranura interna decorativa (detalle de panel arquitectónico)
    final slotPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.018
      ..color = tone.withValues(alpha: 0.4);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.27, s * 0.23, s * 0.26, s * 0.54),
        Radius.circular(s * 0.04),
      ),
      slotPaint,
    );

    // --- Eje del Servomotor y Cerrojo (Punto de rotación) ---
    final servoHub = Offset(s * 0.485, s * 0.52);

    // Anillo exterior del eje
    final hubRingPaint = Paint()..color = tone;
    canvas.drawCircle(servoHub, s * 0.052, hubRingPaint);

    // Núcleo brillante / LED de estado del actuador
    final hubLedPaint = Paint()..color = onTone;
    canvas.drawCircle(servoHub, s * 0.024, hubLedPaint);

    // --- Ondas de Telemetría BLE (Radiofrecuencia) ---
    final wavePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final waves = <(double, double, double)>[
      (0.12, 0.95, 0.055), // (radio, opacidad, grosor)
      (0.20, 0.65, 0.048),
      (0.28, 0.35, 0.040),
    ];

    for (final (radius, alpha, stroke) in waves) {
      wavePaint.color = onTone.withValues(alpha: alpha);
      wavePaint.strokeWidth = s * stroke;
      canvas.drawArc(
        Rect.fromCircle(center: servoHub, radius: s * radius),
        -0.85,
        1.70,
        false,
        wavePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.tone != tone || old.onTone != onTone || old.showBackground != showBackground;
}

/// Logo con tipografía integrada para la pantalla de bienvenida y barra superior.
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
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ManejIA',
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: scheme.onSurface,
              ),
            ),
            Text(
              'IoT BLE DOMOTICS',
              style: TextStyle(
                fontSize: fontSize * 0.32,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: AppTheme.techCyan,
              ),
            ),
          ],
        ),
      ],
    );
  }
}