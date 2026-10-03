import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:pixel_car_player/data/bridge/native_bridge.dart';

import 'link_protocol.dart';
import 'link_transport.dart';

enum LinkPhase { disconnected, searching, connected }

/// Estado de la conexión con el celular.
@immutable
class LinkStatus {
  const LinkStatus._(this.phase, {this.device, this.transport, this.address});

  static const disconnected = LinkStatus._(LinkPhase.disconnected);
  static const searching = LinkStatus._(LinkPhase.searching);

  const LinkStatus.connected({
    required String device,
    required String transport,
    required String address,
  }) : this._(LinkPhase.connected, device: device, transport: transport, address: address);

  final LinkPhase phase;

  /// Nombre del celular (del `hello` o del beacon).
  final String? device;

  /// `wifi` | `bt`.
  final String? transport;

  /// IP o MAC del celular.
  final String? address;

  bool get isConnected => phase == LinkPhase.connected;

  LinkStatus withDevice(String d) => isConnected
      ? LinkStatus.connected(device: d, transport: transport!, address: address!)
      : this;

  @override
  bool operator ==(Object other) =>
      other is LinkStatus &&
      other.phase == phase &&
      other.device == device &&
      other.transport == transport &&
      other.address == address;

  @override
  int get hashCode => Object.hash(phase, device, transport, address);

  @override
  String toString() => 'LinkStatus($phase, $device, $transport, $address)';
}

class _Beacon {
  _Beacon(this.port, this.device, this.at);
  final int port;
  final String device;
  final DateTime at;
}

/// Gestor de conexión de la tableta con el celular.
///
/// Wi-Fi: en paralelo intenta la IP de cada beacon UDP reciente, la IP del
/// gateway (hotspot del celular) y la IP manual. La primera conexión TCP
/// gana. Bluetooth: si hay un celular emparejado elegido, también compite
/// una conexión RFCOMM por el canal nativo.
///
/// Tras conectar envía `hello` + `resync`, contesta `pong` a `ping` y
/// considera caída la conexión si no recibe nada en 25 s.
class CarLinkClient {
  CarLinkClient({
    NativeBridge? bridge,
    this.manualIp,
    this.btAddress,
    this.btName,
    this.watchdog = const Duration(seconds: 25),
    this.useWifi = true,
    this.maxBackoff = const Duration(seconds: 10),
  }) : _bridge = bridge ?? NativeBridge.instance;

  final NativeBridge _bridge;
  final Duration watchdog;

  /// `false` = solo Bluetooth (no se intentan beacons, gateway ni IP manual).
  bool useWifi;

  /// Espera máxima entre intentos fallidos (el backoff arranca en 1 s).
  Duration maxBackoff;

  String? manualIp;
  String? btAddress;
  String? btName;

  final ValueNotifier<LinkStatus> status = ValueNotifier(LinkStatus.disconnected);
  final _messages = StreamController<LinkMessage>.broadcast();

  /// Mensajes decodificados del celular (excepto `ping`, que se contesta aquí).
  Stream<LinkMessage> get messages => _messages.stream;

  bool get canConnect => socketsSupported || _bridge.isSupported;

  bool _running = false;
  LinkConnection? _conn;
  Completer<void>? _wake;
  StreamSubscription<BeaconHit>? _beaconSub;
  Timer? _beaconRetry;
  final Map<String, _Beacon> _beacons = {};
  String _selfName = 'Tableta';

  /// Inicia el bucle de descubrimiento/conexión.
  Future<void> start() async {
    if (_running) return;
    _running = true;
    if (!canConnect) {
      status.value = LinkStatus.disconnected;
      return;
    }
    final info = await _bridge.getDeviceInfo();
    final model = info['model'] as String?;
    if (model != null && model.isNotEmpty) _selfName = model;
    await _bridge.acquireMulticastLock();
    _listenBeacons();
    unawaited(_loop());
  }

