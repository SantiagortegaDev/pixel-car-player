import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/car/settings/car_settings_page.dart';
import 'package:pixel_car_player/car/settings/hotspot_help.dart';
import 'package:pixel_car_player/car/settings/settings_controls.dart';
import 'package:pixel_car_player/car/system/car_hotspot.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/car/widgets/loading_indicator.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/data/bridge/native_bridge.dart';
import 'package:pixel_car_player/data/demo/demo_source.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Configuración → Hotspot e Inicio → App acompañante: lo que toca el sistema de la tableta.

void _hotspotOpts(CarController c, CarHotspotOpts Function(CarHotspotOpts h) f) =>
    c.custom.update((v) => v.copyWith(hotspot: f(v.hotspot)));

void _startupOpts(CarController c, CarStartupOpts Function(CarStartupOpts s) f) =>
    c.custom.update((v) => v.copyWith(startup: f(v.startup)));

// ---------------------------------------------------------------------------
// Hotspot

class HotspotSettings extends StatefulWidget {
  const HotspotSettings({super.key, required this.c});
  final CarController c;

  @override
  State<HotspotSettings> createState() => _HotspotSettingsState();
}

class _HotspotSettingsState extends State<HotspotSettings> {
  late final TextEditingController _ssid = TextEditingController(text: widget.c.cfg.hotspot.ssid);
  late final TextEditingController _pass = TextEditingController(text: widget.c.cfg.hotspot.password);
  late final AppLifecycleListener _life = AppLifecycleListener(onResume: _refresh);
  bool _showPass = false;
  bool _showFieldPass = false;

  CarController get c => widget.c;
  CarHotspot get h => c.hotspot;
  NativeBridge get _bridge => NativeBridge.instance;

  @override
  void initState() {
    super.initState();
    _life;
    _refresh();
  }

  @override
  void dispose() {
    _life.dispose();
    _ssid.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final info = await h.refresh();
    if (!mounted) return;
    _prefill(info);
  }

  /// Si el sistema deja leer la red y el usuario no escribió nada, se completa sola.
  void _prefill(HotspotInfo info) {
    final cur = c.cfg.hotspot;
    final ssid = cur.ssid.isEmpty ? info.ssid : null;
    final pass = cur.password.isEmpty ? info.password : null;
    if (ssid == null && pass == null) return;
    _hotspotOpts(c, (x) => x.copyWith(ssid: ssid, password: pass));
    if (ssid != null) _ssid.text = ssid;
    if (pass != null) _pass.text = pass;
  }

  Future<void> _set(bool on) async {
    final r = await h.setEnabled(on);
    if (!mounted) return;
    _prefill(h.info);
    final ok = r['ok'] == true && r['needsSettings'] != true;
    if (ok) {
      showHxSnack(context, on ? 'Hotspot encendido.' : 'Hotspot apagado.');
    } else if (!h.supported) {
      showHxSnack(context, 'Solo funciona en la tableta.');
    } else if (on) {
      final err = r['error'];
      await showHotspotHelpDialog(
        context,
        canWriteSettings: h.info.canWriteSettings,
        error: err is String ? err : null,
      );
    } else {
      showHxSnack(context, 'No se pudo apagar. Hazlo desde los ajustes del hotspot.');
    }
  }

  void _saveNetwork() {
    FocusScope.of(context).unfocus();
    _hotspotOpts(c, (x) => x.copyWith(ssid: _ssid.text.trim(), password: _pass.text));
    showHxSnack(context, 'Red guardada.');
  }

