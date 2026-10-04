import 'dart:collection';

import 'package:flutter/foundation.dart';

/// Red IPv4 de la tableta (`getWifiNetworks` del canal nativo, o `dart:io` como respaldo).
@immutable
class LinkNetwork {
  const LinkNetwork({
    required this.ip,
    this.iface = '',
    this.prefix = 24,
    this.gateway,
    this.hasInternet = false,
    this.isDefault = false,
    this.isWifi = false,
    this.isHotspot = false,
  });

  final String iface;
  final String ip;
  final int prefix;
  final String? gateway;
  final bool hasInternet;
  final bool isDefault;
  final bool isWifi;

  /// La tableta es el punto de acceso de esta red (hotspot del carro).
  final bool isHotspot;

  static LinkNetwork? fromMap(Map<String, dynamic> m) {
    final ip = m['ip'];
    if (ip is! String || ip.isEmpty) return null;
    final p = m['prefix'];
    final gw = m['gateway'];
    return LinkNetwork(
      ip: ip,
      iface: m['iface'] is String ? m['iface'] as String : '',
      prefix: p is num ? p.toInt() : 24,
      gateway: gw is String && gw.isNotEmpty && gw != '0.0.0.0' ? gw : null,
      hasInternet: m['hasInternet'] == true,
      isDefault: m['isDefault'] == true,
      isWifi: m['isWifi'] == true,
      isHotspot: m['isHotspot'] == true,
    );
  }

  /// Dirección de broadcast de la subred (`null` si no aplica).
  String? get broadcast => subnetBroadcast(ip, prefix);

  /// Descripción corta para la lista de Diagnóstico.
  String get kind => isHotspot
      ? 'Hotspot de la tableta'
      : isWifi
      ? 'Wi-Fi'
      : (iface.isEmpty ? 'Red' : iface);

  @override
  bool operator ==(Object other) =>
      other is LinkNetwork &&
      other.iface == iface &&
      other.ip == ip &&
      other.prefix == prefix &&
      other.gateway == gateway &&
      other.hasInternet == hasInternet &&
      other.isDefault == isDefault &&
      other.isWifi == isWifi &&
      other.isHotspot == isHotspot;

  @override
  int get hashCode => Object.hash(iface, ip, prefix, gateway, hasInternet, isDefault, isWifi, isHotspot);
}

/// Broadcast de `ip/prefix` (p. ej. `192.168.43.1/24` → `192.168.43.255`). `null` si la IP no
/// es IPv4 válida o el prefijo no deja hosts (≥ 31) o es demasiado amplio (< 8).
String? subnetBroadcast(String ip, int prefix) {
  final parts = ip.trim().split('.');
  if (parts.length != 4 || prefix < 8 || prefix > 30) return null;
  var v = 0;
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return null;
    v = (v << 8) | n;
  }
  final mask = (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
  final b = (v & mask) | (~mask & 0xFFFFFFFF);
  return [(b >> 24) & 255, (b >> 16) & 255, (b >> 8) & 255, b & 255].join('.');
}

/// Destinos de los beacons UDP: `255.255.255.255` + el broadcast de cada red (sin repetir).
List<String> beaconTargets(Iterable<LinkNetwork> networks) {
  final out = <String>{'255.255.255.255'};
  for (final n in networks) {
    final b = n.broadcast;
    if (b != null) out.add(b);
  }
  return out.toList();
}

/// Un intento de conexión (saliente o entrante).
@immutable
class LinkAttempt {
  const LinkAttempt({
    required this.at,
    required this.target,
    required this.transport,
    required this.ok,
    this.error,
    this.ms = 0,
    this.inbound = false,
  });
  final DateTime at;

  /// `ip:puerto` o MAC.
  final String target;

  /// `wifi` | `bt`.
  final String transport;
  final bool ok;
  final String? error;
  final int ms;

  /// La inició el celular (marcó a esta tableta).
  final bool inbound;
}

@immutable
class LinkLogEntry {
  const LinkLogEntry(this.at, this.text);
  final DateTime at;
  final String text;
}

/// Beacon de celular escuchado.
@immutable
class HeardBeacon {
  const HeardBeacon({required this.ip, required this.device, required this.port, required this.at, this.id});
  final String ip;
  final String device;
  final int port;
  final DateTime at;
  final String? id;
}

