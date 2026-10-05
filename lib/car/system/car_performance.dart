import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';

/// Modo rendimiento: con [CarPerfMode.auto] mide los cuadros (`addTimingsCallback`) y, si
/// durante [window] el promedio pasa de [slowMs], baja la carga (menos barras y formas, sin
/// desenfoque). Vuelve a la normalidad tras [recover] con cuadros rápidos.
class CarPerformance extends ChangeNotifier {
  CarPerformance({
    CarPerfMode? mode,
    this.window = const Duration(seconds: 5),
    this.recover = const Duration(seconds: 30),
    this.slowMs = 20,
    this.fastMs = 12,
  }) : _mode = mode ?? CarPerfMode.auto;

  final Duration window;
  final Duration recover;
  final double slowMs;
  final double fastMs;

  CarPerfMode _mode;
  bool _autoLow = false;
  bool _listening = false;
  bool _started = false;

  /// Empieza a medir los cuadros (con la app en marcha; no en pruebas sin binding).
  void start() {
    _started = true;
    _sync();
  }

  // Ventana actual.
  Duration _winStart = Duration.zero;
  double _sumMs = 0;
  int _frames = 0;
  Duration _fastSince = Duration.zero;

  CarPerfMode get mode => _mode;
  set mode(CarPerfMode m) {
    if (m == _mode) return;
    final before = low;
    _mode = m;
    if (m != CarPerfMode.auto) _autoLow = false;
    _sync();
    if (before != low) notifyListeners();
  }

  /// ¿Reducir la carga ahora?
  bool get low => switch (_mode) {
    CarPerfMode.on => true,
    CarPerfMode.off => false,
    CarPerfMode.auto => _autoLow,
  };

  /// Se activó solo (para mostrarlo en Configuración).
  bool get autoTriggered => _mode == CarPerfMode.auto && _autoLow;

  void _sync() {
    final want = _started && _mode == CarPerfMode.auto;
    if (want && !_listening) {
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
      _listening = true;
    } else if (!want && _listening) {
      SchedulerBinding.instance.removeTimingsCallback(_onTimings);
      _listening = false;
    }
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      addFrame(t.timestampInMicroseconds(FramePhase.buildStart), t.totalSpan);
    }
  }

  /// Registra un cuadro (visible para pruebas). [at] = instante del cuadro en µs.
  @visibleForTesting
  void addFrame(int atMicros, Duration span) {
    if (_mode != CarPerfMode.auto) return;
    final at = Duration(microseconds: atMicros);
    if (_frames == 0) _winStart = at;
    _sumMs += span.inMicroseconds / 1000;
    _frames++;
    if (at - _winStart < window) return;
    final avg = _sumMs / _frames;
    final enough = _frames >= 30;
    _frames = 0;
    _sumMs = 0;
    if (!enough) return;
    if (!_autoLow && avg > slowMs) {
      _autoLow = true;
      _fastSince = Duration.zero;
      notifyListeners();
    } else if (_autoLow) {
      if (avg < fastMs) {
        if (_fastSince == Duration.zero) _fastSince = at;
        if (at - _fastSince >= recover) {
          _autoLow = false;
          notifyListeners();
        }
      } else {
        _fastSince = Duration.zero;
      }
    }
  }

  @override
  void dispose() {
    if (_listening) SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _listening = false;
    super.dispose();
  }
}
