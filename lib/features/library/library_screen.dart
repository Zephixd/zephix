import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/routes.dart';
import '../../app/theme/zephix_colors.dart';
import '../../app/theme/zephix_theme.dart';
import '../../core/constants/app_info.dart';
import '../../core/utils/format.dart';
import '../../data/database/app_database.dart';
import '../../shared/widgets/artwork.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/track_actions.dart';
import '../../shared/widgets/track_tile.dart';
import '../playlists/playlist_dialogs.dart';
import '../playlists/playlist_io.dart';
import 'scan_banner.dart';

enum LibraryTab {
  songs('Canciones'),
  albums('Álbumes'),
  artists('Artistas'),
  playlists('Playlists'),
  favorites('Favoritos'),
  recent('Recientes'),
  folders('Carpetas'),
  downloads('Descargas');

  const LibraryTab(this.label);
  final String label;
}

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: LibraryTab.values.length,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: ZSpace.page,
          title: Text('Biblioteca', style: context.tt.headlineMedium),
          actions: [
            IconButton(
              tooltip: 'Nueva playlist',
              icon: const Icon(Icons.playlist_add_rounded),
              onPressed: () => createPlaylistFlow(context, ref),
            ),
            PopupMenuButton<String>(
              tooltip: 'Añadir música',
              icon: const Icon(Icons.add_circle_outline_rounded),
              onSelected: (v) => _onAdd(context, ref, v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'scan', child: Text('Reescanear carpetas')),
                PopupMenuItem(value: 'folder', child: Text('Añadir carpeta')),
                PopupMenuItem(value: 'files', child: Text('Añadir archivos')),
                PopupMenuItem(value: 'm3u', child: Text('Importar playlist M3U')),
              ],
            ),
            const SizedBox(width: 4),
          ],
          bottom: TabBar(
            isScrollable: true,
            padding: const EdgeInsets.symmetric(horizontal: ZSpace.sm),
            tabs: [for (final t in LibraryTab.values) Tab(text: t.label)],
          ),
        ),
        body: Column(
          children: [
            const ScanBanner(),
            Expanded(
              child: TabBarView(children: [for (final t in LibraryTab.values) LibraryTabView(tab: t)]),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _onAdd(BuildContext context, WidgetRef ref, String v) async {
    final scan = ref.read(scanProvider.notifier);
    switch (v) {
      case 'scan':
        await scan.scan();
      case 'folder':
        if (!await ScanNotifier.ensurePermission()) {
          if (context.mounted) showSnack(context, 'Concede acceso a tu música para añadir carpetas.');
          return;
        }
        final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Carpeta de música');
        if (dir == null) return;
        await ref.read(databaseProvider).addLibraryFolder(dir);
        await scan.scan();
      case 'files':
        final files = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: AppInfo.audioExtensions.toList(),
        );
        final paths = [for (final f in files) ?f.path];
        if (paths.isEmpty) return;
        final n = await scan.addFiles(paths);
        if (context.mounted) showSnack(context, plural(n, 'archivo añadido', 'archivos añadidos'));
      case 'm3u':
        await importM3uFlow(context, ref);
    }
  }
}

Future<void> createPlaylistFlow(BuildContext context, WidgetRef ref) async {
  final r = await showPlaylistNameDialog(context);
  if (r == null) return;
  final id = await ref.read(databaseProvider).createPlaylist(r.$1, description: r.$2);
  if (context.mounted) context.push(Routes.playlist(id));
}

class LibraryTabView extends ConsumerWidget {
  const LibraryTabView({super.key, required this.tab});
  final LibraryTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (tab) {
      LibraryTab.songs => const _SongsTab(),
      LibraryTab.albums => const _AlbumsGrid(),
      LibraryTab.artists => const _ArtistsList(),
      LibraryTab.playlists => const _PlaylistsList(),
      LibraryTab.favorites => _TrackList(
          provider: favoriteTracksProvider,
          empty: const EmptyState(
            icon: Icons.favorite_border_rounded,
            title: 'Aún no tienes favoritos',
            message: 'Toca el corazón en el reproductor o haz doble toque en la portada.',
          ),
        ),
      LibraryTab.recent => _TrackList(
          provider: recentlyPlayedProvider,
          empty: const EmptyState(icon: Icons.history_rounded, title: 'Nada reproducido todavía'),
        ),
      LibraryTab.folders => const _FoldersList(),
      LibraryTab.downloads => _TrackList(
          provider: downloadsProvider,
          empty: const EmptyState(
            icon: Icons.download_rounded,
            title: 'Sin descargas',
            message: 'Las pistas con licencia abierta del catálogo se pueden descargar para escucharlas sin conexión.',
          ),
        ),
    };
  }
}

class _SongsTab extends ConsumerWidget {
  const _SongsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracks = ref.watch(tracksProvider);
    final sort = ref.watch(trackSortProvider);
    return tracks.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Error', message: '$e'),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            icon: Icons.library_music_rounded,
            title: 'No hay canciones',
            message: 'Escanea las carpetas de música de tu dispositivo.',
            action: 'Escanear ahora',
            onAction: () => ref.read(scanProvider.notifier).scan(),
          );
        }
        return Scrollbar(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 140),
            itemCount: list.length + 1,
            itemBuilder: (c, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.md, ZSpace.sm, ZSpace.sm),
                  child: Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () => ref.playTracks(list, shuffle: true),
                        icon: const Icon(Icons.shuffle_rounded),
                        label: const Text('Aleatorio'),
                      ),
                      const SizedBox(width: ZSpace.sm),
                      Expanded(child: Text(plural(list.length, 'canción', 'canciones'), style: context.tt.bodySmall)),
                      PopupMenuButton<TrackSort>(
                        tooltip: 'Ordenar',
                        initialValue: sort,
                        icon: const Icon(Icons.sort_rounded),
                        onSelected: ref.read(trackSortProvider.notifier).set,
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: TrackSort.title, child: Text('Título')),
                          PopupMenuItem(value: TrackSort.artist, child: Text('Artista')),
                          PopupMenuItem(value: TrackSort.album, child: Text('Álbum')),
                          PopupMenuItem(value: TrackSort.recentlyAdded, child: Text('Añadidas recientemente')),
                        ],
                      ),
                    ],
                  ),
                );
              }
              return TrackTile(track: list[i - 1], onTap: () => ref.playTracks(list, index: i - 1));
            },
          ),
        );
      },
    );
  }
}

