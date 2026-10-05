import 'package:flutter/material.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx_base.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx_controls.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx_motion.dart';

/// Abre un diálogo de Harmonix (`Dialog.svelte`): velo scrim al 32 %, tarjeta que crece
/// desde 90 % con emphasized decelerate.
///
/// El diálogo vive en el Navigator de la app (por encima del tema animado del modo
/// celular), así que se copian el `Theme` y los ajustes de `MediaQuery` (tamaño de texto,
/// animaciones) del [context] que lo abre.
Future<T?> showHxDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  final theme = Theme.of(context);
  final mq = MediaQuery.of(context);
  final reduce = hxReduceMotion(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: 'Cerrar',
    barrierColor: theme.colorScheme.scrim.withValues(alpha: 0.32),
    transitionDuration: reduce ? Duration.zero : HxMotion.dSpringFast,
    pageBuilder: (ctx, a, b) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(
        textScaler: mq.textScaler,
        disableAnimations: mq.disableAnimations,
      ),
      child: Theme(
        data: theme,
        child: Builder(builder: builder),
      ),
    ),
    transitionBuilder: (ctx, a, b, child) {
      final v = HxMotion.emphasizedDecel.transform(a.value);
      return Opacity(
        opacity: a.value.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.9 + 0.1 * v, child: child),
      );
    },
  );
}

/// Contenido estándar de un diálogo: [leading] (forma con ícono), título headline-s,
/// texto, [child] y acciones alineadas a la derecha.
class HxDialog extends StatelessWidget {
  const HxDialog({
    super.key,
    required this.title,
    this.leading,
    this.text,
    this.child,
    this.actions = const [],
    this.maxWidth = 440,
  });
  final Widget? leading;
  final String title;
  final String? text;
  final Widget? child;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Material(
                color: cs.surfaceContainerHigh,
                shape: RoundedRectangleBorder(borderRadius: HxRadius.xl),
                clipBehavior: Clip.antiAlias,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (leading != null) ...[
                        Center(child: leading!),
                        const SizedBox(height: 16),
                      ],
                      Text(
                        title,
                        textAlign: leading != null
                            ? TextAlign.center
                            : TextAlign.start,
                        style: HxType.headlineS(cs.onSurface),
                      ),
                      if (text != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          text!,
                          textAlign: leading != null
                              ? TextAlign.center
                              : TextAlign.start,
                          style: HxType.bodyM(cs.onSurfaceVariant),
                        ),
                      ],
                      if (child != null) ...[
                        const SizedBox(height: 20),
                        child!,
                      ],
                      if (actions.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          runSpacing: 8,
                          children: actions,
                        ),
                      ],
                    ],
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

/// Diálogo de confirmación simple. Devuelve true si se aceptó.
Future<bool> confirmHx(
  BuildContext context, {
  required String title,
  required String text,
  required String confirm,
  String cancel = 'Cancelar',
}) async {
  final r = await showHxDialog<bool>(
    context,
    builder: (ctx) => HxDialog(
      title: title,
      text: text,
      actions: [
        HxButton(
          label: cancel,
          kind: HxButtonKind.text,
          onPressed: () => Navigator.pop(ctx, false),
        ),
        HxButton(label: confirm, onPressed: () => Navigator.pop(ctx, true)),
      ],
    ),
  );
  return r == true;
}

/// Aviso flotante (snackbar de Harmonix: inverseSurface, radio 8).
void showHxSnack(BuildContext context, String text, {bool error = false}) {
  final cs = Theme.of(context).colorScheme;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (error) ...[
              Icon(
                Icons.error_outline_rounded,
                size: 20,
                color: cs.onInverseSurface,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(text, style: HxType.bodyM(cs.onInverseSurface)),
            ),
          ],
        ),
      ),
    );
}