  Future<void> stop() async {
    _running = false;
    _wakeUp();
    await _beaconSub?.cancel();
    _beaconSub = null;
    _beaconRetry?.cancel();
    await _conn?.close();
    _conn = null;
    await _bridge.releaseMulticastLock();
    status.value = LinkStatus.disconnected;
  }

  Future<void> dispose() async {
    await stop();
    await _messages.close();
    status.dispose();
  }

  /// Cambia la configuración y fuerza un nuevo intento de conexión.
  void configure({
    String? manualIp,
    String? btAddress,
    String? btName,
    bool? useWifi,
    Duration? maxBackoff,
  }) {
    this.manualIp = manualIp;
    this.btAddress = btAddress;
    this.btName = btName;
    if (useWifi != null) this.useWifi = useWifi;
    if (maxBackoff != null) this.maxBackoff = maxBackoff;
    reconnect();
  }

  /// Cierra la conexión actual (si hay) y reintenta de inmediato.
  void reconnect() {
    _conn?.close();
    _wakeUp();
  }

  /// Envía un mensaje al celular. `false` si no hay conexión.
  Future<bool> send(Map<String, dynamic> msg) async {
    final c = _conn;
    if (c == null) return false;
    return c.sendLine(LinkProtocol.encodeLine(msg).trimRight());
  }

  Future<bool> sendCommand(LinkAction action, {int? positionMs}) =>
      send(LinkProtocol.cmd(action, positionMs: positionMs));

  // ---------------------------------------------------------------------------

