import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/routes.dart';
import '../../app/theme/zephix_colors.dart';
import '../../app/theme/zephix_theme.dart';
import '../../core/utils/format.dart';
import '../../data/database/app_database.dart';
import '../../data/remote_tracks.dart';
import '../../data/sources/ytm_source.dart';
import '../../shared/widgets/artwork.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/track_actions.dart';
import '../../shared/widgets/track_tile.dart';

enum SearchFilter {
  all('Todo'),
  songs('Canciones'),
  artists('Artistas'),
  albums('Álbumes'),
  playlists('Playlists'),
  folders('Carpetas'),
  open('YouTube Music');

  const SearchFilter(this.label);
  final String label;
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  String _query = '';
  SearchFilter _filter = SearchFilter.all;
  List<TrackRow> _songs = const [];
  Future<YtmSearchResults>? _remote;
  String? _remoteQuery;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _run(v));
  }

  Future<void> _run(String v, {bool submit = false}) async {
    final q = v.trim();
    if (!mounted) return;
    setState(() => _query = q);
    if (q.isEmpty) {
      setState(() => _songs = const []);
      return;
    }
    final songs = await ref.read(databaseProvider).searchTracks(q, limit: 60);
    if (!mounted || q != _query) return;
    setState(() => _songs = songs);
    final openEnabled = ref.read(settingsProvider).openCatalogs;
    // The online source is only queried on submit or when its tab is active,
    // so typing never floods YouTube with requests.
    if (openEnabled && (submit || _filter == SearchFilter.open) && _remoteQuery != q) {
      setState(() {
        _remoteQuery = q;
        _remote = ref.read(ytmSourceProvider).search(q);
      });
    }
    if (submit) await ref.read(databaseProvider).addSearch(q);
  }

  void _useHistory(String q) {
    _controller.text = q;
    _controller.selection = TextSelection.collapsed(offset: q.length);
    _run(q, submit: true);
  }

  @override
  Widget build(BuildContext context) {
    final zc = context.zc;
    final openEnabled = ref.watch(settingsProvider.select((s) => s.openCatalogs));
    final filters = SearchFilter.values.where((f) => f != SearchFilter.open || openEnabled).toList();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.md, ZSpace.page, ZSpace.sm),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: (v) => _run(v, submit: true),
                decoration: InputDecoration(
                  hintText: 'Canciones, artistas, álbumes…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Borrar',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _controller.clear();
                            _run('');
                          },
                        ),
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: ZSpace.page),
                itemCount: filters.length,
                separatorBuilder: (_, _) => const SizedBox(width: ZSpace.sm),
                itemBuilder: (c, i) => ChoiceChip(
                  label: Text(filters[i].label),
                  selected: _filter == filters[i],
                  onSelected: (_) {
                    setState(() => _filter = filters[i]);
                    if (filters[i] == SearchFilter.open && _query.isNotEmpty) _run(_query);
                  },
                ),
              ),
            ),
            Expanded(child: _query.isEmpty ? _history(zc) : _results(openEnabled)),
          ],
        ),
      ),
    );
  }

  Widget _history(ZephixColors zc) {
    final history = ref.watch(searchHistoryProvider).value ?? const [];
    if (history.isEmpty) {
      return const EmptyState(
        icon: Icons.manage_search_rounded,
        title: 'Busca en toda tu música',
        message: 'Resultados de tu biblioteca local y de YouTube Music, separados por fuente.',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 140),
      children: [
        SectionHeader('Búsquedas recientes',
            action: 'Borrar', onAction: () => ref.read(databaseProvider).clearSearchHistory()),
        for (final q in history)
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: Text(q),
            onTap: () => _useHistory(q),
            trailing: IconButton(
              tooltip: 'Quitar',
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: () => ref.read(databaseProvider).removeSearch(q),
            ),
          ),
      ],
    );
  }

  Widget _results(bool openEnabled) {
    final q = _query.toLowerCase();
    final artists = (ref.watch(artistsProvider).value ?? const <ArtistSummary>[])
        .where((a) => a.name.toLowerCase().contains(q))
        .toList();
    final albums = (ref.watch(albumsProvider).value ?? const <AlbumSummary>[])
        .where((a) => a.title.toLowerCase().contains(q) || a.artist.toLowerCase().contains(q))
        .toList();
    final playlists = (ref.watch(playlistsProvider).value ?? const <PlaylistSummary>[])
        .where((p) => p.playlist.name.toLowerCase().contains(q))
        .toList();
    final folders = (ref.watch(trackFoldersProvider).value ?? const <FolderSummary>[])
        .where((f) => f.path.toLowerCase().contains(q))
        .toList();

    bool show(SearchFilter f) => _filter == SearchFilter.all || _filter == f;
    final limit = _filter == SearchFilter.all ? 5 : 1000;
    final children = <Widget>[];

    void group(String title, String source, List<Widget> items, {VoidCallback? more}) {
      if (items.isEmpty) return;
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.xl, ZSpace.page, ZSpace.sm),
        child: Row(
          children: [
            Expanded(child: Text(title, style: context.tt.titleLarge)),
            Pill(source, color: source == 'LOCAL' ? context.zc.primary : context.zc.secondary),
          ],
        ),
      ));
      children.addAll(items);
      if (more != null) {
        children.add(Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZSpace.sm),
            child: TextButton(onPressed: more, child: const Text('Ver más')),
          ),
        ));
      }
    }

    if (show(SearchFilter.songs)) {
      group('Canciones', 'LOCAL', [
        for (final (i, t) in _songs.take(limit).indexed)
          TrackTile(track: t, onTap: () {
            ref.read(databaseProvider).addSearch(_query);
            ref.playTracks(_songs, index: i);
          }),
      ], more: _filter == SearchFilter.all && _songs.length > limit ? () => setState(() => _filter = SearchFilter.songs) : null);
    }
    if (show(SearchFilter.artists)) {
      group('Artistas', 'LOCAL', [
        for (final a in artists.take(limit))
          ListTile(
            leading: SizedBox(width: 48, height: 48, child: Artwork(path: a.artPath, seed: a.name, size: 48, circle: true, icon: Icons.person_rounded)),
            title: Text(a.name),
            subtitle: Text(plural(a.trackCount, 'canción', 'canciones')),
            onTap: () => context.push(Routes.artist(a.name)),
          ),
      ]);
    }
    if (show(SearchFilter.albums)) {
      group('Álbumes', 'LOCAL', [
        for (final a in albums.take(limit))
          ListTile(
            leading: SizedBox(width: 48, height: 48, child: Artwork(path: a.artPath, seed: a.title, size: 48)),
            title: Text(a.title),
            subtitle: Text(a.artist),
            onTap: () => context.push(Routes.album(a.title, a.artist)),
          ),
      ]);
    }
    if (show(SearchFilter.playlists)) {
      group('Playlists', 'LOCAL', [
        for (final p in playlists.take(limit))
          ListTile(
            leading: SizedBox(width: 48, height: 48, child: Artwork(path: p.artPath, seed: p.playlist.name, size: 48, icon: Icons.queue_music_rounded)),
            title: Text(p.playlist.name),
            subtitle: Text(plural(p.trackCount, 'canción', 'canciones')),
            onTap: () => context.push(Routes.playlist(p.playlist.id)),
          ),
      ]);
    }
    if (show(SearchFilter.folders)) {
      group('Carpetas', 'LOCAL', [
        for (final f in folders.take(limit))
          ListTile(
            leading: const Icon(Icons.folder_rounded),
            title: Text(f.path.split('/').last),
            subtitle: Text(f.path, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => context.push(Routes.folder(f.path)),
          ),
      ]);
    }
    if (openEnabled && show(SearchFilter.open)) {
      children.add(_RemoteResults(
        future: _remote,
        query: _query,
        onSearch: () => _run(_query, submit: true),
      ));
    }

    if (children.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'Sin resultados para “$_query”',
        message: openEnabled ? 'Pulsa buscar en el teclado para consultar también YouTube Music.' : null,
      );
    }
    return ListView(padding: const EdgeInsets.only(bottom: 140), children: children);
  }
}

