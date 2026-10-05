import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/core/app_mode.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/phone_controller.dart';
import 'package:pixel_car_player/phone/controllers/pairing_controller.dart';
import 'package:pixel_car_player/phone/phone_root.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx.dart';
import 'package:pixel_car_player/phone/widgets/pairing_dialog.dart';
import 'package:pixel_car_player/phone/widgets/hotspot_card.dart';
import 'package:pixel_car_player/phone/widgets/link_diagnostics_card.dart';
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
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  final scheme = AppTheme.schemeFromSeed(
    AppTheme.fallbackSeed,
    brightness: brightness,
  );
  await tester.pumpWidget(MaterialApp(theme: AppTheme.build(scheme), home: w));
  // Hay animaciones infinitas (formas que giran): nada de pumpAndSettle.
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
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
        expect(find.text('Pixel Car Player'), findsOneWidget);
        expect(find.text('Pantalla del carro (tableta)'), findsOneWidget);
        expect(find.text('Transmisor (celular con Spotify)'), findsOneWidget);
        expect(find.text('Elegir'), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.text('Transmisor (celular con Spotify)'),
        );
        await tester.pump();
        await tester.tap(find.text('Transmisor (celular con Spotify)'));
        expect(picked, AppMode.phone);
        await tester.ensureVisible(find.text('Elegir').first);
        await tester.pump();
        await tester.tap(find.text('Elegir').first);
        expect(picked, AppMode.car);
      });

      testWidgets(
        'PhoneRoot $tag',
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
        (tester) async {
          var changed = false;
          await _pump(
            tester,
            PhoneRoot(
              onChangeMode: () => changed = true,
              now: () => DateTime(2026, 10, 3, 16),
            ),
            size,
            brightness,
          );
          // El tema sigue al sistema.
          final ctx = tester.element(find.text('Buenas tardes'));
          expect(Theme.of(ctx).brightness, brightness);

          expect(find.text('Pixel Car Player'), findsOneWidget);
          expect(find.text('Luces de Neón'), findsOneWidget);
          expect(find.text('Reproduciendo'), findsOneWidget);
          expect(find.text('Letras sincronizadas'), findsOneWidget);
          expect(find.text('Transmisor activo'), findsOneWidget);
          expect(find.text('Detener'), findsOneWidget);
          expect(tester.takeException(), isNull);

          await tester.scrollUntilVisible(
            find.text('Pantalla K24'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Pantalla K24'), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Conexión.
          await tester.tap(find.text('Conexión'));
          await _settle(tester);
          expect(find.text('Cómo conectar'), findsOneWidget);
          expect(find.text('192.168.43.1:47321'), findsOneWidget);
          expect(tester.takeException(), isNull);

          // Hotspot del carro.
          await tester.scrollUntilVisible(
            find.text('Conectarme automáticamente'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.text('Conectarme automáticamente'), findsOneWidget);
          expect(find.text('Sin Wi-Fi'), findsOneWidget);
          await tester.enterText(
            find.widgetWithText(TextField, 'Nombre de la red (SSID)'),
            'Carro',
          );
          await tester.enterText(
            find.widgetWithText(TextField, 'Contraseña'),
            'clave12345',
          );
          await tester.ensureVisible(find.text('Guardar'));
          await tester.pump();
          // Con las tarjetas nuevas queda pegado al borde de arriba: centrarlo.
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, 200),
          );
          await tester.pump();
          await tester.tap(find.text('Guardar'));
          await _settle(tester);
          final hp = await SharedPreferences.getInstance();
          expect(hp.getString('phone_car_hotspot_ssid'), 'Carro');
          expect(hp.getString('phone_car_hotspot_password'), 'clave12345');
          expect(hp.getBool('phone_car_hotspot_autoconnect'), isTrue);
          expect(find.textContaining('Guardado'), findsOneWidget);
          // El snackbar flotante tapa la barra inferior: esperar a que se vaya.
          await tester.pump(const Duration(seconds: 6));
          await _settle(tester);
          expect(tester.takeException(), isNull);

          // Ajustes: fuente de música y permisos.
          await tester.tap(find.text('Ajustes'));
          await _settle(tester);
          expect(find.text('Leer música de'), findsOneWidget);
          expect(find.text('YT Music'), findsOneWidget);
          expect(find.text('Permisos'), findsOneWidget);
          await tester.tap(find.text('YT Music'));
          await _settle(tester);
          final prefs = await SharedPreferences.getInstance();
          expect(prefs.getString('phone_source'), 'youtubeMusic');
          await tester.tap(find.text('Iniciar automáticamente'));
          await _settle(tester);
          expect(prefs.getBool('phone_autostart'), isFalse);
          expect(tester.takeException(), isNull);

          // Menú de la píldora del inicio → Cambiar modo.
          await tester.tap(find.text('Inicio'));
          await _settle(tester);
          await tester.tap(find.byIcon(Symbols.more_vert_rounded));
          await _settle(tester);
          await tester.tap(find.text('Cambiar modo'));
          await _settle(tester);
          expect(changed, isTrue);
        },
      );
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      'Conexión: hotspot + diagnóstico ${brightness.name} 412x915',
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
      (tester) async {
        await _pump(
          tester,
          PhoneRoot(onChangeMode: () {}, now: () => DateTime(2026, 10, 3, 16)),
          const Size(412, 915),
          brightness,
        );
        await tester.tap(find.text('Conexión'));
        await _settle(tester);
        await tester.scrollUntilVisible(
          find.text('IP del carro (opcional)'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('IP del carro (opcional)'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextField, 'IP del carro (opcional)'),
          '192.168.43.1',
        );
        await _settle(tester);
        expect(
          (await SharedPreferences.getInstance()).getString('phone_car_ip'),
          '192.168.43.1',
        );
        expect(tester.takeException(), isNull);

        await tester.scrollUntilVisible(
          find.text('Wi-Fi conectado'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Wi-Fi conectado'), findsOneWidget);
        expect(find.text('Transmisor activo'), findsWidgets);
        expect(find.text('Pantalla conectada'), findsOneWidget);
        expect(find.text('Enviando canción'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Copiar registro'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Actualizar'), findsOneWidget);
        expect(find.text('Borrar'), findsOneWidget);
        expect(find.text('Sin registro todavía.'), findsOneWidget);
        await tester.pump(const Duration(seconds: 4)); // refresco periódico
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'HotspotCard recarga y avisa con hotspotReceived',
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    (tester) async {
      final c = PhoneController();
      await tester.runAsync(c.init);
      await _pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                HotspotCard(c: c),
                LinkDiagnosticsCard(c: c),
              ],
            ),
          ),
        ),
        const Size(412, 1800),
        Brightness.light,
      );
      SharedPreferences.setMockInitialValues({
        'phone_car_hotspot_ssid': 'Tableta K24',
        'phone_car_hotspot_password': 'clave12345',
        'phone_car_hotspot_autoconnect': true,
      });
      await tester.runAsync(() => c.onHotspotReceived('Tableta K24'));
      await _settle(tester);
      expect(find.text('Recibido del carro'), findsOneWidget);
      expect(
        find.text(
          'La tableta compartió su hotspot «Tableta K24»: el celular se unirá solo',
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextField, 'Nombre de la red (SSID)'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(
              find.widgetWithText(TextField, 'Nombre de la red (SSID)'),
            )
            .controller!
            .text,
        'Tableta K24',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  // ---------------------------------------------------------------------------
  // v3: emparejamiento, encendido automático, actualizaciones, apariencia.
  // ---------------------------------------------------------------------------

  Finder codeField() => find.descendant(
    of: find.byType(PairingDialog),
    matching: find.byType(TextField),
  );

  bool pairButtonEnabled(WidgetTester tester) =>
      tester
          .widget<HxButton>(find.widgetWithText(HxButton, 'Emparejar'))
          .onPressed !=
      null;

  for (final brightness in Brightness.values) {
    testWidgets(
      'Emparejamiento: diálogo con pairNeeded, validación, fallo y éxito ${brightness.name}',
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
      (tester) async {
        final c = PhoneController();
        c.pairing.demoAutoResult = false;
        await _pump(
          tester,
          PhoneRoot(
            onChangeMode: () {},
            controller: c,
            now: () => DateTime(2026, 10, 3, 16),
          ),
          const Size(412, 915),
          brightness,
        );
        expect(find.byType(PairingDialog), findsNothing);

        c.handleEvent({
          'type': 'pairNeeded',
          'carId': 'car-1',
          'carName': 'Pantalla K24',
        });
        await _settle(tester);
        expect(find.byType(PairingDialog), findsOneWidget);
        expect(
          find.text(
            'Empareja con «Pantalla K24»: escribe el código de 6 dígitos que '
            'aparece en la pantalla del carro',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        // Solo dígitos, máximo 6; "Emparejar" se habilita con los 6.
        await tester.enterText(codeField(), '1a2b3');
        await tester.pump();
        expect(tester.widget<TextField>(codeField()).controller!.text, '123');
        expect(pairButtonEnabled(tester), isFalse);
        expect(c.pairing.phase, PairPhase.idle);

        // Al completar se envía solo.
        await tester.enterText(codeField(), '12345678');
        await tester.pump();
        expect(
          tester.widget<TextField>(codeField()).controller!.text,
          '123456',
        );
        expect(c.pairing.phase, PairPhase.submitting);
        expect(find.text('Verificando el código…'), findsOneWidget);

        // Código incorrecto: sacude, muestra el motivo y limpia las casillas.
        c.handleEvent({
          'type': 'pairResult',
          'carId': 'car-1',
          'ok': false,
          'reason': 'code',
        });
        await _settle(tester);
        expect(find.text('Código incorrecto'), findsOneWidget);
        expect(tester.widget<TextField>(codeField()).controller!.text, isEmpty);
        expect(tester.takeException(), isNull);

        // Código vencido.
        await tester.enterText(codeField(), '654321');
        await tester.pump();
        c.handleEvent({
          'type': 'pairResult',
          'carId': 'car-1',
          'ok': false,
          'reason': 'expired',
        });
        await _settle(tester);
        expect(find.textContaining('Código vencido'), findsOneWidget);

        // Éxito: check animado, se cierra y avisa.
        await tester.enterText(codeField(), '246810');
        await tester.pump();
        c.handleEvent({'type': 'pairResult', 'carId': 'car-1', 'ok': true});
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.text('¡Listo! Emparejado con «Pantalla K24»'),
          findsOneWidget,
        );
        await tester.pump(const Duration(milliseconds: 1200));
        await _settle(tester);
        expect(find.byType(PairingDialog), findsNothing);
        expect(find.text('Emparejado con «Pantalla K24»'), findsOneWidget);
        expect(c.pairing.hasPending, isFalse);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }

  testWidgets(
    'Emparejamiento: pedido en segundo plano se muestra al volver; "Ahora no" lo descarta',
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    (tester) async {
      final c = PhoneController();
      c.pairing.demoAutoResult = false;
      await _pump(
        tester,
        PhoneRoot(onChangeMode: () {}, controller: c),
        const Size(412, 915),
        Brightness.dark,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      c.handleEvent({
        'type': 'pairNeeded',
        'carId': 'car-2',
        'carName': 'Radio',
      });
      await _settle(tester);
      expect(find.byType(PairingDialog), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);
      expect(find.byType(PairingDialog), findsOneWidget);
      expect(find.textContaining('«Radio»'), findsOneWidget);
      await tester.tap(find.text('Ahora no'));
      await _settle(tester);
      expect(find.byType(PairingDialog), findsNothing);
      expect(c.pairing.hasPending, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  Future<void> openSettingsAt(WidgetTester tester, String text) async {
    await tester.tap(find.text('Ajustes'));
    await _settle(tester);
    await tester.scrollUntilVisible(
      find.text(text),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
  }

  testWidgets(
    'Ajustes: encendido automático y emparejados',
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    (tester) async {
      await _pump(
        tester,
        PhoneRoot(onChangeMode: () {}),
        const Size(412, 915),
        Brightness.light,
      );
      // Hotspot guardado del carro: se sugiere como red.
      final p = await SharedPreferences.getInstance();
      await p.setString('phone_car_hotspot_ssid', 'Tableta K24');
      await openSettingsAt(
        tester,
        'Encender el transmisor solo al subir al carro',
      );
      expect(find.text('Estado ahora'), findsOneWidget);
      expect(find.text('Bluetooth del carro'), findsWidgets);
      await tester.tap(
        find.text('Encender el transmisor solo al subir al carro'),
      );
      await _settle(tester);
      expect(p.getBool('phone_autostart_enabled'), isTrue);
      await tester.scrollUntilVisible(
        find.text('Radio del carro'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Radio del carro'));
      await _settle(tester);
      expect(p.getStringList('phone_autostart_bt'), ['00:1A:7D:DA:71:13']);
      await tester.scrollUntilVisible(
        find.text('Apagar 5 minutos después de bajarse'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byType(HxSlider), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Vincular con el carro'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Vincular con el carro'));
      await _settle(tester);
      expect(find.textContaining('Vinculado'), findsWidgets);
      await tester.pump(
        const Duration(seconds: 6),
      ); // estado cada 5 s + snackbar
      await _settle(tester);
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.text('Requerir emparejamiento'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Carros emparejados'), findsOneWidget);
      expect(find.text('Pantalla K24'), findsOneWidget);
      await tester.tap(find.text('Requerir emparejamiento'));
      await _settle(tester);
      expect(p.getBool(PairingController.kRequire), isFalse);
      await tester.tap(find.text('Olvidar'));
      await _settle(tester);
      await tester.tap(find.widgetWithText(HxButton, 'Olvidar').last);
      await _settle(tester);
      expect(find.text('Pantalla K24'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Ajustes: actualizaciones, copia de seguridad y apariencia',
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
    (tester) async {
      await _pump(
        tester,
        PhoneRoot(onChangeMode: () {}),
        const Size(412, 915),
        Brightness.dark,
      );
      await openSettingsAt(tester, 'Buscar ahora');
      expect(find.text('Pixel Car Player v1.0.0 (1)'), findsOneWidget);
      expect(find.text('Buscar una vez al día'), findsOneWidget);
      await tester.tap(find.text('Buscar ahora'));
      await _settle(tester);
      expect(find.text('Versión 1.1.0 disponible'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Descargar e instalar'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Descargar e instalar'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(HxProgressBar), findsOneWidget);
      expect(find.textContaining('Descargando…'), findsWidgets);
      await tester.pump(const Duration(seconds: 3));
      await _settle(tester);
      expect(find.text('Abriendo el instalador…'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.text('Exportar'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Restaurar'), findsOneWidget);
      expect(find.textContaining('contraseña del hotspot'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await _settle(tester);

      // Apariencia: tema claro forzado y animaciones reducidas.
      await tester.scrollUntilVisible(
        find.text('Tamaño del texto'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.scrollUntilVisible(
        find.text('Tema'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Claro'));
      await tester.pump(const Duration(seconds: 2));
      expect(
        Theme.of(tester.element(find.text('Tema'))).brightness,
        Brightness.light,
      );
      final p = await SharedPreferences.getInstance();
      expect(p.getString('phone_theme_mode'), 'light');
      await tester.scrollUntilVisible(
        find.text('Reducidas'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Reducidas'));
      await _settle(tester);
      expect(
        MediaQuery.of(tester.element(find.text('Reducidas'))).disableAnimations,
        isTrue,
      );
      await tester.scrollUntilVisible(
        find.text('Grande'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Grande'));
      await _settle(tester);
      expect(p.getDouble('phone_text_scale'), 1.15);
      expect(tester.takeException(), isNull);
    },
  );

  // Todas las pestañas, de arriba abajo, sin desbordes.
  for (final (size, brightness) in [
    (const Size(412, 915), Brightness.light),
    (const Size(412, 915), Brightness.dark),
    (const Size(1280, 720), Brightness.dark),
    (const Size(1280, 720), Brightness.light),
  ]) {
    testWidgets(
      'Todas las pestañas sin desbordes ${brightness.name} ${size.width}x${size.height}',
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'phone_autostart_enabled': true,
          'phone_autostart_wifi': [
            'Tableta K24 con un nombre de red bastante largo',
          ],
          'phone_car_hotspot_ssid': 'Tableta K24',
        });
        await _pump(
          tester,
          PhoneRoot(onChangeMode: () {}, now: () => DateTime(2026, 10, 3, 9)),
          size,
          brightness,
        );
        for (final tab in ['Inicio', 'Conexión', 'Ajustes']) {
          await tester.tap(find.text(tab).last);
          await _settle(tester);
          expect(tester.takeException(), isNull, reason: tab);
          for (var i = 0; i < 40; i++) {
            final before = tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .pixels;
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, -500),
            );
            await tester.pump(const Duration(milliseconds: 200));
            expect(tester.takeException(), isNull, reason: '$tab scroll $i');
            final after = tester
                .state<ScrollableState>(find.byType(Scrollable).first)
                .position
                .pixels;
            if (after == before) break;
          }
        }
        await tester.pump(const Duration(seconds: 6));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
