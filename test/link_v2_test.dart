import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/car/custom/car_customization_store.dart';
import 'package:pixel_car_player/data/link/car_link_client.dart';
import 'package:pixel_car_player/data/link/link_protocol.dart';
import 'package:pixel_car_player/data/link/link_transport.dart';

/// Enlace bidireccional v2 (CONTRACT.md §1): beacon de la tableta, decisión de un solo
/// enlace, carrera que no se frena con intentos lentos y pruebas reales por loopback.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('protocolo v2', () {
    test('car_beacon', () {
      final line = LinkProtocol.encodeLine(LinkProtocol.carBeacon(device: 'Radio', id: 'abc123'));
      expect(jsonDecode(line), {'t': 'car_beacon', 'v': 2, 'device': 'Radio', 'id': 'abc123', 'port': 47323});
      final m = LinkProtocol.decodeLine(line)! as CarBeaconMessage;
      expect(m.id, 'abc123');
      expect(m.port, LinkProtocol.carTcpPort);
      expect(LinkProtocol.carBeaconPort, 47324);
    });

    test('hello con id y mensaje hotspot', () {
      expect(LinkProtocol.hello('Tableta', id: 'x1'), {'t': 'hello', 'v': 1, 'device': 'Tableta', 'id': 'x1'});
      final h = LinkProtocol.decodeLine('{"t":"hello","v":2,"device":"Pixel 8","id":"p9"}')! as HelloMessage;
      expect(h.id, 'p9');
      expect((LinkProtocol.decodeLine('{"t":"hello","device":"P"}')! as HelloMessage).id, isNull);
      expect(LinkProtocol.hotspot(ssid: 'Corolla', password: 'carro2026'), {
        't': 'hotspot',
        'ssid': 'Corolla',
        'password': 'carro2026',
      });
    });

    test('broadcast de subred y destinos del beacon', () {
      expect(subnetBroadcast('192.168.43.1', 24), '192.168.43.255');
      expect(subnetBroadcast('10.20.30.40', 16), '10.20.255.255');
      expect(subnetBroadcast('172.16.5.9', 20), '172.16.15.255');
      expect(subnetBroadcast('192.168.1.1', 32), isNull);
      expect(subnetBroadcast('nope', 24), isNull);
      final t = beaconTargets(const [
        LinkNetwork(ip: '192.168.43.1', isHotspot: true),
        LinkNetwork(ip: '10.0.0.5', prefix: 8),
        LinkNetwork(ip: '192.168.43.7'),
      ]);
      expect(t, ['255.255.255.255', '192.168.43.255', '10.255.255.255']);
    });

    test('LinkNetwork.fromMap', () {
      final n = LinkNetwork.fromMap({
        'iface': 'ap0',
        'ip': '192.168.43.1',
        'prefix': 24,
        'gateway': '0.0.0.0',
        'isHotspot': true,
      })!;
      expect(n.gateway, isNull);
      expect(n.isHotspot, isTrue);
      expect(LinkNetwork.fromMap({'ip': ''}), isNull);
    });
  });

  group('decisión de un solo enlace', () {
    final now = DateTime(2026, 10, 4, 12);
    LinkPeerInfo peer({String? id, String t = 'wifi', int idle = 0, bool answered = true}) =>
        LinkPeerInfo(id: id, transport: t, lastRx: now.subtract(Duration(seconds: idle)), answered: answered);

    test('sin enlace: se adopta', () {
      expect(CarLinkClient.decide(current: null, incoming: peer(id: 'a'), now: now), LinkDecision.adopt);
    });

    test('enlace sano: se queda el actual (mismo u otro celular)', () {
      expect(
        CarLinkClient.decide(current: peer(id: 'a', idle: 5), incoming: peer(id: 'a'), now: now),
        LinkDecision.keepCurrent,
      );
      expect(
        CarLinkClient.decide(current: peer(id: 'a'), incoming: peer(id: 'b'), now: now),
        LinkDecision.keepCurrent,
      );
    });

    test('enlace caído (> 25 s sin datos): se cambia', () {
      expect(
        CarLinkClient.decide(current: peer(id: 'a', idle: 26), incoming: peer(id: 'a'), now: now),
        LinkDecision.replace,
      );
      expect(
        CarLinkClient.decide(current: peer(id: 'a', idle: 24), incoming: peer(id: 'a'), now: now),
        LinkDecision.keepCurrent,
      );
    });

    test('el actual nunca respondió y el nuevo sí: gana el nuevo', () {
      expect(
        CarLinkClient.decide(current: peer(answered: false), incoming: peer(id: 'a'), now: now),
        LinkDecision.replace,
      );
      expect(
        CarLinkClient.decide(current: peer(answered: false), incoming: peer(answered: false), now: now),
        LinkDecision.keepCurrent,
      );
    });

    test('Bluetooth → Wi-Fi del mismo celular: se cambia; de otro celular no', () {
      expect(
        CarLinkClient.decide(current: peer(id: 'a', t: 'bt'), incoming: peer(id: 'a'), now: now),
        LinkDecision.replace,
      );
      expect(
        CarLinkClient.decide(current: peer(id: 'a', t: 'bt'), incoming: peer(id: 'b'), now: now),
        LinkDecision.keepCurrent,
      );
      expect(
        CarLinkClient.decide(current: peer(id: 'a'), incoming: peer(id: 'a', t: 'bt'), now: now),
        LinkDecision.keepCurrent,
      );
    });
  });

  group('carrera', () {
    test('un intento lento no frena al rápido', () async {
      final calls = <String>[];
      final hang = Completer<LinkConnection?>();
      final c = CarLinkClient(
      trust: CarTrustStore(requirePairing: false),
        listen: false,
        discovery: false,
        installId: 'car1',
        // Los gateways de las redes son destinos de la carrera.
        networksProvider: () async => const [
          LinkNetwork(ip: '10.0.0.9', gateway: '10.0.0.1'),
          LinkNetwork(ip: '10.0.1.9', gateway: '10.0.1.1'),
        ],
        connector: (host, port, timeout, onError) {
          calls.add(host);
          if (host == '10.0.0.1') return hang.future; // RFCOMM/host lento: nunca contesta
          return Future.delayed(const Duration(milliseconds: 30), () => _FakeConn(host));
        },
      );
      final sw = Stopwatch()..start();
      await c.start();
      await _until(() => c.status.value.isConnected);
      expect(sw.elapsedMilliseconds, lessThan(1500));
      expect(c.status.value.address, '10.0.1.1');
      expect(calls, containsAll(['10.0.0.1', '10.0.1.1']));
      await c.dispose();
      hang.complete(null);
    });

    test('la carrera tiene tope: si todo cuelga se vuelve a intentar', () async {
      var n = 0;
      final c = CarLinkClient(
      trust: CarTrustStore(requirePairing: false),
        listen: false,
        discovery: false,
        installId: 'car1',
        raceCap: const Duration(milliseconds: 200),
        maxBackoff: const Duration(seconds: 1),
        networksProvider: () async => const [LinkNetwork(ip: '10.0.0.9', gateway: '10.0.0.1')],
        connector: (host, port, timeout, onError) {
          n++;
          return Completer<LinkConnection?>().future;
        },
      );
      await c.start();
      await _until(() => n >= 2, timeout: const Duration(seconds: 4));
      expect(c.status.value.phase, LinkPhase.searching);
      await c.dispose();
    });

    test('los fallos quedan en el diagnóstico con su error', () async {
      final c = CarLinkClient(
      trust: CarTrustStore(requirePairing: false),
        listen: false,
        discovery: false,
        installId: 'car1',
        networksProvider: () async => const [LinkNetwork(ip: '10.0.0.9', gateway: '10.0.0.1')],
        connector: (host, port, timeout, onError) async {
          onError('rechazada (no hay app escuchando)');
          return null;
        },
      );
      await c.start();
      await _until(() => c.diag.attempts.isNotEmpty);
      final a = c.diag.attempts.first;
      expect(a.ok, isFalse);
      expect(a.target, '10.0.0.1:47321');
      expect(a.error, contains('rechazada'));
      await c.dispose();
    });
  });

  group('loopback real', () {
    CarLinkClient listening({Duration spare = const Duration(seconds: 6)}) => CarLinkClient(
      trust: CarTrustStore(requirePairing: false),
      listenPort: 0,
      discovery: false,
      useWifi: false,
      installId: 'car-id-1',
      spareGrace: spare,
      helloWait: const Duration(milliseconds: 500),
      networksProvider: () async => const [],
    );

    test('el celular marca a la tableta: hello/resync y llegan los temas', () async {
      final car = listening();
      final got = <LinkMessage>[];
      final sub = car.messages.listen(got.add);
      await car.start();
      expect(car.boundPort, isNotNull);

      final phone = await _FakePhone.dial(car.boundPort!);
      phone.send({'t': 'hello', 'v': 2, 'device': 'Pixel 8', 'id': 'phone-1'});
      // La tableta contesta hello (con su id) + resync.
      final hello = await phone.next('hello');
      expect(hello['id'], 'car-id-1');
      await phone.next('resync');
      await _until(() => car.status.value.device == 'Pixel 8');
      expect(car.status.value.inbound, isTrue);
      expect(car.status.value.device, 'Pixel 8');
      expect(car.peerId, 'phone-1');

      phone.send({
        't': 'track',
        'id': 't1',
        'title': 'Luces de Neón',
        'artist': 'Harmonix Band',
        'album': 'Ruta Nocturna',
        'durationMs': 222000,
      });
      phone.send({'t': 'state', 'playing': true, 'positionMs': 1000, 'speed': 1});
      phone.send({'t': 'ping'});
      await phone.next('pong');
      await _until(() => got.whereType<StateMessage>().isNotEmpty);
      expect(got.whereType<TrackMessage>().single.track.title, 'Luces de Neón');
      expect(car.diag.lastTrackAt, isNotNull);
      expect(car.diag.lastInboundAt, isNotNull);

      // Un segundo tema sigue fluyendo.
      phone.send({'t': 'track', 'id': 't2', 'title': 'Kilómetro Cero', 'artist': '', 'album': '', 'durationMs': 1});
      await _until(() => got.whereType<TrackMessage>().length == 2);

      // Comandos de la tableta llegan al celular.
      await car.sendCommand(LinkAction.next);
      expect((await phone.next('cmd'))['action'], 'next');

      await sub.cancel();
      await phone.close();
      await _until(() => !car.status.value.isConnected);
      await car.dispose();
    });

    test('la tableta marca al celular (saliente) igual que antes', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = Completer<_FakePhone>();
      server.listen((s) => accepted.complete(_FakePhone(s)));
      final car = CarLinkClient(
      trust: CarTrustStore(requirePairing: false),
        listen: false,
        discovery: false,
        installId: 'car-id-2',
        manualIp: '127.0.0.1:${server.port}',
        networksProvider: () async => const [],
      );
      await car.start();
      final phone = await accepted.future.timeout(const Duration(seconds: 5));
      expect((await phone.next('hello'))['id'], 'car-id-2');
      await phone.next('resync');
      expect(car.status.value.inbound, isFalse);
      phone.send({'t': 'hello', 'v': 2, 'device': 'Pixel 8', 'id': 'phone-1'});
      await _until(() => car.status.value.device == 'Pixel 8');
      await car.dispose();
      await phone.close();
      await server.close();
    });

    test('duplicado: se queda el enlace sano; el nuevo se cierra tras la reserva', () async {
      final car = listening(spare: const Duration(milliseconds: 400));
      await car.start();
      final a = await _FakePhone.dial(car.boundPort!);
      a.send({'t': 'hello', 'device': 'Pixel 8', 'id': 'phone-1'});
      await a.next('resync');
      final b = await _FakePhone.dial(car.boundPort!);
      b.send({'t': 'hello', 'device': 'Pixel 8', 'id': 'phone-1'});
      await b.closed.timeout(const Duration(seconds: 3));
      expect(b.received.where((m) => m['t'] == 'hello'), isEmpty, reason: 'la reserva no recibe hello');
      expect(car.status.value.isConnected, isTrue);
      // El primero sigue vivo.
      a.send({'t': 'ping'});
      await a.next('pong');
      expect(car.diag.log.any((l) => l.text.contains('duplicada')), isTrue);
      await car.dispose();
      await a.close();
    });

    test('si el celular cierra el que se quedó la tableta, se usa la reserva', () async {
      final car = listening(spare: const Duration(seconds: 5));
      await car.start();
      final a = await _FakePhone.dial(car.boundPort!);
      a.send({'t': 'hello', 'device': 'Pixel 8', 'id': 'phone-1'});
      await a.next('resync');
      final b = await _FakePhone.dial(car.boundPort!);
      b.send({'t': 'hello', 'device': 'Pixel 8', 'id': 'phone-1'});
      await Future<void>.delayed(const Duration(milliseconds: 700));
      // El celular eligió la otra conexión y cierra la primera.
      await a.close();
      expect((await b.next('hello'))['id'], 'car-id-1');
      await b.next('resync');
      await _until(() => car.status.value.isConnected);
      await car.dispose();
      await b.close();
    });

    test('la tableta comparte la red del carro tras el hello', () async {
      final store = CarCustomizationStore(
        const CarCustomization().copyWith(hotspot: const CarHotspotOpts(ssid: 'Corolla', password: 'carro2026')),
      );
      final car = listening();
      final ctrl = CarController(custom: store, link: car);
      await ctrl.start();
      await _until(() => car.boundPort != null);
      final phone = await _FakePhone.dial(car.boundPort!);
      phone.send({'t': 'hello', 'v': 2, 'device': 'Pixel 8', 'id': 'phone-1'});
      final hs = await phone.next('hotspot');
      expect(hs, {'t': 'hotspot', 'ssid': 'Corolla', 'password': 'carro2026'});
      // Sin permiso del usuario no se manda.
      await phone.close();
      store.update((v) => v.copyWith(hotspot: v.hotspot.copyWith(shareWithPhone: false)));
      await _until(() => !car.status.value.isConnected);
      final again = await _FakePhone.dial(car.boundPort!);
      again.send({'t': 'hello', 'device': 'Pixel 8', 'id': 'phone-1'});
      await again.next('resync');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(again.received.where((m) => m['t'] == 'hotspot'), isEmpty);
      await again.close();
      ctrl.dispose();
      store.dispose();
    });
  });
}

