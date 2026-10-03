import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/car/settings/settings_controls.dart';
import 'package:pixel_car_player/car/system/car_hotspot.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/data/bridge/native_bridge.dart';

/// Diálogo cuando el hotspot del carro no se pudo encender solo: atajo a los ajustes del
/// hotspot y, si falta, al permiso "Modificar ajustes del sistema".
Future<void> showHotspotHelpDialog(BuildContext context, {required bool canWriteSettings, String? error}) {
  final bridge = NativeBridge.instance;
  final reason = hotspotErrorText(error);
  return showHxDialog<void>(
    context,
    title: 'Enciende el hotspot del carro',
    icon: Symbols.wifi_tethering_rounded,
    content: (ctx) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Este radio no deja que Pixel Car Player encienda el hotspot por su cuenta. '
          'Ábrelo en los ajustes y actívalo; el celular se conectará solo.',
        ),
        if (reason != null) ...[const SizedBox(height: 12), Text(reason)],
        if (!canWriteSettings) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HxIcon(Symbols.admin_panel_settings_rounded, size: 20, color: ctx.cs.secondary),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'En algunos radios basta con dar el permiso «Modificar ajustes del sistema» '
                  'para que la próxima vez se encienda solo.',
                ),
              ),
            ],
          ),
        ],
      ],
    ),
    actions: (ctx) => [
      HxButton(label: 'Ahora no', kind: HxButtonKind.text, height: 48, onTap: () => Navigator.of(ctx).pop()),
      if (!canWriteSettings)
        HxButton(
          label: 'Dar permiso',
          kind: HxButtonKind.tonal,
          height: 48,
          onTap: () {
            Navigator.of(ctx).pop();
            bridge.openWriteSettings();
          },
        ),
      HxButton(
        label: 'Abrir ajustes del hotspot',
        icon: Symbols.open_in_new_rounded,
        height: 48,
        onTap: () {
          Navigator.of(ctx).pop();
          bridge.openHotspotSettings();
        },
      ),
    ],
  );
}
