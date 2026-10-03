import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/core/models/now_playing.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';
import 'package:pixel_car_player/data/link/link_protocol.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mensaje queue', () {
    test('parsea títulos y artistas', () {
      final m = LinkProtocol.decodeLine(
        '{"t":"queue","items":[{"title":"Uno","artist":"A"},{"title":"Dos"},{"artist":"sin título"},3]}',
      );
      expect(m, isA<QueueMessage>());
      final items = (m! as QueueMessage).items;
      expect(items, const [QueueItem(title: 'Uno', artist: 'A'), QueueItem(title: 'Dos')]);
    });

    test('sin items o vacío = lista vacía', () {
      expect((LinkProtocol.decodeLine('{"t":"queue"}')! as QueueMessage).items, isEmpty);
      expect((LinkProtocol.decodeLine('{"t":"queue","items":[]}')! as QueueMessage).items, isEmpty);
    });

    test('máximo 20 y codificación de ida y vuelta', () {
      final many = [for (var i = 0; i < 30; i++) QueueItem(title: 't$i', artist: 'a$i')];
      final line = LinkProtocol.encodeLine(LinkProtocol.queue(many));
      final back = (LinkProtocol.decodeLine(line)! as QueueMessage).items;
      expect(back.length, LinkProtocol.maxQueue);
      expect(back.first, many.first);
    });

    test('el controlador la guarda entre temas', () async {
      final c = CarController(demo: true);
      expect(c.queue, isEmpty);
      c.apply(const TrackMessage(TrackInfo(id: 'x', title: 'X', artist: 'Y')));
      c.apply(const QueueMessage([QueueItem(title: 'Sigue', artist: 'Z')]));
      expect(c.queue.single.title, 'Sigue');
      // Cambiar de tema no borra la cola (llega aparte).
      c.apply(const TrackMessage(TrackInfo(id: 'y', title: 'Y', artist: 'Y')));
      expect(c.queue, isNotEmpty);
      c.dispose();
    });
  });

  group('formas MD3', () {
    test('cookie9: radios en (0, 1] con máximo 1', () {
      final r = M3Shape.cookie9.radii;
      expect(r.length, M3Shape.n);
      for (final v in r) {
        expect(v, greaterThan(0));
        expect(v, lessThanOrEqualTo(1));
      }
      expect(r.reduce((a, b) => a > b ? a : b), closeTo(1, 1e-6));
      // 9 lóbulos: el valle es claramente menor que la punta.
      expect(r.reduce((a, b) => a < b ? a : b), lessThan(0.95));
    });

    test('todas las formas del catálogo están normalizadas', () {
      for (final e in M3Shape.all.entries) {
        final max = e.value.radii.reduce((a, b) => a > b ? a : b);
        expect(max, closeTo(1, 1e-6), reason: e.key);
        expect(e.value.radii.every((v) => v > 0), isTrue, reason: e.key);
      }
    });
  });
}
