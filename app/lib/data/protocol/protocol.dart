/// Contrato de protocolo. Espejo exacto de `../PROTOCOL.md`.
///
/// Si tocas algo aca, actualiza tambien PROTOCOL.md,
/// `firmware/include/protocol.h` y `firmware/src/command_router.cpp`.

import 'dart:convert';

// ---------------------------------------------------------------------------
// Comandos app -> ESP32
// ---------------------------------------------------------------------------

enum AppCommand { open, close, estop, ping, getConfig, saveConfig, calibrate }

const Map<AppCommand, String> _wireNames = <AppCommand, String>{
  AppCommand.open: 'open',
  AppCommand.close: 'close',
  AppCommand.estop: 'estop',
  AppCommand.ping: 'ping',
  AppCommand.getConfig: 'get_config',
  AppCommand.saveConfig: 'save_config',
  AppCommand.calibrate: 'calibrate',
};

const Map<String, AppCommand> _wireToCommand = <String, AppCommand>{
  'open': AppCommand.open,
  'close': AppCommand.close,
  'estop': AppCommand.estop,
  'ping': AppCommand.ping,
  'get_config': AppCommand.getConfig,
  'save_config': AppCommand.saveConfig,
  'calibrate': AppCommand.calibrate,
};

class Command {
  const Command(
    this.cmd,
    this.seq, {
    this.pressUs,
    this.restUs,
    this.minUs,
    this.maxUs,
    this.holdMs,
    this.mode,
  });

