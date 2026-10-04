import 'dart:async';

import 'link_transport_types.dart';

export 'link_transport_types.dart';

const bool socketsSupported = false;

Future<LinkConnection?> connectTcp(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 3),
  void Function(String error)? onError,
}) async => null;

Stream<BeaconHit> listenBeacons(int port) => const Stream.empty();

Future<LinkServer?> bindLinkServer(int port, {String? host}) async => null;

Future<UdpSender?> openUdpSender() async => null;

Future<List<String>> localIPv4s() async => const [];
