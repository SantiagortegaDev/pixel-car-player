import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx_layout.dart';

/// Movimiento de Harmonix v2 en el celular: entradas escalonadas, eje compartido entre
/// pestañas, fundido entre modos, sacudida de error y la pantalla de arranque.
///
/// Todas respetan `MediaQuery.disableAnimations` (que el modo celular fija según el
/// ajuste "Animaciones": Sistema / Completas / Reducidas). Ninguna usa `Timer`: los
/// retrasos van dentro de la curva del controlador, así que no dejan temporizadores
/// pendientes en las pruebas.
bool hxReduceMotion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// Entrada de una tarjeta o fila: sube 24 px y aparece (emphasized decelerate, 450 ms),
/// con un retraso de [index] × [step] (máx. [maxDelay]) para escalonar listas.
class HxEntrance extends StatefulWidget {
  const HxEntrance({
    super.key,
    required this.child,
    this.index = 0,
    this.step = const Duration(milliseconds: 45),
    this.maxDelay = const Duration(milliseconds: 360),
    this.duration = const Duration(milliseconds: 450),
    this.offset = 24,
    this.scale = false,
  });
  final Widget child;
  final int index;
  final Duration step;
  final Duration maxDelay;
  final Duration duration;
  final double offset;

  /// Además de subir, crece desde 92 % (para formas grandes y tarjetas destacadas).
  final bool scale;

  @override
  State<HxEntrance> createState() => _HxEntranceState();
}

class _HxEntranceState extends State<HxEntrance>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  late Animation<double> _t;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null || hxReduceMotion(context)) return;
    final delayUs = math.min(
      widget.step.inMicroseconds * widget.index,
      widget.maxDelay.inMicroseconds,
    );
    final total = delayUs + widget.duration.inMicroseconds;
    _c = AnimationController(
      vsync: this,
      duration: Duration(microseconds: total),
    )..forward();
    _t = CurvedAnimation(
      parent: _c!,
      curve: Interval(delayUs / total, 1, curve: HxMotion.emphasizedDecel),
    );
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_c == null) return widget.child;
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) {
        final v = _t.value;
        if (v >= 1) return child!;
        Widget w = Transform.translate(
          offset: Offset(0, widget.offset * (1 - v)),
          child: child,
        );
        if (widget.scale) w = Transform.scale(scale: 0.92 + 0.08 * v, child: w);
        return Opacity(opacity: v.clamp(0.0, 1.0), child: w);
      },
      child: widget.child,
    );
  }
}

/// Transición de eje compartido horizontal (MD3 "shared axis X") entre pestañas: la
/// nueva entra desde el lado hacia el que se navega y la vieja se va hacia el otro.
/// [child] debe tener una `Key` distinta por pestaña.
class HxSharedAxisSwitcher extends StatefulWidget {
  const HxSharedAxisSwitcher({
    super.key,
    required this.index,
    required this.child,
    this.duration = const Duration(milliseconds: 420),
  });
  final int index;
  final Widget child;
  final Duration duration;

  @override
  State<HxSharedAxisSwitcher> createState() => _HxSharedAxisSwitcherState();
}

class _HxSharedAxisSwitcherState extends State<HxSharedAxisSwitcher> {
  double _dir = 1;

  @override
  void didUpdateWidget(HxSharedAxisSwitcher old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _dir = widget.index > old.index ? 1 : -1;
  }

  @override
  Widget build(BuildContext context) {
    final reduce = hxReduceMotion(context);
    final current = widget.child.key;
    final dir = _dir;
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : widget.duration,
      layoutBuilder: (cur, prev) =>
          Stack(fit: StackFit.expand, children: [...prev, ?cur]),
      transitionBuilder: (child, a) {
        final incoming = child.key == current;
        return AnimatedBuilder(
          animation: a,
          child: child,
          builder: (context, child) {
            final v = a.value;
            // Entrante: 0→1 (aparece en 30–100 %). Saliente: 1→0 (se va en 100–65 %).
            final double opacity;
            final double dx;
            if (incoming) {
              opacity = const Interval(
                0.3,
                1,
                curve: HxMotion.emphasizedDecel,
              ).transform(v);
              dx = 30 * dir * (1 - HxMotion.emphasizedDecel.transform(v));
            } else {
              opacity = const Interval(0.65, 1).transform(v);
              dx = -30 * dir * (1 - HxMotion.emphasizedDecel.transform(v));
            }
            return IgnorePointer(
              ignoring: !incoming,
              child: Opacity(
                opacity: opacity,
                child: Transform.translate(offset: Offset(dx, 0), child: child),
              ),
            );
          },
        );
      },
      child: widget.child,
    );
  }
}