class _TrackList extends ConsumerWidget {
  const _TrackList({required this.provider, required this.empty});
  final StreamProvider<List<TrackRow>> provider;
  final Widget empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(provider).value;
    if (list == null) return const Center(child: CircularProgressIndicator());
    if (list.isEmpty) return empty;
    return ListView.builder(
      padding: const EdgeInsets.only(top: ZSpace.sm, bottom: 140),
      itemCount: list.length,
      itemBuilder: (c, i) => TrackTile(track: list[i], onTap: () => ref.playTracks(list, index: i)),
    );
  }
}

class _AlbumsGrid extends ConsumerWidget {
  const _AlbumsGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(albumsProvider).value;
    if (albums == null) return const Center(child: CircularProgressIndicator());
    if (albums.isEmpty) return const EmptyState(icon: Icons.album_rounded, title: 'No hay álbumes');
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.lg, ZSpace.page, 140),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 190,
        mainAxisSpacing: ZSpace.lg,
        crossAxisSpacing: ZSpace.md,
        childAspectRatio: 0.74,
      ),
      itemCount: albums.length,
      itemBuilder: (c, i) => MediaCard(
        title: albums[i].title,
        subtitle: albums[i].artist,
        artPath: albums[i].artPath,
        onTap: () => context.push(Routes.album(albums[i].title, albums[i].artist)),
      ),
    );
  }
}

class _ArtistsList extends ConsumerWidget {
  const _ArtistsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(artistsProvider).value;
    if (artists == null) return const Center(child: CircularProgressIndicator());
    if (artists.isEmpty) return const EmptyState(icon: Icons.person_rounded, title: 'No hay artistas');
    return ListView.builder(
      padding: const EdgeInsets.only(top: ZSpace.sm, bottom: 140),
      itemCount: artists.length,
      itemBuilder: (c, i) {
        final a = artists[i];
        return ListTile(
          leading: SizedBox(
            width: 52,
            height: 52,
            child: Artwork(path: a.artPath, seed: a.name, size: 52, circle: true, icon: Icons.person_rounded),
          ),
          title: Text(a.name),
          subtitle: Text(
              '${plural(a.albumCount, 'álbum', 'álbumes')} · ${plural(a.trackCount, 'canción', 'canciones')}'),
          onTap: () => context.push(Routes.artist(a.name)),
        );
      },
    );
  }
}

class _PlaylistsList extends ConsumerWidget {
  const _PlaylistsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider).value;
    if (playlists == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.only(top: ZSpace.sm, bottom: 140),
      children: [
        ListTile(
          leading: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: context.zc.surfaceElevated,
              borderRadius: BorderRadius.circular(ZRadius.sm),
            ),
            child: Icon(Icons.add_rounded, color: context.zc.primary),
          ),
          title: const Text('Nueva playlist'),
          onTap: () => createPlaylistFlow(context, ref),
        ),
        ListTile(
          leading: const SizedBox(width: 52, child: Icon(Icons.file_open_outlined)),
          title: const Text('Importar M3U'),
          onTap: () => importM3uFlow(context, ref),
        ),
        for (final p in playlists)
          ListTile(
            leading: SizedBox(
              width: 52,
              height: 52,
              child: Artwork(path: p.artPath, seed: p.playlist.name, size: 52, icon: Icons.queue_music_rounded),
            ),
            title: Text(p.playlist.name),
            subtitle: Text(plural(p.trackCount, 'canción', 'canciones')),
            onTap: () => context.push(Routes.playlist(p.playlist.id)),
          ),
      ],
    );
  }
}

class _FoldersList extends ConsumerWidget {
  const _FoldersList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(trackFoldersProvider).value;
    if (folders == null) return const Center(child: CircularProgressIndicator());
    if (folders.isEmpty) {
      return EmptyState(
        icon: Icons.folder_open_rounded,
        title: 'Sin carpetas',
        message: 'Añade una carpeta con música desde el botón +.',
        action: 'Gestionar carpetas',
        onAction: () => context.push(Routes.folders),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: ZSpace.sm, bottom: 140),
      itemCount: folders.length,
      itemBuilder: (c, i) {
        final f = folders[i];
        final name = f.path.split(Platform.pathSeparator).where((s) => s.isNotEmpty).lastOrNull ?? f.path;
        return ListTile(
          leading: Icon(Icons.folder_rounded, color: context.zc.primary),
          title: Text(name),
          subtitle: Text('${plural(f.trackCount, 'canción', 'canciones')} · ${f.path}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => context.push(Routes.folder(f.path)),
        );
      },
    );
  }
}

/// Standalone full list reached from "Ver todo" links.
class LibraryListScreen extends StatelessWidget {
  const LibraryListScreen({super.key, required this.kind});
  final String kind;

  @override
  Widget build(BuildContext context) {
    final tab = LibraryTab.values.firstWhere((t) => t.name == kind, orElse: () => LibraryTab.songs);
    return Scaffold(appBar: AppBar(title: Text(tab.label)), body: LibraryTabView(tab: tab));
  }
}
