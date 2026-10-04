import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/car/car_player_screen.dart';
import 'package:pixel_car_player/car/custom/car_custom_scope.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/car/settings/settings_categories.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// Categorías de Configuración (el nombre del enum es el id de `?settings=` en web).
enum CarSettingsCategory {
  conexion('Conexión', Symbols.link_rounded, [CarSection.connection], 'Cómo encuentra la tableta a tu celular.'),
  diagnostico(
    'Diagnóstico',
    Symbols.troubleshoot_rounded,
    [],
    'Qué ve la tableta: redes, avisos del celular, intentos de conexión y los pasos que faltan.',
  ),
  hotspot('Hotspot', Symbols.wifi_tethering_rounded, [
    CarSection.hotspot,
  ], 'La red Wi-Fi del carro: la tableta la comparte y el celular se conecta a ella.'),
  inicio('Inicio', Symbols.power_settings_new_rounded, [
    CarSection.startup,
  ], 'Qué pasa al encender el carro y al abrir la app, y la app acompañante.'),
  diseno('Diseño', Symbols.palette_rounded, [
    CarSection.design,
  ], 'Animaciones, colores, tamaños, barra de progreso y fondo.'),
  portada('Portada y visualizador', Symbols.album_rounded, [
    CarSection.cover,
    CarSection.visualizer,
  ], 'La forma de la portada y las barras que la rodean.'),
  visibles('Elementos visibles', Symbols.visibility_rounded, [
    CarSection.visibility,
  ], 'Oculta cualquier parte de la pantalla; lo demás se reacomoda.'),
  textos('Textos', Symbols.text_fields_rounded, [
    CarSection.texts,
  ], 'Cambia cualquier texto. Si lo dejas vacío, se oculta.'),
  letra('Letra', Symbols.lyrics_rounded, [CarSection.lyrics], 'Tamaño, alineación, brillo y sincronización.'),
  avanzado('Avanzado', Symbols.tune_rounded, [CarSection.gestures], 'Gestos, copia de seguridad y valores de fábrica.');

  const CarSettingsCategory(this.label, this.icon, this.sections, this.desc);
  final String label;
  final IconData icon;
  final List<CarSection> sections;
  final String desc;

  /// Categorías que muestran la vista previa en vivo del reproductor.
  bool get hasPreview => this == diseno || this == portada || this == visibles || this == textos || this == letra;

  static CarSettingsCategory? byId(String? id) {
    for (final c in values) {
      if (c.name == id) return c;
    }
    return null;
  }
}

