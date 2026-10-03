import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/car/settings/car_settings_page.dart';
import 'package:pixel_car_player/car/settings/settings_controls.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/car/widgets/loading_indicator.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/data/bridge/native_bridge.dart';
import 'package:pixel_car_player/data/link/car_link_client.dart';

/// Contenido de cada categoría de Configuración.
List<Widget> buildCategory(CarSettingsCategory cat, CarController c, VoidCallback onChangeMode) => switch (cat) {
  CarSettingsCategory.conexion => [_ConnectionPage(c: c)],
  CarSettingsCategory.inicio => [_StartupPage(c: c)],
  CarSettingsCategory.diseno => [_DesignPage(c: c)],
  CarSettingsCategory.portada => [_CoverPage(c: c)],
  CarSettingsCategory.visibles => [_VisibilityPage(c: c)],
  CarSettingsCategory.textos => [_TextsPage(c: c)],
  CarSettingsCategory.letra => [_LyricsPage(c: c)],
  CarSettingsCategory.avanzado => [_AdvancedPage(c: c, onChangeMode: onChangeMode)],
};

extension on CarController {
  void edit(CarCustomization Function(CarCustomization v) f) => custom.update(f);
  void design(CarDesign Function(CarDesign d) f) => edit((v) => v.copyWith(design: f(v.design)));
  void coverOpts(CarCoverOpts Function(CarCoverOpts d) f) => edit((v) => v.copyWith(cover: f(v.cover)));
  void viz(CarVisualizerOpts Function(CarVisualizerOpts d) f) => edit((v) => v.copyWith(visualizer: f(v.visualizer)));
  void lyricsOpts(CarLyricsOpts Function(CarLyricsOpts d) f) => edit((v) => v.copyWith(lyrics: f(v.lyrics)));
  void conn(CarConnectionOpts Function(CarConnectionOpts d) f) => edit((v) => v.copyWith(connection: f(v.connection)));
  void startup(CarStartupOpts Function(CarStartupOpts d) f) => edit((v) => v.copyWith(startup: f(v.startup)));
  void gestures(CarGestureOpts Function(CarGestureOpts d) f) => edit((v) => v.copyWith(gestures: f(v.gestures)));
}

String _x(double v) => '${fmtNum(v)}×';
String _px(double v) => '${v.round()} px';
String _s(double v) => '${v.round()} s';

// ---------------------------------------------------------------------------
// Conexión

class _ConnectionPage extends StatefulWidget {
  const _ConnectionPage({required this.c});
  final CarController c;

  @override
  State<_ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<_ConnectionPage> {
  late final TextEditingController _ip = TextEditingController(text: widget.c.prefs.manualIp ?? '');
  List<Map<String, dynamic>> _bonded = const [];
  bool _loadingBonded = true;

  CarController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _loadBonded();
  }

  Future<void> _loadBonded() async {
    await NativeBridge.instance.requestRuntimePermissions();
    final list = await NativeBridge.instance.getBondedDevices();
    if (!mounted) return;
    setState(() {
      _bonded = list;
      _loadingBonded = false;
    });
  }

  @override
  void dispose() {
    _ip.dispose();
    super.dispose();
  }

  Future<void> _saveIp() async {
    FocusScope.of(context).unfocus();
    await c.setConnection(manualIp: _ip.text.trim(), btAddress: c.prefs.btAddress, btName: c.prefs.btName);
    if (mounted) showHxSnack(context, 'IP guardada. Reconectando…');
  }

