import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/permissions.dart';
import '../core/voice_controller.dart';
import '../data/ble/ble_client.dart';
import '../data/protocol/protocol.dart';
import '../speech/speech_service.dart';
import '../speech/tts_service.dart';
import 'app_theme.dart';
import 'widgets/mic_button.dart';

/// Pantalla unica de la app.
///
/// Se eligio una sola pantalla a proposito: menos menus, menos viajes, menos
/// formas de llegar a un estado raro. Conectar, hablar y ver el resultado se
/// hacen sin navegar.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.link});

  final BleLink link;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final SpeechService _speech = SpeechService();
  final TtsService _tts = TtsService();
  const PermissionService _perms = PermissionService();
  late final VoiceController _voice = VoiceController();

  StreamSubscription<List<String>>? _speechSub;
  StreamSubscription<AppEvent>? _eventSub;
  Timer? _pingTimer;

  int? _pressUs;
  int? _restUs;
  bool _calibrated = false;
  String _lastMessage = 'Toca el microfono y di "abre la puerta".';
  bool _micBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _speechSub = _speech.results.listen(_onSpeech);
    _eventSub = widget.link.events.listen(_onEvent);
    widget.link.addListener(_onLinkChanged);

    _voice.addListener(_onVoiceChanged);
    unawaited(_speech.initialize());
    unawaited(_tts.initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.link.removeListener(_onLinkChanged);
    _pingTimer?.cancel();
    _speechSub?.cancel();
    _eventSub?.cancel();
    _speech.dispose();
    _voice.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // El motor de voz se queda colgado si la app pasa a segundo plano
    // mientras escucha. Cortarlo aqui evita el caso raro de "no hace nada".
    if (state != AppLifecycleState.resumed) {
      _speech.cancel();
    }
  }

  // -------------------------------------------------------------------------

  void _onLinkChanged() {
    if (!mounted) return;
    setState(() {});
    if (widget.link.isReady) {
      unawaited(widget.link.requestConfig());
      _startPing();
    } else {
      _pingTimer?.cancel();
      _pingTimer = null;
      // Perdimos el enlace a mitad de una secuencia: hay que devolver el
      // control, no dejar el boton en "ejecutando" para siempre.
      _voice.onSequenceFinished();
    }
  }

  /// El watchdog del firmware es de 30 s sin ping. Se manda uno cada 5 s
  /// mientras haya una secuencia en curso, para que la app no lo dispare
  /// nunca por culpa propia.
  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_voice.phase == VoicePhase.executing && widget.link.isReady) {
        unawaited(widget.link.ping());
      }
    });
  }

  void _onSpeech(List<String> hypotheses) {
    _voice.onSpeechResult(hypotheses);
  }

  void _onVoiceChanged() {
    if (!mounted) return;
    setState(() {});

    final d = _voice.lastDecision;
    switch (d.outcome) {
      case VoiceOutcome.command:
        unawaited(_tts.stop());
        unawaited(_send(d.command!));
      case VoiceOutcome.spoken:
        _lastMessage = d.message;
        unawaited(_tts.speak(d.message));
      case VoiceOutcome.askToRepeat:
        _lastMessage = d.message;
        unawaited(_tts.speak(d.message));
      case VoiceOutcome.error:
        _lastMessage = d.message;
        unawaited(_tts.speak(d.message));
    }
  }

  Future<void> _send(Command command) async {
    if (!widget.link.isReady) {
      _voice.onTransportError(VoiceStrings.notConnected);
      return;
    }
    if (!_calibrated && command.cmd == AppCommand.open) {
      _voice.onTransportError(VoiceStrings.notCalibrated);
      return;
    }
    final ok = await widget.link.send(command.cmd);
    if (!ok) {
      _voice.onTransportError(VoiceStrings.notConnected);
    }
  }

  // -------------------------------------------------------------------------

  void _onEvent(AppEvent e) {
    if (!mounted) return;
    setState(() {});

    switch (e.kind) {
      case AppEventKind.config:
        _pressUs = e.pressUs;
        _restUs = e.restUs;
        _calibrated = e.calibrated ?? false;

      case AppEventKind.done:
        _voice.onSequenceFinished();
        _lastMessage = e.isStall
            ? VoiceStrings.stall
            : (e.action == 'open' ? VoiceStrings.doneOpen : VoiceStrings.doneClose);
        if (e.isStall) {
          unawaited(_tts.speak(VoiceStrings.stall));
        }

      case AppEventKind.error:
        _voice.onSequenceFinished();
        // Los errores "benignos" son de rutina: la app se adiapa al paso
        // lento de la persona o a una repeticion. Gritar "error" por cada uno
        // haria que dejara de escuchar.
        if (!isBenign(e.errorCode ?? DoorErrorCode.malformed)) {
          _lastMessage = e.message;
          unawaited(_tts.speak(_messageFor(e.errorCode ?? DoorErrorCode.malformed)));
        }

      case AppEventKind.status:
      case AppEventKind.ack:
      case AppEventKind.pong:
      case AppEventKind.unknown:
        break;
    }
  }

  String _messageFor(DoorErrorCode code) => switch (code) {
        DoorErrorCode.stall => VoiceStrings.stall,
        DoorErrorCode.watchdog => VoiceStrings.stopped,
        DoorErrorCode.lowBattery => VoiceStrings.lowBattery,
        DoorErrorCode.notCalibrated => VoiceStrings.notCalibrated,
        _ => 'No se pudo completar la orden.',
      };

  // -------------------------------------------------------------------------

  Future<void> _toggleMic() async {
    if (_micBusy) return;
    _micBusy = true;
    try {
      // Tocar el microfono calla a la app: si no, se escucha a si misma.
      await _tts.stop();

      // El microfono se pide aqui y no en el arranque: pedirlo de entrada y que
      // lo denieguen deja la app inservible, mientras que asi los botones
      // manuales siguen sirviendo.
      if (!await _perms.requestMicrophone()) {
        if (mounted) {
          setState(() => _lastMessage = PermissionService.instructionsFor('microphone'));
        }
        return;
      }
      await _perms.requestSpeechRecognition();

      _voice.beginListening();
      final ok = await _speech.listen();
      if (!ok && mounted) {
        setState(() => _lastMessage = _speech.lastError ?? VoiceStrings.repeat);
      }
    } finally {
      _micBusy = false;
    }
  }

  Future<void> _connect() async {
    // Sin este paso, en Android 12+ el escaneo falla en silencio y la pantalla
    // muestra "no se encontro el actuador" sin decir por que.
    final missing = await _perms.missingForScan();
    if (missing.isNotEmpty) {
      if (!mounted) return;
      setState(() => _lastMessage = PermissionService.instructionsFor(missing.first));
      unawaited(_tts.speak(_lastMessage));
      return;
    }

    await widget.link.scan();
    if (!mounted) return;
    if (widget.link.foundDevices.isEmpty) {
      setState(() => _lastMessage = 'No se encontro el actuador. '
          'Revisa que este encendido y cerca.');
      return;
    }
    if (widget.link.foundDevices.length == 1) {
      await widget.link.connect(widget.link.foundDevices.first);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Elige un actuador',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            ),
            for (final d in widget.link.foundDevices)
              ListTile(
                title: Text(d.platformName),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  unawaited(widget.link.connect(d));
                },
              ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final link = widget.link;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Puerta por voz'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Conectar',
            onPressed: _connect,
            icon: Icon(link.isReady ? Icons.bluetooth_connected : Icons.bluetooth),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _statusCard(context),
                  const SizedBox(height: 32),
                  Center(
                    child: MicButton(
                      phase: _voice.phase,
                      enabled: link.isReady,
                      onPressed: _toggleMic,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_voice.phase == VoicePhase.pendingConfirm)
                    _confirmBanner(context),
                  if (_voice.phase == VoicePhase.pendingConfirm)
                    const SizedBox(height: 16),
                  Text(
                    _lastMessage,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: _voice.phase == VoicePhase.pendingConfirm
                              ? AppTheme.warn
                              : scheme.onSurface,
                        ),
                  ),
                  if (_voice.transcript.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      '"${_voice.transcript}"',
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 32),
                  _manualControls(context),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusCard(BuildContext context) {
    final link = widget.link;
    final scheme = Theme.of(context).colorScheme;

    final (IconData icon, String title, Color color) = switch (link.status) {
      BleLinkStatus.ready => (Icons.check_circle_outline, 'Conectado', AppTheme.ok),
      BleLinkStatus.connecting => (Icons.bluetooth_searching, 'Conectando', scheme.primary),
      BleLinkStatus.scanning => (Icons.search, 'Buscando', scheme.primary),
      BleLinkStatus.bluetoothOff => (Icons.bluetooth_disabled, 'Bluetooth apagado', AppTheme.warn),
      BleLinkStatus.error => (Icons.error_outline, 'Error', AppTheme.warn),
      BleLinkStatus.disconnected => (Icons.link_off, 'Sin conectar', scheme.onSurfaceVariant),
      BleLinkStatus.unknown => (Icons.hourglass_empty, 'Iniciando', scheme.onSurfaceVariant),
    };

    final bool detail = _pressUs != null && _restUs != null;
    final int? travel = (detail && _pressUs! > _restUs!) ? _pressUs! - _restUs! : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: Theme.of(context).textTheme.titleLarge),
                ),
              ],
            ),
            if (link.status == BleLinkStatus.error && link.lastError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(link.lastError,
                    style: TextStyle(color: scheme.error, fontSize: 15)),
              ),
            if (link.status == BleLinkStatus.error &&
                link.failure == BleFailure.bluetoothPermissionDenied)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: const Text(
                  'iOS no deja pedir el permiso por codigo. Abre Ajustes > '
                  'Privacidad > Bluetooth y activa el permiso para esta app.',
                  style: TextStyle(fontSize: 15),
                ),
              ),
            if (detail)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Recorrido: $travel microsegundos'
                  '${_calibrated ? '' : '  (sin calibrar)'}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _confirmBanner(BuildContext context) {
    return Card(
      color: AppTheme.warn.withValues(alpha: 0.12),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(Icons.help_outline, color: AppTheme.warn),
            SizedBox(width: 12),
            Expanded(
              child: Text('Di "si" para abrir, o "no" para cancelar.',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }

  /// Botones manuales: hacen falta porque en un corte de red la voz no llega,
  /// y depender solo de la voz seria una mala decision.
  Widget _manualControls(BuildContext context) {
    final enabled = widget.link.isReady;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FilledButton.icon(
          onPressed: enabled ? () => _manual(AppCommand.open) : null,
          icon: const Icon(Icons.lock_open),
          label: const Text('Abrir'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: enabled ? () => _manual(AppCommand.close) : null,
          icon: const Icon(Icons.lock),
          label: const Text('Cerrar'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: enabled ? () => _manual(AppCommand.estop) : null,
          icon: const Icon(Icons.pan_tool),
          label: const Text('Detener'),
        ),
      ],
    );
  }

  Future<void> _manual(AppCommand cmd) async {
    await _tts.stop();
    if (cmd == AppCommand.open && !_calibrated) {
      setState(() => _lastMessage = VoiceStrings.notCalibrated);
      return;
    }
    await widget.link.send(cmd);
  }
}
