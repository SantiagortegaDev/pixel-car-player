import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/car/car_controller.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/car/settings/settings_controls.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/data/bridge/native_bridge.dart';
import 'package:pixel_car_player/data/demo/demo_source.dart';
import 'package:pixel_car_player/data/link/car_link_client.dart';

/// Configuración → Diagnóstico: pasos para conectar (evaluados en vivo), estado del enlace,
/// redes, beacons escuchados, intentos y registro (Dart + nativo).
class DiagnosticsSettings extends StatefulWidget {
  const DiagnosticsSettings({super.key, required this.c});
  final CarController c;

  @override
  State<DiagnosticsSettings> createState() => _DiagnosticsSettingsState();
}

class _DiagnosticsSettingsState extends State<DiagnosticsSettings> {
  Timer? _timer;
  List<String> _native = const [];

  CarController get c => widget.c;
  LinkDiagnostics get d => c.link.diag;
  NativeBridge get _bridge => NativeBridge.instance;

  @override
  void initState() {
    super.initState();
    // `?diag=sample` en web: datos de ejemplo para las capturas.
    if (kIsWeb && Uri.base.queryParameters['diag'] == 'sample' && d.attempts.isEmpty) fillDemoDiagnostics(d);
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  Future<void> _poll() async {
    if (!(kIsWeb && Uri.base.queryParameters['diag'] == 'sample')) await c.link.refreshNetworks();
    final m = await _bridge.getLinkDiagnostics();
    if (!mounted) return;
    setState(() => _native = (m['lines'] as List?)?.cast<String>() ?? const []);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final st = c.link.status.value;
    final ok = await copyText(
      d.export(
        nativeLines: _native,
        header:
            'Pixel Car Player — diagnóstico ${DateTime.now().toIso8601String()}\n'
            'Estado: $st · id tableta: ${c.link.installId ?? '-'} · id celular: ${c.link.peerId ?? '-'}',
      ),
    );
    if (mounted) showHxSnack(context, ok ? 'Registro copiado al portapapeles.' : 'No se pudo copiar.');
  }

  Future<void> _clear() async {
    d.clear();
    await _bridge.clearLinkDiagnostics();
    if (!mounted) return;
    setState(() => _native = const []);
    showHxSnack(context, 'Registro borrado.');
  }

  Future<void> _retry() async {
    await c.connectNow();
    if (mounted) showHxSnack(context, c.demo ? 'En modo demo no se conecta.' : 'Reintentando…');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([d, c.link.status, c.hotspot]),
      builder: (context, _) {
        final st = c.link.status.value;
        final now = DateTime.now();
        final steps = evaluateLinkSteps(
          now: now,
          networks: d.networks,
          hotspotOn: c.hotspot.info.enabled,
          connected: st.isConnected,
          listening: d.listeningPort != null || !c.linkRunning,
          lastBeaconAt: d.lastBeaconAt,
          lastInboundAt: d.lastInboundAt,
          connectedAt: d.connectedAt,
          lastTrackAt: d.lastTrackAt,
          failedStreak: d.failedStreak,
          device: st.device,
          transport: st.transport,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSection(
              icon: Symbols.checklist_rounded,
              title: 'Pasos para conectar',
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [for (var i = 0; i < steps.length; i++) _StepTile(n: i + 1, step: steps[i])],
                  ),
                ),
              ],
            ),
            SettingsSection(
              icon: Symbols.monitor_heart_rounded,
              title: 'Estado',
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: SettingsStatus(
                    ok: st.isConnected,
                    text: switch (st.phase) {
                      LinkPhase.connected =>
                        'Conectado a ${st.device} por ${st.transport == 'bt' ? 'Bluetooth' : 'Wi-Fi'} (${st.address}) · '
                            '${st.inbound ? 'el celular marcó' : 'la tableta marcó'}',
                      LinkPhase.searching => 'Buscando al celular…',
                      LinkPhase.disconnected => c.demo ? 'Modo demo: no se busca al celular' : 'Sin conexión',
                    },
                  ),
                ),
                _Kv(
                  'Escucha (el celular marca aquí)',
                  d.listeningPort == null ? 'no activa' : 'TCP ${d.listeningPort}',
                ),
                _Kv(
                  'Avisos enviados (car_beacon)',
                  d.beaconsSent == 0
                      ? 'ninguno'
                      : '${d.beaconsSent} · último hace ${_age(now, d.lastBeaconSentAt)}',
                ),
                _Kv('Id de esta tableta', c.link.installId ?? '—'),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      HxButton(
                        label: 'Reintentar ahora',
                        icon: Symbols.sync_rounded,
                        height: 48,
                        onTap: c.demo ? null : _retry,
                      ),
                      HxButton(
                        label: 'Copiar registro',
                        icon: Symbols.content_copy_rounded,
                        kind: HxButtonKind.tonal,
                        height: 48,
                        onTap: _copy,
                      ),
                      HxButton(
                        label: 'Borrar',
                        icon: Symbols.delete_sweep_rounded,
                        kind: HxButtonKind.text,
                        height: 48,
                        onTap: _clear,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SettingsSection(
              icon: Symbols.lan_rounded,
              title: 'Redes de la tableta',
              children: [
                if (d.networks.isEmpty)
                  const SettingsNote('Sin redes IPv4: la tableta no está en ningún Wi-Fi ni tiene el hotspot encendido.')
                else
                  for (final n in d.networks)
                    _Row(
                      icon: n.isHotspot ? Symbols.wifi_tethering_rounded : Symbols.wifi_rounded,
                      title: '${n.kind} · ${n.ip}/${n.prefix}',
                      subtitle: [
                        if (n.iface.isNotEmpty) n.iface,
                        if (n.gateway != null) 'gateway ${n.gateway}',
                        n.hasInternet ? 'con internet' : 'sin internet',
                        if (n.isDefault) 'red por defecto',
                      ].join(' · '),
                    ),
              ],
            ),
            SettingsSection(
              icon: Symbols.cell_tower_rounded,
              title: 'Celulares escuchados',
              children: [
                if (d.beacons.isEmpty)
                  const SettingsNote(
                    'Ningún aviso Wi-Fi del celular todavía. En Android 10+ el celular puede no mandarlos por una '
                    'red sin internet; igual marca a la tableta.',
                  )
                else
                  for (final b in d.beacons)
                    _Row(
                      icon: Symbols.smartphone_rounded,
                      title: '${b.device} · ${b.ip}:${b.port}',
                      subtitle: 'hace ${_age(now, b.at)}${b.id == null ? '' : ' · id ${b.id}'}',
                    ),
              ],
            ),
            SettingsSection(
              icon: Symbols.history_rounded,
              title: 'Intentos',
              children: [
                if (d.attempts.isEmpty)
                  const SettingsNote('Sin intentos registrados.')
                else
                  for (final a in d.attempts.take(20))
                    _Row(
                      icon: a.ok ? Symbols.check_circle_rounded : Symbols.cancel_rounded,
                      ok: a.ok,
                      title: '${a.inbound ? '← entrante' : '→'} ${a.transport == 'bt' ? 'Bluetooth' : 'Wi-Fi'} ${a.target}',
                      subtitle: [
                        a.ok ? 'conectó' : 'falló',
                        ?a.error,
                        if (!a.inbound) '${a.ms} ms',
                        'hace ${_age(now, a.at)}',
                      ].join(' · '),
                    ),
              ],
            ),
            SettingsSection(
              icon: Symbols.receipt_long_rounded,
              title: 'Registro',
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: _LogBox(
                    lines: [
                      for (final l in d.log.take(40)) '${_hm(l.at)}  ${l.text}',
                      if (_native.isNotEmpty) '— nativo —',
                      ..._native.reversed.take(40),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  static String _hm(DateTime t) => t.toIso8601String().substring(11, 19);

  static String _age(DateTime now, DateTime? t) {
    if (t == null) return '—';
    final s = now.difference(t).inSeconds;
    if (s < 60) return '${s < 0 ? 0 : s} s';
    if (s < 3600) return '${s ~/ 60} min';
    return '${s ~/ 3600} h';
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.n, required this.step});
  final int n;
  final LinkStep step;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    final (Color bg, Color fg, IconData icon) = switch (step.state) {
      LinkStepState.ok => (cs.primaryContainer, cs.onPrimaryContainer, Symbols.check_rounded),
      LinkStepState.waiting => (cs.surfaceContainerHighest, cs.onSurfaceVariant, Symbols.hourglass_top_rounded),
      LinkStepState.problem => (cs.errorContainer, cs.onErrorContainer, Symbols.priority_high_rounded),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: HxMotion.dFxSlow,
            curve: HxMotion.standard,
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: step.state == LinkStepState.ok ? HxRadius.m : BorderRadius.circular(20),
            ),
            alignment: Alignment.center,
            child: step.state == LinkStepState.ok
                ? HxIcon(icon, size: 22, color: fg)
                : Text('$n', style: hxWeight(tt.titleMedium, 600).copyWith(color: fg)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.title, style: hxWeight(tt.titleMedium, 500).copyWith(color: cs.onSurface)),
                const SizedBox(height: 2),
                Text(step.detail, style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                if (step.state != LinkStepState.ok && step.hint != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: HxIcon(Symbols.lightbulb_rounded, size: 16, color: cs.primary),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(step.hint!, style: tt.bodySmall?.copyWith(color: cs.primary)),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: context.tt.bodyLarge?.copyWith(color: cs.onSurface))),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTheme.numStyle(context, size: 15).copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.subtitle, this.ok});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool? ok;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final color = ok == null ? cs.onSurfaceVariant : (ok! ? cs.primary : cs.error);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          HxIcon(icon, color: color, fill: ok != null),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: hxWeight(context.tt.bodyLarge, 500).copyWith(color: cs.onSurface)),
                Text(subtitle, style: context.tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogBox extends StatelessWidget {
  const _LogBox({required this.lines});
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: HxRadius.m),
      child: lines.isEmpty
          ? Text('Vacío.', style: context.tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
          : SingleChildScrollView(
              child: SelectableText(
                lines.join('\n'),
                style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.4, color: cs.onSurface),
              ),
            ),
    );
  }
}

