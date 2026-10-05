import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/controllers/pairing_controller.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx.dart';

const _months = [
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// Ajustes → Seguridad: "Requerir emparejamiento" y la lista de carros emparejados.
class PairingSection extends StatelessWidget {
  const PairingSection({super.key, required this.c});
  final PairingController c;

  Future<void> _forget(BuildContext context, PairedCar car) async {
    final yes = await confirmHx(
      context,
      title: 'Olvidar «${car.name}»',
      text:
          'La próxima vez que se conecte, la pantalla del carro te pedirá un código '
          'nuevo.',
      confirm: 'Olvidar',
    );
    if (!yes) return;
    await c.forget(car.id);
    if (context.mounted) showHxSnack(context, 'Se olvidó «${car.name}».');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final cs = Theme.of(context).colorScheme;
      return HxSettingsCard(
        children: [
          HxSwitchRow(
            label: 'Requerir emparejamiento',
            description:
                'Solo las pantallas que escribieron el código pueden ver lo que suena '
                'y controlar la música.',
            value: c.requirePairing,
            onChanged: c.setRequirePairing,
          ),
          HxSettingsItem(
            label: 'Carros emparejados',
            description: c.paired.isEmpty
                ? 'Todavía ninguno. Al conectar, la tableta mostrará un código.'
                : 'Olvida uno para volver a pedir el código.',
            child: AnimatedSize(
              duration: HxMotion.dSpringFast,
              curve: HxMotion.standard,
              alignment: Alignment.topCenter,
              child: c.paired.isEmpty
                  ? const SizedBox(width: double.infinity)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < c.paired.length; i++)
                          HxEntrance(
                            key: ValueKey(c.paired[i].id),
                            index: i,
                            child: Padding(
                              padding: EdgeInsets.only(top: i > 0 ? 4 : 0),
                              child: Row(
                                children: [
                                  HxShapeTile(
                                    shape: M3Shape.cookie9,
                                    size: 44,
                                    color: cs.primaryContainer,
                                    icon: Symbols.directions_car_rounded,
                                    iconColor: cs.onPrimaryContainer,
                                    iconSize: 22,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          c.paired[i].name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: hxText(
                                            16,
                                            weight: FontWeight.w500,
                                            color: cs.onSurface,
                                          ),
                                        ),
                                        if (c.paired[i].pairedAt != null)
                                          Text(
                                            'Desde el ${_date(c.paired[i].pairedAt!)}',
                                            style: HxType.bodyM(
                                              cs.onSurfaceVariant,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  HxButton(
                                    label: 'Olvidar',
                                    kind: HxButtonKind.text,
                                    onPressed: () =>
                                        _forget(context, c.paired[i]),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      );
    },
  );
}
