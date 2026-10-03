import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_car_player/core/models/now_playing.dart';
import 'package:pixel_car_player/data/link/link_protocol.dart';

void main() {
  group('LinkProtocol.decodeLine', () {
    test('hello', () {
      final m = LinkProtocol.decodeLine('{"t":"hello","v":1,"device":"Pixel 8","source":""}');
      expect(m, isA<HelloMessage>());
      expect((m as HelloMessage).device, 'Pixel 8');
      expect(m.source, '');
    });

    test('track con números como double', () {
      final m = LinkProtocol.decodeLine(
        '{"t":"track","id":"abc","title":"Canción","artist":"Artista","album":"Disco",'
        '"durationMs":222000.0,"source":"com.spotify.music"}\n',
      );
      final t = (m as TrackMessage).track;
      expect(t.id, 'abc');
      expect(t.title, 'Canción');
      expect(t.duration, const Duration(milliseconds: 222000));
      expect(t.source, 'com.spotify.music');
    });

    test('art decodifica base64', () {
      final b64 = base64Encode([1, 2, 3, 250]);
      final m = LinkProtocol.decodeLine('{"t":"art","id":"abc","mime":"image/jpeg","b64":"$b64"}');
      expect((m as ArtMessage).id, 'abc');
      expect(m.bytes, [1, 2, 3, 250]);
    });

    test('art con b64 inválido no revienta', () {
      final m = LinkProtocol.decodeLine('{"t":"art","id":"abc","b64":"@@@"}');
      expect((m as ArtMessage).bytes, isNull);
    });

    test('state', () {
      final m = LinkProtocol.decodeLine('{"t":"state","playing":true,"positionMs":61500,"speed":1}');
      final s = m as StateMessage;
      expect(s.playing, isTrue);
      expect(s.position, const Duration(milliseconds: 61500));
      expect(s.speed, 1.0);
    });

    test('lyrics', () {
      final m = LinkProtocol.decodeLine(
        '{"t":"lyrics","id":"abc","status":"ok","synced":true,'
        '"lines":[{"ms":0,"text":""},{"ms":1200.0,"text":"Hola"}]}',
      );
      final l = m as LyricsMessage;
      expect(l.status, LyricsStatus.ok);
      expect(l.synced, isTrue);
      expect(l.lines.length, 2);
      expect(l.lines[1].time, const Duration(milliseconds: 1200));
      expect(l.lines[1].text, 'Hola');
      expect(
        (LinkProtocol.decodeLine('{"t":"lyrics","id":"x","status":"not_found"}') as LyricsMessage).status,
        LyricsStatus.notFound,
      );
    });

    test('ping, beacon, desconocido e inválido', () {
      expect(LinkProtocol.decodeLine('{"t":"ping"}'), isA<PingMessage>());
      final b = LinkProtocol.decodeLine('{"t":"beacon","v":1,"device":"Pixel 8","port":47321}');
      expect((b as BeaconMessage).port, 47321);
      expect(LinkProtocol.decodeLine('{"t":"futuro","x":1}'), isA<UnknownMessage>());
      expect(LinkProtocol.decodeLine('no es json'), isNull);
      expect(LinkProtocol.decodeLine('[1,2]'), isNull);
      expect(LinkProtocol.decodeLine('   '), isNull);
    });
  });

  group('codificación', () {
    test('cmd y seek', () {
      expect(LinkProtocol.cmd(LinkAction.toggle), {'t': 'cmd', 'action': 'toggle'});
      expect(LinkProtocol.cmd(LinkAction.seek, positionMs: 5000), {'t': 'cmd', 'action': 'seek', 'positionMs': 5000});
    });

    test('encodeLine termina en \\n y es una sola línea', () {
      final l = LinkProtocol.encodeLine(LinkProtocol.hello('Tableta'));
      expect(l.endsWith('\n'), isTrue);
      expect('\n'.allMatches(l).length, 1);
      expect(jsonDecode(l), {'t': 'hello', 'v': 1, 'device': 'Tableta'});
    });
  });

  group('LineBuffer', () {
    test('fragmentos parciales', () {
      final b = LineBuffer();
      expect(b.add('{"t":"pi'), isEmpty);
      expect(b.add('ng"}\n{"t":'), ['{"t":"ping"}']);
      expect(b.pending, '{"t":');
      expect(b.add('"state"}\n'), ['{"t":"state"}']);
    });

    test('varias líneas, CRLF y líneas vacías', () {
      final b = LineBuffer();
      expect(b.add('a\r\n\nb\nc'), ['a', 'b']);
      expect(b.add('\n'), ['c']);
    });

    test('ByteLineDecoder con UTF-8 multibyte partido', () {
      final d = ByteLineDecoder();
      final bytes = utf8.encode('{"t":"track","title":"Neón"}\n');
      final cut = bytes.indexOf(0xC3) + 1; // parte la "ó" a la mitad
      expect(d.add(bytes.sublist(0, cut)), isEmpty);
      final out = d.add(bytes.sublist(cut));
      expect(out, ['{"t":"track","title":"Neón"}']);
    });
  });
}
