import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

/// Aggregated album derived from [Tracks].
class AlbumSummary {
  const AlbumSummary({
    required this.title,
    required this.artist,
    required this.trackCount,
    this.artPath,
    this.year,
  });
  final String title;
  final String artist;
  final int trackCount;
  final String? artPath;
  final int? year;
}

/// Aggregated artist derived from [Tracks].
class ArtistSummary {
  const ArtistSummary({
    required this.name,
    required this.trackCount,
    required this.albumCount,
    this.artPath,
  });
  final String name;
  final int trackCount;
  final int albumCount;
  final String? artPath;
}

class PlaylistSummary {
  const PlaylistSummary(this.playlist, this.trackCount, this.artPath);
  final PlaylistRow playlist;
  final int trackCount;
  final String? artPath;
}

class PlaylistEntry {
  const PlaylistEntry(this.entryId, this.position, this.track);
  final int entryId;
  final int position;
  final TrackRow track;
}

class FolderSummary {
  const FolderSummary(this.path, this.trackCount);
  final String path;
  final int trackCount;
}

enum TrackSort { title, artist, album, recentlyAdded }

@DriftDatabase(
  tables: [
    Tracks,
    Playlists,
    PlaylistTracks,
    FavoriteTracks,
    ListeningHistory,
    UserPreferences,
    LibraryFolders,
    SearchHistory,
    LyricsCache,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'zephix'));

  /// Bump this and add a step in [migration] for every schema change.
  /// Never drop user tables in an upgrade: playlists, favourites and history
  /// must survive app updates.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_history_track ON listening_history(track_id)');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_history_played ON listening_history(played_at)');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_playlist_tracks ON playlist_tracks(playlist_id, position)');
        },
        onUpgrade: (m, from, to) async {
          // Future migrations go here, e.g.:
          // if (from < 2) await m.addColumn(tracks, tracks.someNewColumn);
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  // ---------------------------------------------------------------- tracks

  Stream<List<TrackRow>> watchTracks({TrackSort sort = TrackSort.title}) {
    final q = select(tracks);
    switch (sort) {
      case TrackSort.title:
        q.orderBy([(t) => OrderingTerm(expression: t.title.collate(Collate.noCase))]);
      case TrackSort.artist:
        q.orderBy([
          (t) => OrderingTerm(expression: t.artist.collate(Collate.noCase)),
          (t) => OrderingTerm(expression: t.title.collate(Collate.noCase)),
        ]);
      case TrackSort.album:
        q.orderBy([
          (t) => OrderingTerm(expression: t.album.collate(Collate.noCase)),
          (t) => OrderingTerm(expression: t.discNumber),
          (t) => OrderingTerm(expression: t.trackNumber),
        ]);
      case TrackSort.recentlyAdded:
        q.orderBy([(t) => OrderingTerm.desc(t.addedAt)]);
    }
    return q.watch();
  }

  Future<List<TrackRow>> allTracks() => select(tracks).get();

  Future<TrackRow?> trackById(int id) =>
      (select(tracks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<TrackRow?> trackByUri(String uri) =>
      (select(tracks)..where((t) => t.uri.equals(uri))).getSingleOrNull();

  Future<List<TrackRow>> tracksByIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await (select(tracks)..where((t) => t.id.isIn(ids))).get();
    final byId = {for (final r in rows) r.id: r};
    return [for (final id in ids) ?byId[id]];
  }

  Stream<List<TrackRow>> watchAlbumTracks(String album, String artist) {
    return (select(tracks)
          ..where((t) =>
              t.album.equals(album) &
              (t.albumArtist.equals(artist) |
                  (t.albumArtist.isNull() & t.artist.equals(artist))))
          ..orderBy([
            (t) => OrderingTerm(expression: t.discNumber),
            (t) => OrderingTerm(expression: t.trackNumber),
            (t) => OrderingTerm(expression: t.title),
          ]))
        .watch();
  }

  Stream<List<TrackRow>> watchArtistTracks(String artist) {
    return (select(tracks)
          ..where((t) => t.artist.equals(artist) | t.albumArtist.equals(artist))
          ..orderBy([
            (t) => OrderingTerm(expression: t.album),
            (t) => OrderingTerm(expression: t.trackNumber),
          ]))
        .watch();
  }

  Stream<List<TrackRow>> watchFolderTracks(String folder) {
    return (select(tracks)
          ..where((t) => t.folder.equals(folder))
          ..orderBy([(t) => OrderingTerm(expression: t.title)]))
        .watch();
  }

  Stream<List<TrackRow>> watchGenreTracks(String genre) {
    return (select(tracks)
          ..where((t) => t.genre.equals(genre))
          ..orderBy([(t) => OrderingTerm(expression: t.artist)]))
        .watch();
  }

  Stream<List<TrackRow>> watchTracksBySource(String source) {
    return (select(tracks)
          ..where((t) => t.source.equals(source))
          ..orderBy([(t) => OrderingTerm.desc(t.addedAt)]))
        .watch();
  }

  Stream<List<TrackRow>> watchTracksBySources(List<String> sources) {
    return (select(tracks)
          ..where((t) => t.source.isIn(sources))
          ..orderBy([(t) => OrderingTerm.desc(t.addedAt)]))
        .watch();
  }

  Future<List<TrackRow>> searchTracks(String query, {int limit = 50}) {
    final like = '%${query.replaceAll('%', r'\%')}%';
    return (select(tracks)
          ..where((t) =>
              t.title.like(like) |
              t.artist.like(like) |
              t.album.like(like) |
              t.genre.like(like))
          ..limit(limit))
        .get();
  }

  /// Insert or update by unique `uri`, returning the row id.
  Future<int> upsertTrack(TracksCompanion entry) async {
    await into(tracks).insert(
      entry,
      onConflict: DoUpdate(
        (old) => entry.copyWith(id: const Value.absent(), addedAt: const Value.absent()),
        target: [tracks.uri],
      ),
    );
    final row = await trackByUri(entry.uri.value);
    return row!.id;
  }

  /// Removes local tracks inside [folder] whose uri is not in [keep].
  Future<int> pruneFolder(String folder, Set<String> keep) async {
    final existing = await (select(tracks)
          ..where((t) => t.source.equals('local') & t.folder.like('$folder%')))
        .get();
    final stale = existing.where((t) => !keep.contains(t.uri)).map((t) => t.id).toList();
    if (stale.isEmpty) return 0;
    return (delete(tracks)..where((t) => t.id.isIn(stale))).go();
  }

  Future<void> deleteTrack(int id) => (delete(tracks)..where((t) => t.id.equals(id))).go();

  Future<Map<String, DateTime?>> localFileIndex() async {
    final rows = await (select(tracks)..where((t) => t.source.equals('local'))).get();
    return {for (final r in rows) r.uri: r.fileModified};
  }

  // -------------------------------------------------------- albums/artists

  Stream<List<AlbumSummary>> watchAlbums() {
    return customSelect(
      'SELECT album, COALESCE(album_artist, artist) AS a, COUNT(*) AS n, '
      'MAX(art_path) AS art, MAX(year) AS y FROM tracks '
      'GROUP BY album, COALESCE(album_artist, artist) '
      'ORDER BY album COLLATE NOCASE',
      readsFrom: {tracks},
    ).watch().map((rows) => [
          for (final r in rows)
            AlbumSummary(
              title: r.read<String>('album'),
              artist: r.read<String>('a'),
              trackCount: r.read<int>('n'),
              artPath: r.readNullable<String>('art'),
              year: r.readNullable<int>('y'),
            )
        ]);
  }

  Stream<List<AlbumSummary>> watchRecentAlbums({int limit = 12}) {
    return customSelect(
      'SELECT album, COALESCE(album_artist, artist) AS a, COUNT(*) AS n, '
      'MAX(art_path) AS art, MAX(year) AS y, MAX(added_at) AS added FROM tracks '
      'GROUP BY album, COALESCE(album_artist, artist) ORDER BY added DESC LIMIT ?',
      variables: [Variable.withInt(limit)],
      readsFrom: {tracks},
    ).watch().map((rows) => [
          for (final r in rows)
            AlbumSummary(
              title: r.read<String>('album'),
              artist: r.read<String>('a'),
              trackCount: r.read<int>('n'),
              artPath: r.readNullable<String>('art'),
              year: r.readNullable<int>('y'),
            )
        ]);
  }

  Stream<List<ArtistSummary>> watchArtists() {
    return customSelect(
      'SELECT artist, COUNT(*) AS n, COUNT(DISTINCT album) AS albums, '
      'MAX(art_path) AS art FROM tracks GROUP BY artist ORDER BY artist COLLATE NOCASE',
      readsFrom: {tracks},
    ).watch().map((rows) => [
          for (final r in rows)
            ArtistSummary(
              name: r.read<String>('artist'),
              trackCount: r.read<int>('n'),
              albumCount: r.read<int>('albums'),
              artPath: r.readNullable<String>('art'),
            )
        ]);
  }

  Stream<List<AlbumSummary>> watchArtistAlbums(String artist) {
    return watchAlbums().map((all) => all.where((a) => a.artist == artist).toList());
  }

  Stream<List<(String, int)>> watchGenres() {
    return customSelect(
      'SELECT genre, COUNT(*) AS n FROM tracks WHERE genre IS NOT NULL AND genre != \'\' '
      'GROUP BY genre ORDER BY n DESC',
      readsFrom: {tracks},
    ).watch().map((rows) => [for (final r in rows) (r.read<String>('genre'), r.read<int>('n'))]);
  }

  Stream<List<FolderSummary>> watchTrackFolders() {
    return customSelect(
      'SELECT folder, COUNT(*) AS n FROM tracks WHERE folder IS NOT NULL '
      'GROUP BY folder ORDER BY folder COLLATE NOCASE',
      readsFrom: {tracks},
    ).watch().map(
        (rows) => [for (final r in rows) FolderSummary(r.read<String>('folder'), r.read<int>('n'))]);
  }

  // ------------------------------------------------------------- favorites

  Stream<Set<int>> watchFavoriteIds() =>
      select(favoriteTracks).watch().map((rows) => {for (final r in rows) r.trackId});

  Future<Set<int>> favoriteIds() async =>
      {for (final r in await select(favoriteTracks).get()) r.trackId};

  Stream<List<TrackRow>> watchFavoriteTracks() {
    final q = select(tracks).join([
      innerJoin(favoriteTracks, favoriteTracks.trackId.equalsExp(tracks.id)),
    ])
      ..orderBy([OrderingTerm.desc(favoriteTracks.addedAt)]);
    return q.watch().map((rows) => [for (final r in rows) r.readTable(tracks)]);
  }

  Future<bool> toggleFavorite(int trackId) async {
    final existing = await (select(favoriteTracks)..where((f) => f.trackId.equals(trackId)))
        .getSingleOrNull();
    if (existing != null) {
      await (delete(favoriteTracks)..where((f) => f.trackId.equals(trackId))).go();
      return false;
    }
    await into(favoriteTracks).insert(FavoriteTracksCompanion.insert(trackId: Value(trackId)));
    return true;
  }

  // ------------------------------------------------------------- playlists

  Stream<List<PlaylistSummary>> watchPlaylists() {
    return customSelect(
      'SELECT p.*, COUNT(pt.id) AS n, '
      '(SELECT t.art_path FROM playlist_tracks pt2 JOIN tracks t ON t.id = pt2.track_id '
      ' WHERE pt2.playlist_id = p.id AND t.art_path IS NOT NULL ORDER BY pt2.position LIMIT 1) AS art '
      'FROM playlists p LEFT JOIN playlist_tracks pt ON pt.playlist_id = p.id '
      'GROUP BY p.id ORDER BY p.updated_at DESC',
      readsFrom: {playlists, playlistTracks, tracks},
    ).watch().map((rows) => [
          for (final r in rows)
            PlaylistSummary(
              playlists.map(r.data),
              r.read<int>('n'),
              r.readNullable<String>('art'),
            )
        ]);
  }

  Stream<PlaylistRow?> watchPlaylist(int id) =>
      (select(playlists)..where((p) => p.id.equals(id))).watchSingleOrNull();

  Stream<List<PlaylistEntry>> watchPlaylistEntries(int playlistId) {
    final q = select(playlistTracks).join([
      innerJoin(tracks, tracks.id.equalsExp(playlistTracks.trackId)),
    ])
      ..where(playlistTracks.playlistId.equals(playlistId))
      ..orderBy([OrderingTerm(expression: playlistTracks.position)]);
    return q.watch().map((rows) => [
          for (final r in rows)
            PlaylistEntry(
              r.readTable(playlistTracks).id,
              r.readTable(playlistTracks).position,
              r.readTable(tracks),
            )
        ]);
  }

  Future<List<TrackRow>> playlistTracksOnce(int playlistId) =>
      watchPlaylistEntries(playlistId).first.then((e) => [for (final x in e) x.track]);

  Future<int> createPlaylist(String name, {String? description}) {
    return into(playlists)
        .insert(PlaylistsCompanion.insert(name: name.trim(), description: Value(description)));
  }

  Future<void> renamePlaylist(int id, String name, {String? description}) {
    return (update(playlists)..where((p) => p.id.equals(id))).write(PlaylistsCompanion(
      name: Value(name.trim()),
      description: Value(description),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> deletePlaylist(int id) => (delete(playlists)..where((p) => p.id.equals(id))).go();

  Future<int> duplicatePlaylist(int id) async {
    final source = await (select(playlists)..where((p) => p.id.equals(id))).getSingle();
    return transaction(() async {
      final newId = await createPlaylist('${source.name} (copia)', description: source.description);
      final entries = await playlistTracksOnce(id);
      await addTracksToPlaylist(newId, [for (final t in entries) t.id]);
      return newId;
    });
  }

  Future<void> addTracksToPlaylist(int playlistId, List<int> trackIds) async {
    if (trackIds.isEmpty) return;
    await transaction(() async {
      final maxPos = playlistTracks.position.max();
      final current = await (selectOnly(playlistTracks)
            ..addColumns([maxPos])
            ..where(playlistTracks.playlistId.equals(playlistId)))
          .map((r) => r.read(maxPos))
          .getSingle();
      var pos = (current ?? -1) + 1;
      await batch((b) {
        for (final id in trackIds) {
          b.insert(playlistTracks,
              PlaylistTracksCompanion.insert(playlistId: playlistId, trackId: id, position: pos++));
        }
      });
      await _touchPlaylist(playlistId);
    });
  }

  Future<void> removePlaylistEntry(int playlistId, int entryId) async {
    await transaction(() async {
      await (delete(playlistTracks)..where((e) => e.id.equals(entryId))).go();
      await _renumber(playlistId);
      await _touchPlaylist(playlistId);
    });
  }

  Future<void> movePlaylistEntry(int playlistId, int oldIndex, int newIndex) async {
    await transaction(() async {
      final entries = await (select(playlistTracks)
            ..where((e) => e.playlistId.equals(playlistId))
            ..orderBy([(e) => OrderingTerm(expression: e.position)]))
          .get();
      if (oldIndex < 0 || oldIndex >= entries.length) return;
      final moved = entries.removeAt(oldIndex);
      entries.insert(newIndex.clamp(0, entries.length), moved);
      await batch((b) {
        for (var i = 0; i < entries.length; i++) {
          b.update(playlistTracks, PlaylistTracksCompanion(position: Value(i)),
              where: (e) => e.id.equals(entries[i].id));
        }
      });
      await _touchPlaylist(playlistId);
    });
  }

  Future<void> _renumber(int playlistId) async {
    final entries = await (select(playlistTracks)
          ..where((e) => e.playlistId.equals(playlistId))
          ..orderBy([(e) => OrderingTerm(expression: e.position)]))
        .get();
    await batch((b) {
      for (var i = 0; i < entries.length; i++) {
        b.update(playlistTracks, PlaylistTracksCompanion(position: Value(i)),
            where: (e) => e.id.equals(entries[i].id));
      }
    });
  }

  Future<void> _touchPlaylist(int id) => (update(playlists)..where((p) => p.id.equals(id)))
      .write(PlaylistsCompanion(updatedAt: Value(DateTime.now())));

  // --------------------------------------------------------------- history

  Future<void> recordPlay({
    required int trackId,
    required DateTime playedAt,
    required int listenedMs,
    required bool completed,
    required bool skipped,
  }) {
    return into(listeningHistory).insert(ListeningHistoryCompanion.insert(
      trackId: trackId,
      playedAt: playedAt,
      listenedMs: listenedMs,
      completed: Value(completed),
      skipped: Value(skipped),
    ));
  }

  Stream<List<TrackRow>> watchRecentlyPlayed({int limit = 20}) {
    return customSelect(
      'SELECT t.* FROM tracks t JOIN (SELECT track_id, MAX(played_at) AS last '
      'FROM listening_history GROUP BY track_id) h ON h.track_id = t.id '
      'ORDER BY h.last DESC LIMIT ?',
      variables: [Variable.withInt(limit)],
      readsFrom: {tracks, listeningHistory},
    ).watch().map((rows) => [for (final r in rows) tracks.map(r.data)]);
  }

  Stream<List<HistoryRow>> watchHistorySince(DateTime since) {
    return (select(listeningHistory)
          ..where((h) => h.playedAt.isBiggerOrEqualValue(since))
          ..orderBy([(h) => OrderingTerm.desc(h.playedAt)]))
        .watch();
  }

  Future<List<HistoryRow>> historySince(DateTime since) =>
      (select(listeningHistory)..where((h) => h.playedAt.isBiggerOrEqualValue(since))).get();

  Stream<int> watchHistoryCount() {
    final c = listeningHistory.id.count();
    return (selectOnly(listeningHistory)..addColumns([c])).map((r) => r.read(c) ?? 0).watchSingle();
  }

  Future<void> clearHistory() => delete(listeningHistory).go();

  // ----------------------------------------------------------- preferences

  Stream<Map<String, String>> watchPreferences() =>
      select(userPreferences).watch().map((rows) => {for (final r in rows) r.key: r.value});

  Future<Map<String, String>> preferences() async =>
      {for (final r in await select(userPreferences).get()) r.key: r.value};

  Future<void> setPreference(String key, String value) => into(userPreferences)
      .insertOnConflictUpdate(UserPreferencesCompanion.insert(key: key, value: value));

  // --------------------------------------------------------------- folders

  Stream<List<LibraryFolderRow>> watchLibraryFolders() => select(libraryFolders).watch();

  Future<List<LibraryFolderRow>> libraryFolderList() => select(libraryFolders).get();

  Future<void> addLibraryFolder(String path) => into(libraryFolders)
      .insert(LibraryFoldersCompanion.insert(path: path), mode: InsertMode.insertOrIgnore);

  Future<void> removeLibraryFolder(String path) async {
    await transaction(() async {
      await (delete(libraryFolders)..where((f) => f.path.equals(path))).go();
      await (delete(tracks)..where((t) => t.source.equals('local') & t.folder.like('$path%'))).go();
    });
  }

  // -------------------------------------------------------- search history

  Stream<List<String>> watchSearchHistory({int limit = 12}) => (select(searchHistory)
        ..orderBy([(s) => OrderingTerm.desc(s.searchedAt)])
        ..limit(limit))
      .watch()
      .map((rows) => [for (final r in rows) r.query]);

  Future<void> addSearch(String query) => into(searchHistory).insert(
        SearchHistoryCompanion.insert(query: query.trim(), searchedAt: DateTime.now()),
        onConflict: DoUpdate((_) => SearchHistoryCompanion(searchedAt: Value(DateTime.now())),
            target: [searchHistory.query]),
      );

  Future<void> removeSearch(String query) =>
      (delete(searchHistory)..where((s) => s.query.equals(query))).go();

  Future<void> clearSearchHistory() => delete(searchHistory).go();

  // ---------------------------------------------------------------- lyrics

  Future<LyricsRow?> cachedLyrics(int trackId) =>
      (select(lyricsCache)..where((l) => l.trackId.equals(trackId))).getSingleOrNull();

  Future<void> cacheLyrics(LyricsCacheCompanion entry) =>
      into(lyricsCache).insertOnConflictUpdate(entry);

  Future<void> clearLyricsCache() => delete(lyricsCache).go();
}
