import 'dart:async';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'widgets/animated_background.dart';
import 'widgets/logo.dart';

/// Pantalla de bienvenida / Secuencia de Inicio del Sistema.
///
/// Permanece activa mientras el subsistema Bluetooth se inicializa y se
/// verifica la disponibilidad del actuador, con una estética de terminal IoT.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.ready,
    required this.onFinished,
    this.minimumDuration = const Duration(milliseconds: 1700),
  });

  final Future<void> ready;
  final VoidCallback onFinished;
  final Duration minimumDuration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 8000),
  )..repeat();

  late final Stopwatch _swatch;

  @override
  void initState() {
    super.initState();
    _swatch = Stopwatch()..start();
    unawaited(_waitThenLeave());
  }

  Future<void> _waitThenLeave() async {
    try {
      await widget.ready;
    } catch (_) {}

    final remaining = widget.minimumDuration - _swatch.elapsed;
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);

    if (!mounted) return;
    widget.onFinished();
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // Logo con anillo de rotación orbital IoT
                ScaleTransition(
                  scale: Tween<double>(begin: 0.82, end: 1.0).animate(
                    CurvedAnimation(parent: _intro, curve: Curves.easeOutBack),
                  ),
                  child: FadeTransition(
                    opacity: _intro,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (!reduceMotion)
                          RotationTransition(
                            turns: _spin,
                            child: SizedBox(
                              width: 170,
                              height: 170,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: scheme.primary.withValues(alpha: 0.25),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        AnimatedBuilder(
                          animation: _pulse,
                          builder: (context, child) {
                            final k = reduceMotion ? 0.0 : _pulse.value;
                            return Transform.scale(scale: 1 + (0.04 * k), child: child);
                          },
                          child: const ManejIALogo(size: 136),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _intro,
                    curve: const Interval(0.25, 1.0, curve: Curves.easeOut),
                  ),
                  child: Column(
                    children: <Widget>[
                      Text(
                        'ManejIA',
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          'SISTEMA DOMÓTICO ESP32-S3 // BLE 5.0',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _intro,
                    curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
                  ),
                  child: Column(
                    children: <Widget>[
                      SizedBox(
                        width: 160,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            minHeight: 5,
                            color: scheme.primary,
                            backgroundColor: scheme.outlineVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Sincronizando subsistema Bluetooth...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}