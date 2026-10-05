import 'package:flutter/material.dart';

import '../../core/voice_controller.dart';
import '../app_theme.dart';

/// Boton de microfono.
///
/// Un solo boton, grande y sin adornos. El color es la unica fuente de
/// informacion sobre el estado, y el estado se lee tambien con el icono, para
/// que no dependa solo del color.
///
/// Mientras esta escuchando salen dos anillos que se expanden y se desvanecen:
/// es la senal de que el microfono esta GRABANDO de verdad. Con el icono quieto
/// no se distingue "esta escuchando" de "esta pensando", y en una app que se
/// usa con la puerta de frente, esperar uno por lo otro es un segundo perdido.
class MicButton extends StatefulWidget {
  const MicButton({
    super.key,
    required this.phase,
    required this.onPressed,
    this.enabled = true,
  });

  final VoicePhase phase;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  bool get _isListening => widget.phase == VoicePhase.listening;

  @override
  void initState() {
    super.initState();
    if (_isListening) _pulse.repeat();
  }

  @override
  void didUpdateWidget(MicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // El controlador sigue vivo aunque la fase cambie, asi que hay que
    // arrancarlo y pararlo a mano.
    if (_isListening && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!_isListening && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final blocked = !widget.enabled || widget.phase == VoicePhase.executing;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final (Color bg, Color fg, IconData icon, String label) = switch (widget.phase) {
      VoicePhase.listening => (scheme.primary, scheme.onPrimary, Icons.mic, 'Escuchando'),
      VoicePhase.pendingConfirm => (
          AppTheme.warn,
          Colors.white,
          Icons.help_outline,
          'Confirmar',
        ),
      VoicePhase.executing => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          Icons.settings,
          'Actuador en movimiento',
        ),
      VoicePhase.idle => (scheme.secondaryContainer, scheme.onSecondaryContainer, Icons.mic_none, 'Tocar para hablar'),
    };

    Widget circle = Semantics(
      button: true,
      enabled: !blocked,
      label: label,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        elevation: blocked ? 0 : 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: blocked ? null : widget.onPressed,
          child: SizedBox(
            // 120 px: sobra para un dedo mayor, sin salirse de la pantalla.
            width: 120,
            height: 120,
            child: Icon(icon, size: 56, color: fg),
          ),
        ),
      ),
    );

    // Los anillos van detras del boton y solo mientras escucha.
    if (_isListening && !reduceMotion) {
      circle = Stack(
        alignment: Alignment.center,
        children: <Widget>[
          for (int i = 0; i < 2; i++)
            _EchoRing(animation: _pulse, delay: i * 0.5, color: bg),
          circle,
        ],
      );
    }

    return AnimatedScale(
      // Un pelin de rebote al cambiar de fase: el boton "responde" en vez de
      // cambiar de golpe.
      scale: _isListening ? 1.04 : 1.0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      child: circle,
    );
  }
}

/// Anillo que se expande y se apaga. Es la onda de "te estoy oyendo".
class _EchoRing extends StatelessWidget {
  const _EchoRing({required this.animation, required this.delay, required this.color});

  final Animation<double> animation;

  /// Retraso del anillo, para que no se expandan los dos a la vez.
  final double delay;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        // 0..1 por ciclo, empezando en `delay` y volviendo al final.
        final raw = (animation.value - delay) % 1.0;
        if (raw < 0) return const SizedBox.shrink();
        final t = raw;

        return SizedBox(
          width: 120 + (60 * t),
          height: 120 + (60 * t),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.55 * (1 - t)),
                width: 3,
              ),
            ),
          ),
        );
      },
    );
  }
}