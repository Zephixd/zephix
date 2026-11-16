import 'package:drift/drift.dart';

/// A playable track. `uri` is unique so rescans never create duplicates.
/// Albums and artists are derived from these columns with grouped queries,
/// which keeps a single source of truth and avoids orphaned rows.
@DataClassName('TrackRow')
class Tracks extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// `file:///...` for local files, `https://...` for open-catalog streams.
  TextColumn get uri => text().unique()();
  TextColumn get title => text()();
  TextColumn get artist => text().withDefault(const Constant('Artista desconocido'))();
  TextColumn get album => text().withDefault(const Constant('Álbum desconocido'))();
  TextColumn get albumArtist => text().nullable()();
  TextColumn get genre => text().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  IntColumn get trackNumber => integer().nullable()();
  IntColumn get discNumber => integer().nullable()();
  IntColumn get year => integer().nullable()();
  TextColumn get artPath => text().nullable()();
  TextColumn get artUrl => text().nullable()();

  /// Id of the [MusicSourceProvider] that produced the track
  /// (`local`, `ytm`; legacy rows keep `archive`, `openverse`, `radio`).
  TextColumn get source => text().withDefault(const Constant('local'))();
  TextColumn get folder => text().nullable()();
  TextColumn get license => text().nullable()();
  TextColumn get embeddedLyrics => text().nullable()();
  IntColumn get fileSize => integer().nullable()();
  DateTimeColumn get fileModified => dateTime().nullable()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('PlaylistRow')
class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('PlaylistTrackRow')
class PlaylistTracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get playlistId =>
      integer().references(Playlists, #id, onDelete: KeyAction.cascade)();
  IntColumn get trackId =>
      integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
}

@DataClassName('FavoriteRow')
class FavoriteTracks extends Table {
  IntColumn get trackId =>
      integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {trackId};
}

/// One row per playback session of a track. Statistics and recommendations
/// are computed from this table and never leave the device.
@DataClassName('HistoryRow')
class ListeningHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get trackId =>
      integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get playedAt => dateTime()();
  IntColumn get listenedMs => integer()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  BoolColumn get skipped => boolean().withDefault(const Constant(false))();
}

@DataClassName('PreferenceRow')
class UserPreferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('LibraryFolderRow')
class LibraryFolders extends Table {
  TextColumn get path => text()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {path};
}

@DataClassName('SearchHistoryRow')
class SearchHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get query => text().unique()();
  DateTimeColumn get searchedAt => dateTime()();
}

@DataClassName('LyricsRow')
class LyricsCache extends Table {
  IntColumn get trackId =>
      integer().references(Tracks, #id, onDelete: KeyAction.cascade)();
  TextColumn get synced => text().nullable()();
  TextColumn get plain => text().nullable()();
  BoolColumn get instrumental => boolean().withDefault(const Constant(false))();
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {trackId};
}
