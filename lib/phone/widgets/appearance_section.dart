import 'package:flutter/material.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/controllers/phone_settings.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx.dart';

/// Ajustes → Apariencia: tema, color (semilla fija + variante, como la tableta),
/// tamaño del texto, animaciones y vibración.
class AppearanceSection extends StatelessWidget {
  const AppearanceSection({super.key, required this.s});
  final PhoneSettings s;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: s,
    builder: (context, _) {
      final seed = s.seed.toARGB32();
      return HxSettingsCard(
        children: [
          HxSettingsItem(
            label: 'Tema',
            child: HxSegmented<PhoneThemeMode>(
              value: s.themeMode,
              onChanged: s.setThemeMode,
              options: [
                for (final m in PhoneThemeMode.values) HxSegment(m, m.label),
              ],
            ),
          ),
          HxSettingsItem(
            label: 'Color',
            description:
                'Color fijo para todo el celular. El color de la portada y el de Material '
                'You del sistema solo están en la pantalla del carro.',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (argb, name) in PhoneSettings.swatches)
                  HxSwatch(
                    color: Color(argb),
                    tooltip: name,
                    selected: (seed & 0xFFFFFF) == (argb & 0xFFFFFF),
                    onTap: () => s.setSeed(Color(argb)),
                  ),
              ],
            ),
          ),
          HxSettingsItem(
            label: 'Variante',
            description:
                'Cómo se reparte el color en la interfaz (Material You).',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in SchemeVariant.values)
                  HxChip(
                    label: PhoneSettings.variantLabels[v]!,
                    on: s.variant == v,
                    onTap: () => s.setVariant(v),
                  ),
              ],
            ),
          ),
          HxSettingsItem(
            label: 'Tamaño del texto',
            description: 'Se suma al tamaño de letra del sistema.',
            child: HxSegmented<double>(
              value: s.textScale,
              onChanged: s.setTextScale,
              options: [
                for (final (v, l) in PhoneSettings.textScales) HxSegment(v, l),
              ],
            ),
          ),
          HxSettingsItem(
            label: 'Animaciones',
            description: switch (s.motion) {
              PhoneMotion.system =>
                'Sigue el ajuste "Quitar animaciones" de Android.',
              PhoneMotion.full =>
                'Todas las transiciones y formas en movimiento.',
              PhoneMotion.reduced =>
                'Cambios instantáneos, sin formas que giran.',
            },
            child: HxSegmented<PhoneMotion>(
              value: s.motion,
              onChanged: s.setMotion,
              options: [
                for (final m in PhoneMotion.values) HxSegment(m, m.label),
              ],
            ),
          ),
          HxSwitchRow(
            label: 'Vibración al tocar',
            description:
                'Un toque suave en botones, pestañas y el teclado del código.',
            value: s.haptics,
            onChanged: s.setHaptics,
          ),
        ],
      );
    },
  );
}
