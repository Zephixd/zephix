import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/services/download_service.dart';
import '../core/services/zephix_audio_handler.dart';
import '../data/database/app_database.dart';
import '../data/sources/local_library_scanner.dart';
import '../data/sources/musicbrainz_client.dart';
import '../data/sources/ytm_source.dart';
import '../features/lyrics/lrc_parser.dart';
import '../features/lyrics/lyrics_repository.dart';
import '../features/recommendations/recommendation_engine.dart';
import '../features/settings/app_settings.dart';
import '../features/statistics/stats_engine.dart';

// ------------------------------------------------------------------- core

/// Overridden in main() with the opened database.
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError());

/// Overridden in main() with the handler returned by AudioService.init.
final audioHandlerProvider = Provider<ZephixAudioHandler>((ref) => throw UnimplementedError());

final ytmSourceProvider = Provider<YtmSource>((ref) => YtmSource());

final musicBrainzProvider = Provider((ref) => MusicBrainzClient());

final downloadServiceProvider = Provider((ref) => DownloadService(ref.watch(databaseProvider)));

final lyricsRepositoryProvider = Provider((ref) => LyricsRepository(ref.watch(databaseProvider)));

// --------------------------------------------------------------- settings

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => AppSettings.fromPrefs(ref.read(initialPreferencesProvider));

  Future<void> update(AppSettings Function(AppSettings) change) async {
    final next = change(state);
    state = next;
    final db = ref.read(databaseProvider);
    await db.transaction(() async {
      for (final e in next.toPrefs().entries) {
        await db.setPreference(e.key, e.value);
      }
    });
    await applyToPlayer(next);
  }

  Future<void> applyToPlayer(AppSettings s) async {
    final handler = ref.read(audioHandlerProvider);
    handler.recordHistory = s.historyEnabled;
    await handler.applyPlaybackSettings(
      skipSilence: s.skipSilence,
      eqEnabled: s.eqEnabled,
      eqGains: s.eqGains.isEmpty ? null : s.eqGains,
    );
  }
}

/// Preferences read once at startup so the first frame already has the
/// right theme. Overridden in main().
final initialPreferencesProvider = Provider<Map<String, String>>((ref) => const {});

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

// ---------------------------------------------------------------- library

class TrackSortNotifier extends Notifier<TrackSort> {
  @override
  TrackSort build() => TrackSort.title;
  void set(TrackSort s) => state = s;
}

final trackSortProvider = NotifierProvider<TrackSortNotifier, TrackSort>(TrackSortNotifier.new);

final tracksProvider = StreamProvider<List<TrackRow>>(
    (ref) => ref.watch(databaseProvider).watchTracks(sort: ref.watch(trackSortProvider)));

final albumsProvider = StreamProvider((ref) => ref.watch(databaseProvider).watchAlbums());
final recentAlbumsProvider = StreamProvider((ref) => ref.watch(databaseProvider).watchRecentAlbums());
final artistsProvider = StreamProvider((ref) => ref.watch(databaseProvider).watchArtists());
final genresProvider = StreamProvider((ref) => ref.watch(databaseProvider).watchGenres());
final trackFoldersProvider = StreamProvider((ref) => ref.watch(databaseProvider).watchTrackFolders());
final libraryFoldersProvider = StreamProvider((ref) => ref.watch(databaseProvider).watchLibraryFolders());
final favoriteIdsProvider = StreamProvider((ref) => ref.watch(databaseProvider).watchFavoriteIds());
final favoriteTracksProvider = StreamProvider((ref) => ref.watch(databaseProvider).watchFavoriteTracks());
final playlistsProvider = StreamProvider((ref) => ref.watch(databaseProvider).watchPlaylists());
final recentlyPlayedProvider =
    StreamProvider((ref) => ref.watch(databaseProvider).watchRecentlyPlayed(limit: 20));
