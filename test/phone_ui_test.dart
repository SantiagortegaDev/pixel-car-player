import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_car_player/core/app_mode.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/phone_root.dart';
import 'package:pixel_car_player/setup/mode_select_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget w,
  Size size,
  Brightness brightness,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final scheme = AppTheme.schemeFromSeed(
    AppTheme.fallbackSeed,
    brightness: brightness,
  );
  await tester.pumpWidget(MaterialApp(theme: AppTheme.build(scheme), home: w));
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  // Sin plataforma Android: PhoneRoot usa el estado demo (como en web).
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const sizes = [
    Size(412, 915),
    Size(1024, 600),
    Size(1280, 720),
    Size(2000, 1200),
  ];

  for (final brightness in Brightness.values) {
    for (final size in sizes) {
      final tag = '${brightness.name} ${size.width}x${size.height}';

      testWidgets('ModeSelectScreen $tag', (tester) async {
        AppMode? picked;
        await _pump(
          tester,
          ModeSelectScreen(onSelected: (m) => picked = m),
          size,
          brightness,
        );
        expect(find.text('Pantalla del carro (tableta)'), findsOneWidget);
        expect(find.text('Transmisor (celular con Spotify)'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, 'Elegir'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Transmisor (celular con Spotify)'));
        expect(picked, AppMode.phone);
        await tester.tap(find.widgetWithText(FilledButton, 'Elegir').first);
        expect(picked, AppMode.car);
      });

      testWidgets(
        'PhoneRoot $tag',
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
        (tester) async {
          var changed = false;
          await _pump(
            tester,
            PhoneRoot(onChangeMode: () => changed = true),
            size,
            brightness,
          );
          expect(find.text('Pixel Car Player'), findsWidgets);
          expect(find.text('Transmisor activo'), findsOneWidget);
          expect(find.text('YT Music'), findsOneWidget);
          expect(find.text('Letras sincronizadas'), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Elementos inferiores (fuera de pantalla en el celular).
          await tester.scrollUntilVisible(
            find.text('Pantalla K24'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
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
}