/// Registro en memoria del enlace (anillos acotados) para Configuración → Diagnóstico.
class LinkDiagnostics extends ChangeNotifier {
  LinkDiagnostics({this.maxAttempts = 60, this.maxLog = 150, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final int maxAttempts;
  final int maxLog;
  final DateTime Function() _clock;

  final _attempts = ListQueue<LinkAttempt>();
  final _log = ListQueue<LinkLogEntry>();
  final Map<String, HeardBeacon> _beacons = {};

  List<LinkNetwork> networks = const [];

  /// Puerto en el que escucha la tableta (`null` = no se pudo abrir).
  int? listeningPort;

  /// Beacons UDP enviados por la tableta.
  int beaconsSent = 0;
  DateTime? lastBeaconSentAt;

  DateTime? lastInboundAt;
  DateTime? connectedAt;
  DateTime? lastTrackAt;
  DateTime? lastRxAt;

  DateTime get now => _clock();

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Más nuevos primero.
  List<LinkAttempt> get attempts => _attempts.toList().reversed.toList();

  /// Más nuevos primero.
  List<LinkLogEntry> get log => _log.toList().reversed.toList();

  /// Beacons escuchados, el más reciente primero.
  List<HeardBeacon> get beacons => _beacons.values.toList()..sort((a, b) => b.at.compareTo(a.at));

  DateTime? get lastBeaconAt => _beacons.isEmpty ? null : beacons.first.at;

  /// Intentos fallidos seguidos (desde el último éxito).
  int get failedStreak {
    var n = 0;
    for (final a in attempts) {
      if (a.ok) break;
      n++;
    }
    return n;
  }

  void attempt(LinkAttempt a) {
    _attempts.add(a);
    while (_attempts.length > maxAttempts) {
      _attempts.removeFirst();
    }
    notifyListeners();
  }

  void note(String text) {
    _log.add(LinkLogEntry(now, text));
    while (_log.length > maxLog) {
      _log.removeFirst();
    }
    if (kDebugMode) debugPrint('link: $text');
    notifyListeners();
  }

  void heard(String ip, {required String device, required int port, String? id}) {
    final isNew = !_beacons.containsKey(ip);
    _beacons[ip] = HeardBeacon(ip: ip, device: device, port: port, at: now, id: id);
    // Se olvidan los de hace más de 2 min.
    _beacons.removeWhere((_, b) => now.difference(b.at) > const Duration(minutes: 2));
    if (isNew) note('Beacon del celular «$device» desde $ip');
    notifyListeners();
  }

  void sentBeacon() {
    beaconsSent++;
    lastBeaconSentAt = now;
  }

  void setNetworks(List<LinkNetwork> list) {
    if (listEquals(list, networks)) return;
    networks = List.unmodifiable(list);
    notifyListeners();
  }

  void markConnected() {
    connectedAt = now;
    lastTrackAt = null;
    notifyListeners();
  }

  void markDisconnected() {
    connectedAt = null;
    notifyListeners();
  }

  void markInbound() {
    lastInboundAt = now;
    notifyListeners();
  }

  void markTrack() {
    lastTrackAt = now;
    notifyListeners();
  }

  void markRx() => lastRxAt = now;

  void clear() {
    _attempts.clear();
    _log.clear();
    _beacons.clear();
    beaconsSent = 0;
    notifyListeners();
  }

  /// Texto para "Copiar registro" (con las líneas nativas al final).
  String export({List<String> nativeLines = const [], String header = ''}) {
    String t(DateTime d) => d.toIso8601String().substring(11, 23);
    final b = StringBuffer();
    if (header.isNotEmpty) b.writeln(header);
    b.writeln('== Redes ==');
    for (final n in networks) {
      b.writeln(
        '${n.iface} ${n.ip}/${n.prefix} gw=${n.gateway ?? '-'} '
        '${n.isWifi ? 'wifi ' : ''}${n.isHotspot ? 'hotspot ' : ''}'
        '${n.hasInternet ? 'internet ' : ''}${n.isDefault ? 'default' : ''}',
      );
    }
    b.writeln('Escucha TCP: ${listeningPort ?? 'no'} · beacons enviados: $beaconsSent');
    b.writeln('== Beacons escuchados ==');
    for (final x in beacons) {
      b.writeln('${t(x.at)} ${x.ip}:${x.port} ${x.device}${x.id == null ? '' : ' id=${x.id}'}');
    }
    b.writeln('== Intentos ==');
    for (final a in attempts) {
      b.writeln(
        '${t(a.at)} ${a.inbound ? '←' : '→'} ${a.transport} ${a.target} '
        '${a.ok ? 'OK' : 'falló'}${a.error == null ? '' : ' (${a.error})'} ${a.ms} ms',
      );
    }
    b.writeln('== Registro ==');
    for (final l in log) {
      b.writeln('${t(l.at)} ${l.text}');
    }
    if (nativeLines.isNotEmpty) {
      b.writeln('== Nativo ==');
      nativeLines.forEach(b.writeln);
    }
    return b.toString();
  }
}

// ---------------------------------------------------------------------------
// Pasos para conectar

enum LinkStepState { ok, waiting, problem }

@immutable
class LinkStep {
  const LinkStep({required this.title, required this.state, required this.detail, this.hint});
  final String title;
  final LinkStepState state;
  final String detail;

  /// Qué hacer si el paso no está listo.
  final String? hint;
}

/// Evalúa los cuatro pasos del enlace con lo que se sabe ahora (función pura).
List<LinkStep> evaluateLinkSteps({
  required DateTime now,
  required List<LinkNetwork> networks,
  bool? hotspotOn,
  required bool connected,
  bool listening = true,
  DateTime? lastBeaconAt,
  DateTime? lastInboundAt,
  DateTime? connectedAt,
  DateTime? lastTrackAt,
  int failedStreak = 0,
  String? device,
  String? transport,
}) {
  final bt = connected && transport == 'bt';
  // 1. Red
  final wifi = networks.where((n) => n.isWifi || n.isHotspot).toList();
  final anyNet = networks.isNotEmpty;
  final hs = networks.any((n) => n.isHotspot) || hotspotOn == true;
  final netOk = hs || wifi.isNotEmpty || (anyNet && networks.every((n) => !n.isWifi && !n.isHotspot && n.iface.isEmpty));
  final step1 = LinkStep(
    title: 'Wi-Fi o hotspot de la tableta activo',
    state: netOk || bt ? LinkStepState.ok : LinkStepState.problem,
    detail: hs
        ? 'Hotspot encendido${networks.where((n) => n.isHotspot).map((n) => ' (${n.ip})').join()}.'
        : wifi.isNotEmpty
        ? 'Conectada a Wi-Fi (${wifi.map((n) => n.ip).join(', ')}).'
        : anyNet
        ? 'Red: ${networks.map((n) => n.ip).join(', ')}.'
        : bt
        ? 'Sin Wi-Fi, conectada por Bluetooth.'
        : 'Sin red Wi-Fi.',
    hint: 'Enciende el hotspot del radio (Configuración → Hotspot) o conecta la tableta al hotspot del celular.',
  );

  // 2. Celular visto
  bool recent(DateTime? t, Duration d) => t != null && now.difference(t) <= d;
  final beaconRecent = recent(lastBeaconAt, const Duration(seconds: 15));
  final inboundRecent = recent(lastInboundAt, const Duration(minutes: 1));
  final heard = connected || beaconRecent || inboundRecent;
  final step2 = LinkStep(
    title: 'Celular a la vista',
    state: heard ? LinkStepState.ok : (step1.state == LinkStepState.ok ? LinkStepState.waiting : LinkStepState.problem),
    detail: connected
        ? 'Enlazado con ${device ?? 'el celular'}.'
        : beaconRecent
        ? 'Se escucha su aviso Wi-Fi (hace ${now.difference(lastBeaconAt!).inSeconds} s).'
        : inboundRecent
        ? 'El celular marcó a esta tableta hace ${now.difference(lastInboundAt!).inSeconds} s.'
        : 'Todavía no se escucha al celular.',
    hint:
        'Abre Pixel Car Player en el celular y activa «Transmitir». El celular debe estar en la misma red '
        '(el hotspot del carro) aunque Android diga «sin internet».',
  );

  // 3. Enlace
  final step3 = LinkStep(
    title: 'Enlace establecido',
    state: connected
        ? LinkStepState.ok
        : (failedStreak >= 6 && heard ? LinkStepState.problem : LinkStepState.waiting),
    detail: connected
        ? 'Conectado${transport == 'bt' ? ' por Bluetooth' : ' por Wi-Fi'}'
              '${connectedAt == null ? '' : ' hace ${_ago(now.difference(connectedAt))}'}.'
        : failedStreak > 0
        ? '$failedStreak intentos fallidos seguidos.'
        : listening
        ? 'Esperando: la tableta marca al celular y también escucha.'
        : 'Marcando al celular (no se pudo abrir el puerto de escucha).',
    hint:
        'Toca «Reintentar ahora». Si sigue fallando, desactiva el ahorro de batería de la app en el '
        'celular y revisa que no haya una VPN o «aislamiento de clientes» en el hotspot.',
  );

  // 4. Datos
  final gotTrack = connected && lastTrackAt != null && (connectedAt == null || !lastTrackAt.isBefore(connectedAt));
  final step4 = LinkStep(
    title: 'Llegan datos del tema',
    state: gotTrack ? LinkStepState.ok : (connected ? LinkStepState.waiting : LinkStepState.waiting),
    detail: gotTrack
        ? 'Último tema recibido hace ${_ago(now.difference(lastTrackAt))}.'
        : connected
        ? 'Conectado, pero aún no llega ningún tema.'
        : 'Falta el enlace.',
    hint: 'Pon música en el celular y revisa que Pixel Car Player tenga acceso a las notificaciones allí.',
  );
  return [step1, step2, step3, step4];
}

String _ago(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds} s';
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  return '${d.inHours} h';
}
