import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/zephix_colors.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/artwork.dart';
import '../playlists/playlist_dialogs.dart';

Future<void> showQueueSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _QueueSheet(),
  );
}

class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zc = context.zc;
    final tracks = ref.watch(queueTracksProvider).value ?? const [];
    final current = ref.watch(currentIndexProvider).value ?? -1;
    final handler = ref.read(audioHandlerProvider);
    final remaining = tracks.skip(current + 1).fold<int>(0, (a, t) => a + t.durationMs);

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Cola de reproducción', style: context.tt.titleLarge),
                      Text(
                        '${plural(tracks.length, 'canción', 'canciones')}'
                        '${remaining > 0 ? ' · ${formatMinutes(remaining)} restantes' : ''}',
                        style: context.tt.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Guardar como playlist',
                  icon: const Icon(Icons.playlist_add_rounded),
                  onPressed: tracks.isEmpty
                      ? null
                      : () => showAddToPlaylistSheet(context, ref, [for (final t in tracks) t.id]),
                ),
                IconButton(
                  tooltip: 'Vaciar cola',
                  icon: const Icon(Icons.clear_all_rounded),
                  onPressed: tracks.isEmpty
                      ? null
                      : () async {
                          await handler.clearQueue();
                          if (context.mounted) Navigator.pop(context);
                        },
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              itemCount: tracks.length,
              buildDefaultDragHandles: false,
              onReorderItem: handler.moveQueueItem,
              itemBuilder: (context, i) {
                final t = tracks[i];
                final isCurrent = i == current;
                return Dismissible(
                  key: ValueKey('q-$i-${t.id}'),
                  direction: isCurrent ? DismissDirection.none : DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    color: zc.surfaceElevated,
                    child: const Icon(Icons.delete_outline_rounded),
                  ),
                  onDismissed: (_) => handler.removeQueueItemAt(i),
                  child: ListTile(
                    onTap: () => handler.skipToQueueItem(i),
                    leading: SizedBox(
                      width: 44,
                      height: 44,
                      child: Artwork(path: t.artPath, url: t.artUrl, seed: '${t.album}${t.artist}', size: 44),
                    ),
                    title: Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.titleSmall?.copyWith(color: isCurrent ? zc.primary : null),
                    ),
                    subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: ReorderableDragStartListener(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(isCurrent ? Icons.graphic_eq_rounded : Icons.drag_handle_rounded,
                            color: isCurrent ? zc.primary : zc.textSecondary,
                            semanticLabel: 'Arrastrar para reordenar'),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
