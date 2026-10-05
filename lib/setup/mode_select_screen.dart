import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/core/app_mode.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx.dart';

/// Selección de rol al primer arranque, con el aspecto de Harmonix v2: formas de fondo,
/// ícono en una forma cookie9, saludo grande y dos tarjetas como las de "Escuchado hace
/// poco".
class ModeSelectScreen extends StatelessWidget {
  const ModeSelectScreen({super.key, required this.onSelected});
  final ValueChanged<AppMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = AppTheme.schemeFromSeed(
      AppTheme.fallbackSeed,
      brightness: Theme.of(context).brightness,
    );
    return HxAnimatedTheme(
      scheme: scheme,
      child: Builder(builder: _build),
    );
  }

  Widget _build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: [
          const Positioned.fill(child: HxBackgroundShapes()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, c) {
                final wide = c.maxWidth >= 720;
                final compact = c.maxHeight < 800;
                final tile = compact ? 80.0 : 112.0;
                final titleSize = wide && !compact
                    ? 57.0
                    : (wide ? 45.0 : 40.0);

                final cards = <Widget>[
                  _ModeCard(
                    shapeColor: cs.primaryContainer,
                    iconColor: cs.onPrimaryContainer,
                    icon: Symbols.tablet_android_rounded,
                    title: 'Pantalla del carro (tableta)',
                    description:
                        'Muestra portada, letras y controles en grande.',
                    compact: compact,
                    stretch: wide,
                    onTap: () => onSelected(AppMode.car),
                  ),
                  _ModeCard(
                    shapeColor: cs.tertiaryContainer,
                    iconColor: cs.onTertiaryContainer,
                    icon: Symbols.phone_android_rounded,
                    title: 'Transmisor (celular con Spotify)',
                    description:
                        'Lee Spotify y envía todo a la tableta del carro.',
                    compact: compact,
                    stretch: wide,
                    onTap: () => onSelected(AppMode.phone),
                  ),
                ];

                final header = Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Entrada: la forma crece y se transforma, luego el título, el
                    // texto y las tarjetas en cascada.
                    HxEntrance(
                      scale: true,
                      offset: 0,
                      duration: const Duration(milliseconds: 600),
                      child: _MorphInTile(
                        size: tile,
                        color: cs.primaryContainer,
                        iconColor: cs.onPrimaryContainer,
                      ),
                    ),
                    SizedBox(height: compact ? 16 : 24),
                    HxEntrance(
                      index: 2,
                      child: Text(
                        'Pixel Car Player',
                        style: HxType.greeting(titleSize, cs.onSurface),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 10),
                    HxEntrance(
                      index: 3,
                      child: Text(
                        '¿Qué será este dispositivo? Puedes cambiarlo después '
                        'desde el menú.',
                        style: HxType.bodyL(cs.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                );

                cards[0] = HxEntrance(index: 5, offset: 40, child: cards[0]);
                cards[1] = HxEntrance(index: 7, offset: 40, child: cards[1]);
                final body = wide
                    ? IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 12),
                            Expanded(child: cards[1]),
                          ],
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          cards[0],
                          const SizedBox(height: 12),
                          cards[1],
                        ],
                      );

                final pad = EdgeInsets.symmetric(
                  horizontal: wide ? 32 : 16,
                  vertical: compact ? 20 : 32,
                );
                return SingleChildScrollView(
                  padding: pad,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (c.maxHeight - pad.vertical).clamp(
                        0,
                        double.infinity,
                      ),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            header,
                            SizedBox(height: compact ? 24 : 40),
                            body,
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Forma del encabezado: entra como cookie4 y se transforma en cookie9 mientras gira.
class _MorphInTile extends StatelessWidget {
  const _MorphInTile({
    required this.size,
    required this.color,
    required this.iconColor,
  });
  final double size;
  final Color color;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final reduce = hxReduceMotion(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduce ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: HxMotion.emphasizedDecel,
      builder: (context, t, child) => Transform.rotate(
        angle: (t - 1) * 1.2,
        child: ClipPath(
          clipper: M3ShapeClipper(
            M3Shape.lerp(M3Shape.cookie4, M3Shape.cookie9, t),
          ),
          child: child,
        ),
      ),
      child: HxShapeTile(
        shape: M3Shape.cookie9,
        size: size,
        color: color,
        icon: Symbols.directions_car_rounded,
        iconColor: iconColor,
        iconSize: size * 0.43,
        spin: true,
      ),
    );
  }
}

/// Tarjeta de modo (`SearchView .card`): surfaceContainer, radio 28 (16 al presionar);
/// la forma pasa de cuadrado redondeado a cookie al pasar el mouse o presionar.
class _ModeCard extends StatefulWidget {
  const _ModeCard({
    required this.shapeColor,
    required this.iconColor,
    required this.icon,
    required this.title,
    required this.description,
    required this.compact,
    required this.stretch,
    required this.onTap,
  });
  final Color shapeColor;
  final Color iconColor;
  final IconData icon;
  final String title;
  final String description;
  final bool compact;
  final bool stretch;
  final VoidCallback onTap;

  @override
  State<_ModeCard> createState() => _ModeCardState();
}

class _ModeCardState extends State<_ModeCard> with HxPressState {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final art = widget.stretch ? (widget.compact ? 104.0 : 136.0) : 88.0;
    final morph = _hover || pressed;
    final artTile = TweenAnimationBuilder<double>(
      tween: Tween(end: morph ? 1 : 0),
      duration: HxMotion.dSpring,
      curve: HxMotion.spring,
      builder: (context, t, child) => ClipPath(
        clipper: M3ShapeClipper(
          M3Shape.lerp(M3Shape.square, M3Shape.cookie12, t),
        ),
        child: child,
      ),
      child: Container(
        width: art,
        height: art,
        color: widget.shapeColor,
        alignment: Alignment.center,
        child: HxIcon(
          widget.icon,
          size: art * 0.4,
          filled: true,
          color: widget.iconColor,
        ),
      ),
    );
    final texts = [
      Text(widget.title, style: HxType.titleL(cs.onSurface)),
      const SizedBox(height: 2),
      Text(widget.description, style: HxType.bodyM(cs.onSurfaceVariant)),
    ];
    final button = Align(
      alignment: Alignment.centerRight,
      child: HxButton(
        label: 'Elegir',
        trailingIcon: Symbols.arrow_forward_rounded,
        onPressed: widget.onTap,
      ),
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: HxSurface(
        onTap: widget.onTap,
        onHighlightChanged: setPressed,
        color: cs.surfaceContainer,
        contentColor: cs.onSurface,
        duration: HxMotion.dFx,
        shape: RoundedRectangleBorder(
          borderRadius: pressed ? HxRadius.l : HxRadius.xl,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: widget.stretch
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    artTile,
                    const SizedBox(height: 16),
                    ...texts,
                    const SizedBox(height: 20),
                    const Spacer(),
                    button,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        artTile,
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: texts,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    button,
                  ],
                ),
        ),
      ),
    );
  }
}
