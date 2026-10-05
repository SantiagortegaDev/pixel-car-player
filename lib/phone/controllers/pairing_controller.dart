import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pixel_car_player/data/bridge/native_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pedido de código de la tableta (evento nativo `pairNeeded`).
class PairRequest {
  PairRequest({required this.carId, required this.carName, DateTime? at})
    : at = at ?? DateTime.now();
  final String carId;
  final String carName;
  final DateTime at;

  /// El código que muestra la tableta vale 2 minutos (CONTRACT §1 v3).
  static const validity = Duration(minutes: 2);
  bool get expired => DateTime.now().difference(at) > validity;
}

class PairedCar {
  const PairedCar({required this.id, required this.name, this.pairedAt});
  final String id;
  final String name;
  final DateTime? pairedAt;

  static DateTime? _date(Object? v) {
    if (v is num) {
      final n = v.toInt();
      // Segundos o milisegundos desde epoch.
      return DateTime.fromMillisecondsSinceEpoch(
        n < 100000000000 ? n * 1000 : n,
      );
    }
    if (v is String) return DateTime.tryParse(v) ?? _date(int.tryParse(v));
    return null;
  }

  factory PairedCar.fromMap(Map<String, dynamic> m) => PairedCar(
    id: '${m['id'] ?? ''}',
    name: '${m['name'] ?? 'Pantalla del carro'}',
    pairedAt: _date(m['pairedAt']),
  );
}

enum PairPhase { idle, submitting, success, failed }

/// Emparejamiento seguro con la tableta (CONTRACT §1 v3): pedido de código, envío,
/// resultado, carros emparejados y la preferencia "Requerir emparejamiento".
class PairingController extends ChangeNotifier {
  PairingController(this._bridge, {required this.supported});

  final NativeBridge _bridge;
  final bool supported;

  /// Leída por el nativo como `flutter.phone_require_pairing`.
  static const kRequire = 'phone_require_pairing';

  /// Sin respuesta de la tableta en este tiempo → error.
  static const submitTimeout = Duration(seconds: 15);

  bool requirePairing = true;
  List<PairedCar> paired = const [];
  PairRequest? pending;
  PairPhase phase = PairPhase.idle;

  /// Motivo del último fallo (`code` | `expired` | `busy` | `send` | `timeout` | …).
  String? failReason;

  /// Sube con cada fallo (para sacudir las casillas).
  int failCount = 0;

  /// Último carro emparejado con éxito (para el aviso).
  String? lastPairedName;

  /// Sin nativo (web / pruebas) el resultado se simula: cualquier código salvo
  /// `000000` empareja. Las pruebas lo apagan para inyectar `pairResult`.
  bool demoAutoResult = true;

  Timer? _timeout;
  Timer? _demo;
  bool _disposed = false;

  Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      requirePairing = p.getBool(kRequire) ?? true;
    } catch (_) {}
    await refreshPaired();
  }

  Future<void> refreshPaired() async {
    if (!supported) {
      paired = [
        PairedCar(
          id: 'demo-k24',
          name: 'Pantalla K24',
          pairedAt: DateTime(2026, 10, 1, 18, 30),
        ),
      ];
      _notify();
      return;
    }
    try {
      paired = (await _bridge.getPairedCars())
          .map(PairedCar.fromMap)
          .where((c) => c.id.isNotEmpty)
          .toList();
    } catch (_) {}
    _notify();
  }

  Future<void> setRequirePairing(bool v) async {
    requirePairing = v;
    _notify();
    try {
      (await SharedPreferences.getInstance()).setBool(kRequire, v);
    } catch (_) {}
  }

  Future<void> forget(String id) async {
    paired = paired.where((c) => c.id != id).toList();
    _notify();
    if (supported) {
      try {
        await _bridge.forgetCar(id);
      } catch (_) {}
      await refreshPaired();
    }
  }

  /// ¿Hay un pedido vigente para mostrar el diálogo?
  bool get hasPending => pending != null && !pending!.expired;

  /// Eventos nativos `pairNeeded` / `pairResult`.
  void handleEvent(Map<String, dynamic> e) {
    switch (e['type']) {
      case 'pairNeeded':
        final id = '${e['carId'] ?? ''}';
        final name = '${e['carName'] ?? ''}'.trim();
        // Un pedido nuevo (o repetido) reinicia el diálogo.
        pending = PairRequest(
          carId: id,
          carName: name.isEmpty ? 'la pantalla del carro' : name,
        );
        if (phase != PairPhase.submitting) {
          phase = PairPhase.idle;
          failReason = null;
        }
        _notify();
      case 'pairResult':
        _onResult(
          carId: '${e['carId'] ?? ''}',
          ok: e['ok'] == true,
          reason: e['reason'] as String?,
        );
    }
  }

  Future<void> submit(String code) async {
    final req = pending;
    if (req == null || phase == PairPhase.submitting) return;
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _fail('format');
      return;
    }
    phase = PairPhase.submitting;
    failReason = null;
    _notify();
    _timeout?.cancel();
    _timeout = Timer(submitTimeout, () {
      if (phase == PairPhase.submitting) _fail('timeout');
    });
    if (!supported) {
      if (demoAutoResult) {
        _demo?.cancel();
        _demo = Timer(const Duration(milliseconds: 700), () {
          _onResult(
            carId: req.carId,
            ok: code != '000000',
            reason: code == '000000' ? 'code' : null,
          );
        });
      }
      return;
    }
    bool sent;
    try {
      sent = await _bridge.submitPairCode(req.carId, code);
    } catch (_) {
      sent = false;
    }
    if (!sent && phase == PairPhase.submitting) _fail('send');
  }

  void _onResult({required String carId, required bool ok, String? reason}) {
    final req = pending;
    if (req != null &&
        carId.isNotEmpty &&
        req.carId.isNotEmpty &&
        carId != req.carId) {
      return; // resultado de otro carro
    }
    _timeout?.cancel();
    if (ok) {
      phase = PairPhase.success;
      failReason = null;
      lastPairedName = req?.carName;
      pending = null;
      _notify();
      refreshPaired();
    } else {
      _fail(reason ?? 'unknown');
    }
  }

  void _fail(String reason) {
    _timeout?.cancel();
    phase = PairPhase.failed;
    failReason = reason;
    failCount++;
    _notify();
  }

  /// El usuario cerró el diálogo sin emparejar.
  void dismiss() {
    _timeout?.cancel();
    _demo?.cancel();
    pending = null;
    if (phase != PairPhase.success) phase = PairPhase.idle;
    failReason = null;
    _notify();
  }

  /// Tras mostrar el éxito: vuelve a reposo.
  void acknowledgeSuccess() {
    phase = PairPhase.idle;
    _notify();
  }

  /// Texto para el usuario del motivo de fallo.
  static String reasonText(String? reason) => switch (reason) {
    'code' => 'Código incorrecto',
    'expired' => 'Código vencido: pide uno nuevo en la pantalla del carro',
    'busy' => 'La pantalla está ocupada; inténtalo de nuevo en un momento',
    'format' => 'Escribe los 6 dígitos',
    'send' => 'No se pudo enviar el código: revisa la conexión con el carro',
    'timeout' => 'La pantalla del carro no respondió',
    _ => 'No se pudo emparejar',
  };

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timeout?.cancel();
    _demo?.cancel();
    super.dispose();
  }
}
