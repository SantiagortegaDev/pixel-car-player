import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_car_player/core/app_mode.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/phone_root.dart';
import 'package:pixel_car_player/setup/mode_select_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester tester, Widget w, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: HarmonixTheme.dark(), home: w));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  // Sin plataforma Android: PhoneRoot usa el estado demo (como en web).
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final size in const [Size(412, 915), Size(1280, 720), Size(1024, 600)]) {
    testWidgets('ModeSelectScreen ${size.width}x${size.height}', (
      tester,
    ) async {
      AppMode? picked;
      await _pump(
        tester,
        ModeSelectScreen(onSelected: (m) => picked = m),
        size,
      );
      expect(find.text('Pantalla del carro (tableta)'), findsOneWidget);
      expect(find.text('Transmisor (celular con Spotify)'), findsOneWidget);
      await tester.tap(find.text('Transmisor (celular con Spotify)'));
      expect(picked, AppMode.phone);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'PhoneRoot ${size.width}x${size.height}',
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
      (tester) async {
        var changed = false;
        await _pump(
          tester,
          PhoneRoot(onChangeMode: () => changed = true),
          size,
        );
        expect(find.text('Transmisor activo'), findsOneWidget);
        expect(find.text('Pantalla K24'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byIcon(Icons.more_vert_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Cambiar modo'));
        expect(changed, isTrue);
      },
    );
  }
}
