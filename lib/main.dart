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
    if (mode == AppMode.car) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
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
    final Widget home = switch (_mode) {
      AppMode.car => CarRoot(
          demo: widget.config.demo,
          onChangeMode: () => _setMode(null),
        ),
      AppMode.phone => PhoneRoot(onChangeMode: () => _setMode(null)),
      null => ModeSelectScreen(onSelected: _setMode),
    };
    return MaterialApp(
      title: 'Pixel Car Player',
      debugShowCheckedModeBanner: false,
      theme: HarmonixTheme.dark(),
      darkTheme: HarmonixTheme.dark(),
      themeMode: ThemeMode.dark,
      home: home,
    );
  }
}
