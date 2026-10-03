import 'package:flutter/material.dart';
import 'package:pixel_car_player/core/app_mode.dart';

/// Selección de rol al primer arranque. (Stub — agente de UI de celular.)
class ModeSelectScreen extends StatelessWidget {
  const ModeSelectScreen({super.key, required this.onSelected});
  final ValueChanged<AppMode> onSelected;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            FilledButton(onPressed: () => onSelected(AppMode.car), child: const Text('Tableta')),
            const SizedBox(width: 16),
            FilledButton(onPressed: () => onSelected(AppMode.phone), child: const Text('Celular')),
          ]),
        ),
      );
}
