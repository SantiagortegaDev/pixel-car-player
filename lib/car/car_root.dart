import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/car/car_player_screen.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/car/custom/car_customization_store.dart';
import 'package:pixel_car_player/car/settings/car_settings_page.dart';
import 'package:pixel_car_player/data/link/link_prefs.dart';
import 'package:provider/provider.dart';

/// Raíz del modo tableta: carga las preferencias y la personalización, crea el
/// [CarController] y muestra la pantalla.
///
/// En web (capturas) se aceptan:
///  - `?lyrics=1`: abre directo la letra en pantalla completa.
///  - `?settings=<id>`: abre Configuración en esa categoría (`conexion`, `inicio`,
///    `diseno`, `portada`, `visibles`, `textos`, `letra`, `avanzado`).
///  - `?custom=<json>` (codificado para URL, o en base64url): personalización inicial
///    (no se guarda).
class CarRoot extends StatefulWidget {
  const CarRoot({super.key, this.demo = false, required this.onChangeMode});
  final bool demo;
  final VoidCallback onChangeMode;

  @override
  State<CarRoot> createState() => _CarRootState();
}

class _CarRootState extends State<CarRoot> {
  CarController? _ctrl;
  CarStartupOpts? _appliedStartup;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await CarPrefs.load();
    var store = await CarCustomizationStore.load();
    // En web manda el parámetro de la URL (?demo=0|1).
    if (kIsWeb) {
      prefs.demo = widget.demo;
      final custom = _customFromUrl();
      if (custom != null) {
        store.dispose();
        store = CarCustomizationStore(custom);
      }
    }
    final c = CarController(demo: widget.demo || prefs.demo, prefs: prefs, custom: store);
    if (!mounted) {
      c.dispose();
      store.dispose();
      return;
    }
    store.addListener(_applySystem);
    _applySystem(store);
    setState(() => _ctrl = c);
    final open = kIsWeb ? CarSettingsCategory.byId(Uri.base.queryParameters['settings']) : null;
    if (open != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openSettings(context, open);
      });
    }
    await c.start();
  }

  static CarCustomization? _customFromUrl() {
    final raw = Uri.base.queryParameters['custom'];
    if (raw == null || raw.isEmpty) return null;
    for (final decode in <String Function(String)>[
      (s) => s,
      (s) => utf8.decode(base64Url.decode(base64Url.normalize(s))),
    ]) {
      try {
        return CarCustomization.decode(decode(raw), shapes: CarCustomizationStore.shapeNames);
      } catch (_) {}
    }
    return null;
  }

  /// Pantalla inmersiva y orientación (Configuración → Inicio).
  void _applySystem([CarCustomizationStore? store]) {
    final s = (store ?? _ctrl?.custom)?.value.startup;
    if (s == null) return;
    final old = _appliedStartup;
    _appliedStartup = s;
    if (old == null || old.immersive != s.immersive) {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(s.immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge),
      );
    }
    if (old == null || old.lockLandscape != s.lockLandscape) {
      unawaited(
        SystemChrome.setPreferredOrientations(
          s.lockLandscape ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight] : const [],
        ),
      );
    }
  }

  void _openSettings(BuildContext context, [CarSettingsCategory initial = CarSettingsCategory.conexion]) {
    final c = _ctrl;
    if (c == null) return;
    // Evita apilar dos Configuraciones (p. ej. botón + mantener presionado).
    var open = false;
    Navigator.of(context).popUntil((r) {
      if (r.settings.name == 'car-settings') open = true;
      return true;
    });
    if (open) return;
    showCarSettings(context, controller: c, onChangeMode: widget.onChangeMode, initial: initial);
  }

  @override
  void dispose() {
    final c = _ctrl;
    if (c != null) {
      c.custom.removeListener(_applySystem);
      c.dispose();
      c.custom.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    if (c == null) return const Scaffold(body: SizedBox.shrink());
    return ChangeNotifierProvider<CarController>.value(
      value: c,
      child: CarPlayerScreen(
        initialLyricsFullscreen:
            c.cfg.startup.startLyricsFullscreen || (kIsWeb && Uri.base.queryParameters['lyrics'] == '1'),
        onSettings: (themed) => _openSettings(themed),
      ),
    );
  }
}
