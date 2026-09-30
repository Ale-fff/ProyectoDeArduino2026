import 'dart:async';

import 'package:flutter/material.dart';

import '../data/ble/ble_client.dart';
import '../data/protocol/protocol.dart';
import 'app_theme.dart';

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
        _statusMsg = 'Obteniendo configuración del dispositivo...';
      });
      unawaited(widget.link.requestConfig());
    } else {
      setState(() {
        _statusMsg = 'Dispositivo no conectado';
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
        _statusMsg = 'Configuración actualizada.';
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
      _statusMsg = 'Iniciando barrido de calibración...';
    });
    final ok = await widget.link.calibrate(mode: 'sweep');
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _loading = false;
        _statusMsg = 'No se pudo enviar el comando de calibración.';
      });
    }
  }

  Future<void> _saveConfig() async {
    setState(() {
      _loading = true;
      _statusMsg = 'Guardando configuración en el ESP32...';
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
        _statusMsg = 'Fallo al enviar configuración.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calibración y Ajustes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar configuración',
            onPressed: widget.link.isReady && !_loading ? _loadConfig : null,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildStatusCard(scheme),
                const SizedBox(height: 20),
                _buildSweepCard(scheme),
                const SizedBox(height: 20),
                _buildServoRangeCard(scheme),
                const SizedBox(height: 20),
                _buildTimingCard(scheme),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: widget.link.isReady && !_loading ? _saveConfig : null,
                  icon: const Icon(Icons.save),
                  label: const Text('Guardar Configuración'),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _calibrated ? Icons.verified : Icons.warning_amber_rounded,
                  color: _calibrated ? AppTheme.ok : AppTheme.warn,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _calibrated ? 'Sistema Calibrado' : 'Sin Calibrar',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _calibrated ? AppTheme.ok : AppTheme.warn,
                        ),
                  ),
                ),
              ],
            ),
            if (_statusMsg.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _statusMsg,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Modo Barrido (Sweep)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Prueba los límites y marca el dispositivo como calibrado ante el sistema.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: widget.link.isReady && !_loading ? _startSweep : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Ejecutar Barrido de Calibración'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServoRangeCard(ColorScheme scheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recorrido del Servomotor (µs)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            _sliderItem(
              title: 'Posición de Reposo (rest_us)',
              subtitle: 'Posición segura donde no toca la manija.',
              value: _restUs.toDouble(),
              min: _minUs.toDouble(),
              max: _maxUs.toDouble(),
              unit: 'µs',
              onChanged: (val) => setState(() => _restUs = val.round()),
            ),
            const Divider(),
            _sliderItem(
              title: 'Posición de Presión (press_us)',
              subtitle: 'Manija completamente presionada (pestillo retraído).',
              value: _pressUs.toDouble(),
              min: _minUs.toDouble(),
              max: _maxUs.toDouble(),
              unit: 'µs',
              onChanged: (val) => setState(() => _pressUs = val.round()),
            ),
            const Divider(),
            _sliderItem(
              title: 'Límite Mínimo Mecánico (min_us)',
              subtitle: 'Tope absoluto inferior.',
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
            const Divider(),
            _sliderItem(
              title: 'Límite Máximo Mecánico (max_us)',
              subtitle: 'Tope absoluto superior.',
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tiempos de Accionamiento',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            _sliderItem(
              title: 'Tiempo de Retención (hold_ms)',
              subtitle: 'Cuánto tiempo sostiene la manija abierta para empujar la puerta.',
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${clampedValue.round()} $unit',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          Text(subtitle,
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              )),
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
