import 'dart:async';

import 'package:flutter/material.dart';

import '../data/ble/ble_client.dart';
import '../data/protocol/protocol.dart';
import 'app_theme.dart';

/// Pantalla de Calibración de Servomotor - Banco de Pruebas IoT.
///
/// Permite ajustar en tiempo real el rango de pulsos PWM (µs), límites mecánicos
/// y tiempo de retención para garantizar compatibilidad con cualquier manija.
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key, required this.link});

  final BleLink link;

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  StreamSubscription<AppEvent>? _eventSub;

  int _minUs = 1000;
  int _maxUs = 2000;
  int _restUs = 1500;
  int _pressUs = 1800;
  int _holdMs = 1500;
  bool _calibrated = false;

  bool _loading = false;
  String _statusMsg = '';

  @override
  void initState() {
    super.initState();
    _eventSub = widget.link.events.listen(_onEvent);
    _loadConfig();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  void _loadConfig() {
    if (widget.link.isReady) {
      setState(() {
        _loading = true;
        _statusMsg = 'Obteniendo parámetros desde la memoria EEPROM...';
      });
      unawaited(widget.link.requestConfig());
    } else {
      setState(() {
        _statusMsg = 'Dispositivo BLE desconectado.';
      });
    }
  }

  void _onEvent(AppEvent e) {
    if (!mounted) return;

    if (e.kind == AppEventKind.config) {
      setState(() {
        _loading = false;
        if (e.minUs != null) _minUs = e.minUs!;
        if (e.maxUs != null) _maxUs = e.maxUs!;
        if (e.restUs != null) _restUs = e.restUs!;
        if (e.pressUs != null) _pressUs = e.pressUs!;
        if (e.holdMs != null) _holdMs = e.holdMs!;
        if (e.calibrated != null) _calibrated = e.calibrated!;
        _statusMsg = 'Configuración sincronizada con el microcontrolador.';
      });
    } else if (e.kind == AppEventKind.error) {
      setState(() {
        _loading = false;
        _statusMsg = 'Error recibido: ${e.message ?? e.errorCode?.name ?? "Desconocido"}';
      });
    }
  }

  Future<void> _startSweep() async {
    setState(() {
      _loading = true;
      _statusMsg = 'Ejecutando barrido de calibración (Modo Sweep)...';
    });
    final ok = await widget.link.calibrate(mode: 'sweep');
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _loading = false;
        _statusMsg = 'No se pudo emitir el comando de barrido.';
      });
    }
  }

  Future<void> _saveConfig() async {
    setState(() {
      _loading = true;
      _statusMsg = 'Escribiendo parámetros en la flash del ESP32...';
    });

    final ok = await widget.link.saveConfig(
      pressUs: _pressUs,
      restUs: _restUs,
      minUs: _minUs,
      maxUs: _maxUs,
      holdMs: _holdMs,
    );

    if (!mounted) return;
    if (!ok) {
      setState(() {
        _loading = false;
        _statusMsg = 'Fallo en la comunicación al guardar configuración.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.tune, size: 22),
            const SizedBox(width: 10),
            const Text('Calibración del Servo'),
          ],
        ),
        actions: [
          IconButton(
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: 'Recargar configuración',
            onPressed: widget.link.isReady && !_loading ? _loadConfig : null,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              children: [
                _buildStatusCard(scheme),
                const SizedBox(height: 20),
                _buildSweepCard(scheme),
                const SizedBox(height: 20),
                _buildServoRangeCard(scheme),
                const SizedBox(height: 20),
                _buildTimingCard(scheme),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: widget.link.isReady && !_loading ? _saveConfig : null,
                  icon: const Icon(Icons.save_outlined, size: 24),
                  label: const Text('GUARDAR CONFIGURACIÓN EN ESP32'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _calibrated ? AppTheme.ok : AppTheme.warn,
                    boxShadow: [
                      BoxShadow(
                        color: (_calibrated ? AppTheme.ok : AppTheme.warn)
                            .withValues(alpha: 0.6),
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
                        _calibrated ? 'Sistema Calibrado' : 'Sin Calibrar',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: _calibrated ? AppTheme.ok : AppTheme.warn,
                            ),
                      ),
                      Text(
                        _calibrated
                            ? 'Topes mecánicos validados para operación segura'
                            : 'Requiere barrido o ajuste de pulsos PWM',
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _calibrated ? Icons.verified : Icons.warning_amber_rounded,
                  color: _calibrated ? AppTheme.ok : AppTheme.warn,
                  size: 28,
                ),
              ],
            ),
            if (_statusMsg.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMsg,
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSweepCard(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.precision_manufacturing, color: scheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Modo Barrido Automatizado (Sweep)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Prueba los límites mecánicos del servomotor MG995 y marca el sistema como calibrado.',
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: widget.link.isReady && !_loading ? _startSweep : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('EJECUTAR BARRIDO DE PRUEBA'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServoRangeCard(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.linear_scale, color: scheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Pulsos PWM del Servomotor (µs)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _sliderItem(
              title: 'Posición de Reposo (rest_us)',
              subtitle: 'Ángulo seguro donde el brazo no toca la manija.',
              value: _restUs.toDouble(),
              min: _minUs.toDouble(),
              max: _maxUs.toDouble(),
              unit: 'µs',
              onChanged: (val) => setState(() => _restUs = val.round()),
            ),
            const Divider(height: 24),
            _sliderItem(
              title: 'Posición de Presión (press_us)',
              subtitle: 'Manija completamente presionada (pestillo retraído).',
              value: _pressUs.toDouble(),
              min: _minUs.toDouble(),
              max: _maxUs.toDouble(),
              unit: 'µs',
              onChanged: (val) => setState(() => _pressUs = val.round()),
            ),
            const Divider(height: 24),
            _sliderItem(
              title: 'Límite Mínimo Mecánico (min_us)',
              subtitle: 'Tope absoluto inferior para prevenir atascos.',
              value: _minUs.toDouble(),
              min: 900,
              max: 1500,
              unit: 'µs',
              onChanged: (val) {
                setState(() {
                  _minUs = val.round();
                  if (_restUs < _minUs) _restUs = _minUs;
                  if (_pressUs < _minUs) _pressUs = _minUs;
                });
              },
            ),
            const Divider(height: 24),
            _sliderItem(
              title: 'Límite Máximo Mecánico (max_us)',
              subtitle: 'Tope absoluto superior para proteger engranajes.',
              value: _maxUs.toDouble(),
              min: 1600,
              max: 2100,
              unit: 'µs',
              onChanged: (val) {
                setState(() {
                  _maxUs = val.round();
                  if (_restUs > _maxUs) _restUs = _maxUs;
                  if (_pressUs > _maxUs) _pressUs = _maxUs;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimingCard(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer_outlined, color: scheme.primary, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Temporización de Accionamiento',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _sliderItem(
              title: 'Tiempo de Retención (hold_ms)',
              subtitle: 'Tiempo que sostiene la manija abierta para permitir empujar la puerta.',
              value: _holdMs.toDouble(),
              min: 300,
              max: 3000,
              divisions: 27,
              unit: 'ms',
              onChanged: (val) => setState(() => _holdMs = val.round()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sliderItem({
    required String title,
    required String subtitle,
    required double value,
    required double min,
    required double max,
    required String unit,
    int? divisions,
    required ValueChanged<double> onChanged,
  }) {
    final clampedValue = value.clamp(min, max);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${clampedValue.round()} $unit',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Slider(
            value: clampedValue,
            min: min,
            max: max,
            divisions: divisions ?? ((max - min) / 25).round().clamp(1, 100),
            label: '${clampedValue.round()} $unit',
            onChanged: widget.link.isReady && !_loading ? onChanged : null,
          ),
        ],
      ),
    );
  }
}
