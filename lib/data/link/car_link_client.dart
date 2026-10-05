import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:pixel_car_player/data/bridge/native_bridge.dart';

import 'link_auth.dart';
import 'link_diagnostics.dart';
import 'link_prefs.dart';
import 'link_protocol.dart';
import 'link_transport.dart';

export 'link_auth.dart';
export 'link_diagnostics.dart';

enum LinkPhase { disconnected, searching, connected }

/// Estado de la conexión con el celular.
@immutable
class LinkStatus {
  const LinkStatus._(
    this.phase, {
    this.device,
    this.transport,
    this.address,
    this.inbound = false,
    this.authenticated = false,
  });

  static const disconnected = LinkStatus._(LinkPhase.disconnected);
  static const searching = LinkStatus._(LinkPhase.searching);

  const LinkStatus.connected({
    required String device,
    required String transport,
    required String address,
    bool inbound = false,
    bool authenticated = true,
  }) : this._(
         LinkPhase.connected,
         device: device,
         transport: transport,
         address: address,
         inbound: inbound,
         authenticated: authenticated,
       );

  final LinkPhase phase;

  /// Nombre del celular (del `hello` o del beacon).
  final String? device;

  /// `wifi` | `bt`.
  final String? transport;

  /// IP o MAC del celular.
  final String? address;

  /// La conexión la inició el celular (v2).
  final bool inbound;

  /// La sesión está autenticada (v3: `auth` válido, emparejado o sin exigir emparejamiento).
  final bool authenticated;

  bool get isConnected => phase == LinkPhase.connected;

  /// Conectado y autenticado: ya pueden fluir los datos.
  bool get isLinked => isConnected && authenticated;

  LinkStatus withDevice(String d) => isConnected
      ? LinkStatus.connected(
          device: d,
          transport: transport!,
          address: address!,
          inbound: inbound,
          authenticated: authenticated,
        )
      : this;

  LinkStatus withAuth(bool a) => isConnected
      ? LinkStatus.connected(
          device: device ?? 'Celular',
          transport: transport!,
          address: address!,
          inbound: inbound,
          authenticated: a,
        )
      : this;

  @override
  bool operator ==(Object other) =>
      other is LinkStatus &&
      other.phase == phase &&
      other.device == device &&
      other.transport == transport &&
      other.address == address &&
      other.inbound == inbound &&
      other.authenticated == authenticated;

  @override
  int get hashCode => Object.hash(phase, device, transport, address, inbound, authenticated);

  @override
  String toString() =>
      'LinkStatus($phase, $device, $transport, $address${inbound ? ', entrante' : ''}'
      '${isConnected && !authenticated ? ', sin autenticar' : ''})';
}

/// Qué hacer con una conexión nueva cuando ya hay (o no) un enlace (CONTRACT.md §1 v2).
enum LinkDecision {
  /// No hay enlace: se usa la nueva.
  adopt,

  /// El enlace actual está sano: se queda; la nueva se descarta.
  keepCurrent,

  /// El actual está caído (sin datos en 25 s) o es Bluetooth y llega Wi-Fi del mismo
  /// celular: se cambia a la nueva.
  replace,
}

/// Lo que se sabe de un extremo para decidir.
@immutable
class LinkPeerInfo {
  const LinkPeerInfo({this.id, this.transport = 'wifi', required this.lastRx, this.answered = true});
  final String? id;
  final String transport;
  final DateTime lastRx;

  /// Ya mandó su `hello` (respondió). Uno que nunca respondió pierde con el nuevo.
  final bool answered;
}

/// Intento de conexión saliente inyectable (pruebas). `onError` recibe un texto corto.
typedef LinkConnector =
    Future<LinkConnection?> Function(String host, int port, Duration timeout, void Function(String error) onError);

Future<LinkConnection?> _tcpConnector(String host, int port, Duration timeout, void Function(String) onError) =>
    connectTcp(host, port, timeout: timeout, onError: onError);

class _Beacon {
  _Beacon(this.port, this.device, this.at);
  final int port;
  final String device;
  final DateTime at;
}

/// Un extremo conectado: se suscribe a las líneas apenas se crea (las guarda hasta que
/// alguien las lea), anota la hora de lo último recibido y detecta el `hello` del celular.
class _Peer {
  _Peer(this.conn, {required this.inbound}) : lastRx = DateTime.now() {
    _sub = conn.lines.listen(
      (l) {
        lastRx = DateTime.now();
        if (!_hello.isCompleted) {
          final m = LinkProtocol.decodeLine(l);
          if (m is HelloMessage) {
            id = m.id;
            device = m.device;
            nonce = m.nonce;
            _hello.complete();
          }
        }
        if (!_buf.isClosed) _buf.add(l);
      },
      onDone: _finish,
      onError: (_) => _finish(),
      cancelOnError: true,
    );
  }

