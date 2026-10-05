import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:pixel_car_player/data/bridge/native_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Resultado de `checkForUpdate`.
class UpdateInfo {
  const UpdateInfo({
    required this.available,
    this.versionName = '',
    this.versionCode = 0,
    this.notes = '',
    this.htmlUrl = '',
    this.apkUrl = '',
    this.apkSize = 0,
    this.error,
  });
  final bool available;
  final String versionName;
  final int versionCode;
  final String notes;
  final String htmlUrl;
  final String apkUrl;
  final int apkSize;
  final String? error;

  factory UpdateInfo.fromMap(Map<String, dynamic> m) {
    final e = '${m['error'] ?? ''}'.trim();
    return UpdateInfo(
      available: m['available'] == true,
      versionName: '${m['versionName'] ?? ''}',
      versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
      notes: '${m['notes'] ?? ''}'.trim(),
      htmlUrl: '${m['htmlUrl'] ?? ''}',
      apkUrl: '${m['apkUrl'] ?? ''}',
      apkSize: (m['apkSize'] as num?)?.toInt() ?? 0,
      error: e.isEmpty ? (m.isEmpty ? 'Sin respuesta' : null) : e,
    );
  }
}

enum UpdatePhase { idle, checking, downloading, installing, error }

/// Copia de seguridad de los ajustes del celular (prefs `phone_*`).
///
/// Incluye la contraseña del hotspot del carro: es la copia del propio usuario. No
/// incluye los emparejamientos (los tokens viven en las prefs nativas).
class PhoneBackup {
  PhoneBackup._();
  static const app = 'pixel-car-player';
  static const kind = 'phone-settings';
  static const format = 1;

  /// Claves que no tiene sentido copiar (estado transitorio).
  static const _skip = {UpdatesController.kLastCheck};

  static Future<String> export({String? appVersion}) async {
    final p = await SharedPreferences.getInstance();
    final prefs = <String, Object?>{};
    final keys =
        p
            .getKeys()
            .where((k) => k.startsWith('phone_') && !_skip.contains(k))
            .toList()
          ..sort();
    for (final k in keys) {
      final v = p.get(k);
      final t = switch (v) {
        bool _ => 'bool',
        int _ => 'int',
        double _ => 'double',
        String _ => 'string',
        List _ => 'list',
        _ => null,
      };
      if (t != null) prefs[k] = {'t': t, 'v': v};
    }
    return const JsonEncoder.withIndent('  ').convert({
      'app': app,
      'kind': kind,
      'format': format,
      'exportedAt': DateTime.now().toIso8601String(),
      'appVersion': ?appVersion,
      'includesHotspotPassword': prefs.containsKey(
        'phone_car_hotspot_password',
      ),
      'prefs': prefs,
    });
  }

  /// Aplica una copia. Devuelve cuántos ajustes se restauraron o lanza
  /// [FormatException] con un mensaje apto para mostrar.
  static Future<int> restore(String json) async {
    final Object? data;
    try {
      data = jsonDecode(json);
    } catch (_) {
      throw const FormatException('El archivo no es un JSON válido.');
    }
    if (data is! Map || data['app'] != app || data['prefs'] is! Map) {
      throw const FormatException('No es una copia de Pixel Car Player.');
    }
    if (data['kind'] != kind) {
      throw const FormatException(
        'Es una copia de la pantalla del carro, no del celular.',
      );
    }
    final p = await SharedPreferences.getInstance();
    var n = 0;
    for (final e in (data['prefs'] as Map).entries) {
      final k = '${e.key}';
      if (!k.startsWith('phone_') || _skip.contains(k)) continue;
      var raw = e.value;
      String? t;
      if (raw is Map && raw.containsKey('v')) {
        t = raw['t'] as String?;
        raw = raw['v'];
      }
      final ok = switch ((t, raw)) {
        ('int', final num v) => await p.setInt(k, v.toInt()),
        ('double', final num v) => await p.setDouble(k, v.toDouble()),
        (_, final bool v) => await p.setBool(k, v),
        (null, final int v) => await p.setInt(k, v),
        (null, final double v) => await p.setDouble(k, v),
        (_, final String v) => await p.setString(k, v),
        (_, final List v) => await p.setStringList(
          k,
          v.map((x) => '$x').toList(),
        ),
        _ => false,
      };
      if (ok) n++;
    }
    return n;
  }
}

