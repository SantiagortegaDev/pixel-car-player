import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pixel_car_player/car/custom/car_custom_scope.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';

/// Entrada de un componente la primera vez que aparece: fundido + sube [offset] px con la
/// curva enfatizada de MD3 (sin rebote). Con [index] se escalona ([CarAnimOpts.staggerMs]);
/// sin él, los que aparecen en el mismo cuadro se escalonan solos por orden de llegada
/// (secciones de Configuración). Con animaciones reducidas aparece directo.
class HxEntrance extends StatefulWidget {
  const HxEntrance({
    super.key,
    required this.child,
    this.index,
    this.enabled = true,
    this.offset = 18,
    this.duration,
    this.stagger,
  });

  final Widget child;

  /// Posición en el escalonado (`null` = automática por cuadro).
  final int? index;
  final bool enabled;
  final double offset;
  final Duration? duration;
  final Duration? stagger;

  @override
  State<HxEntrance> createState() => _HxEntranceState();
}

/// Cuántas entradas automáticas arrancaron en este cuadro (para escalonarlas).
int _frameEntrances = 0;
bool _frameResetScheduled = false;

int _nextAutoIndex() {
  if (!_frameResetScheduled) {
    _frameResetScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _frameEntrances = 0;
      _frameResetScheduled = false;
    });
  }
  return _frameEntrances++;
}

class _HxEntranceState extends State<HxEntrance> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Animation<double>? _a;
  Timer? _delay;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    final cfg = CarCustomScope.of(context);
    if (!widget.enabled || carReducedMotion(context, cfg)) return;
    final o = cfg.anim;
    final c = _c = AnimationController(
      vsync: this,
      duration: widget.duration ?? Duration(milliseconds: o.entranceMs),
    );
    _a = CurvedAnimation(parent: c, curve: HxMotion.emphasizedDecel);
    final i = widget.index ?? _nextAutoIndex();
    final step = widget.stagger ?? Duration(milliseconds: o.staggerMs);
    final wait = step * i.clamp(0, 10);
    if (wait == Duration.zero) {
      c.forward();
    } else {
      _delay = Timer(wait, () {
        if (mounted) c.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = _a;
    if (a == null) return widget.child;
    return AnimatedBuilder(
      animation: a,
      builder: (_, child) => Opacity(
        opacity: a.value.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, widget.offset * (1 - a.value)), child: child),
      ),
      child: widget.child,
    );
  }
}

/// Transición entre pantallas para un [AnimatedSwitcher] (o una ruta). [incoming] = es la
/// pantalla que entra (la que sale recorre la animación al revés).
Widget carScreenTransition(
  CarScreenTransition kind,
  Animation<double> animation,
  Widget child, {
  required bool incoming,
}) {
  final a = CurvedAnimation(
    parent: animation,
    curve: HxMotion.emphasizedDecel,
    reverseCurve: HxMotion.emphasizedAccel,
  );
  switch (kind) {
    case CarScreenTransition.none:
      return child;
    case CarScreenTransition.fade:
      return FadeTransition(opacity: a, child: child);
    case CarScreenTransition.sharedX || CarScreenTransition.sharedY:
      final x = kind == CarScreenTransition.sharedX;
      return AnimatedBuilder(
        animation: a,
        builder: (_, child) {
          final d = 36 * (1 - a.value) * (incoming ? 1 : -1);
          // Shared axis de MD3: la que sale se va antes (primer 35 %), la nueva entra después.
          final t = incoming ? ((a.value - 0.3) / 0.7).clamp(0.0, 1.0) : ((a.value - 0.35) / 0.65).clamp(0.0, 1.0);
          return Opacity(
            opacity: t,
            child: Transform.translate(offset: x ? Offset(d, 0) : Offset(0, d), child: child),
          );
        },
        child: child,
      );
    case CarScreenTransition.zoom:
      return AnimatedBuilder(
        animation: a,
        builder: (_, child) => Opacity(
          opacity: a.value.clamp(0.0, 1.0),
          child: Transform.scale(scale: incoming ? 0.92 + 0.08 * a.value : 1.06 - 0.06 * a.value, child: child),
        ),
        child: child,
      );
  }
}

/// Cambia entre pantallas ([screenKey]) con la transición configurada.
class CarScreenSwitcher extends StatelessWidget {
  const CarScreenSwitcher({super.key, required this.screenKey, required this.child, this.reduced = false});
  final Key screenKey;
  final Widget child;
  final bool reduced;

  @override
  Widget build(BuildContext context) {
    final o = CarCustomScope.of(context).anim;
    final kind = reduced ? CarScreenTransition.none : o.transition;
    return AnimatedSwitcher(
      duration: kind == CarScreenTransition.none ? Duration.zero : Duration(milliseconds: o.transitionMs),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [
          for (final p in previous) IgnorePointer(child: p),
          ?current,
        ],
      ),
      transitionBuilder: (child, animation) =>
          carScreenTransition(kind, animation, child, incoming: child.key == screenKey),
      child: KeyedSubtree(key: screenKey, child: child),
    );
  }
}
