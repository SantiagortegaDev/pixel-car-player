import 'package:flutter/material.dart';
import 'package:pixel_car_player/car/custom/car_custom_scope.dart';
import 'package:pixel_car_player/car/custom/car_customization.dart';
import 'package:pixel_car_player/car/widgets/hx.dart';
import 'package:pixel_car_player/core/shapes/m3_shapes.dart';
import 'package:pixel_car_player/data/link/link_protocol.dart';

/// "A continuación" (`QueueList compact` + `TrackRow`): miniatura cuadrada redondeada
/// (forma MD3 `square`), título en medium y artista en `onSurfaceVariant`.
class HxQueueList extends StatelessWidget {
  const HxQueueList({super.key, required this.items, this.coverFor});
  final List<QueueItem> items;

  /// Portada local opcional (solo la demo la tiene; el protocolo no manda carátulas).
  final String? Function(String title)? coverFor;

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
    return HxTextIn(
      offset: 0,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 2),
        itemBuilder: (context, i) => _Row(item: items[i], asset: coverFor?.call(items[i].title)),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, this.asset});
  final QueueItem item;
  final String? asset;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final tt = context.tt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 48,
            child: ClipPath(
              clipper: M3ShapeClipper(M3Shape.square),
              child: HxCover(bytes: null, asset: asset, iconSize: 22),
            ),
          ),
          const SizedBox(width: 14),
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
        ],
      ),
    );
  }
}
