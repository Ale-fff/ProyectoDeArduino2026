import 'dart:async';

import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'widgets/animated_background.dart';
import 'widgets/logo.dart';

/// Pantalla de bienvenida.
///
/// Se queda delante hasta que el Bluetooth ha iniciado Y ha pasado un tiempo
/// minimo. Las dos condiciones son necesarias:
///
///   * la minima, para que un movil rapido no vea un fogonazo de 120 ms que
///     parece un fallo de render;
///   * la del Bluetooth, para que al entrar se este ya buscando el ESP32 y la
///     pantalla principal no aparezca en "Iniciando" durante 3 s.
///
/// Detras del splash ya esta pasando todo: la app se construye, el
/// `BleLink` arranca y `_autoConnect()` busca el ESP32. Al montar la pantalla
/// principal el enlace suele estar Connected y el usuario no ve el proceso.
///
/// El logo entra con escala y opacidad, y se queda respirando con una
/// pulsacion suave mientras dura.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.ready,
    required this.onFinished,
    this.minimumDuration = const Duration(milliseconds: 1700),
  });

  /// Trabajo que hay que esperar: normalmente `BleLink.initialize()`.
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

  @override
  void initState() {
    super.initState();
    _swatch = Stopwatch()..start();
    unawaited(_waitThenLeave());
  }

  /// Cronometro del splash. Se mide tiempo real, no el valor de la animacion:
  /// si el Bluetooth tarda 200 ms, solo queda el resto de la espera minima.
  late final Stopwatch _swatch;

  Future<void> _waitThenLeave() async {
    // Un fallo de Bluetooth no puede impedir abrir la app: la pantalla
    // principal ya sabe mostrar el error con detalle.
    try {
      await widget.ready;
    } catch (_) {
      // La pantalla principal se encarga.
    }

    final remaining = widget.minimumDuration - _swatch.elapsed;
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);

    if (!mounted) return;
    widget.onFinished();
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
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
                // Entrada del logo: escala desde 0.82 y opacidad 0 -> 1, con
                // una curva que sale rapido y frena (outBack da el rebote).
                ScaleTransition(
                  scale: Tween<double>(begin: 0.82, end: 1.0).animate(
                    CurvedAnimation(parent: _intro, curve: Curves.easeOutBack),
                  ),
                  child: FadeTransition(
                    opacity: _intro,
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, child) {
                        final k = reduceMotion ? 0.0 : _pulse.value;
                        // Solo crece un 4 %: si se nota mucho, parece un fallo
                        // de fidelidad y no una animacion.
                        return Transform.scale(scale: 1 + (0.04 * k), child: child);
                      },
                      child: const ManejIALogo(size: 132),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
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
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Asistente domotico por voz',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 44),
                FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _intro,
                    curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
                  ),
                  // Aviso de que se esta buscando el actuador: la espera no es
                  // tiempo muerto, y decirlo evita el "esta colgada".
                  child: Column(
                    children: <Widget>[
                      SizedBox(
                        width: 132,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            minHeight: 4,
                            color: AppTheme.seedLight,
                            backgroundColor: scheme.outlineVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Buscando el actuador...',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
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