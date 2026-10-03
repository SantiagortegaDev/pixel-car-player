import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_car_player/data/link/car_link_client.dart';
import 'package:pixel_car_player/data/link/link_protocol.dart';

/// Destinos TCP de cada intento de conexión: beacons, gateway, IP manual y las IPs vecinas
/// (celular conectado al hotspot de la tableta).
void main() {
  const port = LinkProtocol.tcpPort;

  test('incluye las IPs vecinas en la carrera', () {
    final t = CarLinkClient.buildTargets(neighbors: ['192.168.43.120', '192.168.43.7']);
    expect(t, {'192.168.43.120': port, '192.168.43.7': port});
  });

  test('orden de prioridad y sin duplicados', () {
    final t = CarLinkClient.buildTargets(
      beacons: {'192.168.1.20': 47999},
      gateway: '192.168.1.1',
      manualIp: '10.0.0.5:5000',
      neighbors: ['192.168.1.20', '192.168.1.1', ' 192.168.1.33 ', '', '0.0.0.0', '192.168.1.33'],
    );
    expect(t.keys.toList(), ['192.168.1.20', '192.168.1.1', '10.0.0.5', '192.168.1.33']);
    // El puerto del beacon gana sobre el de los vecinos.
    expect(t['192.168.1.20'], 47999);
    expect(t['10.0.0.5'], 5000);
    expect(t['192.168.1.33'], port);
  });

  test('gateway inválido e IP manual vacía se ignoran', () {
    expect(CarLinkClient.buildTargets(gateway: '0.0.0.0', manualIp: '  '), isEmpty);
    expect(CarLinkClient.buildTargets(manualIp: '192.168.43.1'), {'192.168.43.1': port});
    expect(CarLinkClient.buildTargets(manualIp: '192.168.43.1:abc'), {'192.168.43.1': port});
  });

  test('limita la cantidad de vecinos', () {
    final many = [for (var i = 2; i < 100; i++) '192.168.43.$i'];
    final t = CarLinkClient.buildTargets(neighbors: many);
    expect(t.length, CarLinkClient.maxNeighbors);
    expect(t.keys.first, '192.168.43.2');
  });
}
