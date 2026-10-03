import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/car/car_player_screen.dart';
import 'package:pixel_car_player/car/car_settings_sheet.dart';
import 'package:pixel_car_player/data/link/link_prefs.dart';
import 'package:provider/provider.dart';

/// Raíz del modo tableta: crea el [CarController] y muestra la pantalla.
///
/// En web se acepta `?lyrics=1` para abrir directo el modo "solo letras"
/// (capturas).
class CarRoot extends StatefulWidget {
  const CarRoot({super.key, this.demo = false, required this.onChangeMode});
  final bool demo;
  final VoidCallback onChangeMode;

  @override
  State<CarRoot> createState() => _CarRootState();
}

class _CarRootState extends State<CarRoot> {
  CarController? _ctrl;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await CarPrefs.load();
    // En web manda el parámetro de la URL (?demo=0|1).
    if (kIsWeb) prefs.demo = widget.demo;
    final c = CarController(demo: widget.demo || prefs.demo, prefs: prefs);
    if (!mounted) {
      c.dispose();
      return;
    }
    setState(() => _ctrl = c);
    await c.start();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    if (c == null) return const Scaffold(body: SizedBox.shrink());
    return ChangeNotifierProvider<CarController>.value(
      value: c,
      child: CarPlayerScreen(
        initialLyricsFullscreen: kIsWeb && Uri.base.queryParameters['lyrics'] == '1',
        // El context recibido ya tiene el tema Material You de la carátula.
        onSettings: (themed) =>
            showCarSettings(themed, controller: c, onChangeMode: widget.onChangeMode),
      ),
    );
  }
}
