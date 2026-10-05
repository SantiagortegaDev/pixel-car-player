import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/controllers/pairing_controller.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx.dart';

/// Muestra el diálogo de emparejamiento. Devuelve true si se emparejó.
Future<bool> showPairingDialog(
  BuildContext context,
  PairingController c,
) async {
  final r = await showHxDialog<bool>(
    context,
    dismissible: false,
    builder: (_) => PairingDialog(c: c),
  );
  return r == true;
}

/// "Empareja con «carro»": seis casillas para el código que muestra la tableta. Se
/// envía solo al completar los 6 dígitos; si falla, las casillas se sacuden y se
/// muestra el motivo; si sale bien, la forma pasa a un check y el diálogo se cierra.
class PairingDialog extends StatefulWidget {
  const PairingDialog({super.key, required this.c});
  final PairingController c;

  @override
  State<PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<PairingDialog>
    with SingleTickerProviderStateMixin {
  final _code = TextEditingController();
  final _focus = FocusNode();
  late int _fails = widget.c.failCount;
  late PairRequest? _req = widget.c.pending;
  late String _carName = widget.c.pending?.carName ?? 'la pantalla del carro';

  /// Tras el éxito: muestra el check ~1 s y cierra.
  late final AnimationController _done =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1100),
      )..addStatusListener((s) {
        if (s == AnimationStatus.completed && mounted) {
          widget.c.acknowledgeSuccess();
          Navigator.of(context).pop(true);
        }
      });

  PairingController get c => widget.c;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    _code.addListener(_onCode);
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    _code.dispose();
    _focus.dispose();
    _done.dispose();
    super.dispose();
  }

  bool _typedAfterFail = true;

  void _onCode() {
    if (!_typedAfterFail && _code.text.isNotEmpty) {
      setState(() => _typedAfterFail = true);
    }
  }

  void _onChange() {
    if (!mounted) return;
    if (c.failCount != _fails) {
      _fails = c.failCount;
      HxHaptics.error();
      _typedAfterFail = false;
      _code.clear();
      _focus.requestFocus();
    }
    // Llegó otro pedido mientras estaba abierto (código nuevo en la tableta).
    if (c.pending != null && !identical(c.pending, _req)) {
      _req = c.pending;
      _carName = _req!.carName;
      _code.clear();
    }
    if (c.phase == PairPhase.success &&
        !_done.isAnimating &&
        !_done.isCompleted) {
      HxHaptics.confirm();
      _done.forward();
    }
    setState(() {});
  }

  void _submit() {
    if (_code.text.length == 6) c.submit(_code.text);
  }

  void _cancel() {
    c.dismiss();
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final phase = c.phase;
    final ok = phase == PairPhase.success;
    final failed = phase == PairPhase.failed && !_typedAfterFail;
    final sending = phase == PairPhase.submitting;

    final (M3Shape shape, Color bg, Color fg, IconData icon) = ok
        ? (M3Shape.sunny, cs.primary, cs.onPrimary, Symbols.check_rounded)
        : failed
        ? (
            M3Shape.softBurst,
            cs.errorContainer,
            cs.onErrorContainer,
            Symbols.lock_rounded,
          )
        : (
            M3Shape.cookie9,
            cs.primaryContainer,
            cs.onPrimaryContainer,
            Symbols.password_rounded,
          );

    final (String status, Color statusColor) = ok
        ? ('¡Listo! Emparejado con «$_carName»', cs.primary)
        : failed
        ? (PairingController.reasonText(c.failReason), cs.error)
        : sending
        ? ('Verificando el código…', cs.onSurfaceVariant)
        : ('El código cambia cada 2 minutos.', cs.onSurfaceVariant);

    return HxDialog(
      title: 'Emparejar con el carro',
      text:
          'Empareja con «$_carName»: escribe el código de 6 dígitos que aparece en '
          'la pantalla del carro',
      leading: AnimatedScale(
        scale: ok ? 1.12 : 1,
        duration: HxMotion.dSpring,
        curve: HxMotion.spring,
        child: HxShapeTile(
          shape: shape,
          size: 72,
          color: bg,
          icon: icon,
          iconColor: fg,
          iconSize: 32,
          spin: sending || ok,
        ),
      ),
      actions: [
        HxButton(
          label: 'Ahora no',
          kind: HxButtonKind.text,
          onPressed: ok ? null : _cancel,
        ),
        HxButton(
          label: 'Emparejar',
          icon: Symbols.link_rounded,
          onPressed: _code.text.length == 6 && !sending && !ok ? _submit : null,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HxShake(
            trigger: _fails,
            child: HxCodeInput(
              controller: _code,
              focusNode: _focus,
              enabled: !sending && !ok,
              error: failed,
              success: ok,
              onChanged: (_) => setState(() {}),
              onCompleted: (_) => _submit(),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 44,
            child: AnimatedSwitcher(
              duration: hxReduceMotion(context)
                  ? Duration.zero
                  : HxMotion.dFxSlow,
              switchInCurve: HxMotion.emphasizedDecel,
              transitionBuilder: (w, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 0.3),
                    end: Offset.zero,
                  ).animate(a),
                  child: w,
                ),
              ),
              child: Row(
                key: ValueKey(status),
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (sending) ...[
                    HxLoadingIndicator(size: 20, color: cs.primary),
                    const SizedBox(width: 8),
                  ] else if (failed) ...[
                    HxIcon(
                      Symbols.error_rounded,
                      size: 18,
                      color: cs.error,
                      filled: true,
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      status,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: (failed || ok ? HxType.labelL : HxType.bodyM)(
                        statusColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