/// Actualizaciones desde GitHub Releases (nativo) + copia antes de instalar.
class UpdatesController extends ChangeNotifier {
  UpdatesController(this._bridge, {required this.supported});

  final NativeBridge _bridge;
  final bool supported;

  static const kAutoCheck = 'phone_update_autocheck';
  static const kLastCheck = 'phone_update_last_check';
  static const kLastBackup = 'phone_backup_last_path';

  String versionName = '';
  int versionCode = 0;
  String abi = '';
  UpdateInfo? info;
  UpdatePhase phase = UpdatePhase.idle;
  String? error;
  int received = 0;
  int total = 0;
  bool canInstall = true;
  bool autoCheck = true;
  DateTime? lastCheck;
  String lastBackup = '';

  /// La búsqueda diaria encontró algo (aviso discreto en el inicio).
  bool bannerVisible = false;

  Timer? _demo;
  bool _disposed = false;

  /// El APK nuevo está firmado con otra clave que la versión instalada: Android no deja
  /// actualizar encima.
  static const signatureHelp =
      'La versión nueva está firmada con otra clave y Android no deja instalarla '
      'encima. Exporta tus ajustes (Copia de seguridad), desinstala la app una vez, '
      'instala la nueva y restaura la copia.';

  String get versionLabel {
    if (versionName.isEmpty) return '—';
    final code = versionCode > 0 ? ' ($versionCode)' : '';
    return 'v$versionName$code';
  }

