import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pixel_car_player/car/custom/car_custom_scope.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/car/widgets/motion.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';
import 'package:pixel_car_player/core/theme/app_theme.dart';
import 'package:pixel_car_player/data/link/link_protocol.dart';

/// "A continuación" (`QueueList compact` + `TrackRow`): miniatura cuadrada redondeada
/// (forma MD3 `square`), título en medium y artista en `onSurfaceVariant`. v3: la miniatura
/// llega en `queue.items[].art` y tocar un tema salta a él (`cmd skipToQueue`).
class HxQueueList extends StatelessWidget {
  const HxQueueList({super.key, required this.items, this.coverFor, this.onTap, this.covers = true});
  final List<QueueItem> items;

  /// Portada local opcional (solo la demo la tiene) si el tema no trae miniatura.
  final String? Function(String title)? coverFor;

  /// Tocar un tema (solo los que tienen `id`). `null` = no se puede.
  final ValueChanged<QueueItem>? onTap;

  /// Mostrar miniaturas.
  final bool covers;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    if (items.isEmpty) {
      final text = CarCustomScope.of(context).text(CarText.emptyQueue);
      if (text.isEmpty) return const SizedBox.shrink();
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: context.tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      );
    }
    final entrance = CarCustomScope.of(context).anim.listEntrance;
    return HxTextIn(
      offset: 0,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 2),
        itemBuilder: (context, i) => HxEntrance(
          key: ValueKey('q-$i-${items[i].title}'),
          index: i.clamp(0, 8),
          enabled: entrance,
          offset: 10,
          child: _Row(
            item: items[i],
            asset: covers ? coverFor?.call(items[i].title) : null,
            covers: covers,
            onTap: onTap != null && items[i].id != null ? () => onTap!(items[i]) : null,
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, this.asset, this.covers = true, this.onTap});
  final QueueItem item;
  final String? asset;
  final bool covers;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      child: Row(
        children: [
          if (covers) ...[
            SizedBox.square(
              dimension: 48,
              child: ClipPath(
                clipper: M3ShapeClipper(M3Shape.square),
                child: HxCover(bytes: item.art, asset: item.art == null ? asset : null, iconSize: 22),
              ),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: hxWeight(tt.bodyLarge, 500).copyWith(color: cs.onSurface, height: 1.45),
                ),
                if (item.artist.isNotEmpty)
                  Text(
                    item.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 8),
            HxIcon(Symbols.play_arrow_rounded, size: 22, color: cs.onSurfaceVariant),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: 'Reproducir ${item.title}',
      child: Material(
        type: MaterialType.transparency,
        borderRadius: HxRadius.l,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: cs.onSurface.withValues(alpha: 0.1),
          highlightColor: cs.onSurface.withValues(alpha: 0.08),
          child: row,
        ),
      ),
    );
  }
}