/// Remote tracks kept on the device: streamed pieces downloaded from any
/// source that permits saving (Internet Archive, Openverse).
final downloadsProvider =
    StreamProvider((ref) => ref.watch(databaseProvider).watchTracksBySources(['archive', 'openverse']));
final searchHistoryProvider = StreamProvider((ref) => ref.watch(databaseProvider).watchSearchHistory());

final albumTracksProvider = StreamProvider.family<List<TrackRow>, (String, String)>(
    (ref, key) => ref.watch(databaseProvider).watchAlbumTracks(key.$1, key.$2));
final artistTracksProvider = StreamProvider.family<List<TrackRow>, String>(
    (ref, artist) => ref.watch(databaseProvider).watchArtistTracks(artist));
final artistAlbumsProvider = StreamProvider.family<List<AlbumSummary>, String>(
    (ref, artist) => ref.watch(databaseProvider).watchArtistAlbums(artist));
final folderTracksProvider = StreamProvider.family<List<TrackRow>, String>(
    (ref, folder) => ref.watch(databaseProvider).watchFolderTracks(folder));
final genreTracksProvider = StreamProvider.family<List<TrackRow>, String>(
    (ref, genre) => ref.watch(databaseProvider).watchGenreTracks(genre));
final playlistProvider = StreamProvider.family<PlaylistRow?, int>(
    (ref, id) => ref.watch(databaseProvider).watchPlaylist(id));
final playlistEntriesProvider = StreamProvider.family<List<PlaylistEntry>, int>(
    (ref, id) => ref.watch(databaseProvider).watchPlaylistEntries(id));

// ---------------------------------------------------------------- scanning

class ScanNotifier extends Notifier<ScanProgress> {
  @override
  ScanProgress build() => const ScanProgress();

  /// Requests the right media permission for this Android version.
  static Future<bool> ensurePermission() async {
    if (!Platform.isAndroid) return true;
    final statuses = await [Permission.audio, Permission.storage].request();
    return statuses.values.any((s) => s.isGranted || s.isLimited);
  }

  Future<void> scan({bool force = false}) async {
    if (state.running) return;
    final db = ref.read(databaseProvider);
    if (!await ensurePermission()) {
      state = const ScanProgress(message: 'Permiso de audio denegado. Concédelo en Ajustes del sistema.');
      return;
    }
    var folders = (await db.libraryFolderList()).map((f) => f.path).toList();
    if (folders.isEmpty && Platform.isAndroid) {
      for (final d in ['/storage/emulated/0/Music', '/storage/emulated/0/Download']) {
        if (await Directory(d).exists()) {
          await db.addLibraryFolder(d);
          folders.add(d);
        }
      }
    }
    if (folders.isEmpty) {
      state = const ScanProgress(message: 'Añade una carpeta con música para empezar.');
      return;
    }
    final scanner = LocalLibraryScanner(db, minDurationMs: ref.read(settingsProvider).minTrackSeconds * 1000);
    await for (final p in scanner.scan(folders, force: force)) {
      state = p;
    }
  }

  Future<int> addFiles(List<String> paths) =>
      LocalLibraryScanner(ref.read(databaseProvider)).addFiles(paths);
}

final scanProvider = NotifierProvider<ScanNotifier, ScanProgress>(ScanNotifier.new);

// ---------------------------------------------------------------- playback

final queueTracksProvider =
    StreamProvider<List<TrackRow>>((ref) => ref.watch(audioHandlerProvider).tracksStream);

final currentTrackProvider =
    StreamProvider<TrackRow?>((ref) => ref.watch(audioHandlerProvider).currentTrackStream);

final currentIndexProvider =
    StreamProvider<int?>((ref) => ref.watch(audioHandlerProvider).player.currentIndexStream);

final playbackStateProvider =
    StreamProvider<PlaybackState>((ref) => ref.watch(audioHandlerProvider).playbackState);

final playingProvider = StreamProvider<bool>((ref) => ref.watch(audioHandlerProvider).player.playingStream);

final positionProvider =
    StreamProvider<Duration>((ref) => ref.watch(audioHandlerProvider).player.positionStream);

