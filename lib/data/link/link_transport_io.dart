import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'link_protocol.dart';
import 'link_transport_types.dart';

export 'link_transport_types.dart';

const bool socketsSupported = true;

class _TcpConnection implements LinkConnection {
  _TcpConnection(this._socket) {
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

  @override
  String get remoteAddress => _socket.remoteAddress.address;

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

Future<LinkConnection?> connectTcp(String host, int port, {Duration timeout = const Duration(seconds: 3)}) async {
  try {
    final s = await Socket.connect(host, port, timeout: timeout);
    return _TcpConnection(s);
  } catch (_) {
    return null;
  }
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
