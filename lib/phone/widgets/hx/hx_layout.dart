import 'package:flutter/material.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx_base.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx_shapes.dart';

class HxNavItem {
  const HxNavItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

/// Barra de navegación del celular (`NavRail.svelte` en ≤700 px): fondo
/// surfaceContainer, indicador en píldora 64×32 que se expande desde el centro.
class HxNavBar extends StatelessWidget {
  const HxNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });
  final List<HxNavItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ColoredBox(
      color: cs.surfaceContainer,
      child: Padding(
        padding: EdgeInsets.only(top: 10, bottom: bottom > 14 ? bottom : 14),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(child: _item(cs, i)),
          ],
        ),
      ),
    );
  }

  Widget _item(ColorScheme cs, int i) {
    final active = i == index;
    final it = items[i];
    return Semantics(
      selected: active,
      button: true,
      label: it.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(i),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 64,
              height: 32,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: active ? 1 : 0),
                      duration: HxMotion.dSpring,
                      curve: HxMotion.spring,
                      builder: (context, v, _) => Opacity(
                        opacity: v.clamp(0, 1),
                        child: Transform.scale(
                          scaleX: 0.3 + 0.7 * v,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: cs.secondaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: HxSurface(
                      onTap: () => onChanged(i),
                      contentColor: active
                          ? cs.onSecondaryContainer
                          : cs.onSurfaceVariant,
                      shape: const StadiumBorder(),
                      child: Center(
                        child: HxIcon(
                          it.icon,
                          filled: active,
                          color: active
                              ? cs.onSecondaryContainer
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              it.label,
              maxLines: 1,
              style: hxText(
                12,
                weight: active ? FontWeight.w700 : FontWeight.w500,
                height: 1.45,
                letterSpacingEm: 0.01,
                color: active ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Píldora superior (el buscador de `SearchView`): 56 px, surfaceContainerHigh.
class HxTopPill extends StatelessWidget {
  const HxTopPill({
    super.key,
    required this.leading,
    required this.title,
    this.trailing,
  });
  final Widget leading;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 56,
      padding: const EdgeInsets.only(left: 16, right: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: hxText(17, color: cs.onSurface),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Logo de Harmonix (`.logo` del riel): tres barras en primary que bailan si suena.
class HxLogo extends StatefulWidget {
  const HxLogo({super.key, this.playing = false, this.height = 22});
  final bool playing;
  final double height;

  @override
  State<HxLogo> createState() => _HxLogoState();
}

class _HxLogoState extends State<HxLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  );

  void _sync() {
    final run =
        widget.playing &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (run && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!run && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(HxLogo old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final h = widget.height;
    final bw = h * 6 / 28;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        double scale(int i) {
          if (!widget.playing) return i == 1 ? 1 : 0.5;
          // Cada barra con su desfase (0, -0.4 s, -0.7 s), ease-in-out alternado.
          const delays = [0.0, 0.4, 0.7];
          var t = (_c.value + delays[i]) % 2;
          if (t > 1) t = 2 - t;
          return 0.3 + 0.7 * Curves.easeInOut.transform(t);
        }

        return SizedBox(
          height: h,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) SizedBox(width: bw * 4 / 6),
                Container(
                  width: bw,
                  height: h * scale(i),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(bw / 2),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Encabezado de sección de Ajustes (`SettingsView h2`): ícono 20 + title-m en primary.
class HxSectionTitle extends StatelessWidget {
  const HxSectionTitle(this.title, {super.key, this.icon});
  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      child: Row(
        children: [
          if (icon != null) ...[
            HxIcon(icon!, size: 20, color: cs.primary),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(title, style: HxType.titleM(cs.primary))),
        ],
      ),
    );
  }
}

/// Título de sección del inicio (`.home h2`): 22 px Medium.
class HxHomeHeading extends StatelessWidget {
  const HxHomeHeading(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: hxText(
                22,
                weight: FontWeight.w500,
                height: 1.45,
                color: cs.onSurface,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Tarjeta de Ajustes (`SettingsView .card`): surfaceContainer, radio 28, separadores
/// outline-variant entre elementos.
class HxSettingsCard extends StatelessWidget {
  const HxSettingsCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: HxRadius.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Container(height: 1, color: cs.outlineVariant),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Elemento de Ajustes (`.item`): etiqueta body-l, descripción body-m y un control.
class HxSettingsItem extends StatelessWidget {
  const HxSettingsItem({
    super.key,
    required this.label,
    this.description,
    this.child,
    this.trailing,
  });
  final String label;
  final String? description;
  final Widget? child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: HxType.bodyL(cs.onSurface)),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(description!, style: HxType.bodyM(cs.onSurfaceVariant)),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (trailing == null)
            text
          else
            Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: 16),
                trailing!,
              ],
            ),
          if (child != null) ...[const SizedBox(height: 14), child!],
        ],
      ),
    );
  }
}

/// Estado con ícono (`.status` de Ajustes): label-l, primary si está bien.
class HxStatus extends StatelessWidget {
  const HxStatus({
    super.key,
    required this.label,
    required this.icon,
    this.ok = false,
  });
  final String label;
  final IconData icon;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = ok ? cs.primary : cs.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        HxIcon(icon, size: 18, color: c, filled: true),
        const SizedBox(width: 6),
        Text(label, style: HxType.labelL(c)),
      ],
    );
  }
}

/// Fila al estilo de `TrackRow.svelte`: miniatura 48 (cuadrado → cookie9 si es la
/// actual), título Medium, subtítulo 14 px y acciones; la actual va en
/// secondaryContainer.
class HxListRow extends StatelessWidget {
  const HxListRow({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.current = false,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool current;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = current ? cs.onSecondaryContainer : cs.onSurface;
    final sub = current
        ? cs.onSecondaryContainer.withValues(alpha: 0.8)
        : cs.onSurfaceVariant;
    return AnimatedContainer(
      duration: HxMotion.dSpringFast,
      curve: HxMotion.standard,
      decoration: BoxDecoration(
        color: current ? cs.secondaryContainer : Colors.transparent,
        borderRadius: HxRadius.l,
      ),
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        children: [
          Expanded(
            child: HxSurface(
              onTap: onTap,
              contentColor: fg,
              shape: RoundedRectangleBorder(borderRadius: HxRadius.l),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    HxShapeTile(
                      shape: current ? M3Shape.cookie9 : M3Shape.square,
                      size: 48,
                      color: current ? cs.primary : cs.surfaceContainerHighest,
                      icon: icon,
                      iconColor: current ? cs.onPrimary : cs.onSurfaceVariant,
                      iconSize: 24,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: hxText(
                              16,
                              weight: FontWeight.w500,
                              color: fg,
                            ),
                          ),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: hxText(14, color: sub),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Riel de navegación de escritorio (`NavRail.svelte` >700 px): 96 px, logo arriba e
/// ítems con píldora 56×32.
class HxNavRail extends StatelessWidget {
  const HxNavRail({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
    this.playing = false,
  });
  final List<HxNavItem> items;
  final int index;
  final ValueChanged<int> onChanged;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 96,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Center(child: HxLogo(playing: playing, height: 28)),
            ),
            const SizedBox(height: 32),
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _railItem(cs, i),
            ],
          ],
        ),
      ),
    );
  }

  Widget _railItem(ColorScheme cs, int i) {
    final active = i == index;
    final it = items[i];
    return Semantics(
      selected: active,
      button: true,
      label: it.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(i),
        child: SizedBox(
          width: 80,
          child: Column(
            children: [
              SizedBox(
                width: 56,
                height: 32,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: active ? 1 : 0),
                        duration: HxMotion.dSpring,
                        curve: HxMotion.spring,
                        builder: (context, v, _) => Opacity(
                          opacity: v.clamp(0, 1),
                          child: Transform.scale(
                            scaleX: 0.3 + 0.7 * v,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: cs.secondaryContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: HxSurface(
                        onTap: () => onChanged(i),
                        contentColor: active
                            ? cs.onSecondaryContainer
                            : cs.onSurfaceVariant,
                        shape: const StadiumBorder(),
                        child: Center(
                          child: HxIcon(
                            it.icon,
                            filled: active,
                            color: active
                                ? cs.onSecondaryContainer
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                it.label,
                maxLines: 1,
                style: hxText(
                  12,
                  weight: active ? FontWeight.w700 : FontWeight.w500,
                  height: 1.45,
                  letterSpacingEm: 0.01,
                  color: active ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
