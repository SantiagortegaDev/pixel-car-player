import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/data/link/link_auth.dart';

/// Muestra el código de emparejamiento en grande mientras [pairing] no sea `null`
/// (se cierra solo, tras la animación de éxito / error). [onCancel] = botón "Cancelar".
Future<void> showPairingDialog(
  BuildContext context, {
  required ValueListenable<PairingPrompt?> pairing,
  required VoidCallback onCancel,
  bool reduced = false,
}) {
  final theme = Theme.of(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Código de emparejamiento',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: reduced ? Duration.zero : const Duration(milliseconds: 500),
    routeSettings: const RouteSettings(name: 'car-pairing'),
    pageBuilder: (ctx, _, _) => Theme(
      data: theme,
      child: PairingDialog(pairing: pairing, onCancel: onCancel, reduced: reduced),
    ),
    transitionBuilder: (_, a, _, child) {
      final c = CurvedAnimation(parent: a, curve: HxMotion.emphasizedDecel, reverseCurve: HxMotion.emphasizedAccel);
      return FadeTransition(
        opacity: c,
        child: ScaleTransition(scale: Tween(begin: 0.88, end: 1.0).animate(c), child: child),
      );
    },
  );
}

class PairingDialog extends StatefulWidget {
  const PairingDialog({super.key, required this.pairing, required this.onCancel, this.reduced = false});
  final ValueListenable<PairingPrompt?> pairing;
  final VoidCallback onCancel;
  final bool reduced;

  @override
  State<PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<PairingDialog> with SingleTickerProviderStateMixin {
  Timer? _tick;
  PairingPrompt? _last;
  bool _popped = false;

  /// Forma que se transforma de galleta a círculo al emparejar.
  late final AnimationController _ok = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void initState() {
    super.initState();
    _last = widget.pairing.value;
    widget.pairing.addListener(_onChange);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _onChange() {
    final v = widget.pairing.value;
    if (v == null) {
      _close();
      return;
    }
    if (v.phase == PairingPhase.success && _last?.phase != PairingPhase.success) {
      widget.reduced ? _ok.value = 1 : _ok.forward(from: 0);
    }
    setState(() => _last = v);
  }

  void _close() {
    if (_popped || !mounted) return;
    _popped = true;
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    widget.pairing.removeListener(_onChange);
    _tick?.cancel();
    _ok.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _last;
    final cs = context.cs;
    final tt = context.tt;
    if (p == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final left = p.expiresAt.difference(now);
    final secs = math.max(0, left.inSeconds);
    final frac = (left.inMilliseconds / LinkAuth.codeTtl.inMilliseconds).clamp(0.0, 1.0);
    final mmss = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
    final (IconData icon, String title, String text) = switch (p.phase) {
      PairingPhase.showing => (
        Symbols.phonelink_lock_rounded,
        'Código de emparejamiento',
        'Escríbelo en el celular «${p.phoneName}»',
      ),
      PairingPhase.success => (
        Symbols.check_rounded,
        '¡Emparejado!',
        '«${p.phoneName}» ya es de confianza. La próxima vez se conecta sin código.',
      ),
      PairingPhase.failed => (
        Symbols.block_rounded,
        'Demasiados intentos',
        'El código se anuló. Vuelve a pedir uno desde el celular.',
      ),
      PairingPhase.expired => (Symbols.timer_off_rounded, 'El código venció', 'Pide uno nuevo desde el celular.'),
    };
    final showing = p.phase == PairingPhase.showing;
    final success = p.phase == PairingPhase.success;
    return SafeArea(
      child: Center(
        child: LayoutBuilder(
          builder: (context, c) {
            final w = math.min(720.0, c.maxWidth - 32);
            final codeSize = (math.min(w / 4.6, c.maxHeight * 0.2)).clamp(40.0, 120.0);
            return ConstrainedBox(
              constraints: BoxConstraints(maxWidth: w, maxHeight: c.maxHeight - 32),
              child: Material(
                color: cs.surfaceContainerHigh,
                shape: RoundedRectangleBorder(borderRadius: HxRadius.xl),
                elevation: 12,
                shadowColor: Colors.black.withValues(alpha: 0.6),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 28, 32, 24),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: w - 64,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _Badge(icon: icon, ok: _ok, success: success, error: !showing && !success),
                          const SizedBox(height: 16),
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            style: hxWeight(tt.headlineSmall, 500).copyWith(color: cs.onSurface),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            text,
                            textAlign: TextAlign.center,
                            style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant, fontSize: 18),
                          ),
                          AnimatedSize(
                            duration: widget.reduced ? Duration.zero : HxMotion.dSpring,
                            curve: HxMotion.emphasizedDecel,
                            child: showing
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 22),
                                    child: Column(
                                      children: [
                                        Text(
                                          LinkAuth.formatCode(p.code),
                                          key: const ValueKey('pair-code'),
                                          style: AppTheme.numStyle(context, size: codeSize).copyWith(
                                            color: cs.primary,
                                            letterSpacing: codeSize * 0.08,
                                            fontWeight: FontWeight.w600,
                                            fontVariations: const [FontVariation('wght', 600)],
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        SizedBox(
                                          width: math.min(360, w - 64),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(4),
                                            child: LinearProgressIndicator(
                                              value: frac,
                                              minHeight: 8,
                                              color: cs.primary,
                                              backgroundColor: cs.secondaryContainer,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          p.attempts > 0
                                              ? 'Vence en $mmss · intentos fallidos: ${p.attempts}/${LinkAuth.maxAttempts}'
                                              : 'Vence en $mmss',
                                          style: tt.labelLarge?.copyWith(
                                            color: p.attempts > 0 ? cs.error : cs.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : const SizedBox(width: double.infinity),
                          ),
                          const SizedBox(height: 20),
                          Align(
                            alignment: Alignment.centerRight,
                            child: HxButton(
                              label: showing ? 'Cancelar' : 'Cerrar',
                              kind: HxButtonKind.text,
                              height: 48,
                              onTap: () {
                                widget.onCancel();
                                _close();
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Insignia: galleta de 9 lados en primaryContainer; al emparejar se vuelve círculo y el
/// ícono pasa a un check (sin rebote).
class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.ok, required this.success, required this.error});
  final IconData icon;
  final Animation<double> ok;
  final bool success;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return AnimatedBuilder(
      animation: ok,
      builder: (_, _) {
        final t = success ? HxMotion.emphasizedDecel.transform(ok.value) : 0.0;
        final bg = error ? cs.errorContainer : Color.lerp(cs.primaryContainer, cs.primary, t)!;
        final fg = error ? cs.onErrorContainer : Color.lerp(cs.onPrimaryContainer, cs.onPrimary, t)!;
        return Transform.rotate(
          angle: t * math.pi / 4,
          child: SizedBox.square(
            dimension: 84,
            child: ClipPath(
              clipper: M3ShapeClipper(M3Shape.lerp(M3Shape.cookie9, M3Shape.circle, t)),
              child: ColoredBox(
                color: bg,
                child: Center(
                  child: Transform.rotate(
                    angle: -t * math.pi / 4,
                    child: HxIcon(icon, size: 40, fill: true, color: fg),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
