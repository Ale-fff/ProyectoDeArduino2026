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

/// Pantalla unica de la app.
///
/// Se eligio una sola pantalla a proposito: menos menus, menos viajes, menos
/// formas de llegar a un estado raro. Conectar, hablar y ver el resultado se
/// hacen sin navegar.
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

  /// Si es `null` no se muestra el conmutador (util en pruebas).
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

  /// `null` = el ESP32 todavia no ha mandado su `config`. No es lo mismo que
  /// "dice que no esta calibrado": sin datos, [IntentAction.open] no se
  /// bloquea. Bloquear por desconocimiento hacia que el primer comando de voz
  /// fallara siempre con "no esta calibrado" en un dispositivo recien
  /// emparejado.
  bool? _calibrated;
  bool _vrailOk = true;
  String _lastMessage = 'Toca el microfono y di "abre la puerta".';
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
    // Conectar sola al abrir: quien usa la puerta no deberia tener que
    // apretar "conectar" cada vez.
    unawaited(_autoConnect());
  }

  /// Busca el ESP32 al arrancar y se conecta si hay exactamente uno.
  ///
  /// Con varios compatibles NO elige ninguno: adivinar cual es el suyo seria
  /// una forma sutil de abrir la puerta de otra casa. En ese caso la persona
  /// usa el boton de conectar, que si lista.
  Future<void> _autoConnect() async {
    final missing = await _perms.missingForScan();
    if (missing.isNotEmpty || !mounted) return;

    // Si la app vuelve a primer plano con el enlace ya vivo, no se toca nada.
    if (widget.link.isReady) return;

    await widget.link.scan();
    if (!mounted) return;

    final targets =
        widget.link.foundDevices.where((d) => d.compatible).toList();
    if (targets.length != 1) return;

    await widget.link.connect(targets.first.device);
    if (!mounted) return;
    setState(() => _lastMessage = 'Actuador conectado.');
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

  /// El watchdog del firmware corta un movimiento si pasan 30 s sin ping, asi
  /// que se manda uno cada 5 s mientras haya conexion.
  ///
  /// Antes solo pulsaba durante una secuencia en ejecucion. Con el servo
  /// quieto presionado hasta un `close` eso dejaba de renovar el reloj del
  /// watchdog en el momento exacto en que mas importaba.
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

  /// El motor de voz cambia de estado por su cuenta (empieza a escuchar, se
  /// agota el tiempo, hay error). Sin esto, la barra de "Escuchando" se queda
  /// pegada encendida porque [VoicePhase] no refleja lo que hace el microfono.
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
        // Clip grabado en vez de TTS: el usuario lo pidio asi y suena siempre
        // igual, con o sin voces espanolas instaladas.
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
    // Solo se frena si el ESP32 ha dicho explicitamente que no esta calibrado.
    // Con `_calibrated == null` todavia no hay config y se deja pasar.
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
        // Los errores "benignos" son de rutina: la app se adiapa al paso
        // lento de la persona o a una repeticion. Gritar "error" por cada uno
        // haria que dejara de escuchar.
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
    await _showDeviceList();
  }

  /// Lista siempre visible de los dispositivos cercanos, con los compatibles
  /// primero. Antes se auto-conectaba cuando solo habia uno, y la persona
  /// nunca llegaba a ver a que se estaba conectando.
  Future<void> _showDeviceList() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            final devices = widget.link.foundDevices;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text('Dispositivos cercanos',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        tooltip: 'Buscar de nuevo',
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
                if (devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        'Buscando... Si no aparece nada, revisa que el '
                        'actuador este encendido y cerca.'),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: <Widget>[
                        for (final d in devices)
                          ListTile(
                            leading: Icon(
                              d.compatible ? Icons.doorbell : Icons.bluetooth_disabled,
                              color: d.compatible ? Theme.of(context).colorScheme.primary : null,
                            ),
                            title: Text(
                              d.device.platformName.isNotEmpty
                                  ? d.device.platformName
                                  : d.device.remoteId.str,
                            ),
                            subtitle: Text(
                              '${d.compatible ? "compatible" : "otro dispositivo"} · '
                              '${d.rssi} dBm',
                            ),
                            trailing: const Icon(Icons.chevron_right),
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
        title: const Text('ManejIA'),
        actions: <Widget>[
          if (link.isReady)
            IconButton(
              tooltip: 'Calibración',
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
            tooltip: 'Conectar',
            onPressed: _connect,
            icon: Icon(link.isReady ? Icons.bluetooth_connected : Icons.bluetooth),
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
                    if (_voice.phase == VoicePhase.pendingConfirm) ...<Widget>[
                      _confirmBanner(context),
                      const SizedBox(height: 16),
                    ],
                    // El mensaje se sustituye con un fundido en vez de saltar:
                    // es la lectura principal durante toda la sesion.
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.25),
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
                              color: _voice.phase == VoicePhase.pendingConfirm
                                  ? AppTheme.warn
                                  : scheme.onSurface,
                            ),
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
      ),
      bottomNavigationBar: _listeningBar(context),
    );
  }

  /// Barra de pie que aparece SOLO mientras el microfono esta grabando.
  ///
  /// Va fija abajo, no dentro del scroll, porque el usuario la pidio "abajo" y
  /// porque tiene que verse aunque la pantalla este en scrolls largos. La
  /// consulta la verdad al microfono ([SpeechService.isListening]) y no a
  /// [VoicePhase]: la fase puede quedarse en `listening` si el turno termina
  /// sin coincidir, y una barra encendida ahi miente.
  Widget _listeningBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      alignment: Alignment.topCenter,
      child: _speech.isListening
          ? Container(
              width: double.infinity,
              color: scheme.primary,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: scheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Escuchando...',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            )
          : const SizedBox(width: double.infinity),
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
            // El titulo se funde en vez de saltar. Con el BLE pasando de
            // "Buscando" a "Conectado" a "Sin conectar" cada pocos segundos,
            // el salto seco hacia parpadear.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              child: Row(
                key: ValueKey<String>('$title/$color'),
                children: <Widget>[
                  Icon(icon, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
                  ),
                ],
              ),
            ),
            if (link.status == BleLinkStatus.error && link.lastError.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(link.lastError,
                    style: TextStyle(color: scheme.error, fontSize: 15)),
              ),
            if (link.status == BleLinkStatus.error &&
                link.failure == BleFailure.bluetoothPermissionDenied)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
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
                  '${_calibrated == false ? '  (sin calibrar)' : ''}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            if (!_vrailOk)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.battery_alert, color: AppTheme.warn, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Alimentación servo insuficiente (< 5.0 V)',
                      style: TextStyle(color: scheme.error, fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ],
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
  ///
  /// El tercer boton NO es una parada de emergencia: desconecta. Un `estop`
  /// por boton era peor que inútil, porque empujaba el servo a reposo sin
  /// saber si la puerta estaba presionada o no, y el producto de un mando a
  /// distancia se pierde igual. La parada de emergencia sigue existiendo por
  /// voz ("para" / "alto"), que si llega al firmware.
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
          onPressed: enabled ? _disconnect : null,
          icon: const Icon(Icons.bluetooth_disabled),
          label: const Text('Desconectar'),
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