  final LinkConnection conn;
  final bool inbound;
  DateTime lastRx;
  String? id;
  String? device;

  /// Nonce del `hello` del celular (v3).
  String? nonce;
  final _buf = StreamController<String>();
  final _hello = Completer<void>();
  final _closed = Completer<void>();
  late final StreamSubscription<String> _sub;

  Stream<String> get lines => _buf.stream;
  bool get isClosed => _closed.isCompleted;
  Future<void> get closed => _closed.future;
  String get transport => conn.transport;
  String get address => conn.remoteAddress;

  LinkPeerInfo get info =>
      LinkPeerInfo(id: id, transport: transport, lastRx: lastRx, answered: _hello.isCompleted);

  void _finish() {
    if (!_closed.isCompleted) _closed.complete();
    if (!_buf.isClosed) _buf.close();
  }

  /// Espera el `hello` (o que se cierre, o [max]).
  Future<void> waitHello(Duration max) =>
      Future.any([_hello.future, _closed.future, Future<void>.delayed(max)]);

  Future<void> close() async {
    _finish();
    await _sub.cancel();
    await conn.close();
  }
}

class _Session {
  _Session(this.peer) : nonce = LinkAuth.nonce();
  final _Peer peer;
  final done = Completer<void>();
  bool replaced = false;

  /// Nonce de la tableta para esta conexión (va en su `hello`).
  final String nonce;

  /// La tableta ya validó al celular (o no exige emparejamiento).
  bool authed = false;

  /// Ya se mandó `auth` para el nonce actual del celular.
  String? answeredNonce;
}

/// Una carrera de intentos salientes. Se le pueden sumar destinos mientras corre.
class _Race {
  final _done = Completer<void>();
  final Set<String> tried = {};
  int pending = 0;

  /// Solo queda el intento Bluetooth (sin destinos Wi-Fi): se lo espera.
  bool waitBt = false;

  bool get isDone => _done.isCompleted;
  Future<void> get done => _done.future;

  void finish() {
    if (!_done.isCompleted) _done.complete();
  }
}

