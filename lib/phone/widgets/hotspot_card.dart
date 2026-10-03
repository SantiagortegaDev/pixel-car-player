import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/phone_controller.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx.dart';

/// Campo de texto con el aspecto de Harmonix (`.field`): relleno surfaceContainerHigh,
/// radio grande y foco en primary.
class HxTextField extends StatelessWidget {
  const HxTextField({
    super.key,
    required this.controller,
    required this.label,
    this.obscure = false,
    this.suffix,
    this.onChanged,
  });
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
      borderRadius: HxRadius.l,
      borderSide: BorderSide(color: c, width: w),
    );
    return TextField(
      controller: controller,
      obscureText: obscure,
      onChanged: onChanged,
      autocorrect: false,
      enableSuggestions: !obscure,
      style: HxType.bodyL(cs.onSurface),
      cursorColor: cs.primary,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: HxType.bodyM(cs.onSurfaceVariant),
        floatingLabelStyle: HxType.bodyM(cs.primary),
        filled: true,
        fillColor: cs.surfaceContainerHigh,
        suffixIcon: suffix,
        enabledBorder: border(Colors.transparent, 1),
        focusedBorder: border(cs.primary, 2),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}

/// Tarjeta "Hotspot del carro": conexión automática del celular + estado del Wi-Fi.
class HotspotCard extends StatefulWidget {
  const HotspotCard({super.key, required this.c});
  final PhoneController c;

  @override
  State<HotspotCard> createState() => _HotspotCardState();
}

class _HotspotCardState extends State<HotspotCard> {
  final _ssid = TextEditingController();
  final _pass = TextEditingController();
  bool _show = false;
  bool _seeded = false;
  Timer? _timer;

  PhoneController get c => widget.c;

  @override
  void initState() {
    super.initState();
    c.addListener(_seed);
    _seed();
    c.refreshWifi();
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => c.refreshWifi(),
    );
  }

  /// Los datos guardados llegan async: se vuelcan a los campos una sola vez.
  void _seed() {
    if (_seeded || !c.hotspotLoaded) return;
    _seeded = true;
    _ssid.text = c.hotspotSsid;
    _pass.text = c.hotspotPassword;
  }

  @override
  void dispose() {
    _timer?.cancel();
    c.removeListener(_seed);
    _ssid.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _apply(bool enabled) async {
    final messenger = ScaffoldMessenger.of(context);
    final cs = Theme.of(context).colorScheme;
    final r = await c.saveHotspot(
      ssid: _ssid.text,
      password: _pass.text,
      enabled: enabled,
    );
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: r.ok ? cs.inverseSurface : cs.errorContainer,
          shape: RoundedRectangleBorder(borderRadius: HxRadius.m),
          content: Text(
            r.message,
            style: HxType.bodyM(
              r.ok ? cs.onInverseSurface : cs.onErrorContainer,
            ),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final wifi = c.wifiConnected
            ? (c.wifiSsid != null
                  ? 'Conectado a «${c.wifiSsid}»'
                  : 'Conectado a Wi-Fi')
            : 'Sin Wi-Fi';
        return HxSettingsCard(
          children: [
            HxSwitchRow(
              label: 'Conectarme automáticamente',
              description: 'El celular se une solo al hotspot de la tableta cuando está cerca.',
              value: c.hotspotAuto,
              onChanged: c.hotspotBusy ? (_) {} : _apply,
            ),
            HxSettingsItem(
              label: 'Red del carro',
              description:
                  'En Android 10 o superior el sistema muestra una vez «¿Permitir '
                  'redes sugeridas?»: hay que aceptarla.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HxTextField(
                    controller: _ssid,
                    label: 'Nombre de la red (SSID)',
                  ),
                  const SizedBox(height: 12),
                  HxTextField(
                    controller: _pass,
                    label: 'Contraseña',
                    obscure: !_show,
                    suffix: HxIconButton(
                      icon: _show
                          ? Symbols.visibility_off_rounded
                          : Symbols.visibility_rounded,
                      tooltip: _show
                          ? 'Ocultar contraseña'
                          : 'Mostrar contraseña',
                      iconSize: 22,
                      onPressed: () => setState(() => _show = !_show),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: HxButton(
                      label: c.hotspotBusy ? 'Guardando…' : 'Guardar',
                      icon: Symbols.save_rounded,
                      onPressed: c.hotspotBusy ? null : () => _apply(true),
                    ),
                  ),
                ],
              ),
            ),
            HxSettingsItem(
              label: 'Wi-Fi del celular',
              trailing: HxStatus(
                label: wifi,
                icon: c.wifiConnected
                    ? Symbols.wifi_rounded
                    : Symbols.wifi_off_rounded,
                ok: c.wifiConnected,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HxIcon(
                    Symbols.qr_code_2_rounded,
                    size: 22,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'En la tableta, en Configuración → Hotspot, puedes ver el '
                      'nombre, la contraseña y un código QR; también puedes '
                      'escanear el QR con la cámara del celular.',
                      style: HxType.bodyM(cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
