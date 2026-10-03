import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/car/widgets/loading_indicator.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/data/bridge/native_bridge.dart';
import 'package:pixel_car_player/data/link/car_link_client.dart';

/// Abre los ajustes de la tableta (vista de Ajustes de Harmonix v2 a pantalla completa,
/// con el mismo color de la portada que suena).
Future<void> showCarSettings(
  BuildContext context, {
  required CarController controller,
  required VoidCallback onChangeMode,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 450),
      reverseTransitionDuration: HxMotion.dFxSlow,
      pageBuilder: (_, _, _) => ListenableBuilder(
        listenable: controller,
        builder: (_, child) => HxAnimatedTheme(scheme: controller.scheme, child: child!),
        child: CarSettingsSheet(controller: controller, onChangeMode: onChangeMode),
      ),
      transitionsBuilder: (_, a, _, child) {
        final c = CurvedAnimation(parent: a, curve: HxMotion.emphasizedDecel, reverseCurve: HxMotion.emphasizedAccel);
        return FadeTransition(
          opacity: c,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(c),
            child: child,
          ),
        );
      },
    ),
  );
}

/// `SettingsView.svelte`: título grande, secciones con encabezado en primary y tarjetas
/// `surfaceContainer` (radio 28) con ítems separados por outline-variant.
class CarSettingsSheet extends StatefulWidget {
  const CarSettingsSheet({super.key, required this.controller, required this.onChangeMode});
  final CarController controller;
  final VoidCallback onChangeMode;

  @override
  State<CarSettingsSheet> createState() => _CarSettingsSheetState();
}

class _CarSettingsSheetState extends State<CarSettingsSheet> {
  late final TextEditingController _ip = TextEditingController(text: widget.controller.prefs.manualIp ?? '');
  List<Map<String, dynamic>> _bonded = const [];

  /// Opción elegida en el segmentado (null = según la conexión guardada).
  bool? _bluetooth;
  bool _loadingBonded = true;

