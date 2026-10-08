import 'package:flutter/material.dart';

import '../../core/voice_controller.dart';
import '../app_theme.dart';

/// Botón principal de comando de voz - Consola Táctil IoT.
///
/// Diseñado para máxima ergonomía (diámetro de 128 px, objetivo táctil amplio)
/// y retroalimentación visual inmediata estilo dashboard de control:
///
///   * [VoicePhase.idle] -> Botón de activación en reposo con borde luminoso.
///   * [VoicePhase.listening] -> Anillos de sonar / radar concéntricos expandiéndose
///     y núcleo vibrante que confirman captura activa de audio.
///   * [VoicePhase.pendingConfirm] -> Alerta ámbar de confirmación vocal.
///   * [VoicePhase.executing] -> Indicador técnico de accionamiento mecánico del servo.
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
    duration: const Duration(milliseconds: 1800),
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

    final (Color bg, Color fg, Color glowColor, IconData icon, String label) = switch (widget.phase) {
      VoicePhase.listening => (
          AppTheme.ok,
          Colors.white,
          AppTheme.ok.withValues(alpha: 0.5),
          Icons.mic,
          'Escuchando comando de voz',
        ),
      VoicePhase.pendingConfirm => (
          AppTheme.warn,
          Colors.white,
          AppTheme.warn.withValues(alpha: 0.5),
          Icons.help_outline,
          'Confirmar acción',
        ),
      VoicePhase.executing => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          Colors.transparent,
          Icons.settings,
          'Actuador mecánico en movimiento',
        ),
      VoicePhase.idle => (
          scheme.surfaceContainerHigh,
          scheme.primary,
          scheme.primary.withValues(alpha: 0.25),
          Icons.mic_none,
          'Tocar para hablar',
        ),
    };

    Widget buttonCore = Semantics(
      button: true,
      enabled: !blocked,
      label: label,
      child: Container(
        width: 128,
        height: 128,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: blocked
              ? null
              : [
                  BoxShadow(
                    color: glowColor,
                    blurRadius: _isListening ? 28 : 16,
                    spreadRadius: _isListening ? 4 : 1,
                  ),
                ],
        ),
        child: Material(
          color: bg,
          shape: CircleBorder(
            side: BorderSide(
              color: _isListening
                  ? Colors.white.withValues(alpha: 0.6)
                  : scheme.outlineVariant,
              width: 2.5,
            ),
          ),
          elevation: blocked ? 0 : 6,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: blocked ? null : widget.onPressed,
            child: Center(
              child: Icon(icon, size: 60, color: fg),
            ),
          ),
        ),
      ),
    );

    // Anillos de radar concéntricos durante escucha activa
    if (_isListening && !reduceMotion) {
      buttonCore = Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: <Widget>[
          for (int i = 0; i < 3; i++)
            _SonarRing(animation: _pulse, delay: i * 0.33, color: bg),
          buttonCore,
        ],
      );
    }

    return AnimatedScale(
      scale: _isListening ? 1.05 : 1.0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutBack,
      child: buttonCore,
    );
  }
}

/// Anillo de sonar / radar que se expande hacia el exterior simulando la onda de audio.
class _SonarRing extends StatelessWidget {
  const _SonarRing({
    required this.animation,
    required this.delay,
    required this.color,
  });

  final Animation<double> animation;
  final double delay;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final raw = (animation.value - delay) % 1.0;
        if (raw < 0) return const SizedBox.shrink();
        final t = raw;

        return SizedBox(
          width: 128 + (90 * t),
          height: 128 + (90 * t),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: color.withValues(alpha: 0.65 * (1 - t)),
                width: 2.5,
              ),
            ),
          ),
        );
      },
    );
  }
}