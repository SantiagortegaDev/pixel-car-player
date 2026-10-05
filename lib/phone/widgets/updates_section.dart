import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/phone/controllers/updates_controller.dart';
import 'package:pixel_car_player/phone/phone_controller.dart';
import 'package:pixel_car_player/phone/widgets/hx/hx.dart';

String _mb(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB';

String _ago(DateTime d) {
  final diff = DateTime.now().difference(d);
  String two(int n) => n.toString().padLeft(2, '0');
  if (diff.inMinutes < 1) return 'hace un momento';
  if (diff.inHours < 1) return 'hace ${diff.inMinutes} min';
  final hm = '${two(d.hour)}:${two(d.minute)}';
  if (diff.inHours < 24 && d.day == DateTime.now().day) return 'hoy a las $hm';
  return 'el ${d.day}/${d.month} a las $hm';
}

/// Ajustes → Actualizaciones: versión instalada, búsqueda en GitHub Releases, notas,
/// descarga con progreso, permiso de instalación y búsqueda diaria.
class UpdatesSection extends StatelessWidget {
  const UpdatesSection({super.key, required this.c});
  final UpdatesController c;

  Future<void> _install(BuildContext context) async {
    final r = await c.install();
    if (context.mounted) showHxSnack(context, r.message, error: !r.ok);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final cs = Theme.of(context).colorScheme;
      final info = c.info;
      final checking = c.phase == UpdatePhase.checking;
      final downloading =
          c.phase == UpdatePhase.downloading ||
          c.phase == UpdatePhase.installing;
      return HxSettingsCard(
        children: [
          HxSettingsItem(
            label: 'Pixel Car Player ${c.versionLabel}',
            description: [
              if (c.abi.isNotEmpty) c.abi,
              if (c.lastCheck != null) 'Última búsqueda ${_ago(c.lastCheck!)}',
            ].join(' · ').ifEmpty('Versión instalada'),
            child: Align(
              alignment: Alignment.centerLeft,
              child: HxButton(
                label: checking ? 'Buscando…' : 'Buscar ahora',
                kind: HxButtonKind.tonal,
                icon: Symbols.refresh_rounded,
                onPressed: c.busy ? null : () => c.check(),
              ),
            ),
          ),
          if (checking || info != null || c.phase == UpdatePhase.error)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: AnimatedSize(
                duration: HxMotion.dSpring,
                curve: HxMotion.emphasizedDecel,
                alignment: Alignment.topCenter,
                child: AnimatedSwitcher(
                  duration: hxReduceMotion(context)
                      ? Duration.zero
                      : HxMotion.dFxSlow,
                  child: KeyedSubtree(
                    key: ValueKey(
                      '${c.phase == UpdatePhase.error}$checking${info?.available}$downloading',
                    ),
                    child: _result(context, cs, info, checking, downloading),
                  ),
                ),
              ),
            ),
          if (!c.canInstall)
            HxSettingsItem(
              label: 'Permitir instalar actualizaciones',
              description:
                  'Android pide autorizar a Pixel Car Player para instalar su propia '
                  'versión nueva.',
              trailing: HxButton(
                label: 'Permitir',
                kind: HxButtonKind.tonal,
                onPressed: c.openInstallPermission,
              ),
            )
          else
            const HxSettingsItem(
              label: 'Instalar actualizaciones',
              description: 'Permiso concedido.',
              trailing: HxStatus(
                label: 'Listo',
                icon: Symbols.check_circle_rounded,
                ok: true,
              ),
            ),
          HxSwitchRow(
            label: 'Buscar una vez al día',
            description: 'Al abrir la app; si hay una versión nueva verás un aviso en Inicio.',
            value: c.autoCheck,
            onChanged: c.setAutoCheck,
          ),
        ],
      );
    },
  );

  Widget _result(
    BuildContext context,
    ColorScheme cs,
    UpdateInfo? info,
    bool checking,
    bool downloading,
  ) {
    if (checking) {
      return Row(
        children: [
          const HxLoadingIndicator(size: 36),
          const SizedBox(width: 12),
          Text('Consultando GitHub…', style: HxType.bodyM(cs.onSurfaceVariant)),
        ],
      );
    }
    if (c.phase == UpdatePhase.error) {
      return Row(
        children: [
          HxIcon(Symbols.error_rounded, color: cs.error, filled: true),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              c.error ?? 'No se pudo buscar.',
              style: HxType.bodyM(cs.error),
            ),
          ),
        ],
      );
    }
    if (info == null) return const SizedBox.shrink();
    if (!info.available) {
      return const HxStatus(
        label: 'Tienes la versión más reciente',
        icon: Symbols.verified_rounded,
        ok: true,
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: HxRadius.l,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              HxShapeTile(
                shape: M3Shape.cookie9,
                size: 44,
                color: cs.primary,
                icon: Symbols.system_update_rounded,
                iconColor: cs.onPrimary,
                iconSize: 22,
                spin: downloading,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Versión ${info.versionName} disponible',
                      style: HxType.titleM(cs.onSecondaryContainer),
                    ),
                    if (info.apkSize > 0)
                      Text(
                        _mb(info.apkSize),
                        style: HxType.bodyS(
                          cs.onSecondaryContainer.withValues(alpha: 0.8),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (info.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Novedades', style: HxType.labelL(cs.onSecondaryContainer)),
            const SizedBox(height: 4),
            Text(
              info.notes,
              maxLines: 12,
              overflow: TextOverflow.ellipsis,
              style: HxType.bodyM(cs.onSecondaryContainer),
            ),
          ],
          const SizedBox(height: 14),
          if (downloading) ...[
            HxProgressBar(
              value: c.phase == UpdatePhase.installing ? 1 : c.progress,
            ),
            const SizedBox(height: 8),
            Text(
              c.phase == UpdatePhase.installing
                  ? 'Abriendo el instalador…'
                  : c.total > 0
                  ? 'Descargando… ${_mb(c.received)} de ${_mb(c.total)} '
                        '(${((c.progress ?? 0) * 100).round()} %)'
                  : 'Descargando…',
              style: HxType.bodyS(cs.onSecondaryContainer),
            ),
          ] else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                HxButton(
                  label: 'Descargar e instalar',
                  icon: Symbols.download_rounded,
                  onPressed: () => _install(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Antes de instalar se guarda una copia de tus ajustes.',
              style: HxType.bodyS(
                cs.onSecondaryContainer.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// Ajustes → Copia de seguridad: exportar / restaurar los ajustes del celular.
class BackupSection extends StatelessWidget {
  const BackupSection({super.key, required this.c});
  final PhoneController c;

  Future<void> _export(BuildContext context) async {
    final path = await c.updates.exportBackup();
    if (!context.mounted) return;
    if (path != null) {
      showHxSnack(context, 'Copia guardada en $path');
      return;
    }
    // Sin archivo (web / escritorio o el nativo falló): al portapapeles.
    final json = c.updates.lastExportJson;
    if (json != null) await Clipboard.setData(ClipboardData(text: json));
    if (context.mounted) {
      showHxSnack(
        context,
        c.supported
            ? 'No se pudo guardar el archivo; la copia quedó en el portapapeles.'
            : 'Copia en el portapapeles (los archivos solo se guardan en el celular).',
      );
    }
  }

  Future<void> _restore(BuildContext context) async {
    final json = await c.updates.pickBackup();
    if (!context.mounted) return;
    if (json == null) {
      if (!c.supported) {
        showHxSnack(context, 'Restaurar solo está disponible en el celular.');
      }
      return;
    }
    final yes = await confirmHx(
      context,
      title: 'Restaurar ajustes',
      text:
          'Se reemplazarán los ajustes del celular por los de la copia (transmisión, '
          'hotspot del carro, encendido automático y apariencia).',
      confirm: 'Restaurar',
    );
    if (!yes || !context.mounted) return;
    final r = await c.restoreBackup(json);
    if (context.mounted) showHxSnack(context, r.message, error: !r.ok);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c.updates,
    builder: (context, _) => HxSettingsCard(
      children: [
        HxSettingsItem(
          label: 'Ajustes del celular',
          description:
              'Se guardan en un archivo JSON (Documentos/PixelCarPlayer). Incluye la '
              'contraseña del hotspot del carro: es tu propia copia, guárdala en un '
              'lugar seguro. Los carros emparejados no se copian.',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              HxButton(
                label: 'Exportar',
                kind: HxButtonKind.tonal,
                icon: Symbols.save_rounded,
                onPressed: () => _export(context),
              ),
              HxButton(
                label: 'Restaurar',
                kind: HxButtonKind.outlined,
                icon: Symbols.settings_backup_restore_rounded,
                onPressed: () => _restore(context),
              ),
            ],
          ),
        ),
        if (c.updates.lastBackup.isNotEmpty)
          HxSettingsItem(
            label: 'Última copia',
            description: c.updates.lastBackup,
          ),
      ],
    ),
  );
}

/// Aviso discreto en Inicio cuando la búsqueda diaria encontró una versión nueva.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.c, required this.onOpen});
  final UpdatesController c;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final cs = Theme.of(context).colorScheme;
      final show = c.bannerVisible && (c.info?.available ?? false);
      return AnimatedSize(
        duration: hxReduceMotion(context) ? Duration.zero : HxMotion.dSpring,
        curve: HxMotion.emphasizedDecel,
        alignment: Alignment.topCenter,
        child: !show
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: HxEntrance(
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      borderRadius: HxRadius.xl,
                    ),
                    child: Row(
                      children: [
                        HxIcon(
                          Symbols.system_update_rounded,
                          color: cs.onSecondaryContainer,
                          filled: true,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Versión ${c.info!.versionName} disponible',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: HxType.bodyM(cs.onSecondaryContainer),
                          ),
                        ),
                        HxButton(
                          label: 'Ver',
                          kind: HxButtonKind.text,
                          onPressed: () {
                            c.dismissBanner();
                            onOpen();
                          },
                        ),
                        HxIconButton(
                          icon: Symbols.close_rounded,
                          tooltip: 'Descartar',
                          color: cs.onSecondaryContainer,
                          onPressed: c.dismissBanner,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      );
    },
  );
}