  double? get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : null;
  bool get busy =>
      phase == UpdatePhase.checking ||
      phase == UpdatePhase.downloading ||
      phase == UpdatePhase.installing;

  Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      autoCheck = p.getBool(kAutoCheck) ?? true;
      final lc = p.getInt(kLastCheck);
      lastCheck = lc == null ? null : DateTime.fromMillisecondsSinceEpoch(lc);
      lastBackup = p.getString(kLastBackup) ?? '';
    } catch (_) {}
    if (!supported) {
      versionName = '1.0.0';
      versionCode = 1;
      abi = 'demo';
    } else {
      try {
        final v = await _bridge.getAppVersion();
        versionName = '${v['versionName'] ?? ''}';
        versionCode = (v['versionCode'] as num?)?.toInt() ?? 0;
        abi = '${v['abi'] ?? ''}';
      } catch (_) {}
    }
    await refreshInstallPermission();
    _notify();
  }

  /// Búsqueda automática (una vez al día, solo con nativo).
  Future<void> maybeAutoCheck() async {
    if (!supported || !autoCheck || busy) return;
    final last = lastCheck;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(hours: 23)) {
      return;
    }
    await check(silent: true);
  }

  Future<void> refreshInstallPermission() async {
    if (!supported) {
      canInstall = true;
    } else {
      try {
        canInstall = await _bridge.canInstallPackages();
      } catch (_) {}
    }
    _notify();
  }

  Future<void> openInstallPermission() =>
      _bridge.openInstallPermissionSettings();

  Future<void> setAutoCheck(bool v) async {
    autoCheck = v;
    _notify();
    try {
      (await SharedPreferences.getInstance()).setBool(kAutoCheck, v);
    } catch (_) {}
  }

  Future<void> check({bool silent = false}) async {
    if (busy) return;
    phase = UpdatePhase.checking;
    error = null;
    _notify();
    UpdateInfo r;
    if (!supported) {
      r = const UpdateInfo(
        available: true,
        versionName: '1.1.0',
        versionCode: 2,
        notes:
            '• Emparejamiento seguro con código de 6 dígitos.\n'
            '• El transmisor se enciende solo al subir al carro.\n'
            '• Actualizaciones y copia de seguridad desde Ajustes.\n'
            '• Animaciones nuevas en todo el celular.',
        apkUrl: 'https://example.invalid/pixel-car-player.apk',
        apkSize: 24117248,
      );
    } else {
      try {
        r = UpdateInfo.fromMap(await _bridge.checkForUpdate());
      } catch (e) {
        r = UpdateInfo(available: false, error: '$e');
      }
    }
    info = r;
    lastCheck = DateTime.now();
    try {
      (await SharedPreferences.getInstance()).setInt(
        kLastCheck,
        lastCheck!.millisecondsSinceEpoch,
      );
    } catch (_) {}
    if (r.error != null) {
      phase = silent ? UpdatePhase.idle : UpdatePhase.error;
      error = silent ? null : r.error;
    } else {
      phase = UpdatePhase.idle;
      if (silent && r.available) bannerVisible = true;
    }
    _notify();
  }

  void dismissBanner() {
    bannerVisible = false;
    _notify();
  }

  /// Exporta los ajustes. Devuelve la ruta (o null si no se pudo guardar como archivo;
  /// en web/escritorio la copia se devuelve en [lastExportJson] para el portapapeles).
  String? lastExportJson;

  Future<String?> exportBackup() async {
    final json = await PhoneBackup.export(
      appVersion: versionName.isEmpty ? null : versionName,
    );
    lastExportJson = json;
    String? path;
    if (supported) {
      try {
        path = await _bridge.saveBackupFile(json);
      } catch (_) {}
    }
    if (path != null && path.isNotEmpty) {
      lastBackup = path;
      try {
        (await SharedPreferences.getInstance()).setString(kLastBackup, path);
      } catch (_) {}
      _notify();
    }
    return path;
  }

  /// Elige un archivo y devuelve su contenido (null si se canceló o no hay nativo).
  Future<String?> pickBackup() async {
    if (!supported) return null;
    try {
      return await _bridge.pickBackupFile();
    } catch (_) {
      return null;
    }
  }

  /// Copia de seguridad automática + descarga + instalador.
  Future<({bool ok, String message})> install() async {
    final i = info;
    if (i == null || !i.available || i.apkUrl.isEmpty || busy) {
      return (ok: false, message: 'No hay una actualización para instalar.');
    }
    if (!canInstall) {
      return (
        ok: false,
        message:
            'Primero permite que Pixel Car Player instale actualizaciones.',
      );
    }
    phase = UpdatePhase.downloading;
    received = 0;
    total = i.apkSize;
    error = null;
    _notify();
    final backup = await exportBackup();
    final note = backup != null ? ' Copia de tus ajustes en $backup.' : '';
    if (!supported) {
      _demo?.cancel();
      _demo = Timer.periodic(const Duration(milliseconds: 120), (t) {
        received = (received + total ~/ 18).clamp(0, total);
        if (received >= total) {
          t.cancel();
          phase = UpdatePhase.installing;
        }
        _notify();
      });
      return (
        ok: true,
        message: 'Descargando la versión ${i.versionName}…$note',
      );
    }
    bool started;
    try {
      started = await _bridge.downloadAndInstallUpdate(i.apkUrl);
    } catch (_) {
      started = false;
    }
    if (!started && phase == UpdatePhase.downloading) {
      phase = UpdatePhase.error;
      error = 'No se pudo iniciar la descarga.';
      _notify();
      return (ok: false, message: error!);
    }
    return (ok: true, message: 'Descargando la versión ${i.versionName}…$note');
  }

  /// Eventos nativos `updateProgress` / `updateState`.
  void handleEvent(Map<String, dynamic> e) {
    switch (e['type']) {
      case 'updateProgress':
        received = (e['received'] as num?)?.toInt() ?? received;
        final t = (e['total'] as num?)?.toInt() ?? 0;
        if (t > 0) total = t;
        if (phase != UpdatePhase.installing) phase = UpdatePhase.downloading;
        _notify();
      case 'updateState':
        switch (e['state']) {
          case 'downloading':
            phase = UpdatePhase.downloading;
          case 'installing':
            phase = UpdatePhase.installing;
          case 'error':
            phase = UpdatePhase.error;
            final err = '${e['error'] ?? ''}'.trim();
            error = err == 'signature'
                ? signatureHelp
                : (err.isEmpty ? 'Falló la actualización.' : err);
          default:
            phase = UpdatePhase.idle;
        }
        _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _demo?.cancel();
    super.dispose();
  }
}