/// Abre Configuración (página completa, estilo `SettingsView` de Harmonix v2, con el
/// color de la portada que suena).
Future<void> showCarSettings(
  BuildContext context, {
  required CarController controller,
  required VoidCallback onChangeMode,
  CarSettingsCategory initial = CarSettingsCategory.conexion,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      settings: const RouteSettings(name: 'car-settings'),
      transitionDuration: const Duration(milliseconds: 450),
      reverseTransitionDuration: HxMotion.dFxSlow,
      pageBuilder: (_, _, _) => CarSettingsPage(controller: controller, onChangeMode: onChangeMode, initial: initial),
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

/// Configuración a pantalla completa pensada en horizontal: riel de categorías a la
/// izquierda, contenido en el centro y (en pantallas anchas) la vista previa en vivo.
class CarSettingsPage extends StatefulWidget {
  const CarSettingsPage({
    super.key,
    required this.controller,
    required this.onChangeMode,
    this.initial = CarSettingsCategory.conexion,
  });
  final CarController controller;
  final VoidCallback onChangeMode;
  final CarSettingsCategory initial;

  @override
  State<CarSettingsPage> createState() => _CarSettingsPageState();
}

class _CarSettingsPageState extends State<CarSettingsPage> {
  late CarSettingsCategory _cat = widget.initial;

  CarController get c => widget.controller;

  void _resetCategory(BuildContext context) {
    final before = c.cfg;
    c.custom.resetSections(_cat.sections);
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('«${_cat.label}» volvió a los valores de fábrica.'),
          action: SnackBarAction(label: 'Deshacer', onPressed: () => c.custom.set(before)),
          duration: const Duration(seconds: 5),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => CarCustomScope(
        value: c.cfg,
        child: HxAnimatedTheme(
          scheme: c.schemeFor(MediaQuery.platformBrightnessOf(context)),
          duration: carReducedMotion(context, c.cfg) ? Duration.zero : HxMotion.dTheme,
          child: Builder(
            builder: (context) {
              final cs = context.cs;
              return Scaffold(
                backgroundColor: cs.surface,
                body: CarScaler(
                  builder: (context, size) {
                    final railW = size.width >= 1200 ? 280.0 : 236.0;
                    final sidePreview = _cat.hasPreview && size.width >= 1180;
                    final previewW = (size.width * 0.32).clamp(340.0, 640.0);
                    return SafeArea(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: railW,
                            child: _Rail(selected: _cat, onSelect: (v) => setState(() => _cat = v)),
                          ),
                          Expanded(child: _content(context, inlinePreview: _cat.hasPreview && !sidePreview)),
                          if (sidePreview)
                            SizedBox(
                              width: previewW,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(0, 24, 24, 24),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    const _PreviewLabel(),
                                    const SizedBox(height: 10),
                                    CarPreview(controller: c),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Los cambios se aplican al instante y se guardan solos.',
                                      style: context.tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, {required bool inlinePreview}) {
    final cs = context.cs;
    final tt = context.tt;
    final isDefault = _cat.sections.every((s) => c.cfg.isDefault(s));
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        key: PageStorageKey('settings-${_cat.name}'),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
              child: HxTextIn(
                key: ValueKey(_cat),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 20, 0, 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              _cat.label,
                              style: hxWeight(
                                tt.displayMedium,
                                400,
                              ).copyWith(fontSize: 40, height: 1.1, letterSpacing: -0.8, color: cs.onSurface),
                            ),
                          ),
                          if (_cat.sections.isNotEmpty)
                            HxButton(
                              label: 'Restablecer',
                              icon: Symbols.restart_alt_rounded,
                              kind: HxButtonKind.text,
                              height: 48,
                              onTap: isDefault ? null : () => _resetCategory(context),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 20),
                      child: Text(_cat.desc, style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                    ),
                    if (inlinePreview) ...[
                      const _PreviewLabel(),
                      const SizedBox(height: 10),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: CarPreview(controller: c),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    ...buildCategory(_cat, c, widget.onChangeMode),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Riel de categorías (NavRail de Harmonix con etiquetas): píldora secondaryContainer
/// que crece desde el centro en la elegida.
class _Rail extends StatelessWidget {
  const _Rail({required this.selected, required this.onSelect});
  final CarSettingsCategory selected;
  final ValueChanged<CarSettingsCategory> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
              Expanded(
                child: Text(
                  'Pixel Car Player',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 16, 16, 20),
          child: Text(
            'Ajustes',
            style: hxWeight(tt.headlineMedium, 400).copyWith(color: cs.onSurface, letterSpacing: -0.4),
          ),
        ),
        Expanded(
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              children: [
                for (final cat in CarSettingsCategory.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _RailItem(cat: cat, selected: cat == selected, onTap: () => onSelect(cat)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({required this.cat, required this.selected, required this.onTap});
  final CarSettingsCategory cat;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final fg = selected ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      child: SizedBox(
        height: 56,
        child: Stack(
          children: [
            // Indicador: se expande desde el centro (scaleX 0,3 → 1), como en el riel de MD3.
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: selected ? 1 : 0),
                duration: HxMotion.dSpring,
                curve: HxMotion.spring,
                builder: (_, t, _) => Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scaleX: 0.3 + 0.7 * t,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(28)),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Material(
                type: MaterialType.transparency,
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onTap,
                  splashColor: fg.withValues(alpha: 0.1),
                  highlightColor: fg.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        HxIcon(cat.icon, color: fg, fill: selected),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            cat.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: hxWeight(
                              context.tt.labelLarge,
                              selected ? 700 : 500,
                            ).copyWith(fontSize: 15, color: selected ? cs.onSecondaryContainer : cs.onSurface),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewLabel extends StatelessWidget {
  const _PreviewLabel();

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          HxIcon(Symbols.preview_rounded, size: 20, color: cs.primary),
          const SizedBox(width: 10),
          Text('Vista previa', style: context.tt.titleMedium?.copyWith(color: cs.primary)),
        ],
      ),
    );
  }
}

/// Vista previa en vivo: la pantalla del reproductor real, achicada, con el mismo
/// controlador (misma canción, mismos ajustes). No recibe toques.
class CarPreview extends StatelessWidget {
  const CarPreview({super.key, required this.controller});
  final CarController controller;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final screen = MediaQuery.sizeOf(context);
    final mq = MediaQuery.of(context);
    return AspectRatio(
      aspectRatio: screen.width / screen.height,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: HxRadius.xl,
          border: Border.all(color: cs.outlineVariant),
        ),
        child: ClipRRect(
          borderRadius: HxRadius.xl,
          child: ExcludeSemantics(
            child: IgnorePointer(
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox.fromSize(
                  size: screen,
                  child: MediaQuery(
                    data: mq.copyWith(size: screen, padding: EdgeInsets.zero, viewPadding: EdgeInsets.zero),
                    child: ChangeNotifierProvider<CarController>.value(
                      value: controller,
                      child: CarPlayerScreen(onSettings: (_) {}, preview: true),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Formato con coma decimal (es-CO).
String fmtNum(double v, [int digits = 2]) => v.toStringAsFixed(digits).replaceAll('.', ',');

/// Opciones de variante de esquema con una muestra (primario, secundario, terciario).
List<(SchemeVariant, String, List<Color>)> variantOptions(Color seed, Brightness b) => [
  for (final (v, label) in const [
    (SchemeVariant.tonalSpot, 'Tonal'),
    (SchemeVariant.vibrant, 'Vibrante'),
    (SchemeVariant.expressive, 'Expresivo'),
    (SchemeVariant.fidelity, 'Fiel'),
    (SchemeVariant.content, 'Contenido'),
    (SchemeVariant.neutral, 'Neutro'),
    (SchemeVariant.monochrome, 'Monocromo'),
  ])
    (
      v,
      label,
      () {
        final s = AppTheme.schemeFromSeed(seed, brightness: b, variant: v);
        return [s.primary, s.secondary, s.tertiary];
      }(),
    ),
];