  Future<void> _pickBt(String? address, String? name) async {
    await c.setConnection(manualIp: c.prefs.manualIp, btAddress: address, btName: name);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c.link.status,
      builder: (context, _) {
        final conn = c.cfg.connection;
        final st = c.displayStatus;
        final t = conn.transport;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSection(
              icon: Symbols.link_rounded,
              title: 'Conexión con el celular',
              children: [
                _StatusRow(status: st, demo: c.demo, idleDemo: c.idleDemo),
                if (!c.demo)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        HxButton(
                          label: c.linkRunning ? 'Reconectar ahora' : 'Conectar ahora',
                          icon: Symbols.sync_rounded,
                          kind: HxButtonKind.tonal,
                          height: 48,
                          onTap: c.connectNow,
                        ),
                        if (c.linkRunning)
                          HxButton(
                            label: 'Desconectar',
                            icon: Symbols.link_off_rounded,
                            kind: HxButtonKind.outlined,
                            height: 48,
                            onTap: c.disconnect,
                          ),
                      ],
                    ),
                  ),
                SettingsSwitch(
                  label: 'Conexión automática',
                  description: 'Busca y se conecta al celular apenas se abre la app.',
                  value: conn.autoConnect,
                  onChanged: (v) => c.conn((d) => d.copyWith(autoConnect: v)),
                ),
                SettingsItem(
                  label: 'Cómo se conecta',
                  desc: switch (t) {
                    CarTransport.auto =>
                      'Prueba Wi-Fi y, si elegiste un celular emparejado, también Bluetooth. Gana el primero.',
                    CarTransport.wifi =>
                      'Hotspot del celular o la misma red Wi-Fi. Se busca solo; la IP manual es opcional.',
                    CarTransport.bt => 'Bluetooth: elige el celular emparejado. Sirve aunque no haya Wi-Fi.',
                  },
                  child: SettingsSegmented<CarTransport>(
                    value: t,
                    options: const [
                      (CarTransport.auto, 'Automático'),
                      (CarTransport.wifi, 'Wi-Fi'),
                      (CarTransport.bt, 'Bluetooth'),
                    ],
                    onChanged: (v) => c.conn((d) => d.copyWith(transport: v)),
                  ),
                ),
                if (t != CarTransport.bt)
                  SettingsItem(
                    label: 'IP manual del celular',
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SettingsField(
                            controller: _ip,
                            hint: '192.168.43.1',
                            helper: 'Opcional: solo si no se encuentra solo.',
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onSubmitted: _saveIp,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: HxButton(label: 'Guardar', kind: HxButtonKind.tonal, height: 48, onTap: _saveIp),
                        ),
                      ],
                    ),
                  ),
                if (t != CarTransport.wifi) SettingsItem(label: 'Celular emparejado', child: _bondedList(context)),
                SettingsSlider(
                  label: 'Reintentar cada',
                  desc: 'Espera máxima entre intentos cuando no encuentra al celular.',
                  value: conn.reconnectSeconds.toDouble(),
                  range: CarConnectionOpts.reconnectRange,
                  defaultValue: 10,
                  format: _s,
                  onChanged: (v) => c.conn((d) => d.copyWith(reconnectSeconds: v.round())),
                ),
                _Stats(ips: c.tabletIps),
              ],
            ),
            SettingsSection(
              icon: Symbols.smartphone_rounded,
              title: 'Sin celular',
              children: [
                SettingsSwitch(
                  label: 'Mostrar demo sin celular',
                  description: 'Mientras no haya un celular conectado se ven canciones de ejemplo en vez de la pantalla de espera.',
                  value: conn.demoWhenIdle,
                  onChanged: (v) => c.conn((d) => d.copyWith(demoWhenIdle: v)),
                ),
                SettingsSwitch(
                  label: 'Modo demo',
                  description: 'Siempre canciones de ejemplo (no se conecta al celular).',
                  value: c.demo,
                  onChanged: c.setDemo,
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _bondedList(BuildContext context) {
    final cs = context.cs;
    if (_loadingBonded) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Center(child: HxLoadingIndicator(size: 48, label: 'Buscando celulares emparejados')),
      );
    }
    if (_bonded.isEmpty) {
      return Text(
        'No hay celulares emparejados por Bluetooth (o este radio no expone el Bluetooth estándar). Usa Wi-Fi.',
        style: context.tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
      );
    }
    return Column(
      children: [
        for (final d in _bonded)
          _DeviceRow(
            title: (d['name'] as String?)?.isNotEmpty == true ? d['name'] as String : 'Dispositivo',
            subtitle: 'Bluetooth · ${d['address']}',
            selected: c.prefs.btAddress == d['address'],
            onTap: () => c.prefs.btAddress == d['address']
                ? _pickBt(null, null)
                : _pickBt(d['address'] as String?, d['name'] as String?),
          ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.status, required this.demo, required this.idleDemo});
  final LinkStatus status;
  final bool demo;
  final bool idleDemo;

  @override
  Widget build(BuildContext context) {
    final text = demo
        ? 'Modo demo activo — datos simulados'
        : switch (status.phase) {
            LinkPhase.connected =>
              'Conectado a ${status.device} por ${status.transport == 'bt' ? 'Bluetooth' : 'Wi-Fi'} (${status.address})',
            LinkPhase.searching => idleDemo ? 'Buscando al celular… (mostrando la demo)' : 'Buscando al celular…',
            LinkPhase.disconnected => 'Sin conexión',
          };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: SettingsStatus(ok: status.isConnected || demo, text: text),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.ips});
  final List<String> ips;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('IP de esta tableta', style: context.tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(
            ips.isEmpty ? 'sin red' : ips.join('  ·  '),
            style: AppTheme.numStyle(context, size: 16).copyWith(color: cs.onSurface, fontWeight: FontWeight.w400),
          ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.title, required this.subtitle, required this.selected, required this.onTap});
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    final fg = selected ? cs.onSecondaryContainer : cs.onSurface;
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                HxIcon(Symbols.smartphone_rounded, color: fg, fill: selected),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: hxWeight(tt.bodyLarge, 500).copyWith(color: fg)),
                      Text(subtitle, style: tt.bodyMedium?.copyWith(color: fg.withValues(alpha: 0.8))),
                    ],
                  ),
                ),
                HxIcon(
                  selected ? Symbols.check_circle_rounded : Symbols.radio_button_unchecked_rounded,
                  fill: selected,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inicio

class _StartupPage extends StatefulWidget {
  const _StartupPage({required this.c});
  final CarController c;

  @override
  State<_StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<_StartupPage> {
  bool? _overlay;
  late final AppLifecycleListener _life = AppLifecycleListener(onResume: _check);

  CarController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _life;
    _check();
  }

  Future<void> _check() async {
    // `?overlay=0` en web simula el permiso faltante (capturas).
    final ok = kIsWeb && Uri.base.queryParameters['overlay'] == '0'
        ? false
        : await NativeBridge.instance.canDrawOverlays();
    if (mounted) setState(() => _overlay = ok);
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = c.cfg.startup;
    final overlayOk = _overlay ?? true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          icon: Symbols.power_settings_new_rounded,
          title: 'Inicio automático',
          children: [
            SettingsSwitch(
              label: 'Abrir al encender el carro',
              description: 'Pixel Car Player se abre solo cuando la tableta arranca o el carro se enciende (ACC).',
              value: s.autostart,
              onChanged: (v) {
                c.startup((d) => d.copyWith(autostart: v));
                if (v) _check();
              },
            ),
            if (s.autostart) ...[
              SettingsSlider(
                label: 'Esperar antes de abrir',
                desc: 'Da tiempo a que el radio termine de arrancar.',
                value: s.autostartDelay.toDouble(),
                range: CarStartupOpts.delayRange,
                defaultValue: 3,
                format: _s,
                onChanged: (v) => c.startup((d) => d.copyWith(autostartDelay: v.round())),
              ),
              SettingsActionRow(
                icon: overlayOk ? Symbols.check_rounded : Symbols.layers_rounded,
                warning: !overlayOk,
                label: 'Permiso «Mostrar sobre otras apps»',
                desc: overlayOk
                    ? 'Concedido. Android 10 o más nuevo lo necesita para que la app se abra sola.'
                    : 'Falta: Android 10 o más nuevo lo necesita para abrir la app sola al encender.',
                action: overlayOk
                    ? const SettingsStatus(ok: true, text: 'Listo')
                    : HxButton(
                        label: 'Dar permiso',
                        height: 48,
                        onTap: () async {
                          await NativeBridge.instance.openOverlaySettings();
                          await _check();
                        },
                      ),
              ),
              SettingsActionRow(
                icon: Symbols.battery_saver_rounded,
                label: 'Optimización de batería',
                desc: 'Algunas tabletas bloquean el inicio automático de las apps optimizadas. Elige «Sin restricciones».',
                action: HxButton(
                  label: 'Abrir',
                  kind: HxButtonKind.tonal,
                  height: 48,
                  onTap: NativeBridge.instance.openBatteryOptimizationSettings,
                ),
              ),
            ],
          ],
        ),
        SettingsSection(
          icon: Symbols.open_in_full_rounded,
          title: 'Al abrir',
          children: [
            SettingsSwitch(
              label: 'Pantalla completa inmersiva',
              description: 'Oculta las barras de estado y navegación del sistema.',
              value: s.immersive,
              onChanged: (v) => c.startup((d) => d.copyWith(immersive: v)),
            ),
            SettingsSwitch(
              label: 'Fijar en horizontal',
              description: 'No gira la pantalla aunque el radio lo permita.',
              value: s.lockLandscape,
              onChanged: (v) => c.startup((d) => d.copyWith(lockLandscape: v)),
            ),
            SettingsSwitch(
              label: 'Mantener pantalla encendida',
              description: 'La tableta no se apaga mientras muestra la música.',
              value: c.prefs.keepScreenOn,
              onChanged: c.setKeepScreenOn,
            ),
            SettingsSwitch(
              label: 'Empezar con la letra en pantalla completa',
              description: 'Al abrir la app se ve directo la letra grande.',
              value: s.startLyricsFullscreen,
              onChanged: (v) => c.startup((d) => d.copyWith(startLyricsFullscreen: v)),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Diseño

class _DesignPage extends StatefulWidget {
  const _DesignPage({required this.c});
  final CarController c;

  @override
  State<_DesignPage> createState() => _DesignPageState();
}

class _DesignPageState extends State<_DesignPage> {
  late final TextEditingController _hex = TextEditingController(text: colorHex(widget.c.cfg.design.fixedColor));
  final _hexFocus = FocusNode();

  CarController get c => widget.c;

  @override
  void dispose() {
    _hex.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  void _applyHex() {
    final v = parseColorHex(_hex.text);
    if (v == null) {
      showHxSnack(context, 'Color no válido. Usa el formato #RRGGBB.');
      return;
    }
    c.design((d) => d.copyWith(fixedColor: v));
    _hex.text = colorHex(v);
  }

  @override
  Widget build(BuildContext context) {
    final d = c.cfg.design;
    final cs = context.cs;
    final hex = colorHex(d.fixedColor);
    if (!_hexFocus.hasFocus && _hex.text != hex) _hex.text = hex;
    final brightness = cs.brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          icon: Symbols.palette_rounded,
          title: 'Color',
          children: [
            SettingsItem(
              label: 'Origen del color',
              desc: 'De la portada: la interfaz toma los colores de cada tema. Fijo: siempre el mismo.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsSegmented<CarColorSource>(
                    value: d.colorSource,
                    options: const [(CarColorSource.art, 'De la portada'), (CarColorSource.fixed, 'Fijo')],
                    onChanged: (v) => c.design((x) => x.copyWith(colorSource: v)),
                  ),
                  if (d.colorSource == CarColorSource.fixed) ...[
                    const SizedBox(height: 16),
                    ColorSwatches(
                      value: d.fixedColor,
                      onChanged: (v) => c.design((x) => x.copyWith(fixedColor: v)),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(color: Color(d.fixedColor), borderRadius: HxRadius.m),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Focus(
                            focusNode: _hexFocus,
                            child: SettingsField(
                              controller: _hex,
                              hint: '#3F6D8E',
                              helper: 'Cualquier color en hexadecimal (#RRGGBB).',
                              onSubmitted: _applyHex,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: HxButton(label: 'Aplicar', kind: HxButtonKind.tonal, height: 48, onTap: _applyHex),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            SettingsItem(
              label: 'Estilo del esquema',
              desc: 'Cómo se reparte el color en la interfaz (variantes de Material You).',
              child: ChoiceTiles<SchemeVariant>(
                value: d.variant,
                options: variantOptions(c.seed, brightness),
                onChanged: (v) => c.design((x) => x.copyWith(variant: v)),
              ),
            ),
            SettingsItem(
              label: 'Tema',
              desc: 'Automático sigue el modo claro/oscuro de la tableta.',
              child: SettingsSegmented<CarThemeMode>(
                value: d.themeMode,
                options: const [
                  (CarThemeMode.dark, 'Oscuro'),
                  (CarThemeMode.light, 'Claro'),
                  (CarThemeMode.auto, 'Automático'),
                ],
                onChanged: (v) => c.design((x) => x.copyWith(themeMode: v)),
              ),
            ),
          ],
        ),
        SettingsSection(
          icon: Symbols.format_size_rounded,
          title: 'Tamaños',
          children: [
            SettingsSlider(
              label: 'Escala de la interfaz',
              desc: 'Agranda o achica toda la pantalla del reproductor.',
              value: d.uiScale,
              range: CarDesign.uiScaleRange,
              defaultValue: 1,
              format: _x,
              onChanged: (v) => c.design((x) => x.copyWith(uiScale: v)),
            ),
            SettingsSlider(
              label: 'Tamaño del título',
              desc: 'Título, artista y álbum.',
              value: d.titleScale,
              range: CarDesign.titleScaleRange,
              defaultValue: 1,
              format: _x,
              onChanged: (v) => c.design((x) => x.copyWith(titleScale: v)),
            ),
            SettingsSlider(
              label: 'Alto de los botones de control',
              desc: 'Más grandes = más fáciles de tocar manejando.',
              value: d.controlHeight,
              range: CarDesign.controlHeightRange,
              defaultValue: 56,
              format: _px,
              onChanged: (v) => c.design((x) => x.copyWith(controlHeight: v)),
            ),
          ],
        ),
        SettingsSection(
          icon: Symbols.airwave_rounded,
          title: 'Barra de progreso',
          children: [
            SettingsSwitch(
              label: 'Onda',
              description: 'La parte reproducida ondula mientras suena (slider ondulado de Harmonix).',
              value: d.wavy,
              onChanged: (v) => c.design((x) => x.copyWith(wavy: v)),
            ),
            if (d.wavy)
              SettingsSlider(
                label: 'Amplitud de la onda',
                value: d.waveAmplitude,
                range: CarDesign.waveAmplitudeRange,
                defaultValue: 1,
                format: _x,
                onChanged: (v) => c.design((x) => x.copyWith(waveAmplitude: v)),
              ),
          ],
        ),
        SettingsSection(
          icon: Symbols.interests_rounded,
          title: 'Formas de fondo',
          children: [
            SettingsSlider(
              label: 'Cantidad',
              desc: '0 = sin formas.',
              value: d.shapesCount.toDouble(),
              range: CarDesign.shapesCountRange,
              defaultValue: 14,
              format: (v) => '${v.round()}',
              onChanged: (v) => c.design((x) => x.copyWith(shapesCount: v.round())),
            ),
            SettingsSlider(
              label: 'Intensidad',
              value: d.shapesOpacity,
              range: CarDesign.shapesOpacityRange,
              defaultValue: 1,
              format: _x,
              onChanged: (v) => c.design((x) => x.copyWith(shapesOpacity: v)),
            ),
            SettingsSwitch(
              label: 'Movimiento',
              description: 'Flotan y giran despacio mientras suena la música.',
              value: d.shapesAnimate,
              onChanged: (v) => c.design((x) => x.copyWith(shapesAnimate: v)),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Portada y visualizador

class _CoverPage extends StatelessWidget {
  const _CoverPage({required this.c});
  final CarController c;

  @override
  Widget build(BuildContext context) {
    final cv = c.cfg.cover;
    final v = c.cfg.visualizer;
    final cs = context.cs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          icon: Symbols.album_rounded,
          title: 'Portada',
          onReset: () => c.custom.resetSections(const [CarSection.cover]),
          resetEnabled: !c.cfg.isDefault(CarSection.cover),
          children: [
            SettingsItem(
              label: 'Forma',
              desc: 'Formas de Material 3 Expressive para recortar la portada.',
              child: ShapePicker(
                value: cv.shape,
                onChanged: (s) => c.coverOpts((d) => d.copyWith(shape: s)),
              ),
            ),
            SettingsSlider(
              label: 'Tamaño',
              value: cv.scale,
              range: CarCoverOpts.scaleRange,
              defaultValue: 1,
              format: _x,
              onChanged: (x) => c.coverOpts((d) => d.copyWith(scale: x)),
            ),
            SettingsSwitch(
              label: 'Girar mientras suena',
              value: cv.rotate,
              onChanged: (x) => c.coverOpts((d) => d.copyWith(rotate: x)),
            ),
            if (cv.rotate)
              SettingsSlider(
                label: 'Tiempo por vuelta',
                desc: 'Menos segundos = gira más rápido.',
                value: cv.turnSeconds,
                range: CarCoverOpts.turnRange,
                defaultValue: 23.5,
                format: (x) => '${fmtNum(x, x == x.roundToDouble() ? 0 : 1)} s',
                onChanged: (x) => c.coverOpts((d) => d.copyWith(turnSeconds: x)),
              ),
            SettingsSwitch(
              label: 'Contorno suave',
              description: 'Un brillo fino alrededor de la forma.',
              value: cv.outline,
              onChanged: (x) => c.coverOpts((d) => d.copyWith(outline: x)),
            ),
            SettingsSwitch(
              label: 'Resplandor de color',
              description: 'Un halo del color principal detrás de la portada.',
              value: cv.glow,
              onChanged: (x) => c.coverOpts((d) => d.copyWith(glow: x)),
            ),
          ],
        ),
        SettingsSection(
          icon: Symbols.graphic_eq_rounded,
          title: 'Visualizador',
          onReset: () => c.custom.resetSections(const [CarSection.visualizer]),
          resetEnabled: !c.cfg.isDefault(CarSection.visualizer),
          children: [
            if (!c.cfg.show(CarElement.visualizer))
              const SettingsNote(
                'Las barras están ocultas (Elementos visibles → Barras del visualizador).',
                icon: Symbols.visibility_off_rounded,
              ),
            SettingsSlider(
              label: 'Amplificación de las líneas',
              desc: 'Qué tan largas se estiran las barras. Si no caben, la portada se achica un poco.',
              value: v.amplification,
              range: CarVisualizerOpts.amplificationRange,
              defaultValue: 1,
              format: _x,
              onChanged: (x) => c.viz((d) => d.copyWith(amplification: x)),
            ),
            SettingsSlider(
              label: 'Cantidad de barras',
              value: v.bars.toDouble(),
              range: CarVisualizerOpts.barsRange,
              defaultValue: 44,
              format: (x) => '${x.round()}',
              onChanged: (x) => c.viz((d) => d.copyWith(bars: x.round() ~/ 2 * 2)),
            ),
            SettingsSlider(
              label: 'Grosor',
              value: v.thickness,
              range: CarVisualizerOpts.thicknessRange,
              defaultValue: 1,
              format: _x,
              onChanged: (x) => c.viz((d) => d.copyWith(thickness: x)),
            ),
            SettingsSlider(
              label: 'Separación de la portada',
              value: v.spacing,
              range: CarVisualizerOpts.spacingRange,
              defaultValue: 12,
              format: _px,
              onChanged: (x) => c.viz((d) => d.copyWith(spacing: x)),
            ),
            SettingsSlider(
              label: 'Velocidad de la animación',
              desc: 'Qué tan rápido cambian las barras.',
              value: v.speed,
              range: CarVisualizerOpts.speedRange,
              defaultValue: 1,
              format: _x,
              onChanged: (x) => c.viz((d) => d.copyWith(speed: x)),
            ),
            SettingsItem(
              label: 'Extremos',
              child: SettingsSegmented<bool>(
                value: v.roundCaps,
                options: const [(true, 'Redondeados'), (false, 'Rectos')],
                onChanged: (x) => c.viz((d) => d.copyWith(roundCaps: x)),
              ),
            ),
            SettingsItem(
              label: 'Color de las barras',
              child: ChoiceTiles<CarVizColor>(
                value: v.color,
                minWidth: 140,
                options: [
                  (CarVizColor.primary, 'Principal', [cs.primary]),
                  (CarVizColor.secondary, 'Secundario', [cs.secondary]),
                  (CarVizColor.tertiary, 'Terciario', [cs.tertiary]),
                  (CarVizColor.onSurface, 'Texto', [cs.onSurface]),
                ],
                onChanged: (x) => c.viz((d) => d.copyWith(color: x)),
              ),
            ),
            SettingsSwitch(
              label: 'Puntos en pausa',
              description: 'En pausa las barras quedan como puntos alrededor de la portada.',
              value: v.pausedDots,
              onChanged: (x) => c.viz((d) => d.copyWith(pausedDots: x)),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Elementos visibles

class _VisibilityPage extends StatelessWidget {
  const _VisibilityPage({required this.c});
  final CarController c;

  static const _icons = {
    CarElementGroup.header: Symbols.top_panel_open_rounded,
    CarElementGroup.info: Symbols.music_note_rounded,
    CarElementGroup.controls: Symbols.play_pause_rounded,
    CarElementGroup.chips: Symbols.label_rounded,
    CarElementGroup.side: Symbols.right_panel_open_rounded,
    CarElementGroup.stage: Symbols.album_rounded,
    CarElementGroup.idle: Symbols.hourglass_empty_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final vis = c.cfg.visibility;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          icon: Symbols.touch_app_rounded,
          title: 'Atajos',
          children: [
            const SettingsNote(
              'Mantén presionado el fondo del reproductor para abrir Configuración, aunque ocultes el botón.',
              icon: Symbols.info_rounded,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  HxButton(
                    label: 'Mostrar todo',
                    icon: Symbols.visibility_rounded,
                    kind: HxButtonKind.tonal,
                    height: 48,
                    onTap: () => c.edit((v) => v.copyWith(visibility: v.visibility.withAll(true))),
                  ),
                  HxButton(
                    label: 'Ocultar todo',
                    icon: Symbols.visibility_off_rounded,
                    kind: HxButtonKind.outlined,
                    height: 48,
                    onTap: () => c.edit((v) => v.copyWith(visibility: v.visibility.withAll(false))),
                  ),
                ],
              ),
            ),
          ],
        ),
        for (final g in CarElementGroup.values)
          SettingsSection(
            icon: _icons[g]!,
            title: g.label,
            children: [
              for (final e in CarElement.values.where((e) => e.group == g))
                SettingsSwitch(
                  key: ValueKey('vis-${e.name}'),
                  label: e.label,
                  description: e.description,
                  value: vis[e],
                  onChanged: (on) => c.edit((v) => v.copyWith(visibility: v.visibility.withElement(e, on))),
                ),
            ],
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Textos

class _TextsPage extends StatefulWidget {
  const _TextsPage({required this.c});
  final CarController c;

  @override
  State<_TextsPage> createState() => _TextsPageState();
}

class _TextsPageState extends State<_TextsPage> {
  final Map<CarText, TextEditingController> _ctl = {};
  final Map<CarText, FocusNode> _focus = {};

  CarController get c => widget.c;

  TextEditingController _controller(CarText t) => _ctl.putIfAbsent(t, () => TextEditingController(text: c.cfg.text(t)));
  FocusNode _node(CarText t) => _focus.putIfAbsent(t, FocusNode.new);

  @override
  void dispose() {
    for (final x in _ctl.values) {
      x.dispose();
    }
    for (final x in _focus.values) {
      x.dispose();
    }
    super.dispose();
  }

  static const _icons = {
    CarTextGroup.player: Symbols.music_note_rounded,
    CarTextGroup.panel: Symbols.lyrics_rounded,
    CarTextGroup.status: Symbols.link_rounded,
    CarTextGroup.idle: Symbols.hourglass_empty_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final texts = c.cfg.texts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in CarTextGroup.values)
          SettingsSection(
            icon: _icons[g]!,
            title: g.label,
            children: [
              for (final t in CarText.values.where((t) => t.group == g))
                Builder(
                  builder: (context) {
                    final ctl = _controller(t);
                    final node = _node(t);
                    final value = texts[t];
                    // Sincroniza si cambió desde afuera (restablecer, importar).
                    if (!node.hasFocus && ctl.text != value) ctl.text = value;
                    return SettingsItem(
                      label: t.label,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (value.isEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: cs.errorContainer, borderRadius: HxRadius.s),
                              child: Text(
                                'Oculto',
                                style: context.tt.labelMedium?.copyWith(color: cs.onErrorContainer),
                              ),
                            ),
                          if (texts.isCustom(t))
                            HxIconButton(
                              icon: Symbols.restart_alt_rounded,
                              tooltip: 'Restablecer «${t.defaultText}»',
                              onTap: () {
                                node.unfocus();
                                c.edit((v) => v.copyWith(texts: v.texts.withText(t, null)));
                              },
                            ),
                        ],
                      ),
                      child: Focus(
                        focusNode: node,
                        child: SettingsField(
                          fieldKey: ValueKey('text-${t.name}'),
                          controller: ctl,
                          hint: 'Vacío = oculto',
                          maxLines: t.defaultText.length > 48 ? 3 : 1,
                          onChanged: (s) => c.edit((v) => v.copyWith(texts: v.texts.withText(t, s))),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Letra

class _LyricsPage extends StatelessWidget {
  const _LyricsPage({required this.c});
  final CarController c;

  @override
  Widget build(BuildContext context) {
    final l = c.cfg.lyrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          icon: Symbols.format_size_rounded,
          title: 'Estilo',
          children: [
            SettingsSlider(
              label: 'Tamaño de la letra',
              desc: 'En el panel y en pantalla completa.',
              value: l.scale,
              range: CarLyricsOpts.scaleRange,
              defaultValue: 1,
              format: _x,
              onChanged: (x) => c.lyricsOpts((d) => d.copyWith(scale: x)),
            ),
            SettingsSlider(
              label: 'Espacio entre líneas',
              value: l.spacing,
              range: CarLyricsOpts.spacingRange,
              defaultValue: 1,
              format: _x,
              onChanged: (x) => c.lyricsOpts((d) => d.copyWith(spacing: x)),
            ),
            SettingsItem(
              label: 'Alineación',
              child: SettingsSegmented<CarLyricsAlign>(
                value: l.align,
                options: const [(CarLyricsAlign.left, 'Izquierda'), (CarLyricsAlign.center, 'Centro')],
                onChanged: (x) => c.lyricsOpts((d) => d.copyWith(align: x)),
              ),
            ),
            SettingsSwitch(
              label: 'Brillo en la línea actual',
              description: 'Un resplandor del color principal alrededor de la línea que suena.',
              value: l.glow,
              onChanged: (x) => c.lyricsOpts((d) => d.copyWith(glow: x)),
            ),
          ],
        ),
        SettingsSection(
          icon: Symbols.timer_rounded,
          title: 'Sincronización',
          children: [
            SettingsSlider(
              label: 'Adelanto de la letra',
              desc: 'Resalta cada línea antes para compensar el retraso del Bluetooth. Negativo = después.',
              value: l.offsetMs.toDouble(),
              range: CarLyricsOpts.offsetRange,
              defaultValue: 150,
              format: (x) => '${x >= 0 ? '+' : ''}${fmtNum(x / 1000, 2)} s',
              onChanged: (x) => c.lyricsOpts((d) => d.copyWith(offsetMs: x.round())),
            ),
          ],
        ),
        SettingsSection(
          icon: Symbols.touch_app_rounded,
          title: 'Al tocar una línea',
          children: [
            SettingsItem(
              label: 'Saltar a esa parte de la canción',
              desc: 'Con doble toque es más difícil saltar sin querer.',
              child: SettingsSegmented<CarSeekMode>(
                value: l.seek,
                options: const [
                  (CarSeekMode.tap, 'Un toque'),
                  (CarSeekMode.doubleTap, 'Doble toque'),
                  (CarSeekMode.off, 'Nunca'),
                ],
                onChanged: (x) => c.lyricsOpts((d) => d.copyWith(seek: x)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Avanzado

class _AdvancedPage extends StatelessWidget {
  const _AdvancedPage({required this.c, required this.onChangeMode});
  final CarController c;
  final VoidCallback onChangeMode;

  Future<void> _export(BuildContext context) async {
    final json = c.custom.export();
    await showHxDialog<void>(
      context,
      title: 'Exportar personalización',
      icon: Symbols.file_export_rounded,
      maxWidth: 640,
      content: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Copia este texto y guárdalo; puedes pegarlo en «Importar» en esta u otra tableta.'),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 320),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: ctx.cs.surfaceContainerHighest, borderRadius: HxRadius.m),
            child: SingleChildScrollView(
              child: SelectableText(
                json,
                style: TextStyle(fontFamily: 'monospace', fontSize: 13, color: ctx.cs.onSurface),
              ),
            ),
          ),
        ],
      ),
      actions: (ctx) => [
        HxButton(label: 'Cerrar', kind: HxButtonKind.text, height: 48, onTap: () => Navigator.of(ctx).pop()),
        HxButton(
          label: 'Copiar',
          icon: Symbols.content_copy_rounded,
          height: 48,
          onTap: () async {
            final ok = await copyText(json);
            if (!ctx.mounted) return;
            Navigator.of(ctx).pop();
            if (context.mounted) showHxSnack(context, ok ? 'Copiado al portapapeles.' : 'No se pudo copiar.');
          },
        ),
      ],
    );
  }

  Future<void> _import(BuildContext context) async {
    final ctl = TextEditingController();
    final error = ValueNotifier<String?>(null);
    await showHxDialog<void>(
      context,
      title: 'Importar personalización',
      icon: Symbols.file_open_rounded,
      maxWidth: 640,
      content: (ctx) => ValueListenableBuilder<String?>(
        valueListenable: error,
        builder: (ctx, err, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Pega el texto que exportaste. Lo que no esté en el texto queda con su valor de fábrica.'),
            const SizedBox(height: 12),
            SettingsField(controller: ctl, hint: '{ "v": 1, … }', maxLines: 8, monospace: true),
            if (err != null) ...[
              const SizedBox(height: 8),
              Text(err, style: ctx.tt.bodyMedium?.copyWith(color: ctx.cs.error)),
            ],
          ],
        ),
      ),
      actions: (ctx) => [
        HxButton(label: 'Cancelar', kind: HxButtonKind.text, height: 48, onTap: () => Navigator.of(ctx).pop()),
        HxButton(
          label: 'Pegar',
          icon: Symbols.content_paste_rounded,
          kind: HxButtonKind.tonal,
          height: 48,
          onTap: () async {
            final t = await pasteText();
            if (t != null) ctl.text = t;
          },
        ),
        HxButton(
          label: 'Importar',
          height: 48,
          onTap: () {
            try {
              c.custom.import(ctl.text);
              Navigator.of(ctx).pop();
              showHxSnack(context, 'Personalización importada.');
            } on FormatException {
              error.value = 'El texto no es una personalización válida (JSON).';
            }
          },
        ),
      ],
    );
    ctl.dispose();
    error.dispose();
  }

  Future<void> _resetAll(BuildContext context) async {
    final ok = await showHxDialog<bool>(
      context,
      title: '¿Restablecer todo?',
      icon: Symbols.restart_alt_rounded,
      content: (_) => const Text(
        'El diseño, los elementos visibles, los textos, la letra, el inicio y los gestos vuelven a los valores de '
        'fábrica. La IP manual y el celular Bluetooth elegido se conservan.',
      ),
      actions: (ctx) => [
        HxButton(label: 'Cancelar', kind: HxButtonKind.text, height: 48, onTap: () => Navigator.of(ctx).pop(false)),
        HxButton(
          label: 'Restablecer',
          kind: HxButtonKind.text,
          danger: true,
          height: 48,
          onTap: () => Navigator.of(ctx).pop(true),
        ),
      ],
    );
    if (ok != true) return;
    final before = c.cfg;
    c.custom.resetAll();
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Todo volvió a los valores de fábrica.'),
          action: SnackBarAction(label: 'Deshacer', onPressed: () => c.custom.set(before)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final g = c.cfg.gestures;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          icon: Symbols.swipe_rounded,
          title: 'Gestos',
          children: [
            SettingsSwitch(
              label: 'Tocar la portada: reproducir / pausar',
              value: g.tapCover,
              onChanged: (x) => c.gestures((d) => d.copyWith(tapCover: x)),
            ),
            SettingsSwitch(
              label: 'Deslizar la portada: siguiente / anterior',
              description: 'Hacia la izquierda = siguiente; hacia la derecha = anterior.',
              value: g.swipeCover,
              onChanged: (x) => c.gestures((d) => d.copyWith(swipeCover: x)),
            ),
            const SettingsNote('Mantener presionado el fondo siempre abre Configuración.', icon: Symbols.info_rounded),
          ],
        ),
        SettingsSection(
          icon: Symbols.backup_rounded,
          title: 'Copia de seguridad',
          children: [
            const SettingsNote('Toda la personalización como texto (JSON), para guardarla o pasarla a otra tableta.'),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  HxButton(
                    label: 'Exportar',
                    icon: Symbols.file_export_rounded,
                    kind: HxButtonKind.tonal,
                    height: 48,
                    onTap: () => _export(context),
                  ),
                  HxButton(
                    label: 'Importar',
                    icon: Symbols.file_open_rounded,
                    kind: HxButtonKind.outlined,
                    height: 48,
                    onTap: () => _import(context),
                  ),
                ],
              ),
            ),
          ],
        ),
        SettingsSection(
          icon: Symbols.apps_rounded,
          title: 'Aplicación',
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  HxButton(
                    label: 'Restablecer todo',
                    icon: Symbols.restart_alt_rounded,
                    kind: HxButtonKind.text,
                    danger: true,
                    height: 48,
                    onTap: () => _resetAll(context),
                  ),
                  HxButton(
                    label: 'Cambiar modo (celular/tableta)',
                    icon: Symbols.swap_horiz_rounded,
                    kind: HxButtonKind.outlined,
                    height: 48,
                    onTap: () {
                      Navigator.of(context).pop();
                      onChangeMode();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
