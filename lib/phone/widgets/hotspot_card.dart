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
    this.helper,
    this.keyboardType,
  });
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final String? helper;
  final TextInputType? keyboardType;

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
      keyboardType: keyboardType,
      autocorrect: false,
      enableSuggestions: !obscure,
      style: HxType.bodyL(cs.onSurface),
      cursorColor: cs.primary,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
        helperStyle: HxType.bodyM(cs.onSurfaceVariant),
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
  final _ip = TextEditingController();
  int _tick = 0;
  int _reload = 0;
  bool _show = false;
  bool _seeded = false;
  Timer? _timer;

  PhoneController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _tick = c.receivedTick;
    _reload = c.reloadTick;
    c.addListener(_seed);
    c.addListener(_onReceived);
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
    _fill();
  }

  void _fill() {
    _ssid.text = c.hotspotSsid;
    _pass.text = c.hotspotPassword;
    _ip.text = c.carIp;
  }

  /// La tableta compartió su hotspot: recarga los campos y avisa.
  void _onReceived() {
    if (c.reloadTick != _reload) {
      _reload = c.reloadTick;
      if (_seeded && mounted) _fill();
    }
    if (c.receivedTick == _tick) return;
    _tick = c.receivedTick;
    if (!mounted) return;
    _fill();
    final cs = Theme.of(context).colorScheme;
    final name = c.receivedSsid ?? c.hotspotSsid;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: cs.inverseSurface,
          shape: RoundedRectangleBorder(borderRadius: HxRadius.m),
          content: Text(
            'La tableta compartió su hotspot «$name»: el celular se unirá solo',
            style: HxType.bodyM(cs.onInverseSurface),
          ),
        ),
      );
  }

  @override
  void dispose() {
    _timer?.cancel();
    c.removeListener(_seed);
    c.removeListener(_onReceived);
    _ip.dispose();
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
            if (c.receivedSsid != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: HxChip(
                    label: 'Recibido del carro',
                    icon: Symbols.check_circle_rounded,
                    on: true,
                  ),
                ),
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
              label: 'Dirección del carro',
              child: HxTextField(
                controller: _ip,
                label: 'IP del carro (opcional)',
                helper:
                    'Solo si no se conectan solos: la IP de la tableta, p. ej. 192.168.43.1.',
                keyboardType: TextInputType.number,
                onChanged: c.setCarIp,
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
