import 'dart:async';

import 'link_transport_types.dart';

export 'link_transport_types.dart';

const bool socketsSupported = false;

Future<LinkConnection?> connectTcp(String host, int port, {Duration timeout = const Duration(seconds: 3)}) async =>
    null;

Stream<BeaconHit> listenBeacons(int port) => const Stream.empty();
