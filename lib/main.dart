import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pixel_car_player/car/car_root.dart';
import 'package:pixel_car_player/core/app_mode.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/phone_root.dart';
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

  /// Color semilla del wallpaper (Material You, Android 12+). null = no disponible.
  Color? _systemSeed;

  @override
  void initState() {
    super.initState();
    if (_mode == AppMode.car) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    _loadSystemSeed();
  }

  Future<void> _loadSystemSeed() async {
    Color? seed;
    try {
      final palette = await DynamicColorPlugin.getCorePalette();
      if (palette != null) {
        seed = Color(palette.primary.get(40));
      } else {
        seed = await DynamicColorPlugin.getAccentColor();
      }
    } catch (_) {
      seed = null; // Web / Android < 12: se usa la semilla Harmonix.
    }
    if (mounted && seed != null) setState(() => _systemSeed = seed);
  }

  @override
  Widget build(BuildContext context) {
    final Widget home = switch (_mode) {
      // La tableta genera su propio tema Material You desde la carátula.
      AppMode.car => CarRoot(
          demo: widget.config.demo,
          onChangeMode: () => _setMode(null),
        ),
      AppMode.phone => PhoneRoot(onChangeMode: () => _setMode(null)),
      null => ModeSelectScreen(onSelected: _setMode),
    };
    // Material You: esquema tonal desde el color del wallpaper (Android 12+);
    // si no hay, desde la semilla Harmonix.
    final seed = _systemSeed ?? AppTheme.fallbackSeed;
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
