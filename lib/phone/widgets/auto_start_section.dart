import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/controllers/auto_start_controller.dart';
import 'package:pixel_car_player/phone/phone_controller.dart';
import 'package:pixel_car_player/phone/widgets/hotspot_card.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx.dart';

/// Ajustes → "Encendido automático": el transmisor se enciende al subir al carro
/// (Bluetooth / Wi-Fi del carro) y se apaga unos minutos después de bajarse.
class AutoStartSection extends StatefulWidget {
  const AutoStartSection({super.key, required this.c});
  final PhoneController c;

  @override
  State<AutoStartSection> createState() => _AutoStartSectionState();
}

class _AutoStartSectionState extends State<AutoStartSection> {
  final _wifi = TextEditingController();
  Timer? _timer;

  AutoStartController get a => widget.c.carAutoStart;

  @override
  void initState() {
    super.initState();
    if (!a.bondedLoaded) a.loadBonded();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh());
  }

  void _refresh() =>
      a.refreshStatus(transmitterRunning: widget.c.status.running);

  @override
  void dispose() {
    _timer?.cancel();
    _wifi.dispose();
    super.dispose();
  }

  Future<void> _addWifi() async {
    final added = await a.addWifi(_wifi.text);
    if (added) _wifi.clear();
  }

  Future<void> _associate() async {
    final r = await a.associate();
    if (mounted && r.message.isNotEmpty) {
      showHxSnack(context, r.message, error: !r.ok);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([a, widget.c]),
    builder: (context, _) {
      final cs = Theme.of(context).colorScheme;
      final mins = a.stopAfterMinutes;
      final suggestion = widget.c.hotspotSsid.trim();
      // Un solo hijo: los separadores van a mano para que el bloque plegable no deje
      // líneas dobles al ocultarse.
      return HxSettingsCard(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HxSwitchRow(
                label: 'Encender el transmisor solo al subir al carro',
                description:
                    'Ahorra batería: se enciende al conectarte al Bluetooth o al Wi-Fi del '
                    'carro y se apaga cuando te bajas.',
                value: a.enabled,
                onChanged: (v) => a.setEnabled(v, suggestSsid: suggestion),
              ),
              _Reveal(
                show: a.enabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HxSettingsItem(
                      label: 'Bluetooth del carro',
                      description: 'Elige el radio o la tableta del carro (puedes marcar varios).',
                      child: !a.bondedLoaded
                          ? const Center(child: HxLoadingIndicator(size: 36))
                          : a.bonded.isEmpty
                          ? Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'No hay equipos Bluetooth emparejados con este celular.',
                                    style: HxType.bodyM(cs.onSurfaceVariant),
                                  ),
                                ),
                                HxButton(
                                  label: 'Actualizar',
                                  kind: HxButtonKind.text,
                                  onPressed: a.loadBonded,
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < a.bonded.length; i++)
                                  HxEntrance(
                                    index: i,
                                    child: Padding(
                                      padding: EdgeInsets.only(
                                        top: i > 0 ? 4 : 0,
                                      ),
                                      child: HxCheckRow(
                                        icon: Symbols.bluetooth_rounded,
                                        title: a.bonded[i].name,
                                        subtitle: a.bonded[i].address,
                                        checked: a.btAddresses.contains(
                                          a.bonded[i].address,
                                        ),
                                        onChanged: (v) =>
                                            a.toggleBt(a.bonded[i].address, v),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                    const _Divider(),
                    HxSettingsItem(
                      label: 'Redes Wi-Fi del carro',
                      description:
                          'Nombre exacto de la red (SSID), p. ej. el hotspot de la tableta. '
                          'Ojo: Android solo deja ver la red con el permiso de ubicación y con la app '
                          'abierta, así que este aviso puede fallar en segundo plano. Lo confiable '
                          'es el Bluetooth del carro, mejor aún con «Vincular con el carro».',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (a.wifiSsids.isNotEmpty ||
                              (suggestion.isNotEmpty &&
                                  !a.wifiSsids.contains(suggestion)))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final s in a.wifiSsids)
                                    HxChip(
                                      key: ValueKey('wifi:$s'),
                                      icon: Symbols.close_rounded,
                                      label: s,
                                      on: true,
                                      tooltip: 'Quitar «$s»',
                                      onTap: () => a.removeWifi(s),
                                    ),
                                  if (suggestion.isNotEmpty &&
                                      !a.wifiSsids.contains(suggestion))
                                    HxChip(
                                      key: const ValueKey('wifi-suggest'),
                                      icon: Symbols.add_rounded,
                                      label: suggestion,
                                      tooltip: 'Agregar el hotspot guardado del carro',
                                      onTap: () => a.addWifi(suggestion),
                                    ),
                                ],
                              ),
                            ),
                          Row(
                            children: [
                              Expanded(
                                child: HxTextField(
                                  controller: _wifi,
                                  label: 'Agregar red',
                                ),
                              ),
                              const SizedBox(width: 8),
                              HxIconButton(
                                icon: Symbols.add_rounded,
                                tooltip: 'Agregar',
                                color: cs.primary,
                                size: 48,
                                onPressed: _addWifi,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const _Divider(),
                    HxSettingsItem(
                      label: mins == 0
                          ? 'Apagar apenas te bajes'
                          : 'Apagar $mins minuto${mins == 1 ? '' : 's'} después de bajarse',
                      description: 'Por si solo te bajaste un momento (cargar gasolina, una compra).',
                      child: HxSlider(
                        value: mins.toDouble(),
                        max: 30,
                        divisions: 30,
                        semanticLabel: 'Minutos antes de apagar',
                        onChanged: (v) => a.previewStop(v.round()),
                        onChangeEnd: (v) => a.setStopAfter(v.round()),
                      ),
                    ),
                    const _Divider(),
                    HxSettingsItem(
                      label: 'Vincular con el carro (recomendado)',
                      description:
                          'Asocia el Bluetooth del carro con Android. Así el sistema deja que el '
                          'transmisor arranque en segundo plano (Android 12 o más nuevo lo exige '
                          'para encenderlo sin abrir la app).',
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          HxButton(
                            label: a.associated.isEmpty
                                ? 'Vincular con el carro'
                                : 'Volver a vincular',
                            kind: HxButtonKind.tonal,
                            icon: Symbols.link_rounded,
                            onPressed: a.associating ? null : _associate,
                          ),
                          if (a.associated.isNotEmpty)
                            HxStatus(
                              label: 'Vinculado: ${a.nameFor(a.associated)}',
                              icon: Symbols.check_circle_rounded,
                              ok: true,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const _Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: _StatusPanel(s: a.status, enabled: a.enabled),
              ),
            ],
          ),
        ],
      );
    },
  );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: Theme.of(context).colorScheme.outlineVariant);
}

