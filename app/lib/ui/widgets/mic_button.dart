import 'package:flutter/material.dart';

import '../../core/voice_controller.dart';
import '../app_theme.dart';

/// Boton de microfono.
///
/// Un solo boton, grande y sin adornos. El color es la unica fuente de
/// informacion sobre el estado, y el estado se lee tambien con el icono, para
/// que no dependa solo del color.
class MicButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bool blocked = !enabled || phase == VoicePhase.executing;

    final (Color bg, Color fg, IconData icon, String label) = switch (phase) {
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

    return Semantics(
      button: true,
      enabled: !blocked,
      label: label,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        elevation: blocked ? 0 : 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: blocked ? null : onPressed,
          child: SizedBox(
            // 120 px: sobra para un dedo mayor, sin salirse de la pantalla.
            width: 120,
            height: 120,
            child: Icon(icon, size: 56, color: fg),
          ),
        ),
      ),
    );
  }
}
