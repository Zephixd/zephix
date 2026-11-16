import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/routes.dart';
import '../../app/theme/zephix_colors.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/artwork.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/track_actions.dart';
import 'playlist_dialogs.dart';
import 'playlist_io.dart';

class PlaylistScreen extends ConsumerStatefulWidget {
  const PlaylistScreen({super.key, required this.id});
  final int id;
  @override
  ConsumerState<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends ConsumerState<PlaylistScreen> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final zc = context.zc;
    final db = ref.read(databaseProvider);
    final playlist = ref.watch(playlistProvider(widget.id)).value;
    final entries = ref.watch(playlistEntriesProvider(widget.id)).value ?? const [];
    final tracks = [for (final e in entries) e.track];
    final current = ref.watch(currentTrackProvider.select((v) => v.value?.id));

    if (playlist == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final ms = tracks.fold<int>(0, (a, t) => a + t.durationMs);
    final art = tracks.map((t) => t.artPath).firstWhere((a) => a != null, orElse: () => null);

    Future<void> menu(String v) async {
      switch (v) {
        case 'rename':
          final r = await showPlaylistNameDialog(context,
              title: 'Editar playlist',
              initialName: playlist.name,
              initialDescription: playlist.description,
              confirm: 'Guardar');
          if (r != null) await db.renamePlaylist(playlist.id, r.$1, description: r.$2);
        case 'duplicate':
          final id = await db.duplicatePlaylist(playlist.id);
          if (context.mounted) context.push(Routes.playlist(id));
        case 'export':
          await exportM3u(context, playlist.name, tracks);
        case 'delete':
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('¿Eliminar playlist?'),
              content: Text('“${playlist.name}” se eliminará. Las canciones seguirán en tu biblioteca.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar')),
              ],
            ),
          );
          if (ok == true) {
            await db.deletePlaylist(playlist.id);
            if (context.mounted) context.pop();
          }
      }
    }

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: _editing ? 'Terminar edición' : 'Reordenar',
            icon: Icon(_editing ? Icons.check_rounded : Icons.swap_vert_rounded),
            onPressed: () => setState(() => _editing = !_editing),
          ),
          PopupMenuButton<String>(
            onSelected: menu,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Editar nombre')),
              const PopupMenuItem(value: 'duplicate', child: Text('Duplicar')),
              PopupMenuItem(value: 'export', enabled: tracks.isNotEmpty, child: const Text('Exportar M3U')),
              const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
            ],
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: CollectionHeader(
              title: playlist.name,
              seed: 'playlist${playlist.id}',
              kicker: 'Playlist',
              subtitle: [
                if (playlist.description != null) playlist.description!,
                '${plural(tracks.length, 'canción', 'canciones')}${ms > 0 ? ' · ${formatMinutes(ms)}' : ''}',
              ].join('\n'),
              artPath: art,
              icon: Icons.queue_music_rounded,
              actions: [
                FilledButton.icon(
                  onPressed: tracks.isEmpty ? null : () => ref.playTracks(tracks),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Reproducir'),
                ),
                OutlinedButton.icon(
                  onPressed: tracks.isEmpty ? null : () => ref.playTracks(tracks, shuffle: true),
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('Aleatorio'),
                ),
              ],
            ),
          ),
          if (tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.playlist_add_rounded,
                title: 'Playlist vacía',
                message: 'Mantén pulsada una canción en cualquier lista y elige “Añadir a playlist”.',
                action: 'Ir a la biblioteca',
                onAction: () => context.go(Routes.library),
              ),
            )
          else
            SliverReorderableList(
              itemCount: entries.length,
              onReorderItem: (from, to) => db.movePlaylistEntry(playlist.id, from, to),
              itemBuilder: (c, i) {
                final e = entries[i];
                final t = e.track;
                final isCurrent = current == t.id;
                return Material(
                  key: ValueKey(e.entryId),
                  color: Colors.transparent,
                  child: Dismissible(
                    key: ValueKey('d${e.entryId}'),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      color: zc.surfaceElevated,
                      child: const Icon(Icons.remove_circle_outline_rounded),
                    ),
                    onDismissed: (_) => db.removePlaylistEntry(playlist.id, e.entryId),
                    child: ListTile(
                      onTap: () => ref.playTracks(tracks, index: i),
                      onLongPress: () => showTrackActions(context, ref, t, extra: [
                        TrackMenuAction(Icons.remove_circle_outline_rounded, 'Quitar de esta playlist',
                            () => db.removePlaylistEntry(playlist.id, e.entryId)),
                      ]),
                      leading: SizedBox(
                        width: 48,
                        height: 48,
                        child: Artwork(path: t.artPath, url: t.artUrl, seed: '${t.album}${t.artist}', size: 48),
                      ),
                      title: Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.tt.titleSmall?.copyWith(color: isCurrent ? zc.primary : null)),
                      subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: _editing
                          ? ReorderableDragStartListener(
                              index: i,
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.drag_handle_rounded, semanticLabel: 'Arrastrar para reordenar'),
                              ),
                            )
                          : IconButton(
                              tooltip: 'Más opciones',
                              icon: const Icon(Icons.more_vert_rounded),
                              onPressed: () => showTrackActions(context, ref, t, extra: [
                                TrackMenuAction(Icons.remove_circle_outline_rounded, 'Quitar de esta playlist',
                                    () => db.removePlaylistEntry(playlist.id, e.entryId)),
                              ]),
                            ),
                    ),
                  ),
                );
              },
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
    );
  }
}
