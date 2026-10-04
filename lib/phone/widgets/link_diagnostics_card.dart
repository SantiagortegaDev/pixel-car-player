import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/phone_controller.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx.dart';

/// Tarjeta "Diagnóstico de conexión": lista de pasos evaluada en vivo, redes Wi-Fi
/// y las últimas líneas del registro del enlace. Se refresca cada 3 s mientras está
/// en pantalla.
class LinkDiagnosticsCard extends StatefulWidget {
  const LinkDiagnosticsCard({super.key, required this.c});
  final PhoneController c;

  @override
  State<LinkDiagnosticsCard> createState() => _LinkDiagnosticsCardState();
}

class _LinkDiagnosticsCardState extends State<LinkDiagnosticsCard> {
  Timer? _timer;
  PhoneController get c => widget.c;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }

  void _refresh() {
    c.refreshLink();
    c.refreshWifi();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.of(context);
    final cs = Theme.of(context).colorScheme;
    await Clipboard.setData(ClipboardData(text: c.linkLines.join('\n')));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: cs.inverseSurface,
          shape: RoundedRectangleBorder(borderRadius: HxRadius.m),
          content: Text(
            'Registro copiado',
            style: HxType.bodyM(cs.onInverseSurface),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final nets = c.linkNetworks;
        final wifiNet = nets.isEmpty ? null : nets.first;
        final wifiOk = c.wifiConnected || nets.isNotEmpty;
        final noInternet = wifiNet != null && wifiNet['hasInternet'] == false;
        final ip = wifiNet == null ? null : _s(wifiNet['ip']);
        final gw = wifiNet == null ? null : _s(wifiNet['gateway']);
        final detail = [
          if (c.wifiSsid != null) '«${c.wifiSsid}»',
          if (ip != null) 'IP $ip',
          if (gw != null) 'puerta $gw',
        ].join(' · ');
        final s = c.status;
        return HxSettingsCard(
          children: [
            _Step(
              ok: wifiOk,
              title: 'Wi-Fi conectado',
              detail: detail.isEmpty ? null : detail,
              hint:
                  'Une el celular al hotspot de la tableta (Ajustes de Wi-Fi).',
              chip: noInternet
                  ? const HxChip(
                      label: 'Sin internet: normal en el hotspot del carro',
                      icon: Symbols.warning_rounded,
                    )
                  : null,
            ),
            _Step(
              ok: s.running,
              title: 'Transmisor activo',
              hint: 'Enciende el transmisor en Inicio.',
            ),
            _Step(
              ok: s.clients.isNotEmpty,
              title: 'Pantalla conectada',
              detail: s.clients.isEmpty
                  ? null
                  : s.clients.map((e) => e.device).join(', '),
              hint: 'Abre la app en la tableta; si no conecta, escribe la IP del carro arriba.',
            ),
            _Step(
              ok: s.session != null,
              title: 'Enviando canción',
              detail: s.session?.title,
              hint: 'Reproduce algo en la app de música elegida.',
            ),
            HxSettingsItem(
              label: 'Redes',
              child: nets.isEmpty
                  ? Text(
                      'Sin redes Wi-Fi detectadas.',
                      style: HxType.bodyM(cs.onSurfaceVariant),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [for (final n in nets) _NetRow(n)],
                    ),
            ),
            HxSettingsItem(
              label: 'Registro',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: HxRadius.m,
                    ),
                    child: c.linkLines.isEmpty
                        ? Text(
                            'Sin registro todavía.',
                            style: HxType.bodyM(cs.onSurfaceVariant),
                          )
                        : SingleChildScrollView(
                            reverse: true,
                            child: SelectableText(
                              c.linkLines.join('\n'),
                              style: HxType.bodyM(cs.onSurface).copyWith(
                                fontFamily: AppTheme.fontNum,
                                fontSize: 11.5,
                                height: 1.45,
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      HxButton(
                        label: 'Actualizar',
                        icon: Symbols.refresh_rounded,
                        onPressed: _refresh,
                      ),
                      HxButton(
                        label: 'Copiar registro',
                        kind: HxButtonKind.tonal,
                        icon: Symbols.content_copy_rounded,
                        onPressed: _copy,
                      ),
                      HxButton(
                        label: 'Borrar',
                        kind: HxButtonKind.text,
                        icon: Symbols.delete_rounded,
                        onPressed: c.clearLink,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

String? _s(Object? v) {
  final t = v == null ? '' : '$v'.trim();
  return t.isEmpty ? null : t;
}

class _Step extends StatelessWidget {
  const _Step({
    required this.ok,
    required this.title,
    required this.hint,
    this.detail,
    this.chip,
  });
  final bool ok;
  final String title;
  final String hint;
  final String? detail;
  final Widget? chip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sub = ok ? detail : hint;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HxIcon(
            ok ? Symbols.check_circle_rounded : Symbols.cancel_rounded,
            size: 22,
            filled: true,
            color: ok ? cs.primary : cs.error,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: HxType.bodyL(cs.onSurface)),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub, style: HxType.bodyM(cs.onSurfaceVariant)),
                ],
                if (ok && chip != null) ...[const SizedBox(height: 8), chip!],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NetRow extends StatelessWidget {
  const _NetRow(this.n);
  final Map<String, dynamic> n;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = _s(n['name']) ?? _s(n['iface']) ?? 'Red';
    final parts = [
      if (_s(n['ip']) != null) 'IP ${_s(n['ip'])}',
      if (_s(n['gateway']) != null) 'puerta ${_s(n['gateway'])}',
      n['hasInternet'] == true ? 'con internet' : 'sin internet',
      if (n['isDefault'] == true) 'predeterminada',
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: name, style: HxType.bodyM(cs.onSurface)),
            TextSpan(
              text: '  ${parts.join(' · ')}',
              style: HxType.bodyM(cs.onSurfaceVariant)
                  .copyWith(fontFamily: AppTheme.fontNum, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