  /// [seq] monotono creciente. El firmware descarta cualquier seq <= al ultimo
  /// aceptado, asi que nunca se debe reenviar el mismo numero.
  final AppCommand cmd;
  final int seq;
  final int? pressUs;
  final int? restUs;
  final int? minUs;
  final int? maxUs;
  final int? holdMs;
  final String? mode;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'cmd': _wireNames[cmd], 'seq': seq};
    void put(String key, int? value) {
      if (value != null) json[key] = value;
    }

    put('press_us', pressUs);
    put('rest_us', restUs);
    put('min_us', minUs);
    put('max_us', maxUs);
    put('hold_ms', holdMs);
    if (mode != null) json['mode'] = mode;
    return json;
  }

  /// JSON de una sola linea, sin saltos: el firmware lo lee como UTF-8 crudo.
  String encode() => jsonEncode(toJson());

  @override
  String toString() => 'Command(${_wireNames[cmd]}, seq=$seq)';

  /// Devuelve null si el payload esta mal formado o el comando no existe.
  /// replica las validaciones del lado C++ para fallar antes de enviar.
  static Command? decode(String raw) {
    if (raw.isEmpty) return null;

    Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (parsed is! Map<String, dynamic>) return null;

    final wire = parsed['cmd'];
    if (wire is! String) return null;
    final command = _wireToCommand[wire];
    if (command == null) return null;

    final seq = parsed['seq'];
    // seq 0 no sirve para ordenar y el firmware lo rechaza.
    if (seq is! int || seq <= 0 || seq > 65535) return null;

    int? intOrNull(Object? v) => v is int ? v : null;

    return Command(
      command,
      seq,
      pressUs: intOrNull(parsed['press_us']),
      restUs: intOrNull(parsed['rest_us']),
      minUs: intOrNull(parsed['min_us']),
      maxUs: intOrNull(parsed['max_us']),
      holdMs: intOrNull(parsed['hold_ms']),
      mode: parsed['mode'] is String ? parsed['mode'] as String : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Estados y errores del firmware
// ---------------------------------------------------------------------------

enum ServoState {
  idle,
  presenting,
  holding,
  returning,
  unknown,
  /// Solo aparece en un evento 'done': la secuencia termino en reposo.
  rest,
}

const Map<String, ServoState> _stateByName = <String, ServoState>{
  'IDLE': ServoState.idle,
  'PRESENTING': ServoState.presenting,
  'HOLDING': ServoState.holding,
  'RETURNING': ServoState.returning,
  'REST': ServoState.rest,
};

ServoState servoStateFromName(String? name) =>
    name == null ? ServoState.unknown : (_stateByName[name] ?? ServoState.unknown);

enum DoorErrorCode {
  malformed,
  unknownCmd,
  staleSeq,
  debounced,
  notCalibrated,
  outOfRange,
  stall,
  voltageLow,
}

const Map<String, DoorErrorCode> _errorByName = <String, DoorErrorCode>{
  'MALFORMED': DoorErrorCode.malformed,
  'UNKNOWN_CMD': DoorErrorCode.unknownCmd,
  'STALE_SEQ': DoorErrorCode.staleSeq,
  'DEBOUNCED': DoorErrorCode.debounced,
  'NOT_CALIBRATED': DoorErrorCode.notCalibrated,
  'OUT_OF_RANGE': DoorErrorCode.outOfRange,
  'STALL': DoorErrorCode.stall,
  'VOLTAGE_LOW': DoorErrorCode.voltageLow,
};

/// Que hacer cuando el firmware rechaza algo.
///
/// La distincion importa: un STALE_SEQ solo se ignora, un STALL hay que
// contarselo a la persona.
bool isBenign(DoorErrorCode code) =>
    code == DoorErrorCode.staleSeq || code == DoorErrorCode.debounced;

enum AppEventKind { ack, done, error, config, status, pong, unknown }

// ---------------------------------------------------------------------------
// Eventos ESP32 -> app
// ---------------------------------------------------------------------------

class AppEvent {
  const AppEvent({
    required this.kind,
    this.seq,
    this.action,
    this.state = ServoState.unknown,
    this.durMs,
    this.note,
    this.errorCode,
    this.message,
    this.pressUs,
    this.restUs,
    this.minUs,
    this.maxUs,
    this.holdMs,
    this.calibrated,
    this.servoUs,
    this.vrailOk,
    this.firmware,
  });

  final AppEventKind kind;
  final int? seq;
  final String? action;
  final ServoState state;
  final int? durMs;
  final String? note;
  final DoorErrorCode? errorCode;
  final String? message;
  final int? pressUs;
  final int? restUs;
  final int? minUs;
  final int? maxUs;
  final int? holdMs;
  final bool? calibrated;
  final int? servoUs;
  final bool? vrailOk;
  final String? firmware;

  bool get isAtRest => state == ServoState.rest || state == ServoState.idle;

  /// La secuencia fue cortada por el watchdog de la app.
  bool get isWatchdogAbort => note == 'watchdog';

  /// El servo no llego a press_us: algo esta trabado.
  bool get isStall => errorCode == DoorErrorCode.stall || note == 'stall';

  @override
  String toString() => 'AppEvent(${kind.name}, seq=$seq, state=${state.name})';

  /// Devuelve null si el payload no es un evento valido. Un mensaje que no
  /// entendemos no debe romper la app: se ignora y se loguea.
  static AppEvent? decode(String raw) {
    if (raw.isEmpty) return null;

    Object? parsed;
    try {
      parsed = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (parsed is! Map<String, dynamic>) return null;

    final ev = parsed['ev'];
    if (ev is! String) return null;

    final kind = switch (ev) {
      'ack' => AppEventKind.ack,
      'done' => AppEventKind.done,
      'error' => AppEventKind.error,
      'config' => AppEventKind.config,
      'status' => AppEventKind.status,
      'pong' => AppEventKind.pong,
      _ => AppEventKind.unknown,
    };

    int? intOrNull(Object? v) => v is int ? v : null;
    bool? boolOrNull(Object? v) => v is bool ? v : null;

    return AppEvent(
      kind: kind,
      seq: intOrNull(parsed['seq']),
      action: parsed['action'] is String ? parsed['action'] as String : null,
      state: servoStateFromName(parsed['state'] is String ? parsed['state'] as String : null),
      durMs: intOrNull(parsed['dur_ms']),
      note: parsed['note'] is String ? parsed['note'] as String : null,
      errorCode: parsed['code'] is String ? _errorByName[parsed['code'] as String] : null,
      message: parsed['msg'] is String ? parsed['msg'] as String : null,
      pressUs: intOrNull(parsed['press_us']),
      restUs: intOrNull(parsed['rest_us']),
      minUs: intOrNull(parsed['min_us']),
      maxUs: intOrNull(parsed['max_us']),
      holdMs: intOrNull(parsed['hold_ms']),
      calibrated: boolOrNull(parsed['calibrated']),
      servoUs: intOrNull(parsed['servo_us']),
      vrailOk: boolOrNull(parsed['vrail_ok']),
      firmware: parsed['fw'] is String ? parsed['fw'] as String : null,
    );
  }
}
