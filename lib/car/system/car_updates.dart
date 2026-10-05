import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pixel_car_player/data/bridge/native_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Texto para mostrar de un error de `updateState`.
String updateErrorText(Object? code) => switch (code) {
  'signature' =>
    'La versión nueva está firmada con otra clave: Android no deja actualizar encima. Exporta la '
        'configuración a un archivo, desinstala Pixel Car Player e instala la nueva (solo esta vez).',
  String s when s.isNotEmpty => 'No se pudo instalar ($s).',
  _ => 'No se pudo instalar.',
};

enum UpdatePhase { idle, checking, upToDate, available, downloading, installing, error }

/// Versión publicada en GitHub Releases (`checkForUpdate`).
@immutable
class UpdateInfo {
  const UpdateInfo({
    required this.available,
    this.versionName,
    this.versionCode,
    this.notes = '',
    this.htmlUrl,
    this.apkUrl,
    this.apkSize,
    this.error,
  });

  final bool available;
  final String? versionName;
  final int? versionCode;
  final String notes;
  final String? htmlUrl;
  final String? apkUrl;
  final int? apkSize;
  final String? error;

  factory UpdateInfo.fromMap(Map<String, dynamic> m) {
    String? s(Object? v) => v is String && v.isNotEmpty ? v : null;
    int? i(Object? v) => v is num ? v.toInt() : null;
    return UpdateInfo(
      available: m['available'] == true,
      versionName: s(m['versionName']),
      versionCode: i(m['versionCode']),
      notes: s(m['notes']) ?? '',
      htmlUrl: s(m['htmlUrl']),
      apkUrl: s(m['apkUrl']),
      apkSize: i(m['apkSize']),
      error: s(m['error']),
    );
  }
}

/// Buscar, descargar e instalar actualizaciones (canal nativo v3). Antes de instalar se
/// exporta la configuración a un archivo ([backup]).
class CarUpdater extends ChangeNotifier {
  CarUpdater({NativeBridge? bridge, this.backup, DateTime Function()? clock})
    : _bridge = bridge ?? NativeBridge.instance,
      _clock = clock ?? DateTime.now;

  final NativeBridge _bridge;
  final DateTime Function() _clock;

  /// Guarda la copia de seguridad; devuelve la ruta o `null`.
  Future<String?> Function()? backup;

  static const kLastCheck = 'car_update_last_check';

  UpdatePhase phase = UpdatePhase.idle;
  UpdateInfo? info;
  String? error;
  int received = 0;
  int total = 0;

  /// Versión instalada: `{versionName, versionCode, abi, package}`.
  Map<String, dynamic> version = const {};

  /// Ruta de la última copia guardada antes de instalar.
  String? backupPath;

  /// El aviso del reproductor se cerró.
  bool bannerDismissed = false;
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _disposed = false;

  bool get supported => _bridge.isSupported;
  double? get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : null;
  bool get busy =>
      phase == UpdatePhase.checking || phase == UpdatePhase.downloading || phase == UpdatePhase.installing;

  /// Mostrar el aviso discreto en el reproductor.
  bool get showBanner => phase == UpdatePhase.available && !bannerDismissed;

  String get versionName => version['versionName'] is String ? version['versionName'] as String : '—';

  void _set(void Function() f) {
    if (_disposed) return;
    f();
    notifyListeners();
  }

  void start() {
    if (_bridge.isSupported) {
      _sub ??= _bridge.events.where((e) => e['type'] == 'updateProgress' || e['type'] == 'updateState').listen(
        _onEvent,
        onError: (_) {},
      );
    }
    unawaited(loadVersion());
  }

  Future<void> loadVersion() async {
    final v = await _bridge.getAppVersion();
    if (v.isNotEmpty) _set(() => version = v);
  }

  void _onEvent(Map<String, dynamic> e) {
    if (e['type'] == 'updateProgress') {
      _set(() {
        received = (e['received'] as num?)?.toInt() ?? received;
        total = (e['total'] as num?)?.toInt() ?? total;
        if (phase != UpdatePhase.installing) phase = UpdatePhase.downloading;
      });
      return;
    }
    switch (e['state']) {
      case 'downloading':
        _set(() => phase = UpdatePhase.downloading);
      case 'installing':
        _set(() => phase = UpdatePhase.installing);
      case 'error':
        _set(() {
          phase = UpdatePhase.error;
          error = updateErrorText(e['error']);
        });
    }
  }

  /// Consulta GitHub. [silent]: no marca error si falla (búsqueda automática).
  Future<UpdateInfo?> check({bool silent = false}) async {
    if (busy) return info;
    _set(() {
      phase = UpdatePhase.checking;
      error = null;
    });
    final m = await _bridge.checkForUpdate();
    unawaited(_markChecked());
    if (m.isEmpty) {
      _set(() {
        phase = silent ? UpdatePhase.idle : UpdatePhase.error;
        error = _bridge.isSupported ? 'No se pudo consultar. ¿Hay internet?' : 'Solo funciona en la tableta.';
      });
      return null;
    }
    final i = UpdateInfo.fromMap(m);
    _set(() {
      info = i;
      if (i.error != null && !i.available) {
        phase = silent ? UpdatePhase.idle : UpdatePhase.error;
        error = i.error;
      } else {
        phase = i.available ? UpdatePhase.available : UpdatePhase.upToDate;
      }
    });
    return i;
  }

  /// Una vez por día, si el ajuste está activo.
  Future<void> autoCheckIfDue() async {
    try {
      final p = await SharedPreferences.getInstance();
      final last = p.getInt(kLastCheck);
      final now = _clock().millisecondsSinceEpoch;
      if (last != null && now - last < const Duration(hours: 24).inMilliseconds) return;
    } catch (_) {}
    await check(silent: true);
  }

  Future<void> _markChecked() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(kLastCheck, _clock().millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Exporta la configuración (si [withBackup]) y arranca la descarga + instalador.
  Future<bool> install({bool withBackup = true}) async {
    final url = info?.apkUrl;
    if (url == null || busy) return false;
    if (withBackup && backup != null) {
      final path = await backup!();
      _set(() => backupPath = path);
    }
    _set(() {
      phase = UpdatePhase.downloading;
      received = 0;
      total = info?.apkSize ?? 0;
      error = null;
    });
    final ok = await _bridge.downloadAndInstallUpdate(url);
    if (!ok) {
      _set(() {
        phase = UpdatePhase.error;
        error = _bridge.isSupported ? 'No se pudo descargar la actualización.' : 'Solo funciona en la tableta.';
      });
    }
    return ok;
  }

  void dismissBanner() => _set(() => bannerDismissed = true);

  /// Datos de ejemplo (demo web `?update=sample`).
  void fillSample() => _set(() {
    version = const {'versionName': '1.2.0', 'versionCode': 12, 'abi': 'arm64-v8a'};
    info = const UpdateInfo(
      available: true,
      versionName: '1.3.0',
      versionCode: 13,
      notes:
          '• Emparejamiento seguro con código\n• Reloj de espera y modo noche\n• Animaciones configurables\n'
          '• Aleatorio, repetir y me gusta desde la tableta',
      apkSize: 24 * 1024 * 1024,
      apkUrl: 'https://example.invalid/app.apk',
    );
    phase = UpdatePhase.available;
  });

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
