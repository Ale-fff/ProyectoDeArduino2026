import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Fondo animado de la app - Malla de Telemetría IoT.
///
/// Refleja la actividad domótica en tiempo real:
///
///   * [Brightness.dark]  -> Constelación de nodos BLE interconectados con pulsos de telemetría.
///   * [Brightness.light] -> Retícula de ingeniería tipo blueprint con sutil deriva de señal.
///
/// Optimizado al máximo: utiliza un único [CustomPainter] encapsulado en un
/// [RepaintBoundary] para aislar los repintados sin reconstruir el árbol de widgets.
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
    duration: const Duration(seconds: 45),
  )..repeat();

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce != _reduceMotion) {
      _reduceMotion = reduce;
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
        ColoredBox(color: scheme.surface),
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final double t = _reduceMotion ? 0.0 : _controller.value;
              return CustomPaint(
                painter: isDark
                    ? _DarkMeshPainter(t: t, base: scheme.primary, ink: scheme.onSurface, nodes: _nodes)
                    : _LightGridPainter(t: t, ink: scheme.onSurface, nodes: _nodes),
                size: Size.infinite,
              );
            },
          ),
        ),
        widget.child,
      ],
    );
  }

  late final List<_MeshNode> _nodes = _makeNodes();

  List<_MeshNode> _makeNodes() {
    final rnd = math.Random(42);
    return List<_MeshNode>.generate(40, (i) {
      return _MeshNode(
        x: rnd.nextDouble(),
        y: rnd.nextDouble(),
        radius: 1.2 + rnd.nextDouble() * 2.2,
        phase: rnd.nextDouble() * math.pi * 2,
        pulseSpeed: 0.8 + rnd.nextDouble() * 2.0,
        driftSpeedX: (rnd.nextDouble() - 0.5) * 0.08,
        driftSpeedY: (rnd.nextDouble() - 0.5) * 0.08,
        isHub: rnd.nextDouble() > 0.82,
      );
    });
  }
}

/// Pintor para modo oscuro: Malla de nodos BLE y líneas de datos sutiles.
class _DarkMeshPainter extends CustomPainter {
  const _DarkMeshPainter({
    required this.t,
    required this.base,
    required this.ink,
    required this.nodes,
  });

  final double t;
  final Color base;
  final Color ink;
  final List<_MeshNode> nodes;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Líneas de cuadrícula tenue de fondo
    final gridPaint = Paint()
      ..color = ink.withValues(alpha: 0.025)
      ..strokeWidth = 1.0;

    const gridSize = 48.0;
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 2. Nodos calculados con deriva suave
    final positions = <Offset>[];
    for (final n in nodes) {
      final nx = ((n.x + n.driftSpeedX * t) % 1.0) * size.width;
      final ny = ((n.y + n.driftSpeedY * t) % 1.0) * size.height;
      positions.add(Offset(nx, ny));
    }

    // 3. Conexiones entre nodos cercanos (Topología de Red Mesh)
    final linePaint = Paint()..strokeWidth = 0.8;
    for (int i = 0; i < positions.length; i++) {
      for (int j = i + 1; j < positions.length; j++) {
        final d = (positions[i] - positions[j]).distance;
        if (d < 85.0) {
          final alpha = (1.0 - (d / 85.0)) * 0.12;
          linePaint.color = base.withValues(alpha: alpha);
          canvas.drawLine(positions[i], positions[j], linePaint);
        }
      }
    }

    // 4. Dibujar los nodos
    final nodePaint = Paint();
    for (int i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      final pos = positions[i];

      final wave = math.sin((t * math.pi * 2 * n.pulseSpeed) + n.phase);
      final alpha = (0.2 + (0.6 * (wave + 1) / 2)).clamp(0.0, 1.0);

      nodePaint.color = (n.isHub ? base : ink).withValues(alpha: alpha * (n.isHub ? 0.85 : 0.45));
      canvas.drawCircle(pos, n.radius, nodePaint);

      // Los nodos concentradores emiten un halo concéntrico
      if (n.isHub) {
        final haloPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = base.withValues(alpha: alpha * 0.35);
        canvas.drawCircle(pos, n.radius * 2.8, haloPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_DarkMeshPainter old) =>
      old.t != t || old.ink != ink || old.base != base;
}

/// Pintor para modo claro: Blueprint de arquitectura con nodos de referencia técnica.
class _LightGridPainter extends CustomPainter {
  const _LightGridPainter({
    required this.t,
    required this.ink,
    required this.nodes,
  });

  final double t;
  final Color ink;
  final List<_MeshNode> nodes;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = ink.withValues(alpha: 0.04)
      ..strokeWidth = 1.0;

    const gridSize = 40.0;
    for (double x = 0; x < size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final pointPaint = Paint()..color = ink.withValues(alpha: 0.12);
    for (final n in nodes) {
      final nx = ((n.x + n.driftSpeedX * t * 0.5) % 1.0) * size.width;
      final ny = ((n.y + n.driftSpeedY * t * 0.5) % 1.0) * size.height;
      canvas.drawCircle(Offset(nx, ny), n.radius * 0.9, pointPaint);
    }
  }

  @override
  bool shouldRepaint(_LightGridPainter old) => old.t != t || old.ink != ink;
}

class _MeshNode {
  const _MeshNode({
    required this.x,
    required this.y,
    required this.radius,
    required this.phase,
    required this.pulseSpeed,
    required this.driftSpeedX,
    required this.driftSpeedY,
    required this.isHub,
  });

  final double x;
  final double y;
  final double radius;
  final double phase;
  final double pulseSpeed;
  final double driftSpeedX;
  final double driftSpeedY;
  final bool isHub;
}