import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Audio real de la tableta: los eventos `{type:'fft', bands(64), rms}` del Visualizer
/// nativo (sesión 0 = todo lo que suena, también la app Bluetooth del radio).
///
/// Guarda el último cuadro sin notificar (el disco lo lee en cada frame) y publica
/// [detected] = "hay audio": se enciende cuando `rms` supera [threshold] y se apaga tras
/// [hold] sin energía (o sin cuadros), para no parpadear en los silencios cortos.
class CarAudioLevels {
  CarAudioLevels({
    DateTime Function()? clock,
    this.threshold = 0.04,
    this.hold = const Duration(milliseconds: 1500),
    this.stale = const Duration(milliseconds: 600),
  }) : _clock = clock ?? DateTime.now;

  static const bandCount = 64;

  final DateTime Function() _clock;

  /// `rms` mínimo para considerar que suena algo.
  final double threshold;

  /// Cuánto se mantiene "audio detectado" después del último cuadro con energía.
  final Duration hold;

  /// Un cuadro más viejo que esto ya no cuenta (el Visualizer se detuvo).
  final Duration stale;

  final Float32List bands = Float32List(bandCount);
  double rms = 0;
  DateTime? _lastFrame;
  DateTime? _lastLoud;
  Timer? _expiry;
  bool _disposed = false;

  /// Hay audio real sonando (con histéresis de [hold]).
  final ValueNotifier<bool> detected = ValueNotifier(false);

  /// Llegaron cuadros hace poco.
  bool get live {
    final t = _lastFrame;
    return t != null && _clock().difference(t) <= stale;
  }

  /// Aplica un evento `fft` del canal nativo.
  void onEvent(Map<String, dynamic> e) {
    final b = e['bands'];
    final r = e['rms'];
    onFrame(b is List ? b : const [], r is num ? r.toDouble() : 0);
  }

  void onFrame(List<dynamic> values, double level) {
    if (_disposed) return;
    final now = _clock();
    _lastFrame = now;
    rms = level.isFinite ? level : 0;
    final n = math.min(values.length, bandCount);
    for (var i = 0; i < bandCount; i++) {
      final v = i < n ? values[i] : 0;
      final d = v is num ? v.toDouble() : 0.0;
      bands[i] = d.isFinite ? d.clamp(0.0, 1.0) : 0;
    }
    if (rms > threshold) {
      _lastLoud = now;
      detected.value = true;
      _expiry?.cancel();
      _expiry = Timer(hold + const Duration(milliseconds: 50), expire);
    } else {
      expire();
    }
  }

  /// Apaga [detected] si pasó [hold] desde el último cuadro con energía.
  void expire() {
    if (_disposed) return;
    final loud = _lastLoud;
    if (loud == null || _clock().difference(loud) >= hold) {
      if (!live) bands.fillRange(0, bandCount, 0);
      detected.value = false;
    }
  }

  /// Sin Visualizer (se detuvo o la app pasó a segundo plano).
  void reset() {
    _expiry?.cancel();
    _lastFrame = null;
    _lastLoud = null;
    rms = 0;
    bands.fillRange(0, bandCount, 0);
    if (!_disposed) detected.value = false;
  }

  /// Nivel 0..1 de la barra [k] (0 = graves, arriba) de [half] barras por lado.
  double level(int k, int half, {double sensitivity = 1}) => mapBands(bands, k, half, sensitivity: sensitivity);

  /// Reparte las [src] bandas (graves → agudos) entre [half] barras: cada barra promedia
  /// su tramo (o toma la banda más cercana si hay más barras que bandas). Aplica la
  /// ganancia [sensitivity] y la curva de Harmonix (`pow(x, 1.8) * 0.9`).
  static double mapBands(Float32List src, int k, int half, {double sensitivity = 1}) {
    final n = src.length;
    if (n == 0 || half <= 0 || k < 0 || k >= half) return 0;
    var lo = (k * n / half).floor();
    var hi = ((k + 1) * n / half).floor();
    lo = lo.clamp(0, n - 1);
    hi = hi.clamp(lo + 1, n);
    var sum = 0.0;
    for (var i = lo; i < hi; i++) {
      sum += src[i];
    }
    final v = (sum / (hi - lo) * sensitivity).clamp(0.0, 1.0);
    return math.pow(v, 1.8) * 0.9;
  }

  void dispose() {
    _disposed = true;
    _expiry?.cancel();
    detected.dispose();
  }
}
