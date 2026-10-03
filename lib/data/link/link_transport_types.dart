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
