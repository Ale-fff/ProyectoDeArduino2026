import 'dart:async';

import 'package:flutter/material.dart';

import '../core/permissions.dart';
import '../core/voice_controller.dart';
import '../data/ble/ble_client.dart';
import '../data/protocol/protocol.dart';
import '../speech/speech_service.dart';
import '../speech/tts_service.dart';
import 'app_theme.dart';
import 'calibration_screen.dart';
import 'widgets/animated_background.dart';
import 'widgets/mic_button.dart';

/// Pantalla única de control - Consola Domótica ManejIA.
///
/// Integra la gestión del enlace BLE, captura de voz local y accionamiento
/// mecánico del servomotor con una estética de panel de control IoT.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.link,
    this.isDarkMode = false,
    this.onToggleTheme,
  });

  final BleLink link;

  /// Solo para pintar el icono del conmutador; el modo real vive arriba, en el
  /// `MaterialApp`.
  final bool isDarkMode;

  /// Si es `null` no se muestra el conmutador (útil en pruebas).
  final VoidCallback? onToggleTheme;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final SpeechService _speech = SpeechService();
  final TtsService _tts = TtsService();
  final PermissionService _perms = const PermissionService();
  late final VoiceController _voice = VoiceController();

  StreamSubscription<List<String>>? _speechSub;
  StreamSubscription<AppEvent>? _eventSub;
  Timer? _pingTimer;

  int? _pressUs;
  int? _restUs;

  /// `null` = el ESP32 todavía no ha mandado su `config`.
  bool? _calibrated;
  bool _vrailOk = true;
  String _lastMessage = 'Toca el micrófono y di "abre la puerta".';
  bool _micBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _speechSub = _speech.results.listen(_onSpeech);
    _eventSub = widget.link.events.listen(_onEvent);
    widget.link.addListener(_onLinkChanged);
    _speech.addListener(_onSpeechStateChanged);

    _voice.addListener(_onVoiceChanged);
    unawaited(_speech.initialize());
    unawaited(_tts.initialize());
    unawaited(_autoConnect());
  }

  Future<void> _autoConnect() async {
    final missing = await _perms.missingForScan();
    if (missing.isNotEmpty || !mounted) return;

    if (widget.link.isReady) return;

    await widget.link.scan();
    if (!mounted) return;

    final targets =
        widget.link.foundDevices.where((d) => d.compatible).toList();
    if (targets.length != 1) return;

    await widget.link.connect(targets.first.device);
    if (!mounted) return;
    setState(() => _lastMessage = 'Actuador conectado vía BLE.');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.link.removeListener(_onLinkChanged);
    _speech.removeListener(_onSpeechStateChanged);
    _pingTimer?.cancel();
    _speechSub?.cancel();
    _eventSub?.cancel();
    _speech.dispose();
    _voice.dispose();
    unawaited(_tts.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
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
      _voice.onSequenceFinished();
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (widget.link.isReady) {
        unawaited(widget.link.ping());
      }
    });
  }

  void _onSpeech(List<String> hypotheses) {
    _voice.onSpeechResult(hypotheses);
  }

  void _onSpeechStateChanged() {
    if (!mounted) return;
    setState(() {});
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
        unawaited(_tts.speakNotUnderstood());
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
    if (_calibrated == false && command.cmd == AppCommand.open) {
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

      case AppEventKind.status:
        if (e.vrailOk != null) {
          _vrailOk = e.vrailOk!;
        }

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
        if (!isBenign(e.errorCode ?? DoorErrorCode.malformed)) {
          _lastMessage = e.message ?? '';
          unawaited(_tts.speak(_messageFor(e.errorCode ?? DoorErrorCode.malformed)));
        }

      case AppEventKind.ack:
      case AppEventKind.pong:
      case AppEventKind.unknown:
        break;
    }
  }

  String _messageFor(DoorErrorCode code) => switch (code) {
        DoorErrorCode.stall => VoiceStrings.stall,
        DoorErrorCode.voltageLow => VoiceStrings.lowBattery,
        DoorErrorCode.notCalibrated => VoiceStrings.notCalibrated,
        _ => 'No se pudo completar la orden.',
      };

  // -------------------------------------------------------------------------

  Future<void> _toggleMic() async {
    if (_micBusy) return;
    _micBusy = true;
    try {
      await _tts.stop();

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
    final missing = await _perms.missingForScan();
    if (missing.isNotEmpty) {
      if (!mounted) return;
      setState(() => _lastMessage = PermissionService.instructionsFor(missing.first));
      unawaited(_tts.speak(_lastMessage));
      return;
    }

    await widget.link.scan();
    if (!mounted) return;
    await _showDeviceList();
  }

  Future<void> _showDeviceList() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            final devices = widget.link.foundDevices;
            final scheme = Theme.of(context).colorScheme;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.radar, color: scheme.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Escáner de Dispositivos BLE',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            Text(
                              'Dispositivos compatibles con ManejIA',
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Escanear de nuevo',
                        icon: const Icon(Icons.refresh),
                        onPressed: () async {
                          setSheetState(() {});
                          await widget.link.scan();
                          if (context.mounted) setSheetState(() {});
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (devices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      children: [
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Buscando actuadores en rango BLE...',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: <Widget>[
                        for (final d in devices)
                          ListTile(
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: d.compatible
                                    ? AppTheme.ok.withValues(alpha: 0.15)
                                    : scheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                d.compatible ? Icons.bluetooth_connected : Icons.bluetooth,
                                color: d.compatible ? AppTheme.ok : scheme.onSurfaceVariant,
                              ),
                            ),
                            title: Text(
                              d.device.platformName.isNotEmpty
                                  ? d.device.platformName
                                  : d.device.remoteId.str,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              '${d.compatible ? "COMPATIBLE ESP32" : "OTRO DISPOSITIVO"} · ${d.rssi} dBm',
                              style: TextStyle(
                                fontSize: 13,
                                color: d.compatible ? AppTheme.ok : scheme.onSurfaceVariant,
                                fontWeight: d.compatible ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: () {
                              Navigator.pop(context);
                              unawaited(widget.link.connect(d.device));
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ManejIA'),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
              ),
              child: Text(
                'BLE IoT',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: scheme.primary,
                ),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          if (link.isReady)
            IconButton(
              tooltip: 'Calibración de Servomotor',
              icon: const Icon(Icons.tune),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => CalibrationScreen(link: link),
                  ),
                );
              },
            ),
          IconButton(
            tooltip: link.isReady ? 'Conectado a BLE' : 'Conectar actuador',
            onPressed: _connect,
            icon: Icon(
              link.isReady ? Icons.bluetooth_connected : Icons.bluetooth,
              color: link.isReady ? AppTheme.ok : null,
            ),
          ),
          if (widget.onToggleTheme != null)
            IconButton(
              tooltip: widget.isDarkMode ? 'Modo claro' : 'Modo oscuro',
              onPressed: widget.onToggleTheme,
              icon: Icon(widget.isDarkMode ? Icons.light_mode : Icons.dark_mode),
            ),
        ],
      ),
      body: AnimatedBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _statusCard(context),
                    const SizedBox(height: 28),
                    Center(
                      child: MicButton(
                        phase: _voice.phase,
                        enabled: link.isReady,
                        onPressed: _toggleMic,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_voice.phase == VoicePhase.pendingConfirm) ...<Widget>[
                      _confirmBanner(context),
                      const SizedBox(height: 16),
                    ],
                    // Consola de lectura de comandos de voz
                    _voiceConsoleCard(context),
                    const SizedBox(height: 28),
                    _manualControls(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: _listeningBar(context),
    );
  }

  /// Consola / Terminal de texto para el comando vocal recibido.
  Widget _voiceConsoleCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _voice.phase == VoicePhase.pendingConfirm
              ? AppTheme.warn.withValues(alpha: 0.5)
              : scheme.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.record_voice_over,
                size: 16,
                color: scheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'COMANDO VOCAL',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.2),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              _lastMessage,
              key: ValueKey<String>(_lastMessage),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _voice.phase == VoicePhase.pendingConfirm
                        ? AppTheme.warn
                        : scheme.onSurface,
                  ),
            ),
          ),
          if (_voice.transcript.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '"${_voice.transcript}"',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Barra de pie fija durante escucha activa.
  Widget _listeningBar(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topCenter,
      child: _speech.isListening
          ? Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.ok,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.ok.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 14),
                  Text(
                    'ESCUCHANDO COMANDO DE VOZ...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox(width: double.infinity),
    );
  }

  /// HUD / Tarjeta de Telemetría de Hardware.
  Widget _statusCard(BuildContext context) {
    final link = widget.link;
    final scheme = Theme.of(context).colorScheme;

    final (IconData icon, String title, Color color, String stateTag) = switch (link.status) {
      BleLinkStatus.ready => (Icons.sensors, 'ESP32-S3 Conectado', AppTheme.ok, 'ENLACE ACTIVO'),
      BleLinkStatus.connecting => (Icons.bluetooth_searching, 'Conectando...', scheme.primary, 'SINCRONIZANDO'),
      BleLinkStatus.scanning => (Icons.radar, 'Buscando Actuador...', scheme.primary, 'ESCANEANDO'),
      BleLinkStatus.bluetoothOff => (Icons.bluetooth_disabled, 'Bluetooth Apagado', AppTheme.warn, 'DESACTIVADO'),
      BleLinkStatus.error => (Icons.error_outline, 'Falla de Conexión', AppTheme.warn, 'ERROR'),
      BleLinkStatus.disconnected => (Icons.link_off, 'Sin Conexión BLE', scheme.onSurfaceVariant, 'DESCONECTADO'),
      BleLinkStatus.unknown => (Icons.hourglass_empty, 'Iniciando Subsistema...', scheme.onSurfaceVariant, 'INICIANDO'),
    };

    final bool detail = _pressUs != null && _restUs != null;
    final int? travel = (detail && _pressUs! > _restUs!) ? _pressUs! - _restUs! : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Cabecera con LED de telemetría y título
            Row(
              children: <Widget>[
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.6),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        stateTag,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(icon, color: color, size: 28),
              ],
            ),

            if (link.status == BleLinkStatus.error && link.lastError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(link.lastError,
                    style: TextStyle(color: scheme.error, fontSize: 14)),
              ),

            if (link.status == BleLinkStatus.error &&
                link.failure == BleFailure.bluetoothPermissionDenied)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'iOS no deja pedir el permiso por código. Abre Ajustes > '
                  'Privacidad > Bluetooth y activa el permiso para esta app.',
                  style: TextStyle(fontSize: 14),
                ),
              ),

            // Métricas de telemetría del servomotor
            if (link.isReady) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (travel != null)
                    _telemetryChip(
                      label: 'RECORRIDO PWM',
                      value: '$travel µs',
                      color: AppTheme.techCyan,
                    ),
                  _telemetryChip(
                    label: 'CALIBRACIÓN',
                    value: _calibrated == true ? 'CALIBRADO' : 'PENDIENTE',
                    color: _calibrated == true ? AppTheme.ok : AppTheme.amberAccent,
                  ),
                  _telemetryChip(
                    label: 'V-RAIL 6V',
                    value: _vrailOk ? '6.0V OK' : 'BAJO < 5.0V',
                    color: _vrailOk ? AppTheme.ok : AppTheme.warn,
                  ),
                ],
              ),
            ],

            if (!_vrailOk)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.warn.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.warn.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.battery_alert, color: AppTheme.warn, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Alimentación servo insuficiente (< 5.0 V). Requiere fuente externa.',
                        style: TextStyle(color: AppTheme.warn, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _telemetryChip({
    required String label,
    required String value,
    required Color color,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _confirmBanner(BuildContext context) {
    return Card(
      color: AppTheme.warn.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.warn, width: 1.5),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, color: AppTheme.warn, size: 28),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'Di "si" para abrir la puerta, o "no" para cancelar.',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Botones de control manual tipo interruptores táctiles de cabina.
  Widget _manualControls(BuildContext context) {
    final enabled = widget.link.isReady;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FilledButton.icon(
          onPressed: enabled ? () => _manual(AppCommand.open) : null,
          icon: const Icon(Icons.lock_open, size: 24),
          label: const Text('ABRIR PUERTA'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: enabled ? () => _manual(AppCommand.close) : null,
          icon: const Icon(Icons.lock, size: 24),
          label: const Text('CERRAR / REPOSO'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: enabled ? _disconnect : null,
          icon: const Icon(Icons.bluetooth_disabled, size: 22),
          label: const Text('DESCONECTAR BLE'),
        ),
      ],
    );
  }

  Future<void> _disconnect() async {
    await _tts.stop();
    await widget.link.disconnect();
  }

  Future<void> _manual(AppCommand cmd) async {
    await _tts.stop();
    if (cmd == AppCommand.open && _calibrated == false) {
      setState(() => _lastMessage = VoiceStrings.notCalibrated);
      return;
    }
    await widget.link.send(cmd);
  }
}
