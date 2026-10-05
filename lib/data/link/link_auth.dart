import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Emparejamiento seguro (CONTRACT.md §1 v3): HMAC-SHA256, códigos de 6 dígitos y la lista
/// de celulares de confianza de la tableta.
class LinkAuth {
  LinkAuth._();

  /// Nonce nuevo por conexión: 16 bytes en hex (32 caracteres).
  static String nonce([math.Random? rnd]) {
    final r = rnd ?? math.Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// `HMAC_SHA256(key = token (bytes de la cadena hex), msg = "<nonce>:<id>")` en hex minúsculas.
  static String mac({required String token, required String nonce, required String id}) =>
      Hmac(sha256, utf8.encode(token)).convert(utf8.encode('$nonce:$id')).toString();

  /// Compara en tiempo constante (no revela por dónde difiere).
  static bool sameMac(String a, String b) {
    final x = a.toLowerCase(), y = b.toLowerCase();
    if (x.length != y.length) return false;
    var diff = 0;
    for (var i = 0; i < x.length; i++) {
      diff |= x.codeUnitAt(i) ^ y.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Código de 6 dígitos (con `Random.secure`).
  static String pairCode([math.Random? rnd]) {
    final r = rnd ?? math.Random.secure();
    return List.generate(6, (_) => r.nextInt(10)).join();
  }

  /// `123456` → `123 456` (para leerlo en voz alta / en pantalla).
  static String formatCode(String code) =>
      code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;

  /// Token aceptable: 32–128 caracteres hex (el celular manda 64).
  static bool validToken(Object? t) => t is String && RegExp(r'^[0-9a-fA-F]{32,128}$').hasMatch(t);

  /// Validez de un código mostrado.
  static const codeTtl = Duration(minutes: 2);

  /// Intentos por código.
  static const maxAttempts = 5;
}

/// Un celular de confianza.
@immutable
class TrustedPhone {
  const TrustedPhone({required this.id, required this.token, required this.name, required this.pairedAt});
  final String id;
  final String token;
  final String name;
  final DateTime pairedAt;

  Map<String, dynamic> toJson() => {'token': token, 'name': name, 'pairedAt': pairedAt.millisecondsSinceEpoch};

  static TrustedPhone? fromJson(String id, Object? j) {
    if (j is! Map) return null;
    final token = j['token'];
    if (!LinkAuth.validToken(token)) return null;
    final at = j['pairedAt'];
    return TrustedPhone(
      id: id,
      token: token as String,
      name: j['name'] is String && (j['name'] as String).isNotEmpty ? j['name'] as String : 'Celular',
      pairedAt: at is num ? DateTime.fromMillisecondsSinceEpoch(at.toInt()) : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Celulares de confianza (`car_trusted_phones`: JSON `{id: {token, name, pairedAt}}`) y el
/// ajuste "Requerir emparejamiento" (`car_require_pairing`, def. true).
class CarTrustStore extends ChangeNotifier {
  CarTrustStore({Map<String, TrustedPhone>? phones, bool requirePairing = true, this.persist = false})
    : _phones = {...?phones},
      _require = requirePairing;

  static const kPhones = 'car_trusted_phones';
  static const kRequire = 'car_require_pairing';

  /// `false` = solo en memoria (pruebas / web con `?custom=`).
  final bool persist;
  final Map<String, TrustedPhone> _phones;
  bool _require;

  static Future<CarTrustStore> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return CarTrustStore(
        phones: decodePhones(p.getString(kPhones)),
        requirePairing: p.getBool(kRequire) ?? true,
        persist: true,
      );
    } catch (_) {
      return CarTrustStore();
    }
  }

  static Map<String, TrustedPhone> decodePhones(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return {};
      final out = <String, TrustedPhone>{};
      for (final e in j.entries) {
        final t = TrustedPhone.fromJson('${e.key}', e.value);
        if (t != null) out[t.id] = t;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  bool get requirePairing => _require;
  set requirePairing(bool v) {
    if (v == _require) return;
    _require = v;
    notifyListeners();
    unawaited(_save());
  }

  /// Ordenados del más reciente al más viejo.
  List<TrustedPhone> get phones => _phones.values.toList()..sort((a, b) => b.pairedAt.compareTo(a.pairedAt));

  TrustedPhone? operator [](String? id) => id == null ? null : _phones[id];
  String? tokenFor(String? id) => this[id]?.token;

  void trust(String id, String token, String name, {DateTime? at}) {
    _phones[id] = TrustedPhone(id: id, token: token, name: name, pairedAt: at ?? DateTime.now());
    notifyListeners();
    unawaited(_save());
  }

  void forget(String id) {
    if (_phones.remove(id) == null) return;
    notifyListeners();
    unawaited(_save());
  }

  void forgetAll() {
    if (_phones.isEmpty) return;
    _phones.clear();
    notifyListeners();
    unawaited(_save());
  }

  /// `{id: {token, name, pairedAt}}` (para la copia de seguridad).
  Map<String, dynamic> toJson() => {for (final p in _phones.values) p.id: p.toJson()};

  /// Reemplaza todo (restaurar copia de seguridad).
  void restore(Object? json, {bool? requirePairing}) {
    _phones
      ..clear()
      ..addAll(json is Map ? decodePhones(jsonEncode(json)) : const {});
    if (requirePairing != null) _require = requirePairing;
    notifyListeners();
    unawaited(_save());
  }

  Future<void> _save() async {
    if (!persist) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(kPhones, jsonEncode(toJson()));
      await p.setBool(kRequire, _require);
    } catch (e) {
      debugPrint('CarTrustStore: no se pudo guardar ($e)');
    }
  }
}

/// Estado del código que muestra la tableta.
enum PairingPhase { showing, success, failed, expired }

/// Código de emparejamiento en pantalla.
@immutable
class PairingPrompt {
  const PairingPrompt({
    required this.code,
    required this.phoneName,
    required this.phoneId,
    required this.expiresAt,
    this.attempts = 0,
    this.phase = PairingPhase.showing,
  });

  final String code;
  final String phoneName;
  final String? phoneId;
  final DateTime expiresAt;
  final int attempts;
  final PairingPhase phase;

  bool expiredAt(DateTime now) => !now.isBefore(expiresAt);

  PairingPrompt copyWith({int? attempts, PairingPhase? phase}) => PairingPrompt(
    code: code,
    phoneName: phoneName,
    phoneId: phoneId,
    expiresAt: expiresAt,
    attempts: attempts ?? this.attempts,
    phase: phase ?? this.phase,
  );
}

/// Estado de seguridad de la sesión actual.
enum LinkAuthState {
  /// Sin enlace.
  none,

  /// Conectado; esperando `auth` o emparejamiento.
  pending,

  /// Mostrando un código.
  pairing,

  /// Autenticado (o "Requerir emparejamiento" apagado).
  authenticated,
}