/// Gestor de conexión de la tableta con el celular (enlace bidireccional, CONTRACT.md §1 v2).
///
/// - **Marca**: en paralelo a la IP de cada beacon UDP reciente del celular, al gateway
///   (hotspot del celular), a la IP manual y a los vecinos ARP (hotspot de la tableta). Un
///   beacon nuevo durante la carrera suma su intento al instante. Bluetooth (RFCOMM) corre
///   aparte, en segundo plano: nunca frena la carrera Wi-Fi.
/// - **Escucha** TCP [listenPort] (47323): el celular marca a la tableta, así el orden en que
///   se abren las apps no importa. Las conexiones entrantes se tratan igual que las salientes.
/// - **Avisa** cada 2 s con un `car_beacon` UDP (puerto 47324) a `255.255.255.255` y al
///   broadcast de cada red.
/// - **Un solo enlace**: si llega otra conexión con uno sano, se queda el actual (la otra se
///   guarda unos segundos de reserva por si el celular eligió esa); si el actual no recibió
///   nada en [watchdog], se cambia. Ver [decide].
/// - Si cambian las redes (cada 5 s sin enlace) se vuelve a intentar de inmediato.
///
/// Tras conectar envía `hello` (con [installId]) + `resync`, contesta `pong` a `ping` y
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
    this.listenPort = LinkProtocol.carTcpPort,
    this.listen = true,
    this.discovery = true,
    this.installId,
    LinkConnector? connector,
    Future<LinkServer?> Function(int port)? serverFactory,
    this.networksProvider,
    this.attemptTimeout = const Duration(seconds: 3),
    this.raceCap = const Duration(seconds: 6),
    this.helloWait = const Duration(seconds: 3),
    this.spareGrace = const Duration(seconds: 6),
    this.netPoll = const Duration(seconds: 5),
    LinkDiagnostics? diagnostics,
    CarTrustStore? trust,
    this.codeTtl = LinkAuth.codeTtl,
  }) : _bridge = bridge ?? NativeBridge.instance,
       _connector = connector ?? _tcpConnector,
       _serverFactory = serverFactory ?? bindLinkServer,
       diag = diagnostics ?? LinkDiagnostics(),
       trust = trust ?? CarTrustStore();

  final NativeBridge _bridge;
  final LinkConnector _connector;
  final Future<LinkServer?> Function(int port) _serverFactory;
  /// Redes de la tableta (pruebas); `null` = `getWifiNetworks` / `dart:io`.
  final Future<List<LinkNetwork>> Function()? networksProvider;
  final Duration watchdog;

  /// `false` = solo Bluetooth (no se intentan beacons, gateway ni IP manual).
  bool useWifi;

  /// Espera máxima entre intentos fallidos (el backoff arranca en 1 s).
  Duration maxBackoff;

  String? manualIp;
  String? btAddress;
  String? btName;

  /// Puerto de escucha (0 = cualquiera, para pruebas; el real queda en [boundPort]).
  final int listenPort;

  /// Escuchar conexiones del celular.
  final bool listen;

  /// Escuchar beacons del celular y enviar los propios.
  final bool discovery;

  /// Identificador estable de esta tableta (si es `null` se lee/crea en [start]).
  String? installId;

  final Duration attemptTimeout;

  /// Tope de una carrera de intentos (luego se espera el backoff y se reintenta).
  final Duration raceCap;

  /// Cuánto se espera el `hello` de una conexión que llega con un enlace activo.
  final Duration helloWait;

  /// Cuánto se guarda de reserva la conexión duplicada antes de cerrarla.
  final Duration spareGrace;
  final Duration netPoll;

  /// Registro para Configuración → Diagnóstico.
  final LinkDiagnostics diag;

  /// Celulares de confianza y "Requerir emparejamiento" (v3).
  final CarTrustStore trust;

  /// Validez de un código de emparejamiento.
  final Duration codeTtl;

  final ValueNotifier<LinkStatus> status = ValueNotifier(LinkStatus.disconnected);

  /// Seguridad de la sesión actual (v3).
  final ValueNotifier<LinkAuthState> auth = ValueNotifier(LinkAuthState.none);

  /// Código de emparejamiento que hay que mostrar (o `null`).
  final ValueNotifier<PairingPrompt?> pairing = ValueNotifier(null);
  Timer? _pairTimer;
  Timer? _pairClear;
  final _authenticated = StreamController<void>.broadcast();

  /// Se emite cada vez que una sesión queda autenticada (ahí se manda `resync`/`hotspot`).
  Stream<void> get onAuthenticated => _authenticated.stream;
  final _messages = StreamController<LinkMessage>.broadcast();

  /// Mensajes decodificados del celular (excepto `ping`, que se contesta aquí).
  Stream<LinkMessage> get messages => _messages.stream;

  bool get canConnect => socketsSupported || _bridge.isSupported;

  /// Puerto en el que se escucha de verdad (`null` si no se pudo).
  int? get boundPort => _server?.port;

  /// `id` del celular conectado (del `hello`, v2).
  String? get peerId => _session?.peer.id;

  bool _running = false;
  _Session? _session;
  _Peer? _spare;
  Timer? _spareTimer;
  _Race? _race;
  bool _rfcommBusy = false;
  Completer<void>? _wake;
  StreamSubscription<BeaconHit>? _beaconSub;
  Timer? _beaconRetry;
  LinkServer? _server;
  StreamSubscription<LinkConnection>? _serverSub;
  Timer? _serverRetry;
  UdpSender? _udp;
  Timer? _beaconTimer;
  Timer? _netTimer;
  String? _netKey;
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
    installId ??= await LinkIdentity.load();
    if (!_running) return;
    await _bridge.acquireMulticastLock();
    if (discovery) _listenBeacons();
    if (listen) await _startServer();
    await _refreshNetworks();
    if (discovery) await _startBeaconing();
    var ticks = 0;
    _netTimer = Timer.periodic(netPoll, (_) {
      // Sin enlace: cada [netPoll]; con enlace basta cada 6 vueltas (para los beacons).
      if (_session == null || ++ticks % 6 == 0) unawaited(_refreshNetworks());
    });
    unawaited(_loop());
  }

  Future<void> stop() async {
    _running = false;
    _wakeUp();
    _race?.finish();
    _netTimer?.cancel();
    _netTimer = null;
    _beaconTimer?.cancel();
    _beaconTimer = null;
    _udp?.close();
    _udp = null;
    await _beaconSub?.cancel();
    _beaconSub = null;
    _beaconRetry?.cancel();
    _serverRetry?.cancel();
    await _serverSub?.cancel();
    _serverSub = null;
    await _server?.close();
    _server = null;
    diag.listeningPort = null;
    _dropSpare();
    final s = _session;
    _session = null;
    await s?.peer.close();
    await _bridge.releaseMulticastLock();
    _clearPairing();
    auth.value = LinkAuthState.none;
    status.value = LinkStatus.disconnected;
  }

  Future<void> dispose() async {
    await stop();
    _pairTimer?.cancel();
    _pairClear?.cancel();
    await _messages.close();
    await _authenticated.close();
    status.dispose();
    auth.dispose();
    pairing.dispose();
    diag.dispose();
  }

  /// Cambia la configuración y fuerza un nuevo intento de conexión.
  void configure({String? manualIp, String? btAddress, String? btName, bool? useWifi, Duration? maxBackoff}) {
    this.manualIp = manualIp;
    this.btAddress = btAddress;
    this.btName = btName;
    if (useWifi != null) this.useWifi = useWifi;
    if (maxBackoff != null) this.maxBackoff = maxBackoff;
    reconnect();
  }

  /// Cierra la conexión actual (si hay) y reintenta de inmediato.
  void reconnect() {
    diag.note('Reintento manual');
    _session?.peer.close();
    _wakeUp();
  }

  /// Envía un mensaje al celular. `false` si no hay conexión o si la sesión aún no está
  /// autenticada y el tipo no se permite antes (v3: solo `hello`/`auth`/`pair_*`/`pong`).
  Future<bool> send(Map<String, dynamic> msg) async {
    final s = _session;
    if (s == null) return false;
    if (!s.authed && !LinkProtocol.preAuthTypes.contains(msg['t'])) return false;
    return s.peer.conn.sendLine(LinkProtocol.encodeLine(msg).trimRight());
  }

  Future<bool> sendCommand(LinkAction action, {int? positionMs, int? queueId}) =>
      send(LinkProtocol.cmd(action, positionMs: positionMs, queueId: queueId));

  /// La sesión actual está autenticada.
  bool get authenticated => _session?.authed ?? false;

  /// Cierra el código en pantalla sin emparejar (botón "Cancelar").
  void cancelPairing() {
    final p = pairing.value;
    if (p == null) return;
    if (p.phase == PairingPhase.showing) {
      // `busy` (no `expired`): con `expired` el celular pide otro código al instante.
      unawaited(send(LinkProtocol.pairFail('busy')));
      diag.note('Emparejamiento cancelado en la tableta');
    }
    _clearPairing();
    final s = _session;
    if (s != null && !s.authed) auth.value = LinkAuthState.pending;
  }

  void _clearPairing() {
    _pairTimer?.cancel();
    _pairTimer = null;
    _pairClear?.cancel();
    _pairClear = null;
    pairing.value = null;
  }

  /// Cierra la conexión si es la del celular [id] (al "Olvidar" un celular).
  void dropPeer(String id) {
    final s = _session;
    if (s != null && s.peer.id == id) {
      diag.note('Se olvidó al celular conectado: se cierra el enlace');
      unawaited(s.peer.close());
    }
  }

  /// Redes actuales (se refrescan solas; esto fuerza una lectura).
  Future<List<LinkNetwork>> refreshNetworks() => _refreshNetworks();

  // ---------------------------------------------------------------------------
  // Decisión (pura)

  /// Qué hacer con una conexión nueva [incoming] habiendo (o no) un enlace [current].
  /// - Sin enlace → [LinkDecision.adopt].
  /// - El actual no recibió nada en [staleAfter] → [LinkDecision.replace].
  /// - El actual nunca mandó `hello` y el nuevo sí → replace.
  /// - El actual es Bluetooth y llega Wi-Fi del mismo celular (o sin `id`) → replace (Wi-Fi
  ///   es más rápido y lleva las carátulas).
  /// - Si no → [LinkDecision.keepCurrent]: se queda el más viejo (el que se estableció
  ///   antes), igual que el celular, así ambos lados convergen en la misma conexión.
  static LinkDecision decide({
    required LinkPeerInfo? current,
    required LinkPeerInfo incoming,
    required DateTime now,
    Duration staleAfter = const Duration(seconds: 25),
  }) {
    if (current == null) return LinkDecision.adopt;
    if (now.difference(current.lastRx) >= staleAfter) return LinkDecision.replace;
    // Como el celular: si el actual nunca respondió (sin `hello`) y el nuevo sí, gana el nuevo.
    if (!current.answered && incoming.answered) return LinkDecision.replace;
    final samePhone = current.id == null || incoming.id == null || current.id == incoming.id;
    if (samePhone && current.transport == 'bt' && incoming.transport == 'wifi') return LinkDecision.replace;
    return LinkDecision.keepCurrent;
  }

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
        diag.heard(hit.address, device: m.device, port: m.port, id: m.id);
        if (!useWifi || _session != null) return;
        // Carrera en curso: el intento a este celular arranca ya, sin esperar a los lentos.
        final race = _race;
        if (race != null && !race.isDone) {
          _attemptTcp(race, hit.address, m.port);
        } else if (isNew) {
          _wakeUp();
        }
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

  Future<void> _startServer() async {
    if (!socketsSupported || !_running) return;
    final s = await _serverFactory(listenPort);
    if (!_running) {
      await s?.close();
      return;
    }
    if (s == null) {
      diag.listeningPort = null;
      diag.note('No se pudo escuchar en el puerto $listenPort; se reintenta en 5 s');
      _serverRetry = Timer(const Duration(seconds: 5), () => unawaited(_startServer()));
      return;
    }
    _server = s;
    diag.listeningPort = s.port;
    diag.note('Escuchando conexiones del celular en el puerto ${s.port}');
    _serverSub = s.connections.listen((c) {
      diag.markInbound();
      diag.attempt(
        LinkAttempt(at: DateTime.now(), target: c.remoteAddress, transport: c.transport, ok: true, inbound: true),
      );
      unawaited(_offer(c, inbound: true));
    });
  }

  Future<void> _startBeaconing() async {
    if (!socketsSupported) return;
    _udp = await openUdpSender();
    if (_udp == null || !_running) return;
    void tick() {
      final udp = _udp;
      final id = installId;
      if (udp == null || id == null) return;
      final payload = LinkProtocol.encodeLine(
        LinkProtocol.carBeacon(device: _selfName, id: id, port: boundPort ?? listenPort),
      ).trimRight();
      var any = false;
      for (final host in beaconTargets(diag.networks)) {
        any = udp.send(host, LinkProtocol.carBeaconPort, payload) || any;
      }
      if (any) diag.sentBeacon();
    }

    tick();
    _beaconTimer = Timer.periodic(LinkProtocol.carBeaconInterval, (_) => tick());
  }

  Future<List<LinkNetwork>> _readNetworks() async {
    final custom = networksProvider;
    if (custom != null) return custom();
    if (_bridge.isSupported) {
      final raw = await _bridge.getWifiNetworks();
      final list = [for (final m in raw) ?LinkNetwork.fromMap(m)];
      if (list.isNotEmpty) return list;
    }
    return [for (final ip in await localIPv4s()) LinkNetwork(ip: ip)];
  }

  Future<List<LinkNetwork>> _refreshNetworks() async {
    final list = await _readNetworks();
    diag.setNetworks(list);
    final key = (list.map((n) => n.ip).toList()..sort()).join(',');
    final old = _netKey;
    _netKey = key;
    if (old != null && old != key && _running) {
      diag.note('Cambiaron las redes: ${key.isEmpty ? 'ninguna' : key}');
      if (_session == null) {
        // Se reintenta ya (y los intentos de la carrera actual siguen).
        final race = _race;
        if (race != null && !race.isDone) {
          unawaited(_addTargets(race));
        } else {
          _wakeUp();
        }
      }
    }
    return list;
  }

  Future<void> _loop() async {
    var backoff = const Duration(seconds: 1);
    while (_running) {
      final s = _session;
      if (s != null) {
        await s.done.future;
        if (!_running) break;
        backoff = const Duration(seconds: 1);
        if (_session == null) await _sleep(const Duration(milliseconds: 300));
        continue;
      }
      status.value = LinkStatus.searching;
      await _runRace();
      if (!_running) break;
      if (_session != null) continue;
      await _sleep(backoff);
      backoff = Duration(
        milliseconds: math.min(backoff.inMilliseconds * 2, math.max(1000, maxBackoff.inMilliseconds)),
      );
    }
  }

  /// Lanza todos los intentos en paralelo y termina cuando: hay enlace (saliente o
  /// entrante), fallaron todos los intentos Wi-Fi, o pasó [raceCap].
  Future<void> _runRace() async {
    final race = _race = _Race();
    final cap = Timer(raceCap, race.finish);
    await _addTargets(race);
    final bt = btAddress;
    final hasBt = bt != null && bt.isNotEmpty && _bridge.isSupported;
    if (hasBt) _startRfcomm(bt);
    if (race.pending == 0) {
      if (hasBt && _rfcommBusy) {
        race.waitBt = true; // solo Bluetooth: se espera (con el tope)
      } else {
        race.finish();
      }
    }
    await race.done;
    cap.cancel();
    if (identical(_race, race)) _race = null;
  }

  Future<void> _addTargets(_Race race) async {
    if (!useWifi || !socketsSupported) return;
    final now = DateTime.now();
    _beacons.removeWhere((_, b) => now.difference(b.at) > const Duration(seconds: 15));
    final gw = await _bridge.getGatewayIp();
    // Con el hotspot de la tableta encendido, el celular es un cliente: sus IPs están en
    // la tabla de vecinos (ARP). Se refresca en cada intento.
    final neighbors = await _bridge.getNeighborIps();
    final gateways = [?gw, for (final n in diag.networks) ?n.gateway];
    final targets = buildTargets(
      beacons: {for (final e in _beacons.entries) e.key: e.value.port},
      gateway: gateways.isEmpty ? null : gateways.first,
      manualIp: manualIp,
      neighbors: [...gateways.skip(1), ...neighbors],
    );
    if (race.isDone) return;
    for (final t in targets.entries) {
      _attemptTcp(race, t.key, t.value);
    }
  }

  void _attemptTcp(_Race race, String host, int port) {
    final key = '$host:$port';
    if (race.isDone || !race.tried.add(key)) return;
    race.pending++;
    final sw = Stopwatch()..start();
    String? error;
    _connector(host, port, attemptTimeout, (e) => error = e).then((c) {
      race.pending--;
      diag.attempt(
        LinkAttempt(
          at: DateTime.now(),
          target: key,
          transport: 'wifi',
          ok: c != null,
          error: c == null ? (error ?? 'sin respuesta') : null,
          ms: sw.elapsedMilliseconds,
        ),
      );
      if (c != null) {
        unawaited(_offer(c, inbound: false));
      } else if (race.pending == 0 && !race.waitBt) {
        race.finish();
      }
    });
  }

  /// RFCOMM en segundo plano (puede tardar varios segundos): si conecta, se ofrece como
  /// cualquier otra conexión.
  void _startRfcomm(String address) {
    if (_rfcommBusy) return;
    _rfcommBusy = true;
    final sw = Stopwatch()..start();
    final conn = _RfcommConnection(_bridge, address);
    _bridge
        .connectRfcomm(address)
        .then((ok) async {
          diag.attempt(
            LinkAttempt(
              at: DateTime.now(),
              target: address,
              transport: 'bt',
              ok: ok,
              error: ok ? null : 'no conectó',
              ms: sw.elapsedMilliseconds,
            ),
          );
          if (ok && _running) {
            await _offer(conn, inbound: false);
          } else {
            await conn.dispose();
          }
        })
        .whenComplete(() {
          _rfcommBusy = false;
          final race = _race;
          if (race != null && race.waitBt) race.finish();
        });
  }

  /// Punto único de entrada de toda conexión (saliente, entrante o Bluetooth).
  Future<void> _offer(LinkConnection conn, {required bool inbound}) async {
    if (!_running) {
      await conn.close();
      return;
    }
    final p = _Peer(conn, inbound: inbound);
    if (_session == null) {
      _adopt(p);
      return;
    }
    // Ya hay enlace: se decide con el `id` del recién llegado (si lo manda pronto).
    await p.waitHello(helloWait);
    if (p.isClosed) return;
    if (!_running) {
      await p.close();
      return;
    }
    final cur = _session;
    final d = decide(current: cur?.peer.info, incoming: p.info, now: DateTime.now(), staleAfter: watchdog);
    final who = '${inbound ? 'entrante' : 'saliente'} ${p.transport} ${p.address}';
    switch (d) {
      case LinkDecision.adopt:
        _adopt(p);
      case LinkDecision.replace:
        diag.note('Se cambia al enlace $who (el anterior estaba caído o era Bluetooth)');
        if (cur != null) {
          cur.replaced = true;
          unawaited(cur.peer.close());
        }
        _adopt(p);
      case LinkDecision.keepCurrent:
        diag.note('Conexión duplicada $who: se guarda de reserva ${spareGrace.inSeconds} s');
        _setSpare(p);
    }
  }

  /// La duplicada no se cierra enseguida: si el celular eligió esa (y cierra la nuestra),
  /// se promueve sin perder tiempo. Si no, se cierra al pasar [spareGrace].
  void _setSpare(_Peer p) {
    _dropSpare();
    _spare = p;
    _spareTimer = Timer(spareGrace, () {
      if (identical(_spare, p)) _dropSpare();
    });
    p.closed.then((_) {
      if (identical(_spare, p)) {
        _spare = null;
        _spareTimer?.cancel();
      }
    });
  }

  void _dropSpare() {
    _spareTimer?.cancel();
    _spareTimer = null;
    final s = _spare;
    _spare = null;
    if (s != null) unawaited(s.close());
  }

  void _adopt(_Peer p) {
    final s = _session = _Session(p);
    final beacon = _beacons[p.address];
    final name = p.device ?? (p.transport == 'bt' ? (btName ?? 'Celular') : (beacon?.device ?? 'Celular'));
    // Sin "Requerir emparejamiento" se confía desde el principio (como v2).
    s.authed = !trust.requirePairing;
    auth.value = s.authed ? LinkAuthState.authenticated : LinkAuthState.pending;
    status.value = LinkStatus.connected(
      device: name,
      transport: p.transport,
      address: p.address,
      inbound: p.inbound,
      authenticated: s.authed,
    );
    diag
      ..markConnected()
      ..note('Conectado (${p.inbound ? 'el celular marcó' : 'la tableta marcó'}) por ${p.transport} con ${p.address}');
    _race?.finish();
    _wakeUp();
    unawaited(_serve(s));
  }

  Future<void> _serve(_Session s) async {
    final p = s.peer;
    final conn = p.conn;
    final done = Completer<void>();
    final dog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (DateTime.now().difference(p.lastRx) > watchdog) {
        diag.note('Sin datos en ${watchdog.inSeconds} s: se da por caída');
        p.close();
      }
    });
    void sendRaw(Map<String, dynamic> m) => conn.sendLine(LinkProtocol.encodeLine(m).trimRight());
    final sub = p.lines.listen(
      (line) {
        diag.markRx();
        final msg = LinkProtocol.decodeLine(line);
        if (msg == null) return;
        final current = identical(_session, s);
        switch (msg) {
          case PingMessage():
            sendRaw(LinkProtocol.pong());
          case HelloMessage(:final device):
            if (current) status.value = status.value.withDevice(device);
            _answerAuth(s, msg);
            _messages.add(msg);
          case AuthMessage(:final mac):
            if (current) _checkAuth(s, mac);
          case PairRequestMessage(:final name):
            if (current) _onPairRequest(s, name);
          case PairMessage(:final code, :final token):
            if (current) _onPair(s, code, token);
          case _ when !s.authed:
            // v3: nada de datos de un celular sin autenticar.
            break;
          case TrackMessage():
            diag.markTrack();
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

    await conn.sendLine(
      LinkProtocol.encodeLine(LinkProtocol.hello(_selfName, id: installId, nonce: s.nonce)).trimRight(),
    );
    // El hello del celular pudo llegar antes de que esta sesión se adoptara.
    if (p.device != null) _answerAuth(s, HelloMessage(device: p.device!, id: p.id, nonce: p.nonce));
    if (s.authed) {
      await conn.sendLine(LinkProtocol.encodeLine(LinkProtocol.resync()).trimRight());
      if (!_authenticated.isClosed) _authenticated.add(null);
    } else {
      diag.note('Esperando que el celular se autentique (emparejamiento requerido)');
    }

    await Future.any([done.future, p.closed]);
    dog.cancel();
    await sub.cancel();
    await p.close();
    if (identical(_session, s)) {
      _session = null;
      auth.value = LinkAuthState.none;
      if (pairing.value?.phase == PairingPhase.showing) _clearPairing();
      diag
        ..markDisconnected()
        ..note('Enlace cerrado (${p.address})');
      final spare = _spare;
      if (spare != null && !spare.isClosed && _running) {
        // El celular se quedó con la otra conexión: se usa esa.
        _spareTimer?.cancel();
        _spare = null;
        diag.note('Se usa la conexión de reserva (${spare.address})');
        _adopt(spare);
      } else if (_running) {
        status.value = LinkStatus.searching;
      }
    }
    if (!s.done.isCompleted) s.done.complete();
  }

  // ---------------------------------------------------------------------------
  // v3: autenticación y emparejamiento

  /// Si hay token para el celular, contesta su `hello` con `auth` (una vez por nonce).
  void _answerAuth(_Session s, HelloMessage hello) {
    final nonce = hello.nonce, id = hello.id, me = installId;
    if (nonce == null || id == null || me == null || s.answeredNonce == nonce) return;
    final token = trust.tokenFor(id);
    if (token == null) {
      if (!s.authed) diag.note('Celular sin emparejar (${hello.device}): se espera el código');
      return;
    }
    s.answeredNonce = nonce;
    unawaited(s.peer.conn.sendLine(
      LinkProtocol.encodeLine(LinkProtocol.auth(LinkAuth.mac(token: token, nonce: nonce, id: me))).trimRight(),
    ));
  }

  void _checkAuth(_Session s, String mac) {
    if (s.authed) return;
    final id = s.peer.id;
    final token = trust.tokenFor(id);
    if (id == null || token == null) {
      diag.note('El celular mandó «auth» pero no es de confianza: hay que emparejar');
      return;
    }
    if (LinkAuth.sameMac(mac, LinkAuth.mac(token: token, nonce: s.nonce, id: id))) {
      diag.note('Celular de confianza «${trust[id]?.name ?? id}» autenticado');
      _authenticate(s);
    } else {
      diag.note('Autenticación inválida del celular: hay que volver a emparejar');
    }
  }

  void _onPairRequest(_Session s, String? name) {
    final now = DateTime.now();
    final cur = pairing.value;
    final phoneName = name ?? s.peer.device ?? 'Celular';
    if (cur != null &&
        cur.phase == PairingPhase.showing &&
        !cur.expiredAt(now) &&
        cur.phoneId != s.peer.id) {
      unawaited(send(LinkProtocol.pairFail('busy')));
      return;
    }
    _pairClear?.cancel();
    _pairTimer?.cancel();
    final prompt = PairingPrompt(
      code: LinkAuth.pairCode(),
      phoneName: phoneName,
      phoneId: s.peer.id,
      expiresAt: now.add(codeTtl),
    );
    pairing.value = prompt;
    auth.value = LinkAuthState.pairing;
    diag.note('«$phoneName» pidió emparejar: código en pantalla (${codeTtl.inSeconds} s)');
    _pairTimer = Timer(codeTtl, () {
      final p = pairing.value;
      if (p == null || p.phase != PairingPhase.showing) return;
      diag.note('El código de emparejamiento venció');
      _finishPairing(p.copyWith(phase: PairingPhase.expired));
      if (!s.authed && identical(_session, s)) auth.value = LinkAuthState.pending;
    });
    unawaited(send(LinkProtocol.pairShown()));
  }

  void _onPair(_Session s, String code, String token) {
    final p = pairing.value;
    if (p == null || p.phase != PairingPhase.showing) {
      unawaited(send(LinkProtocol.pairFail('expired')));
      return;
    }
    if (p.expiredAt(DateTime.now())) {
      unawaited(send(LinkProtocol.pairFail('expired')));
      _finishPairing(p.copyWith(phase: PairingPhase.expired));
      return;
    }
    final id = s.peer.id;
    final digits = code.replaceAll(RegExp(r'\s'), '');
    if (digits != p.code || id == null || !LinkAuth.validToken(token)) {
      final attempts = p.attempts + 1;
      unawaited(send(LinkProtocol.pairFail('code')));
      diag.note('Código de emparejamiento incorrecto ($attempts/${LinkAuth.maxAttempts})');
      if (attempts >= LinkAuth.maxAttempts) {
        _finishPairing(p.copyWith(attempts: attempts, phase: PairingPhase.failed));
        if (!s.authed) auth.value = LinkAuthState.pending;
      } else {
        pairing.value = p.copyWith(attempts: attempts);
      }
      return;
    }
    trust.trust(id, token.toLowerCase(), p.phoneName);
    unawaited(send(LinkProtocol.pairOk()));
    diag.note('Emparejado con «${p.phoneName}»');
    _finishPairing(p.copyWith(phase: PairingPhase.success));
    _authenticate(s);
  }

  /// Deja el resultado en pantalla un momento (para la animación) y luego lo cierra.
  void _finishPairing(PairingPrompt result) {
    _pairTimer?.cancel();
    pairing.value = result;
    _pairClear?.cancel();
    _pairClear = Timer(const Duration(milliseconds: 1800), () {
      if (identical(pairing.value, result)) pairing.value = null;
    });
  }

  void _authenticate(_Session s) {
    if (s.authed) return;
    s.authed = true;
    if (!identical(_session, s)) return;
    auth.value = LinkAuthState.authenticated;
    status.value = status.value.withAuth(true);
    unawaited(s.peer.conn.sendLine(LinkProtocol.encodeLine(LinkProtocol.resync()).trimRight()));
    if (!_authenticated.isClosed) _authenticated.add(null);
  }

  /// Máximo de IPs vecinas que se prueban por intento.
  static const maxNeighbors = 24;

  /// Destinos TCP (IP → puerto) de un intento, en orden de prioridad: beacons recientes,
  /// gateway (hotspot del celular), IP manual (`ip` o `ip:puerto`) y vecinos (hotspot de
  /// la tableta). Sin duplicados; se descartan direcciones vacías / `0.0.0.0`.
  @visibleForTesting
  static Map<String, int> buildTargets({
    Map<String, int> beacons = const {},
    String? gateway,
    String? manualIp,
    List<String> neighbors = const [],
  }) {
    bool valid(String? ip) => ip != null && ip.isNotEmpty && ip != '0.0.0.0';
    final targets = <String, int>{};
    for (final e in beacons.entries) {
      if (valid(e.key)) targets[e.key] = e.value;
    }
    final gw = gateway?.trim();
    if (valid(gw)) targets.putIfAbsent(gw!, () => LinkProtocol.tcpPort);
    final manual = manualIp?.trim();
    if (manual != null && manual.isNotEmpty) {
      final parts = manual.split(':');
      if (valid(parts.first)) {
        targets.putIfAbsent(
          parts.first,
          () => parts.length > 1 ? int.tryParse(parts[1]) ?? LinkProtocol.tcpPort : LinkProtocol.tcpPort,
        );
      }
    }
    var added = 0;
    for (final raw in neighbors) {
      final ip = raw.trim();
      if (!valid(ip) || targets.containsKey(ip)) continue;
      if (added++ >= maxNeighbors) break;
      targets[ip] = LinkProtocol.tcpPort;
    }
    return targets;
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