/// Muestra/oculta [child] con altura y opacidad animadas.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.show, required this.child});
  final bool show;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduce = hxReduceMotion(context);
    return AnimatedSize(
      duration: reduce ? Duration.zero : HxMotion.dSpring,
      curve: HxMotion.emphasizedDecel,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: reduce ? Duration.zero : HxMotion.dFxSlow,
        child: show
            ? Column(
                key: const ValueKey(true),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 1,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  child,
                ],
              )
            : const SizedBox(key: ValueKey(false), width: double.infinity),
      ),
    );
  }
}

/// Estado en vivo (se refresca cada 5 s).
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.s, required this.enabled});
  final AutoStartStatus s;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget row(IconData icon, String label, String value, bool on) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          AnimatedContainer(
            duration: HxMotion.dFxSlow,
            curve: HxMotion.standard,
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: on ? cs.primary : cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(on ? 12 : 18),
            ),
            child: Center(
              child: HxIcon(
                icon,
                size: 20,
                color: on ? cs.onPrimary : cs.onSurfaceVariant,
                filled: on,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: HxType.bodyM(cs.onSurfaceVariant)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: AnimatedSwitcher(
              duration: HxMotion.dFxSlow,
              child: Text(
                value,
                key: ValueKey(value),
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HxType.labelL(on ? cs.primary : cs.onSurface),
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: HxRadius.l,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              HxIcon(
                Symbols.monitor_heart_rounded,
                size: 18,
                color: cs.primary,
              ),
              const SizedBox(width: 8),
              Text('Estado ahora', style: HxType.titleM(cs.onSurface)),
            ],
          ),
          const SizedBox(height: 6),
          row(
            Symbols.bluetooth_connected_rounded,
            'Bluetooth del carro',
            !s.known
                ? '…'
                : (s.btCarConnected
                      ? 'Conectado${s.btDevice != null ? ' · ${s.btDevice}' : ''}'
                      : 'No conectado'),
            s.btCarConnected,
          ),
          row(
            Symbols.wifi_rounded,
            'Wi-Fi',
            !s.known ? '…' : (s.wifiSsid ?? 'Sin Wi-Fi'),
            s.wifiSsid != null && s.matches,
          ),
          row(
            Symbols.cast_rounded,
            'Transmisor',
            !s.known ? '…' : (s.transmitterRunning ? 'Encendido' : 'Apagado'),
            s.transmitterRunning,
          ),
          if (s.reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(s.reason, style: HxType.bodyS(cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
