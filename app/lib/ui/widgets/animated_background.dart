import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Fondo animado de la app.
///
/// El fondo NO es estatico, y cambia segun el tema:
///
///   * [Brightness.light] -> nubes que se desplazan HACIA LA DERECHA.
///   * [Brightness.dark]  -> estrellas que titilan y derivan muy despacio.
///
/// Se dibuja con un solo [CustomPainter] sobre el contenido, en lugar de un
/// monton de widgets animados: un `Stack` con N hijos reubicados por frame
/// obliga a Flutter a recomponer el arbol entero, mientras que un painter solo
/// repinta.
///
/// ### Coste
///
/// Es un fondo, no una animacion protagonista: se repinta a 60 fps pero solo
/// pinta circulos y rectangulos, y va dentro de un [RepaintBoundary] para que
/// el contenido de encima no se vuelva a construir.
///
/// Si el sistema pide reducir animacion (accesibilidad, ahorro de bateria),
/// se congela: el fondo se dibuja una vez y se queda quieto.
class AnimatedBackground extends StatefulWidget {
  const AnimatedBackground({super.key, required this.child});

  final Widget child;

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    // 40 s por vuelta: una nube tarda medio minuto en cruzar la pantalla, que
    // se nota sin llegar a distraer. Las estrellas van a 60 s.
    duration: const Duration(seconds: 40),
  )..repeat();

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce != _reduceMotion) {
      _reduceMotion = reduce;
      // Fuera del ciclo de build a proposito: `stop()` y `repeat()` notifican a
      // los listeners, y llamarlos durante el build daria "setState() called
      // during build".
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_reduceMotion) {
          _controller.stop();
        } else {
          _controller.repeat();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        // El fondo plano va debajo del painter: si el painter se repinta, el
        // color de base no se vuelve a pintar.
        ColoredBox(color: scheme.surface),
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final double t = _reduceMotion ? 0.0 : _controller.value;
              // Las listas se crean UNA vez y se reutilizan. Si el painter las
              // generara en su constructor se estarian creando 70 estrellas y
              // 7 nubes nuevas en cada uno de los 60 frames por segundo.
              return CustomPaint(
                painter: isDark
                    ? _StarsPainter(t: t, base: scheme.primary, ink: scheme.onSurface, stars: _stars)
                    : _CloudsPainter(t: t, ink: scheme.onSurface, clouds: _clouds),
                size: Size.infinite,
              );
            },
          ),
        ),
        widget.child,
      ],
    );
  }

  /// Posiciones fijas, generadas con semilla para que no "salten" de sitio.
  ///
  /// Se crean una sola vez y se pasan al painter. Si cada painter generase las
  /// suyas en el constructor, se construirian 70 estrellas y 7 nubes nuevas en
  /// cada uno de los 60 frames por segundo.
  late final List<_Star> _stars = _makeStars();
  late final List<_Cloud> _clouds = _makeClouds();

  List<_Star> _makeStars() {
    final rnd = math.Random(11);
    return List<_Star>.generate(70, (i) {
      return _Star(
        x: rnd.nextDouble(),
        y: rnd.nextDouble(),
        radius: 0.6 + rnd.nextDouble() * 1.5,
        phase: rnd.nextDouble() * math.pi * 2,
        // Periodos distintos: un mismo pulso para todas se ve como un
        // parpadeo general en vez de como cielo.
        twinkleSpeed: 0.5 + rnd.nextDouble() * 2.2,
        drift: 0.15 + rnd.nextDouble() * 0.5,
        bright: rnd.nextDouble() > 0.86,
      );
    });
  }

  List<_Cloud> _makeClouds() {
    final rnd = math.Random(7);
    return List<_Cloud>.generate(7, (i) {
      return _Cloud(
        y: 0.04 + rnd.nextDouble() * 0.88,
        scale: 0.55 + rnd.nextDouble() * 0.95,
        speed: 0.55 + rnd.nextDouble() * 0.75,
        offset: rnd.nextDouble(),
      );
    });
  }
}

