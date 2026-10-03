/// Transporte de red con import condicional: `dart:io` en Android/desktop,
/// stub en web (allí no hay sockets; la tableta web solo corre en demo).
library;

export 'link_transport_stub.dart' if (dart.library.io) 'link_transport_io.dart';