/// Fundido con escala (MD3 "fade through" / eje Z) para cambiar de pantalla completa,
/// p. ej. de la selección de modo al modo elegido.
class HxFadeThroughSwitcher extends StatelessWidget {
  const HxFadeThroughSwitcher({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 520),
  });
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final current = child.key;
    return AnimatedSwitcher(
      duration: hxReduceMotion(context) ? Duration.zero : duration,
      layoutBuilder: (cur, prev) =>
          Stack(fit: StackFit.expand, children: [...prev, ?cur]),
      transitionBuilder: (c, a) {
        final incoming = c.key == current;
        return AnimatedBuilder(
          animation: a,
          child: c,
          builder: (context, child) {
            final v = a.value;
            final opacity = incoming
                ? const Interval(0.35, 1).transform(v)
                : const Interval(0.6, 1).transform(v);
            final s = incoming
                ? 0.92 + 0.08 * HxMotion.emphasizedDecel.transform(v)
                : 1.06 - 0.06 * v;
            return IgnorePointer(
              ignoring: !incoming,
              child: Opacity(
                opacity: opacity,
                child: Transform.scale(scale: s, child: child),
              ),
            );
          },
        );
      },
      child: child,
    );
  }
}

/// Sacude [child] a los lados cuando cambia [trigger] (código incorrecto).
class HxShake extends StatefulWidget {
  const HxShake({super.key, required this.trigger, required this.child});
  final int trigger;
  final Widget child;

  @override
  State<HxShake> createState() => _HxShakeState();
}

class _HxShakeState extends State<HxShake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );

  @override
  void didUpdateWidget(HxShake old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && !hxReduceMotion(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      final t = _c.value;
      // Oscilación amortiguada: 3,5 vaivenes que se apagan.
      final dx = math.sin(t * math.pi * 7) * 12 * (1 - t);
      return Transform.translate(offset: Offset(dx, 0), child: child);
    },
  );
}

/// Pantalla de arranque: el logo de Harmonix dentro de una cookie que se transforma
/// (cookie4 → cookie9 → softBurst) mientras gira; luego la forma crece, se desvanece
/// y aparece el contenido (que se construye recién a mitad de camino, para que sus
/// entradas escalonadas se vean).
class HxSplash extends StatefulWidget {
  const HxSplash({
    super.key,
    required this.child,
    this.enabled = true,
    this.duration = const Duration(milliseconds: 1000),
  });
  final Widget child;
  final bool enabled;
  final Duration duration;

  @override
  State<HxSplash> createState() => _HxSplashState();
}

class _HxSplashState extends State<HxSplash>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  bool _done = false;

  static const _reveal = 0.5;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c != null || _done) return;
    if (!widget.enabled || hxReduceMotion(context)) {
      _done = true;
      return;
    }
    _c = AnimationController(vsync: this, duration: widget.duration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          setState(() => _done = true);
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // La estructura (Stack con el contenido primero) no cambia al terminar, para que el
    // contenido conserve su estado.
    return AnimatedBuilder(
      animation: _c ?? kAlwaysCompleteAnimation,
      builder: (context, _) {
        final t = _done ? 1.0 : _c!.value;
        if (_done) {
          return Stack(fit: StackFit.expand, children: [widget.child]);
        }
        // 0–50 %: entra y se transforma. 50–100 %: crece y se desvanece.
        final inT = HxMotion.emphasizedDecel.transform(
          (t / _reveal).clamp(0, 1),
        );
        final outT = HxMotion.emphasizedAccel.transform(
          ((t - _reveal) / (1 - _reveal)).clamp(0, 1),
        );
        final m = (t / _reveal).clamp(0.0, 1.0) * 2;
        final shape = m < 1
            ? M3Shape.lerp(
                M3Shape.cookie4,
                M3Shape.cookie9,
                HxMotion.spring.transform(m),
              )
            : M3Shape.lerp(
                M3Shape.cookie9,
                M3Shape.softBurst,
                HxMotion.spring.transform(m - 1),
              );
        final size = 112 * (0.6 + 0.4 * inT) * (1 + 0.5 * outT);
        return Stack(
          fit: StackFit.expand,
          children: [
            if (t >= _reveal) widget.child,
            IgnorePointer(
              child: Opacity(
                opacity: 1 - outT,
                child: ColoredBox(
                  color: cs.surface,
                  child: Center(
                    child: Transform.rotate(
                      angle: (t * 0.6 - 0.15) * math.pi,
                      child: SizedBox.square(
                        dimension: size,
                        child: ClipPath(
                          clipper: M3ShapeClipper(shape),
                          child: ColoredBox(
                            color: cs.primaryContainer,
                            child: Center(
                              child: Transform.rotate(
                                angle: -(t * 0.6 - 0.15) * math.pi,
                                child: Opacity(
                                  opacity: inT.clamp(0.0, 1.0),
                                  child: HxLogo(
                                    playing: true,
                                    height: size * 0.32,
                                  ),
                                ),
                              ),
                            ),
                          ),
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
    );
  }
}
