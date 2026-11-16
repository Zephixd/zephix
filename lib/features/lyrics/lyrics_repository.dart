import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/constants/app_info.dart';
import '../../data/database/app_database.dart';
import 'lrc_parser.dart';

/// Resolves lyrics for a track: embedded tags first, then the local cache,
/// then LRCLIB (only when the user allows online lyrics). LRCLIB is a lyrics
/// service, never an audio source. Only title, artist, album and duration
/// are sent.
class LyricsRepository {
  LyricsRepository(this._db, {Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://lrclib.net/api',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: {'User-Agent': AppInfo.userAgent},
            ));

  final AppDatabase _db;
  final Dio _dio;

  Future<Lyrics> lyricsFor(TrackRow track, {required bool allowOnline, bool refresh = false}) async {
    final embedded = track.embeddedLyrics;
    if (embedded != null && embedded.trim().isNotEmpty && !refresh) {
      return lyricsFromText(
        synced: embedded.contains(RegExp(r'\[\d+:\d+')) ? embedded : null,
        plain: embedded,
        source: 'embedded',
      );
    }

    if (!refresh) {
      final cached = await _db.cachedLyrics(track.id);
      if (cached != null) {
        return lyricsFromText(
          synced: cached.synced,
          plain: cached.plain,
          instrumental: cached.instrumental,
          source: 'lrclib',
        );
      }
    }

    if (!allowOnline) return const Lyrics();

    final found = await _fetch(track);
    if (found != null) {
      await _db.cacheLyrics(LyricsCacheCompanion.insert(
        trackId: Value(track.id),
        synced: Value(found['syncedLyrics'] as String?),
        plain: Value(found['plainLyrics'] as String?),
        instrumental: Value(found['instrumental'] == true),
        fetchedAt: DateTime.now(),
      ));
      return lyricsFromText(
        synced: found['syncedLyrics'] as String?,
        plain: found['plainLyrics'] as String?,
        instrumental: found['instrumental'] == true,
        source: 'lrclib',
      );
    }
    return const Lyrics();
  }

  Future<Map<String, dynamic>?> _fetch(TrackRow t) async {
    final artist = t.artist == 'Artista desconocido' ? null : t.artist;
    try {
      if (artist != null) {
        final res = await _dio.get<Map<String, dynamic>>('/get', queryParameters: {
          'track_name': t.title,
          'artist_name': artist,
          if (t.album != 'Álbum desconocido') 'album_name': t.album,
          if (t.durationMs > 0) 'duration': (t.durationMs / 1000).round(),
        });
        if (res.data != null) return res.data;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) rethrow;
    }

    final res = await _dio.get<List<dynamic>>('/search', queryParameters: {
      'track_name': t.title,
      'artist_name': ?artist,
    });
    final list = (res.data ?? const []).cast<Map<String, dynamic>>();
    if (list.isEmpty) return null;
    if (t.durationMs <= 0) return list.first;
    // Choose the candidate whose duration is closest to the file.
    final target = t.durationMs / 1000;
    list.sort((a, b) => (((a['duration'] as num?) ?? 0) - target)
        .abs()
        .compareTo((((b['duration'] as num?) ?? 0) - target).abs()));
    final best = list.first;
    final delta = (((best['duration'] as num?) ?? 0) - target).abs();
    return delta <= 8 ? best : null;
  }
}