Future<void> _until(bool Function() ok, {Duration timeout = const Duration(seconds: 5)}) async {
  final end = DateTime.now().add(timeout);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('condición no cumplida');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _FakeConn implements LinkConnection {
  _FakeConn(this.remoteAddress);
  final _lines = StreamController<String>.broadcast();
  final sent = <String>[];
  @override
  final String remoteAddress;
  @override
  String get transport => 'wifi';
  @override
  Stream<String> get lines => _lines.stream;
  @override
  Future<bool> sendLine(String line) async {
    sent.add(line);
    return true;
  }

  @override
  Future<void> close() async {
    if (!_lines.isClosed) await _lines.close();
  }
}

/// Celular de mentira sobre un socket real.
class _FakePhone {
  _FakePhone(this._s) {
    final dec = ByteLineDecoder();
    _s.listen(
      (d) {
        for (final l in dec.add(d)) {
          final m = Map<String, dynamic>.from(jsonDecode(l) as Map);
          received.add(m);
          _ctl.add(m);
        }
      },
      onDone: () {
        if (!_closed.isCompleted) _closed.complete();
      },
      onError: (_) {
        if (!_closed.isCompleted) _closed.complete();
      },
    );
  }

  static Future<_FakePhone> dial(int port) async => _FakePhone(await Socket.connect('127.0.0.1', port));

  final Socket _s;
  final received = <Map<String, dynamic>>[];
  final _ctl = StreamController<Map<String, dynamic>>.broadcast();
  final _closed = Completer<void>();
  Future<void> get closed => _closed.future;

  void send(Map<String, dynamic> m) => _s.add(utf8.encode(LinkProtocol.encodeLine(m)));

  /// Próximo mensaje de tipo [t] (o uno ya recibido que no se consumió).
  final _consumed = <Map<String, dynamic>>{};
  Future<Map<String, dynamic>> next(String t) async {
    for (final m in received) {
      if (m['t'] == t && _consumed.add(m)) return m;
    }
    final m = await _ctl.stream.firstWhere((m) => m['t'] == t).timeout(const Duration(seconds: 5));
    _consumed.add(m);
    return m;
  }

  Future<void> close() async {
    await _s.close();
    _s.destroy();
  }
}