/// Nubes que van hacia la derecha. Solo para el modo claro.
class _CloudsPainter extends CustomPainter {
  const _CloudsPainter({required this.t, required this.ink, required this.clouds});

  final double t;
  final Color ink;
  final List<_Cloud> clouds;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = ink.withValues(alpha: 0.07);

    for (final c in clouds) {
      final width = size.width * 0.42 * c.scale;
      final height = width * 0.44;

      // Recorrido: la nube entra por la izquierda y sale por la derecha. El
      // `+1` de ancho extra es para que no aparezca de golpe al aparecer.
      final travel = size.width + width;
      final x = -width + (travel * ((c.offset + t * c.speed) % 1.0));
      final y = size.height * c.y;

      _paintCloud(canvas, paint, Offset(x, y), width, height);
    }
  }

  /// Nube = tres circulos solapados sobre un rectangulo redondeado.
  void _paintCloud(Canvas canvas, Paint paint, Offset origin, double w, double h) {
    final r = h / 2;

    canvas.drawOval(
      Rect.fromLTWH(origin.dx, origin.dy + h * 0.42, w, h * 0.58),
      paint,
    );
    canvas.drawCircle(origin + Offset(w * 0.26, h * 0.55), r * 0.95, paint);
    canvas.drawCircle(origin + Offset(w * 0.55, h * 0.34), r * 1.20, paint);
    canvas.drawCircle(origin + Offset(w * 0.80, h * 0.58), r * 0.85, paint);
  }

  @override
  bool shouldRepaint(_CloudsPainter old) => old.t != t || old.ink != ink;
}

class _Cloud {
  const _Cloud({
    required this.y,
    required this.scale,
    required this.speed,
    required this.offset,
  });

  /// Altura relativa dentro de la pantalla.
  final double y;
  final double scale;
  final double speed;

  /// Posicion inicial normalizada, para que no salgan todas en fila.
  final double offset;
}

/// Estrellas que titilan. Solo para el modo oscuro.
///
/// Recibe la lista de estrellas ya generada: ver [_AnimatedBackgroundState._stars].
class _StarsPainter extends CustomPainter {
  const _StarsPainter({
    required this.t,
    required this.base,
    required this.ink,
    required this.stars,
  });

  final double t;
  final Color base;
  final Color ink;
  final List<_Star> stars;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final baseShift = size.width * 0.06;

    for (final s in stars) {
      // Cada estrella deriva a su propia velocidad: eso da profundidad, como
      // un paralaje. Con un desplazamiento comun se ven como una sola capa.
      final x = ((s.x * size.width + t * baseShift * s.drift) % (size.width + 8.0)) - 4.0;
      final y = s.y * size.height;

      // Titileo: seno del tiempo, entre 0.25 y 1 de opacidad.
      final wave = math.sin((t * math.pi * 2 * s.twinkleSpeed) + s.phase);
      final alpha = 0.25 + (0.5 * (wave + 1) / 2) + (s.bright ? 0.25 : 0);
      paint.color = ink.withValues(alpha: alpha.clamp(0.0, 1.0));

      canvas.drawCircle(Offset(x, y), s.radius, paint);

      // Las mas brillantes sacan cuatro puntas: rompen la monotonia de los
      // puntos y parecen estrellas de verdad.
      if (s.bright) {
        paint.strokeWidth = 0.7;
        canvas.drawLine(
          Offset(x - s.radius * 3, y),
          Offset(x + s.radius * 3, y),
          paint,
        );
        canvas.drawLine(
          Offset(x, y - s.radius * 3),
          Offset(x, y + s.radius * 3),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) =>
      old.t != t || old.ink != ink || old.base != base;
}

class _Star {
  const _Star({
    required this.x,
    required this.y,
    required this.radius,
    required this.phase,
    required this.twinkleSpeed,
    required this.drift,
    required this.bright,
  });

  final double x;
  final double y;
  final double radius;
  final double phase;
  final double twinkleSpeed;
  final double drift;
  final bool bright;
}