  void _wakeUp() {
    final w = _wake;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<void> _sleep(Duration d) {
    final w = _wake = Completer<void>();
    final t = Timer(d, () {
      if (!w.isCompleted) w.complete();
    });
    return w.future.whenComplete(t.cancel);
  }

  void _listenBeacons() {
    if (!socketsSupported) return;
    _beaconSub = listenBeacons(LinkProtocol.beaconPort).listen(
      (hit) {
        final m = LinkProtocol.decodeLine(hit.payload);
        if (m is! BeaconMessage) return;
        final isNew = !_beacons.containsKey(hit.address);
        _beacons[hit.address] = _Beacon(m.port, m.device, DateTime.now());
        if (isNew && useWifi && !status.value.isConnected) _wakeUp();
      },
      onDone: () {
        // No se pudo enlazar (o se cerró): reintentar más tarde.
        if (_running) {
          _beaconRetry = Timer(const Duration(seconds: 5), () {
            if (_running) _listenBeacons();
          });
        }
      },
    );
  }

  Future<void> _loop() async {
    var backoff = const Duration(seconds: 1);
    while (_running) {
      status.value = LinkStatus.searching;
      final conn = await _race();
      if (!_running) {
        await conn?.close();
        break;
      }
      if (conn == null) {
        await _sleep(backoff);
        backoff = Duration(
            milliseconds: math.min(
                backoff.inMilliseconds * 2, math.max(1000, maxBackoff.inMilliseconds)));
        continue;
      }
      backoff = const Duration(seconds: 1);
      await _serve(conn);
      if (_running) await _sleep(const Duration(milliseconds: 600));
    }
  }

  /// Lanza todos los intentos en paralelo; devuelve la primera conexión.
  Future<LinkConnection?> _race() async {
    final now = DateTime.now();
    _beacons.removeWhere((_, b) => now.difference(b.at) > const Duration(seconds: 15));

    final targets = <String, int>{};
    for (final e in _beacons.entries) {
      targets[e.key] = e.value.port;
    }
    final gw = useWifi ? await _bridge.getGatewayIp() : null;
    if (gw != null && gw.isNotEmpty && gw != '0.0.0.0') {
      targets.putIfAbsent(gw, () => LinkProtocol.tcpPort);
    }
    final manual = manualIp?.trim();
    if (manual != null && manual.isNotEmpty) {
      final parts = manual.split(':');
      targets.putIfAbsent(
        parts.first,
        () => parts.length > 1
            ? int.tryParse(parts[1]) ?? LinkProtocol.tcpPort
            : LinkProtocol.tcpPort,
      );
    }

    final attempts = <Future<LinkConnection?>>[
      if (socketsSupported && useWifi)
        for (final t in targets.entries) connectTcp(t.key, t.value),
      if (btAddress != null && btAddress!.isNotEmpty && _bridge.isSupported)
        _connectRfcomm(btAddress!),
    ];
    if (attempts.isEmpty) return null;

    final winner = Completer<LinkConnection?>();
    var pending = attempts.length;
    for (final a in attempts) {
      a.then((c) {
        if (c != null && !winner.isCompleted) {
          winner.complete(c);
        } else if (c != null) {
          c.close(); // llegó tarde: se descarta
        }
        pending--;
        if (pending == 0 && !winner.isCompleted) winner.complete(null);
      });
    }
    return winner.future;
  }

  Future<LinkConnection?> _connectRfcomm(String address) async {
    final conn = _RfcommConnection(_bridge, address);
    final ok = await _bridge.connectRfcomm(address);
    if (!ok) {
      await conn.dispose();
      return null;
    }
    return conn;
  }

  Future<void> _serve(LinkConnection conn) async {
    _conn = conn;
    final beacon = _beacons[conn.remoteAddress];
    final initialName = conn.transport == 'bt'
        ? (btName ?? 'Celular')
        : (beacon?.device ?? 'Celular');
    status.value = LinkStatus.connected(
      device: initialName,
      transport: conn.transport,
      address: conn.remoteAddress,
    );

    final done = Completer<void>();
    Timer? dog;
    void feed() {
      dog?.cancel();
      dog = Timer(watchdog, () {
        debugPrint('CarLinkClient: watchdog — sin datos en ${watchdog.inSeconds}s');
        conn.close();
      });
    }

    feed();
    final sub = conn.lines.listen(
      (line) {
        feed();
        final msg = LinkProtocol.decodeLine(line);
        if (msg == null) return;
        switch (msg) {
          case PingMessage():
            conn.sendLine(LinkProtocol.encodeLine(LinkProtocol.pong()).trimRight());
          case HelloMessage(:final device):
            status.value = status.value.withDevice(device);
            _messages.add(msg);
          default:
            _messages.add(msg);
        }
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      onError: (_) {
        if (!done.isCompleted) done.complete();
      },
    );

    await conn.sendLine(LinkProtocol.encodeLine(LinkProtocol.hello(_selfName)).trimRight());
    await conn.sendLine(LinkProtocol.encodeLine(LinkProtocol.resync()).trimRight());

    await done.future;
    dog?.cancel();
    await sub.cancel();
    await conn.close();
    if (identical(_conn, conn)) _conn = null;
    if (_running) status.value = LinkStatus.searching;
  }
}

/// Conexión RFCOMM a través del canal nativo (eventos `rfcomm`).
class _RfcommConnection implements LinkConnection {
  _RfcommConnection(this._bridge, this._address) {
    _sub = _bridge.events.where((e) => e['type'] == 'rfcomm').listen((e) {
      switch (e['event']) {
        case 'line':
          final data = e['data'];
          if (data is String) {
            for (final l in _buf.add(data.endsWith('\n') ? data : '$data\n')) {
              _lines.add(l);
            }
          }
        case 'disconnected':
          _finish();
      }
    }, onError: (_) {});
  }

  final NativeBridge _bridge;
  final String _address;
  final LineBuffer _buf = LineBuffer();
  final _lines = StreamController<String>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _closed = false;

  void _finish() {
    if (_closed) return;
    _closed = true;
    _sub?.cancel();
    _lines.close();
  }

  Future<void> dispose() async => _finish();

  @override
  Stream<String> get lines => _lines.stream;

  @override
  String get remoteAddress => _address;

  @override
  String get transport => 'bt';

  @override
  Future<bool> sendLine(String line) async {
    if (_closed) return false;
    final ok = await _bridge.sendRfcomm(line);
    if (!ok) _finish();
    return ok;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _finish();
    await _bridge.disconnectRfcomm();
  }
}