final durationProvider =
    StreamProvider<Duration?>((ref) => ref.watch(audioHandlerProvider).player.durationStream);

final bufferedProvider =
    StreamProvider<Duration>((ref) => ref.watch(audioHandlerProvider).player.bufferedPositionStream);

final shuffleProvider =
    StreamProvider<bool>((ref) => ref.watch(audioHandlerProvider).player.shuffleModeEnabledStream);

final loopModeProvider = StreamProvider<LoopMode>((ref) => ref.watch(audioHandlerProvider).player.loopModeStream);

final processingProvider =
    StreamProvider<ProcessingState>((ref) => ref.watch(audioHandlerProvider).player.processingStateStream);

final sleepAtProvider = StreamProvider<DateTime?>((ref) => ref.watch(audioHandlerProvider).sleepAtStream);
final sleepEndOfTrackProvider =
    StreamProvider<bool>((ref) => ref.watch(audioHandlerProvider).sleepAtEndOfTrackStream);

// ------------------------------------------------------------------ lyrics

final lyricsProvider = FutureProvider.autoDispose.family<Lyrics, int>((ref, trackId) async {
  final db = ref.watch(databaseProvider);
  final track = await db.trackById(trackId);
  if (track == null) return const Lyrics();
  final online = ref.watch(settingsProvider.select((s) => s.onlineLyrics));
  return ref.watch(lyricsRepositoryProvider).lyricsFor(track, allowOnline: online);
});

// ------------------------------------------------- statistics / recommendations

enum StatsRange { week, month, year, all }

final _historyAllProvider = StreamProvider<List<HistoryRow>>(
    (ref) => ref.watch(databaseProvider).watchHistorySince(DateTime.fromMillisecondsSinceEpoch(0)));

final _trackMapProvider = Provider<Map<int, TrackRow>>((ref) {
  final all = ref.watch(_allTracksUnsortedProvider).value ?? const [];
  return {for (final t in all) t.id: t};
});

final _allTracksUnsortedProvider =
    StreamProvider<List<TrackRow>>((ref) => ref.watch(databaseProvider).watchTracks());

final statsProvider = Provider.family<AsyncValue<ListeningStats>, StatsRange>((ref, range) {
  final history = ref.watch(_historyAllProvider);
  final tracks = ref.watch(_trackMapProvider);
  return history.whenData((h) {
    final now = DateTime.now();
    final from = switch (range) {
      StatsRange.week => DateTime(now.year, now.month, now.day - 6),
      StatsRange.month => DateTime(now.year, now.month, 1),
      StatsRange.year => DateTime(now.year, 1, 1),
      StatsRange.all => h.isEmpty
          ? DateTime(now.year, now.month, now.day)
          : h.map((e) => e.playedAt).reduce((a, b) => a.isBefore(b) ? a : b),
    };
    return computeStats(history: h, tracks: tracks, from: from, to: now, top: 10);
  });
});

final recommendationEngineProvider = Provider<RecommendationEngine>((ref) => const LocalScoringEngine());

final smartMixesProvider = Provider<AsyncValue<List<SmartMix>>>((ref) {
  final library = ref.watch(_allTracksUnsortedProvider);
  final history = ref.watch(_historyAllProvider);
  final favs = ref.watch(favoriteIdsProvider);
  final tracks = ref.watch(_trackMapProvider);
  final engine = ref.watch(recommendationEngineProvider);
  if (library.isLoading || history.isLoading || favs.isLoading) return const AsyncLoading();
  final lib = library.value ?? const [];
  final signals = buildSignals(history.value ?? const [], favs.value ?? const {}, tracks);
  return AsyncData(engine.buildMixes(lib, signals));
});

/// Recently updated, non-empty playlists for the home dashboard.
final frequentPlaylistsProvider = Provider<List<PlaylistSummary>>((ref) {
  return ref.watch(playlistsProvider).value?.where((p) => p.trackCount > 0).take(6).toList() ?? const [];
});