class _RemoteResults extends ConsumerWidget {
  const _RemoteResults({required this.future, required this.query, required this.onSearch});
  final Future<YtmSearchResults>? future;
  final String query;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zc = context.zc;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.xl, ZSpace.page, ZSpace.sm),
      child: Row(
        children: [
          Expanded(child: Text('YouTube Music', style: context.tt.titleLarge)),
          Pill('SIN ANUNCIOS', color: zc.secondary),
        ],
      ),
    );
    if (future == null) {
      return Column(children: [
        header,
        ListTile(
          leading: Icon(Icons.travel_explore_rounded, color: zc.secondary),
          title: Text('Buscar “$query” en YouTube Music'),
          subtitle: const Text('Canciones y álbumes de todo el catálogo'),
          onTap: onSearch,
        ),
      ]);
    }
    return FutureBuilder<YtmSearchResults>(
      future: future,
      builder: (context, snap) {
        Widget body;
        if (snap.connectionState != ConnectionState.done) {
          body = const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        } else if (snap.hasError) {
          body = ListTile(leading: const Icon(Icons.cloud_off_rounded), title: Text(snap.error.toString()), onTap: onSearch);
        } else if (snap.data!.songs.isEmpty && snap.data!.albums.isEmpty) {
          body = const ListTile(title: Text('Sin resultados.'));
        } else {
          final songs = snap.data!.songs;
          final albums = snap.data!.albums;
          // Spotify-style: tapping a result plays it and queues the whole
          // result set; the chevron opens the track's detail page. Albums
          // open their full tracklist instead.
          Future<void> playFrom(int index) async {
            final db = ref.read(databaseProvider);
            final handler = ref.read(audioHandlerProvider);
            final tracks = ref.read(ytmSourceProvider).tracksFromCollections(songs);
            final rows = await materializeRemote(db, tracks);
            await handler.playTracks(rows, index: index.clamp(0, rows.length - 1));
          }

          body = Column(children: [
            for (final (i, c) in songs.indexed)
              ListTile(
                leading: SizedBox(width: 48, height: 48, child: Artwork(url: c.artUrl, seed: c.externalId, size: 48)),
                title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(c.creator, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => playFrom(i),
                trailing: IconButton(
                  tooltip: 'Detalles',
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: () => context.push(Routes.remoteItem(c.externalId), extra: c),
                ),
              ),
            if (albums.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.xl, ZSpace.page, ZSpace.xs),
                child: Row(children: [
                  Expanded(child: Text('Álbumes', style: context.tt.titleMedium)),
                  Pill('TRACKLIST COMPLETO', color: zc.secondary),
                ]),
              ),
              for (final a in albums.take(8))
                ListTile(
                  leading: SizedBox(width: 48, height: 48, child: Artwork(url: a.artUrl, seed: a.externalId, size: 48)),
                  title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(a.creator, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => context.push(Routes.remoteItem(a.externalId), extra: a),
                ),
            ],
          ]);
        }
        return Column(children: [header, body]);
      },
    );
  }
}
