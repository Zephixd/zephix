import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/routes.dart';
import '../../app/theme/zephix_colors.dart';
import '../../app/theme/zephix_theme.dart';
import '../../core/utils/format.dart';
import '../../data/database/app_database.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/track_actions.dart';
import '../../shared/widgets/track_tile.dart';
import '../playlists/playlist_dialogs.dart';

/// Play / shuffle buttons shared by collection headers.
List<Widget> playButtons(WidgetRef ref, List<TrackRow> tracks) => [
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
    ];

String _totalLabel(List<TrackRow> t) {
  final ms = t.fold<int>(0, (a, b) => a + b.durationMs);
  return '${plural(t.length, 'canción', 'canciones')}${ms > 0 ? ' · ${formatMinutes(ms)}' : ''}';
}

class _TrackCollection extends ConsumerWidget {
  const _TrackCollection({
    required this.async,
    required this.header,
    this.numbered = false,
    this.footer,
    this.actions = const [],
  });

  final AsyncValue<List<TrackRow>> async;
  final Widget Function(List<TrackRow>) header;
  final bool numbered;
  final Widget? footer;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(actions: actions),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Error', message: '$e'),
        data: (tracks) => CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: header(tracks)),
            if (tracks.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(icon: Icons.music_off_rounded, title: 'Sin canciones'),
              )
            else
              SliverList.builder(
                itemCount: tracks.length,
                itemBuilder: (c, i) => TrackTile(
                  track: tracks[i],
                  showArt: !numbered,
                  leadingNumber: tracks[i].trackNumber ?? i + 1,
                  onTap: () => ref.playTracks(tracks, index: i),
                ),
              ),
            if (footer != null) SliverToBoxAdapter(child: footer),
            const SliverToBoxAdapter(child: SizedBox(height: 140)),
          ],
        ),
      ),
    );
  }
}

class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({super.key, required this.title, required this.artist});
  final String title;
  final String artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(albumTracksProvider((title, artist)));
    return _TrackCollection(
      async: async,
      numbered: true,
      actions: [
        IconButton(
          tooltip: 'Añadir a playlist',
          icon: const Icon(Icons.playlist_add_rounded),
          onPressed: () => showAddToPlaylistSheet(context, ref, [for (final t in async.value ?? <TrackRow>[]) t.id]),
        ),
      ],
      header: (tracks) {
        final art = tracks.map((t) => t.artPath).firstWhere((a) => a != null, orElse: () => null);
        final year = tracks.map((t) => t.year).firstWhere((y) => y != null, orElse: () => null);
        return CollectionHeader(
          title: title,
          seed: '$title$artist',
          kicker: 'Álbum',
          subtitle: [artist, if (year != null) '$year', _totalLabel(tracks)].join(' · '),
          artPath: art,
          actions: [
            ...playButtons(ref, tracks),
            OutlinedButton(onPressed: () => context.push(Routes.artist(artist)), child: const Text('Artista')),
          ],
        );
      },
    );
  }
}

class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(artistTracksProvider(name));
    final albums = ref.watch(artistAlbumsProvider(name)).value ?? const [];
    return _TrackCollection(
      async: async,
      header: (tracks) {
        final art = tracks.map((t) => t.artPath).firstWhere((a) => a != null, orElse: () => null);
        return Column(
          children: [
            CollectionHeader(
              title: name,
              seed: name,
              kicker: 'Artista',
              subtitle: '${plural(albums.length, 'álbum', 'álbumes')} · ${_totalLabel(tracks)}',
              artPath: art,
              circle: true,
              icon: Icons.person_rounded,
              actions: playButtons(ref, tracks),
            ),
            if (albums.isNotEmpty) ...[
              const SectionHeader('Álbumes'),
              Shelf(
                itemCount: albums.length,
                itemBuilder: (c, i) => MediaCard(
                  title: albums[i].title,
                  subtitle: albums[i].year?.toString() ?? plural(albums[i].trackCount, 'canción', 'canciones'),
                  artPath: albums[i].artPath,
                  onTap: () => context.push(Routes.album(albums[i].title, albums[i].artist)),
                ),
              ),
            ],
            const SectionHeader('Canciones'),
          ],
        );
      },
    );
  }
}

class FolderScreen extends ConsumerWidget {
  const FolderScreen({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(folderTracksProvider(path));
    return _TrackCollection(
      async: async,
      header: (tracks) => CollectionHeader(
        title: path.split('/').where((s) => s.isNotEmpty).lastOrNull ?? path,
        seed: path,
        kicker: 'Carpeta',
        subtitle: '$path\n${_totalLabel(tracks)}',
        icon: Icons.folder_rounded,
        actions: playButtons(ref, tracks),
      ),
    );
  }
}

class GenreScreen extends ConsumerWidget {
  const GenreScreen({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(genreTracksProvider(name));
    return _TrackCollection(
      async: async,
      header: (tracks) => CollectionHeader(
        title: name,
        seed: 'genre$name',
        kicker: 'Género',
        subtitle: _totalLabel(tracks),
        icon: Icons.graphic_eq_rounded,
        actions: playButtons(ref, tracks),
      ),
    );
  }
}

class MixScreen extends ConsumerWidget {
  const MixScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mixes = ref.watch(smartMixesProvider);
    final mix = mixes.value?.where((m) => m.id == id).firstOrNull;
    return _TrackCollection(
      async: mixes.whenData((_) => mix?.tracks ?? const []),
      actions: [
        IconButton(
          tooltip: 'Guardar como playlist',
          icon: const Icon(Icons.playlist_add_rounded),
          onPressed: mix == null
              ? null
              : () async {
                  final db = ref.read(databaseProvider);
                  final pid = await db.createPlaylist(mix.title, description: mix.subtitle);
                  await db.addTracksToPlaylist(pid, [for (final t in mix.tracks) t.id]);
                  if (context.mounted) showSnack(context, 'Guardada como playlist');
                },
        ),
      ],
      header: (tracks) => CollectionHeader(
        title: mix?.title ?? 'Mezcla',
        seed: id,
        kicker: 'Mezcla inteligente',
        subtitle: '${mix?.subtitle ?? ''}\n${_totalLabel(tracks)}',
        artPath: mix?.artPath,
        icon: Icons.auto_awesome_rounded,
        actions: playButtons(ref, tracks),
      ),
      footer: Padding(
        padding: const EdgeInsets.all(ZSpace.page),
        child: Text(
          'Generada en tu dispositivo con tu historial, favoritos y canciones omitidas. Se actualiza cada día.',
          style: context.tt.bodySmall?.copyWith(color: context.zc.textSecondary),
        ),
      ),
    );
  }
}
