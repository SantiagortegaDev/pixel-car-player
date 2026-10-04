import 'dart:async';

/// Conexión de líneas JSON (TCP o RFCOMM).
abstract class LinkConnection {
  /// Líneas completas recibidas (sin `\n`). Se cierra al caer la conexión.
  Stream<String> get lines;

  /// Envía una línea (sin `\n`; se agrega).
  Future<bool> sendLine(String line);

  Future<void> close();

  /// IP o dirección MAC del otro extremo.
  String get remoteAddress;

  /// `wifi` | `bt`.
  String get transport;
}

/// Beacon UDP recibido: IP de origen + contenido.
class BeaconHit {
  const BeaconHit(this.address, this.payload);
  final String address;
  final String payload;
}

/// Servidor TCP que acepta conexiones entrantes (v2: el celular marca a la tableta).
abstract class LinkServer {
  /// Puerto real (útil con puerto 0 en pruebas).
  int get port;

  /// Conexiones aceptadas. Termina al cerrar el servidor.
  Stream<LinkConnection> get connections;

  Future<void> close();
}

/// Socket UDP para enviar beacons (broadcast habilitado).
abstract class UdpSender {
  /// `false` si no se pudo enviar (red caída, sin permiso…).
  bool send(String host, int port, String payload);

  void close();
}