  CarController get c => widget.controller;

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
    if (mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('IP guardada. Reconectando…')));
    }
  }

  Future<void> _pickBt(String? address, String? name) async {
    await c.setConnection(manualIp: c.prefs.manualIp, btAddress: address, btName: name);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    return Scaffold(
      backgroundColor: cs.surface,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([c, c.link.status]),
          builder: (context, _) {
            final bt = _bluetooth ?? c.prefs.btAddress != null;
            final st = c.displayStatus;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    children: [
                      HxIconButton(
                        icon: Symbols.arrow_back_rounded,
                        tooltip: 'Volver',
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 4),
                      Text('Pixel Car Player', style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                Expanded(
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                    child: SingleChildScrollView(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 20),
                                  child: Text(
                                    'Ajustes',
                                    style: hxWeight(
                                      tt.displayMedium,
                                      400,
                                    ).copyWith(fontSize: 45, height: 1.1, letterSpacing: -0.9, color: cs.onSurface),
                                  ),
                                ),
                                _Section(
                                  icon: Symbols.link_rounded,
                                  title: 'Conexión con el celular',
                                  children: [
                                    _Item(
                                      label: 'Cómo se conecta',
                                      desc: bt ? 'Bluetooth: elige el celular emparejado. Sirve aunque no haya Wi-Fi.' : 'Hotspot del celular o la misma red Wi-Fi. Se busca solo; la IP manual es opcional.',
                                      child: _Segmented<bool>(
                                        value: bt,
                                        options: const [(false, 'Wi-Fi'), (true, 'Bluetooth')],
                                        onChanged: (v) {
                                          setState(() => _bluetooth = v);
                                          if (!v) _pickBt(null, null);
                                        },
                                      ),
                                    ),
                                    if (!bt)
                                      _Item(
                                        label: 'IP manual del celular',
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: _Field(controller: _ip, onSubmitted: _saveIp),
                                            ),
                                            const SizedBox(width: 12),
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: HxButton(
                                                label: 'Guardar',
                                                kind: HxButtonKind.tonal,
                                                height: 48,
                                                onTap: _saveIp,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    else
                                      _Item(label: 'Celular emparejado', child: _bondedList(context)),
                                    _StatusRow(status: st, demo: c.demo),
                                    _Stats(ips: c.tabletIps),
                                  ],
                                ),
                                _Section(
                                  icon: Symbols.tablet_rounded,
                                  title: 'Pantalla',
                                  children: [
                                    _Switch(
                                      label: 'Mantener pantalla encendida',
                                      description: 'La tableta no se apaga mientras muestra la música.',
                                      value: c.prefs.keepScreenOn,
                                      onChanged: c.setKeepScreenOn,
                                    ),
                                    _Switch(
                                      label: 'Modo demo',
                                      description: 'Canciones de ejemplo para probar la pantalla sin celular.',
                                      value: c.demo,
                                      onChanged: c.setDemo,
                                    ),
                                  ],
                                ),
                                _Section(
                                  icon: Symbols.apps_rounded,
                                  title: 'Aplicación',
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          HxButton(
                                            label: 'Cambiar modo (celular/tableta)',
                                            icon: Symbols.swap_horiz_rounded,
                                            kind: HxButtonKind.outlined,
                                            height: 48,
                                            onTap: () {
                                              Navigator.of(context).pop();
                                              widget.onChangeMode();
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
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
            onTap: () => _pickBt(d['address'] as String?, d['name'] as String?),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.icon, required this.title, required this.children});
  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: Row(
              children: [
                HxIcon(icon, size: 20, color: cs.primary),
                const SizedBox(width: 10),
                Text(title, style: context.tt.titleMedium?.copyWith(color: cs.primary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: HxRadius.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: cs.outlineVariant),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.label, this.desc, required this.child});
  final String label;
  final String? desc;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: tt.bodyLarge?.copyWith(color: cs.onSurface)),
          if (desc != null) ...[
            const SizedBox(height: 4),
            Text(desc!, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.status, required this.demo});
  final LinkStatus status;
  final bool demo;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final ok = status.isConnected;
    final text = demo
        ? 'Modo demo activo — datos simulados'
        : switch (status.phase) {
            LinkPhase.connected =>
              'Conectado a ${status.device} por ${status.transport == 'bt' ? 'Bluetooth' : 'Wi-Fi'} (${status.address})',
            LinkPhase.searching => 'Buscando al celular…',
            LinkPhase.disconnected => 'Sin conexión',
          };
    final color = ok ? cs.primary : cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          HxIcon(ok ? Symbols.check_circle_rounded : Symbols.info_rounded, size: 18, fill: true, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: context.tt.labelLarge?.copyWith(color: color)),
          ),
        ],
      ),
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

/// Botones segmentados de MD3 (`Segmented.svelte`), con check en el elegido.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({required this.value, required this.options, required this.onChanged});
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    const h = 48.0;
    return Container(
      height: h,
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline),
        borderRadius: BorderRadius.circular(h / 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) VerticalDivider(width: 1, thickness: 1, color: cs.outline),
            Expanded(child: _segment(context, options[i])),
          ],
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, (T, String) o) {
    final cs = context.cs;
    final sel = o.$1 == value;
    final fg = sel ? cs.onSecondaryContainer : cs.onSurface;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: sel,
      child: AnimatedContainer(
        duration: HxMotion.dFxSlow,
        curve: HxMotion.standard,
        color: sel ? cs.secondaryContainer : cs.secondaryContainer.withValues(alpha: 0),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: () => onChanged(o.$1),
            splashColor: fg.withValues(alpha: 0.1),
            highlightColor: fg.withValues(alpha: 0.1),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSize(
                    duration: HxMotion.dFxSlow,
                    curve: HxMotion.standard,
                    child: sel
                        ? Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: HxIcon(Symbols.check_rounded, size: 18, color: fg),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Text(o.$2, style: context.tt.labelLarge?.copyWith(color: fg, fontSize: 15)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Switch de MD3 (`Switch.svelte`): fila con etiqueta + descripción y el control propio.
class _Switch extends StatefulWidget {
  const _Switch({required this.label, required this.value, required this.onChanged, this.description});
  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<_Switch> createState() => _SwitchState();
}

class _SwitchState extends State<_Switch> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    final on = widget.value;
    final handle = _pressed ? 28.0 : (on ? 24.0 : 16.0);
    // Centro del cursor: 16 px (apagado) / 36 px (encendido) desde el borde izquierdo.
    final cx = on ? 36.0 : 16.0;
    return Semantics(
      toggled: on,
      label: widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          setState(() => _pressed = false);
          widget.onChanged(!on);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label, style: tt.bodyLarge?.copyWith(color: cs.onSurface)),
                    if (widget.description != null)
                      Text(widget.description!, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              AnimatedContainer(
                duration: HxMotion.dFxSlow,
                curve: HxMotion.standard,
                width: 52,
                height: 32,
                decoration: BoxDecoration(
                  color: on ? cs.primary : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: on ? cs.primary : cs.outline, width: 2),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedPositioned(
                      duration: HxMotion.dSpringFast,
                      curve: HxMotion.springFast,
                      left: cx - 2 - handle / 2,
                      top: (28 - handle) / 2,
                      width: handle,
                      height: handle,
                      child: AnimatedContainer(
                        duration: HxMotion.dFxSlow,
                        curve: HxMotion.standard,
                        decoration: BoxDecoration(color: on ? cs.onPrimary : cs.outline, shape: BoxShape.circle),
                        child: on
                            ? Center(child: HxIcon(Symbols.check_rounded, size: 16, color: cs.onPrimaryContainer))
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Campo de texto relleno de MD3 (`.field`): 56 px, surfaceContainerHighest, línea abajo.
class _Field extends StatelessWidget {
  const _Field({required this.controller, required this.onSubmitted});
  final TextEditingController controller;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    const radius = BorderRadius.vertical(top: Radius.circular(4));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: tt.bodyLarge?.copyWith(color: cs.onSurface, fontSize: 18),
          onSubmitted: (_) => onSubmitted(),
          decoration: InputDecoration(
            hintText: '192.168.43.1',
            hintStyle: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant, fontSize: 18),
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            border: UnderlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: cs.onSurfaceVariant),
            ),
            enabledBorder: UnderlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: cs.onSurfaceVariant),
            ),
            focusedBorder: UnderlineInputBorder(
              borderRadius: radius,
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            'Opcional: solo si no se encuentra solo.',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      ],
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
