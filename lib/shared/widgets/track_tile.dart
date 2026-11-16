import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/zephix_colors.dart';
import '../../core/utils/format.dart';
import '../../data/database/app_database.dart';
import '../../data/sources/music_source_provider.dart';
import '../../data/sources/source_registry.dart';
import '../../domain/entities/track_x.dart';
import 'artwork.dart';
import 'common.dart';
import 'track_actions.dart';

/// Standard track row. Highlights the track that is currently playing.
class TrackTile extends ConsumerWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onTap,
    this.leadingNumber,
    this.trailing,
    this.showArt = true,
    this.extraActions = const [],
  });

  final TrackRow track;
  final VoidCallback onTap;
  final int? leadingNumber;
  final Widget? trailing;
  final bool showArt;
  final List<TrackMenuAction> extraActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zc = context.zc;
    final current = ref.watch(currentTrackProvider.select((v) => v.value?.id));
    final isCurrent = current == track.id;
    final isFav = ref.watch(favoriteIdsProvider.select((v) => v.value?.contains(track.id) ?? false));

    Widget leading;
    if (showArt) {
      leading = SizedBox(
        width: 48,
        height: 48,
        child: Artwork(path: track.artPath, url: track.artUrl, seed: '${track.album}${track.artist}', size: 48),
      );
    } else {
      leading = SizedBox(
        width: 28,
        child: Text(
          leadingNumber?.toString() ?? '·',
          textAlign: TextAlign.center,
          style: context.tt.bodyMedium?.copyWith(color: isCurrent ? zc.primary : zc.textSecondary),
        ),
      );
    }

    return ListTile(
      onTap: onTap,
      onLongPress: () => showTrackActions(context, ref, track, extra: extraActions),
      leading: leading,
      minLeadingWidth: 0,
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.tt.titleSmall?.copyWith(color: isCurrent ? zc.primary : zc.textPrimary),
      ),
      subtitle: Row(
        children: [
          if (isFav) ...[Icon(Icons.favorite_rounded, size: 12, color: zc.primary), const SizedBox(width: 4)],
          if (track.isRemote) ...[const Pill('STREAM'), const SizedBox(width: 6)],
          if (!track.isRemote &&
              (sourceInfoById(track.source)?.can(SourceCapability.download) ?? false))
            ...[const Pill('DESCARGADA'), const SizedBox(width: 6)],
          Expanded(
            child: Text(
              '${track.artist}${track.durationMs > 0 ? ' · ${formatMs(track.durationMs)}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.tt.bodySmall,
            ),
          ),
        ],
      ),
      trailing: trailing ??
          IconButton(
            tooltip: 'Más opciones',
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () => showTrackActions(context, ref, track, extra: extraActions),
          ),
    );
  }
}
