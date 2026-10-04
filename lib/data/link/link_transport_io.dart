import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'link_protocol.dart';
import 'link_transport_types.dart';

export 'link_transport_types.dart';

const bool socketsSupported = true;

class _TcpConnection implements LinkConnection {
  _TcpConnection(this._socket) : remoteAddress = _address(_socket) {
    _socket.setOption(SocketOption.tcpNoDelay, true);
    final decoder = ByteLineDecoder();
    _sub = _socket.listen(
      (data) {
        for (final l in decoder.add(data)) {
          _lines.add(l);
        }
      },
      onError: (Object e) => _finish(),
      onDone: _finish,
      cancelOnError: true,
    );
  }

  final Socket _socket;
  late final StreamSubscription<List<int>> _sub;
  final _lines = StreamController<String>.broadcast();
  bool _closed = false;

  void _finish() {
    if (_closed) return;
    _closed = true;
    _sub.cancel();
    _socket.destroy();
    _lines.close();
  }

  @override
  Stream<String> get lines => _lines.stream;

  /// Se lee al conectar: después de cerrado el socket, `remoteAddress` lanza.
  @override
  final String remoteAddress;

  static String _address(Socket s) {
    try {
      return s.remoteAddress.address;
    } catch (_) {
      return '?';
    }
  }

  @override
  String get transport => 'wifi';

  @override
  Future<bool> sendLine(String line) async {
    if (_closed) return false;
    try {
      _socket.add(utf8.encode('$line\n'));
      return true;
    } catch (_) {
      _finish();
      return false;
    }
  }

  @override
  Future<void> close() async => _finish();
}

Future<LinkConnection?> connectTcp(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 3),
  void Function(String error)? onError,
}) async {
  try {
    final s = await Socket.connect(host, port, timeout: timeout);
    return _TcpConnection(s);
  } catch (e) {
    onError?.call(describeSocketError(e));
    return null;
  }
}

/// Texto corto en español de un error de socket (para Diagnóstico).
String describeSocketError(Object e) {
  final msg = (e is SocketException ? (e.osError?.message ?? e.message) : '$e').toLowerCase();
  if (msg.contains('refused')) return 'rechazada (no hay app escuchando)';
  if (msg.contains('timed out') || msg.contains('timeout')) return 'sin respuesta (tiempo agotado)';
  if (msg.contains('unreachable')) return 'red inalcanzable';
  if (msg.contains('no route')) return 'sin ruta a ese equipo';
  if (msg.contains('permission')) return 'sin permiso de red';
  return msg.length > 60 ? msg.substring(0, 60) : msg;
}

/// Escucha beacons UDP en [port]. Si no puede enlazar el puerto, el stream
/// termina sin eventos.
Stream<BeaconHit> listenBeacons(int port) {
  late StreamController<BeaconHit> ctrl;
  RawDatagramSocket? sock;
  ctrl = StreamController<BeaconHit>(
    onListen: () async {
      try {
        sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port, reuseAddress: true);
        sock!.broadcastEnabled = true;
        sock!.listen(
          (ev) {
            if (ev != RawSocketEvent.read) return;
            final dg = sock?.receive();
            if (dg == null) return;
            try {
              ctrl.add(BeaconHit(dg.address.address, utf8.decode(dg.data, allowMalformed: true)));
            } catch (_) {}
          },
          onError: (_) {},
          onDone: () {
            if (!ctrl.isClosed) ctrl.close();
          },
        );
      } catch (_) {
        await ctrl.close();
      }
    },
    onCancel: () {
      sock?.close();
      sock = null;
    },
  );
  return ctrl.stream;
}

class _TcpServer implements LinkServer {
  _TcpServer(this._server) {
    _sub = _server.listen(
      (s) {
        try {
          _conns.add(_TcpConnection(s));
        } catch (_) {
          s.destroy();
        }
      },
      onError: (_) {},
      onDone: () => _conns.close(),
    );
  }

  final ServerSocket _server;
  late final StreamSubscription<Socket> _sub;
  final _conns = StreamController<LinkConnection>();

  @override
  int get port => _server.port;

  @override
  Stream<LinkConnection> get connections => _conns.stream;

  @override
  Future<void> close() async {
    await _sub.cancel();
    await _server.close();
    if (!_conns.isClosed) await _conns.close();
  }
}

/// Escucha TCP en [port] (todas las interfaces IPv4, `shared` para poder reabrir rápido).
/// `null` si no se pudo enlazar.
Future<LinkServer?> bindLinkServer(int port, {String? host}) async {
  try {
    final s = await ServerSocket.bind(host ?? InternetAddress.anyIPv4, port, shared: true);
    return _TcpServer(s);
  } catch (_) {
    return null;
  }
}

class _Udp implements UdpSender {
  _Udp(this._sock);
  final RawDatagramSocket _sock;
  bool _closed = false;

  @override
  bool send(String host, int port, String payload) {
    if (_closed) return false;
    try {
      final addr = InternetAddress.tryParse(host);
      if (addr == null) return false;
      return _sock.send(utf8.encode(payload), addr, port) > 0;
    } catch (_) {
      return false;
    }
  }

  @override
  void close() {
    _closed = true;
    _sock.close();
  }
}

/// Socket UDP con broadcast para los beacons de la tableta.
Future<UdpSender?> openUdpSender() async {
  try {
    final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    s.broadcastEnabled = true;
    return _Udp(s);
  } catch (_) {
    return null;
  }
}

/// IPv4 locales (sin loopback) según `dart:io`.
Future<List<String>> localIPv4s() async {
  try {
    final list = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
    return [
      for (final i in list)
        for (final a in i.addresses) a.address,
    ];
  } catch (_) {
    return const [];
  }
}