  static String _method(String m) => switch (m) {
    'tethering' => 'Anclaje a red (tethering)',
    'wifiAp' => 'Punto de acceso Wi-Fi',
    'localOnly' => 'Hotspot local (lo mantiene esta app)',
    'system' => 'Encendido desde el sistema',
    'none' => 'Ninguno (apagado)',
    _ => 'Sin determinar',
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: h,
      builder: (context, _) {
        final hs = c.cfg.hotspot;
        final info = h.info;
        final cs = context.cs;
        final ssid = info.ssid ?? (hs.ssid.isEmpty ? null : hs.ssid);
        final pass = info.password ?? (hs.password.isEmpty ? null : hs.password);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSection(
              icon: Symbols.wifi_tethering_rounded,
              title: 'Estado',
              children: [
                _StatusCard(info: info, busy: h.busy, loaded: info.loaded),
                if (info.loaded && info.enabled == null)
                  SettingsNote(
                    h.supported
                        ? 'Este radio no deja leer el estado del hotspot. Puedes encenderlo igual o abrir sus ajustes.'
                        : 'El estado del hotspot solo se puede leer en la tableta.',
                    icon: Symbols.info_rounded,
                  ),
                _KeyValue(label: 'Nombre de la red', value: ssid ?? '—'),
                _KeyValue(
                  label: 'Contraseña',
                  value: pass == null ? '—' : (_showPass ? pass : '•' * pass.length.clamp(6, 16)),
                  trailing: pass == null
                      ? null
                      : HxIconButton(
                          icon: _showPass ? Symbols.visibility_off_rounded : Symbols.visibility_rounded,
                          tooltip: _showPass ? 'Ocultar contraseña' : 'Mostrar contraseña',
                          onTap: () => setState(() => _showPass = !_showPass),
                        ),
                ),
                _KeyValue(label: 'Método', value: _method(info.method)),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      HxButton(
                        label: 'Encender ahora',
                        icon: Symbols.wifi_tethering_rounded,
                        height: 48,
                        onTap: h.busy ? null : () => _set(true),
                      ),
                      HxButton(
                        label: 'Apagar',
                        icon: Symbols.wifi_tethering_off_rounded,
                        kind: HxButtonKind.outlined,
                        height: 48,
                        onTap: h.busy ? null : () => _set(false),
                      ),
                      HxButton(
                        label: 'Actualizar',
                        icon: Symbols.refresh_rounded,
                        kind: HxButtonKind.text,
                        height: 48,
                        onTap: h.busy ? null : _refresh,
                      ),
                    ],
                  ),
                ),
                SettingsActionRow(
                  icon: Symbols.settings_rounded,
                  label: 'Ajustes del hotspot',
                  desc: 'Si el radio no deja encenderlo desde aquí, actívalo en los ajustes de Android.',
                  action: HxButton(
                    label: 'Abrir',
                    icon: Symbols.open_in_new_rounded,
                    kind: HxButtonKind.tonal,
                    height: 48,
                    onTap: _bridge.openHotspotSettings,
                  ),
                ),
                SettingsActionRow(
                  icon: info.canWriteSettings ? Symbols.check_rounded : Symbols.admin_panel_settings_rounded,
                  warning: info.loaded && h.supported && !info.canWriteSettings,
                  label: 'Permiso «Modificar ajustes del sistema»',
                  desc: info.canWriteSettings
                      ? 'Concedido. Algunos radios lo necesitan para encender el hotspot solos.'
                      : 'Algunos radios lo necesitan para encender el hotspot solos.',
                  action: info.canWriteSettings
                      ? const SettingsStatus(ok: true, text: 'Listo')
                      : HxButton(
                          label: 'Dar permiso',
                          height: 48,
                          onTap: () async {
                            await _bridge.openWriteSettings();
                            await _refresh();
                          },
                        ),
                ),
              ],
            ),
            SettingsSection(
              icon: Symbols.autorenew_rounded,
              title: 'Automático',
              children: [
                SettingsSwitch(
                  label: 'Verificar y encender el hotspot al iniciar',
                  description:
                      'Al abrir Pixel Car Player revisa el hotspot y, si está apagado, lo enciende. '
                      'Si el radio no lo permite, te muestra el atajo a sus ajustes.',
                  value: hs.autoEnable,
                  onChanged: (v) => _hotspotOpts(c, (x) => x.copyWith(autoEnable: v)),
                ),
                if (hs.autoEnable)
                  SettingsSlider(
                    label: 'Volver a verificar cada',
                    desc: 'Por si el radio lo apaga solo. 0 = solo al iniciar.',
                    value: hs.recheckMinutes.toDouble(),
                    range: CarHotspotOpts.recheckRange,
                    defaultValue: 0,
                    format: (v) => v == 0 ? 'Solo al iniciar' : '${v.round()} min',
                    onChanged: (v) => _hotspotOpts(c, (x) => x.copyWith(recheckMinutes: v.round())),
                  ),
              ],
            ),
            SettingsSection(
              icon: Symbols.qr_code_2_rounded,
              title: 'Red del carro',
              children: [
                const SettingsNote(
                  'Escribe el nombre y la contraseña del hotspot (se completan solos si el radio deja leerlos). '
                  'Con el QR, el celular se une apuntando la cámara.',
                ),
                SettingsItem(
                  label: 'Nombre de la red (SSID)',
                  child: SettingsField(fieldKey: const ValueKey('hotspot-ssid'), controller: _ssid, hint: 'Mi carro'),
                ),
                SettingsItem(
                  label: 'Contraseña',
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SettingsField(
                          fieldKey: const ValueKey('hotspot-pass'),
                          controller: _pass,
                          hint: 'Mínimo 8 caracteres',
                          obscure: !_showFieldPass,
                          onSubmitted: _saveNetwork,
                          suffix: IconButton(
                            tooltip: _showFieldPass ? 'Ocultar' : 'Mostrar',
                            onPressed: () => setState(() => _showFieldPass = !_showFieldPass),
                            icon: HxIcon(
                              _showFieldPass ? Symbols.visibility_off_rounded : Symbols.visibility_rounded,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: HxButton(label: 'Guardar', kind: HxButtonKind.tonal, height: 48, onTap: _saveNetwork),
                      ),
                    ],
                  ),
                ),
                if (hs.ssid.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: WifiQrCard(ssid: hs.ssid, password: hs.password),
                  ),
              ],
            ),
            const SettingsSection(
              icon: Symbols.travel_explore_rounded,
              title: 'Cómo se encuentran',
              children: [
                SettingsNote(
                  'Con el hotspot de la tableta encendido, el celular es un cliente de esta red: Pixel Car Player '
                  'lo busca entre los equipos conectados (y por el aviso Wi-Fi del celular). No hace falta escribir IPs.',
                  icon: Symbols.info_rounded,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Tarjeta grande con el estado (encendido / apagado / desconocido).
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.info, required this.busy, required this.loaded});
  final HotspotInfo info;
  final bool busy;
  final bool loaded;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    final (IconData icon, String title, Color bg, Color fg) = switch (info.enabled) {
      true => (Symbols.wifi_tethering_rounded, 'Encendido', cs.primaryContainer, cs.onPrimaryContainer),
      false => (Symbols.wifi_tethering_off_rounded, 'Apagado', cs.surfaceContainerHighest, cs.onSurfaceVariant),
      null => (Symbols.wifi_tethering_error_rounded, 'Desconocido', cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          AnimatedContainer(
            duration: HxMotion.dFxSlow,
            curve: HxMotion.standard,
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: bg, borderRadius: info.enabled == true ? HxRadius.l : HxRadius.xl),
            alignment: Alignment.center,
            child: busy || !loaded
                ? const HxLoadingIndicator(size: 40, label: 'Consultando el hotspot')
                : HxIcon(icon, size: 30, color: fg, fill: info.enabled == true),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hotspot del carro', style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
                Text(
                  loaded ? title : 'Consultando…',
                  style: hxWeight(tt.headlineSmall, 500).copyWith(color: cs.onSurface),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value, this.trailing});
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(value, style: context.tt.bodyLarge?.copyWith(color: cs.onSurface)),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// QR `WIFI:` con los colores del esquema: módulos redondos del tono primario oscuro sobre
/// un recuadro claro (los lectores necesitan contraste oscuro sobre claro).
class WifiQrCard extends StatelessWidget {
  const WifiQrCard({super.key, required this.ssid, required this.password, this.size = 196});
  final String ssid;
  final String password;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    final dark = cs.brightness == Brightness.dark;
    final tile = dark ? cs.onPrimaryContainer : cs.primaryContainer;
    final ink = dark ? cs.onPrimary : cs.onPrimaryContainer;
    final qr = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: tile, borderRadius: HxRadius.l),
      child: QrImageView(
        data: wifiQrData(ssid, password),
        size: size,
        padding: EdgeInsets.zero,
        backgroundColor: tile,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        semanticsLabel: 'Código QR de la red $ssid',
        eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.square, color: ink),
        dataModuleStyle: QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: ink),
      ),
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        HxIcon(Symbols.photo_camera_rounded, color: cs.primary),
        const SizedBox(height: 10),
        Text('Únete desde el celular', style: hxWeight(tt.titleLarge, 500).copyWith(color: cs.onSurface)),
        const SizedBox(height: 4),
        Text(
          'Abre la cámara del celular y apunta al código para conectarte a «$ssid».',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        if (password.isEmpty) ...[
          const SizedBox(height: 8),
          Text('Red sin contraseña.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth < size + 28 + 220
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [qr, const SizedBox(height: 16), text])
          : Row(
              children: [
                qr,
                const SizedBox(width: 24),
                Expanded(child: text),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// App acompañante

/// App lanzable (`getLaunchableApps`).
class LaunchableApp {
  const LaunchableApp({required this.package, required this.label, this.icon});
  final String package;
  final String label;
  final Uint8List? icon;

  static LaunchableApp? fromMap(Map<String, dynamic> m) {
    final pkg = m['package'];
    if (pkg is! String || pkg.isEmpty) return null;
    final label = m['label'];
    final icon = m['icon'];
    return LaunchableApp(
      package: pkg,
      label: label is String && label.isNotEmpty ? label : pkg,
      icon: icon is Uint8List ? icon : (icon is List<int> ? Uint8List.fromList(icon) : null),
    );
  }

  /// ¿Coincide con la búsqueda [q] (nombre o paquete, sin mayúsculas)?
  bool matches(String q) {
    final t = q.trim().toLowerCase();
    return t.isEmpty || label.toLowerCase().contains(t) || package.toLowerCase().contains(t);
  }
}

class CompanionSettings extends StatefulWidget {
  const CompanionSettings({super.key, required this.c});
  final CarController c;

  static const _self = 'com.santiagortega.pixelcarplayer';

  @override
  State<CompanionSettings> createState() => _CompanionSettingsState();
}

class _CompanionSettingsState extends State<CompanionSettings> {
  final _search = TextEditingController();
  List<LaunchableApp>? _apps;
  bool _picking = false;

  CarController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _picking = c.cfg.startup.companionPackage.isEmpty;
    _search.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    var raw = await NativeBridge.instance.getLaunchableApps();
    // En la demo web no hay sistema: apps de ejemplo para ver el selector.
    if (raw.isEmpty && kIsWeb) raw = demoLaunchableApps;
    final apps = [for (final m in raw) ?LaunchableApp.fromMap(m)]
        .where((a) => a.package != CompanionSettings._self)
        .toList();
    if (mounted) setState(() => _apps = apps);
  }

  void _pick(LaunchableApp a) {
    _startupOpts(c, (s) => s.copyWith(companionPackage: a.package, companionLabel: a.label, companionEnabled: true));
    setState(() => _picking = false);
    _search.clear();
  }

  Future<void> _test() async {
    final ok = await c.launchCompanionNow();
    if (!mounted) return;
    if (!ok) {
      showHxSnack(
        context,
        NativeBridge.instance.isSupported ? 'No se pudo abrir la app.' : 'Solo funciona en la tableta.',
      );
    }
  }

  LaunchableApp? _selected() {
    final s = c.cfg.startup;
    if (s.companionPackage.isEmpty) return null;
    for (final a in _apps ?? const <LaunchableApp>[]) {
      if (a.package == s.companionPackage) return a;
    }
    return LaunchableApp(
      package: s.companionPackage,
      label: s.companionLabel.isEmpty ? s.companionPackage : s.companionLabel,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = c.cfg.startup;
    final sel = _selected();
    return SettingsSection(
      icon: Symbols.apps_rounded,
      title: 'App acompañante',
      children: [
        const SettingsNote(
          'Por ejemplo, la app de música Bluetooth del radio: se abre sola al iniciar y queda corriendo detrás '
          'de Pixel Car Player.',
          icon: Symbols.info_rounded,
        ),
        if (sel != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: _AppRow(
              app: sel,
              selected: true,
              trailing: HxButton(
                label: _picking ? 'Listo' : 'Cambiar',
                kind: HxButtonKind.tonal,
                height: 48,
                onTap: () => setState(() => _picking = !_picking),
              ),
              onTap: () => setState(() => _picking = !_picking),
            ),
          ),
        if (_picking || sel == null) SettingsItem(label: 'Elegir app', child: _picker(context, sel)),
        SettingsSwitch(
          label: 'Abrir la app acompañante al iniciar Pixel Car Player (en segundo plano)',
          description: sel == null
              ? 'Primero elige una app.'
              : 'Se abre ${sel.label} y, al rato, Pixel Car Player vuelve al frente. También al encender el carro.',
          value: s.companionEnabled && sel != null,
          onChanged: (v) {
            if (sel == null) {
              setState(() => _picking = true);
              showHxSnack(context, 'Elige primero la app acompañante.');
              return;
            }
            _startupOpts(c, (x) => x.copyWith(companionEnabled: v));
          },
        ),
        SettingsSlider(
          label: 'Volver a Pixel Car Player después de',
          desc: 'Tiempo que la otra app queda al frente para arrancar bien. Súbelo si no alcanza a abrir.',
          value: s.companionDelayMs.toDouble(),
          range: CarStartupOpts.companionDelayRange,
          defaultValue: 1500,
          format: (v) => '${fmtNum(v / 1000, v % 1000 == 0 ? 0 : (v % 500 == 0 ? 1 : 2))} s',
          onChanged: (v) => _startupOpts(c, (x) => x.copyWith(companionDelayMs: v.round())),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              HxButton(
                label: 'Probar ahora',
                icon: Symbols.play_arrow_rounded,
                kind: HxButtonKind.tonal,
                height: 48,
                onTap: sel == null ? null : _test,
              ),
              if (sel != null)
                HxButton(
                  label: 'Quitar',
                  icon: Symbols.close_rounded,
                  kind: HxButtonKind.text,
                  height: 48,
                  onTap: () {
                    _startupOpts(
                      c,
                      (x) => x.copyWith(companionPackage: '', companionLabel: '', companionEnabled: false),
                    );
                    setState(() => _picking = true);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _picker(BuildContext context, LaunchableApp? sel) {
    final cs = context.cs;
    final apps = _apps;
    if (apps == null) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Center(child: HxLoadingIndicator(size: 48, label: 'Buscando apps')),
      );
    }
    if (apps.isEmpty) {
      return Text(
        'No se encontraron apps (el selector funciona en la tableta).',
        style: context.tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      );
    }
    final shown = apps.where((a) => a.matches(_search.text)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsField(
          fieldKey: const ValueKey('companion-search'),
          controller: _search,
          hint: 'Buscar app',
          prefix: Padding(
            padding: const EdgeInsets.only(left: 12, right: 4),
            child: HxIcon(Symbols.search_rounded, color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 336),
          child: shown.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Ninguna app coincide con «${_search.text.trim()}».',
                    style: context.tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: shown.length,
                  itemBuilder: (_, i) => _AppRow(
                    key: ValueKey('app-${shown[i].package}'),
                    app: shown[i],
                    selected: shown[i].package == sel?.package,
                    onTap: () => _pick(shown[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Fila de app (como las filas de lista de Harmonix): ícono, nombre y paquete; la
/// elegida sobre secondaryContainer.
class _AppRow extends StatelessWidget {
  const _AppRow({super.key, required this.app, required this.selected, required this.onTap, this.trailing});
  final LaunchableApp app;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    final fg = selected ? cs.onSecondaryContainer : cs.onSurface;
    final icon = app.icon;
    return AnimatedContainer(
      duration: HxMotion.dFxSlow,
      decoration: BoxDecoration(
        color: selected ? cs.secondaryContainer : cs.secondaryContainer.withValues(alpha: 0),
        borderRadius: HxRadius.l,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: HxRadius.l,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: HxRadius.m,
                  child: SizedBox.square(
                    dimension: 44,
                    child: icon != null
                        ? Image.memory(icon, fit: BoxFit.cover, gaplessPlayback: true)
                        : ColoredBox(
                            color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
                            child: Center(
                              child: HxIcon(
                                Symbols.android_rounded,
                                color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        app.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: hxWeight(tt.bodyLarge, 500).copyWith(color: fg),
                      ),
                      Text(
                        app.package,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(color: fg.withValues(alpha: 0.75)),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  trailing!,
                ] else if (selected)
                  HxIcon(Symbols.check_circle_rounded, fill: true, color: cs.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
