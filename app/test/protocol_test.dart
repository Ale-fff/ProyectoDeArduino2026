import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:puertavoz/data/protocol/protocol.dart';

void main() {
  group('Command.encode', () {
    test('open produce una sola linea sin saltos', () {
      final json = const Command(AppCommand.open, 42).encode();
      expect(json, '{"cmd":"open","seq":42}');
      expect(json.contains('\n'), isFalse);
    });

    test('los nombres de comando coinciden con el firmware', () {
      expect(const Command(AppCommand.open, 1).encode(), contains('"open"'));
      expect(const Command(AppCommand.close, 1).encode(), contains('"close"'));
      expect(const Command(AppCommand.getConfig, 1).encode(), contains('"get_config"'));
      expect(const Command(AppCommand.saveConfig, 1).encode(), contains('"save_config"'));
    });

    test('save_config solo incluye los campos presentes', () {
      final c = const Command(AppCommand.saveConfig, 7, pressUs: 1800, restUs: 1500);
      final json = c.encode();
      expect(json, contains('"press_us":1800'));
      expect(json, contains('"rest_us":1500'));
      expect(json, isNot(contains('min_us')));
      expect(json, isNot(contains('hold_ms')));
    });

    test('calibrate incluye el modo', () {
      final c = const Command(AppCommand.calibrate, 8, mode: 'sweep');
      expect(c.encode(), '{"cmd":"calibrate","seq":8,"mode":"sweep"}');
    });

    test('nunca supera el limite de 240 bytes del contrato', () {
      final c = const Command(
        AppCommand.saveConfig,
        65535,
        pressUs: 2100,
        restUs: 900,
        minUs: 900,
        maxUs: 2100,
        holdMs: 3000,
      );
      expect(c.encode().length, lessThan(240));
    });
  });

  group('Command.decode', () {
    test('lee un comando valido', () {
      final c = Command.decode('{"cmd":"open","seq":42}');
      expect(c, isNotNull);
      expect(c!.cmd, AppCommand.open);
      expect(c.seq, 42);
    });

    test('rechaza JSON mal formado', () {
      expect(Command.decode('esto no es json'), isNull);
      expect(Command.decode('{'), isNull);
      expect(Command.decode(''), isNull);
    });

    test('rechaza un comando desconocido', () {
      expect(Command.decode('{"cmd":"explotar","seq":1}'), isNull);
    });

    test('rechaza seq ausente, cero, negativo o fuera de rango', () {
      // Son las mismas validaciones que hace el firmware, para fallar antes
      // de enviar y no gastar una ventana de debounce.
      expect(Command.decode('{"cmd":"open"}'), isNull);
      expect(Command.decode('{"cmd":"open","seq":0}'), isNull);
      expect(Command.decode('{"cmd":"open","seq":-5}'), isNull);
      expect(Command.decode('{"cmd":"open","seq":70000}'), isNull);
    });

    test('rechaza un JSON que no es un objeto', () {
      expect(Command.decode('[1,2,3]'), isNull);
      expect(Command.decode('"open"'), isNull);
    });

    test('ida y vuelta con save_config', () {
      const original = '{"cmd":"save_config","seq":47,"press_us":1800,'
          '"rest_us":1500,"min_us":950,"max_us":2050,"hold_ms":1500}';
      final c = Command.decode(original);
      expect(c, isNotNull);
      expect(c!.cmd, AppCommand.saveConfig);
      expect(c.pressUs, 1800);
      expect(c.restUs, 1500);
      expect(c.minUs, 950);
      expect(c.maxUs, 2050);
      expect(c.holdMs, 1500);
    });
  });

  group('AppEvent.decode', () {
    test('ack', () {
      final e = AppEvent.decode(
        '{"ev":"ack","seq":42,"action":"open","state":"PRESENTING"}');
      expect(e, isNotNull);
      expect(e!.kind, AppEventKind.ack);
      expect(e.seq, 42);
      expect(e.action, 'open');
      expect(e.state, ServoState.presenting);
    });

    test('done normal', () {
      final e = AppEvent.decode(
        '{"ev":"done","seq":42,"action":"open","state":"REST","dur_ms":2340}');
      expect(e!.kind, AppEventKind.done);
      expect(e.state, ServoState.rest);
      expect(e.durMs, 2340);
      expect(e.isAtRest, isTrue);
      expect(e.isStall, isFalse);
      expect(e.isWatchdogAbort, isFalse);
    });

    test('done con nota already_at_rest', () {
      final e = AppEvent.decode('{"ev":"done","seq":43,"action":"close",'
          '"state":"REST","dur_ms":0,"note":"already_at_rest"}');
      expect(e!.note, 'already_at_rest');
      expect(e.durMs, 0);
    });

    test('done con nota watchdog', () {
      final e = AppEvent.decode('{"ev":"done","seq":0,"action":"open",'
          '"state":"REST","dur_ms":900,"note":"watchdog"}');
      expect(e!.isWatchdogAbort, isTrue);
    });

    test('error de stall', () {
      final e = AppEvent.decode('{"ev":"error","seq":42,"code":"STALL",'
          '"msg":"no alcanzo press_us; retorno a reposo"}');
      expect(e!.kind, AppEventKind.error);
      expect(e.errorCode, DoorErrorCode.stall);
      expect(e.isStall, isTrue);
      expect(e.message, contains('retorno a reposo'));
    });

    test('error benigno: stale_seq se puede ignorar', () {
      final e = AppEvent.decode('{"ev":"error","seq":3,"code":"STALE_SEQ",'
          '"msg":"seq fuera de orden"}');
      expect(e!.errorCode, DoorErrorCode.staleSeq);
      expect(isBenign(e.errorCode!), isTrue);
    });

    test('error que hay que mostrar: not_calibrated no es benigno', () {
      final e = AppEvent.decode(
          '{"ev":"error","seq":1,"code":"NOT_CALIBRATED","msg":"falta calibracion"}');
      expect(isBenign(e!.errorCode!), isFalse);
    });

    test('config completa', () {
      final e = AppEvent.decode('{"ev":"config","press_us":1800,"rest_us":1500,'
          '"min_us":950,"max_us":2050,"hold_ms":1500,"calibrated":true,'
          '"fw":"1.0.0"}');
      expect(e!.kind, AppEventKind.config);
      expect(e.pressUs, 1800);
      expect(e.restUs, 1500);
      expect(e.minUs, 950);
      expect(e.maxUs, 2050);
      expect(e.holdMs, 1500);
      expect(e.calibrated, isTrue);
      expect(e.firmware, '1.0.0');
    });

    test('status', () {
      final e = AppEvent.decode('{"ev":"status","state":"IDLE","servo_us":1500,'
          '"vrail_ok":true,"fw":"1.0.0"}');
      expect(e!.kind, AppEventKind.status);
      expect(e.state, ServoState.idle);
      expect(e.servoUs, 1500);
      expect(e.vrailOk, isTrue);
    });

    test('pong', () {
      final e = AppEvent.decode('{"ev":"pong","seq":45}');
      expect(e!.kind, AppEventKind.pong);
      expect(e.seq, 45);
    });

    test('un evento desconocido no rompe nada', () {
      final e = AppEvent.decode('{"ev":"inventado","seq":1}');
      expect(e, isNotNull);
      expect(e!.kind, AppEventKind.unknown);
    });

    test('un payload que no es evento devuelve null', () {
      expect(AppEvent.decode('no soy json'), isNull);
      expect(AppEvent.decode('{"seq":1}'), isNull);
      expect(AppEvent.decode(''), isNull);
    });

    test('un estado desconocido se degrada en vez de romper', () {
      final e = AppEvent.decode('{"ev":"ack","state":"DESTRUYENDO"}');
      expect(e!.state, ServoState.unknown);
    });
  });

  group('estados del servo', () {
    test('los cinco nombres del firmware estan mapeados', () {
      expect(servoStateFromName('IDLE'), ServoState.idle);
      expect(servoStateFromName('PRESENTING'), ServoState.presenting);
      expect(servoStateFromName('HOLDING'), ServoState.holding);
      expect(servoStateFromName('RETURNING'), ServoState.returning);
      expect(servoStateFromName('REST'), ServoState.rest);
      expect(servoStateFromName('BASURA'), ServoState.unknown);
      expect(servoStateFromName(null), ServoState.unknown);
    });
  });

  group('ejemplo del contrato, byte a byte', () {
    test('el comando de abrir del PROTOCOL.md se decodifica', () {
      // Si esto falla, el contrato se desincronizo del documento.
      const wire = '{"cmd":"open","seq":42}';
      final c = Command.decode(wire);
      expect(c!.cmd, AppCommand.open);
      expect(c.seq, 42);
      // Reencodificar tiene que dar exactamente lo mismo.
      expect(c.encode(), wire);
    });

    test('la respuesta de configuracion del PROTOCOL.md se decodifica', () {
      const wire = '{"ev":"config","press_us":1800,"rest_us":1500,"min_us":950,'
          '"max_us":2050,"hold_ms":1500,"calibrated":true,"fw":"1.0.0"}';
      final e = AppEvent.decode(wire);
      expect(e!.calibrated, isTrue);
      expect(jsonDecode(wire), isA<Map<String, dynamic>>());
    });
  });
}