/// Estado de la fuente del visualizador (Portada y visualizador): audio real con señal
/// (y cuántos cuadros por segundo llegan), sin señal o simulado. Se refresca cada segundo.
class VizSourceStatus extends StatefulWidget {
  const VizSourceStatus({super.key, required this.c});
  final CarController c;

  @override
  State<VizSourceStatus> createState() => _VizSourceStatusState();
}

class _VizSourceStatusState extends State<VizSourceStatus> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final v = c.cfg.visualizer;
    final auto = v.source == CarVizSource.auto;
    final fallback = auto ? ' → usando simulado' : ' → barras quietas';
    final (bool ok, String text, String? hint) = switch (c.vizNow) {
      CarVizNow.simulated => (false, 'Simulado: espectro generado mientras suena (no usa el audio)', null),
      CarVizNow.real => (true, 'Audio real: recibiendo señal (${c.audio.fps.round()} fps)', null),
      CarVizNow.realNoSignal when !NativeBridge.instance.isSupported => (
        false,
        'Audio real no disponible aquí (solo en la tableta)$fallback',
        null,
      ),
      CarVizNow.realNoSignal when c.audioPermission == false => (false, 'Audio real sin permiso$fallback', null),
      CarVizNow.realNoSignal when !c.visualizerRunning => (
        false,
        'El visualizador de Android no arrancó en este equipo$fallback',
        null,
      ),
      CarVizNow.realNoSignal when c.audio.live => (
        false,
        'Audio real sin señal: el radio no pasa el audio Bluetooth por Android$fallback',
        'Llegan cuadros (${c.audio.fps.round()} fps) pero en silencio: el sonido sale directo por el radio. '
            'Prueba con música sonando; si sigue igual, usa «Simulado» o «Animar siempre».',
      ),
      CarVizNow.realNoSignal => (false, 'Audio real sin cuadros del sistema$fallback', null),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsStatus(
          key: const ValueKey('viz-now'),
          ok: ok,
          okIcon: Symbols.graphic_eq_rounded,
          offIcon: v.source == CarVizSource.simulated ? Symbols.auto_awesome_rounded : Symbols.volume_off_rounded,
          text: 'Ahora: $text',
        ),
        if (hint != null) ...[
          const SizedBox(height: 8),
          Text(hint, style: context.tt.bodySmall?.copyWith(color: context.cs.onSurfaceVariant)),
        ],
      ],
    );
  }
}
