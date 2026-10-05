import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pixel_car_player/car/car_root.dart';
import 'package:pixel_car_player/core/app_mode.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/phone_root.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx_motion.dart';
import 'package:pixel_car_player/setup/mode_select_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = await AppConfig.load();
  runApp(PixelCarPlayerApp(config: config));
}

class PixelCarPlayerApp extends StatefulWidget {
  const PixelCarPlayerApp({super.key, required this.config});
  final AppConfig config;

  @override
  State<PixelCarPlayerApp> createState() => _PixelCarPlayerAppState();
}

class _PixelCarPlayerAppState extends State<PixelCarPlayerApp> {
  late AppMode? _mode = widget.config.mode;

  Future<void> _setMode(AppMode? mode) async {
    await AppConfig.saveMode(mode);
    await SystemChrome.setEnabledSystemUIMode(mode == AppMode.car
        ? SystemUiMode.immersiveSticky
        : SystemUiMode.edgeToEdge);
    setState(() => _mode = mode);
  }

  @override
  void initState() {
    super.initState();
    if (_mode == AppMode.car) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget screen = switch (_mode) {
      // La tableta genera su propio tema Material You desde la carátula.
      AppMode.car => CarRoot(
          demo: widget.config.demo,
          onChangeMode: () => _setMode(null),
        ),
      AppMode.phone => PhoneRoot(onChangeMode: () => _setMode(null)),
      null => ModeSelectScreen(onSelected: _setMode),
    };
    // Cambio de modo (p. ej. elegir "Transmisor" en la selección): fundido con escala.
    final Widget home = HxFadeThroughSwitcher(
      child: KeyedSubtree(key: ValueKey(_mode), child: screen),
    );
    // Como Harmonix v2: el color sale de la portada que suena (cada pantalla envuelve
    // su contenido en HxAnimatedTheme); aquí va el tema base con la semilla por defecto.
    const seed = AppTheme.fallbackSeed;
    return MaterialApp(
      title: 'Pixel Car Player',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(
          AppTheme.schemeFromSeed(seed, brightness: Brightness.light)),
      darkTheme: AppTheme.build(AppTheme.schemeFromSeed(seed)),
      // En el carro siempre oscuro; el celular sigue al sistema.
      themeMode: _mode == AppMode.car ? ThemeMode.dark : ThemeMode.system,
      home: home,
    );
  }
}
