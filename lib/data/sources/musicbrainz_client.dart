import 'package:dio/dio.dart';

import '../../core/constants/app_info.dart';

class MusicBrainzMatch {
  const MusicBrainzMatch({
    required this.recordingId,
    required this.title,
    required this.artist,
    required this.score,
    this.album,
    this.year,
    this.lengthMs,
  });

  final String recordingId;
  final String title;
  final String artist;
  final String? album;
  final int? year;
  final int? lengthMs;
  final int score;
}

/// MusicBrainz is used only to correct tags (title, artist, album, year).
/// It is a metadata service, never an audio source. Requests are made only
/// when the user taps "Buscar metadatos", which keeps us far below the
/// one-request-per-second rate limit.
class MusicBrainzClient {
  MusicBrainzClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://musicbrainz.org/ws/2',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: {'User-Agent': AppInfo.userAgent, 'Accept': 'application/json'},
            ));

  final Dio _dio;

  static String _escape(String s) => s.replaceAllMapped(
      RegExp(r'[+\-&|!(){}\[\]^"~*?:\\/]'), (m) => '\\${m.group(0)}');

  Future<List<MusicBrainzMatch>> searchRecording(String title, {String? artist}) async {
    final q = StringBuffer('recording:"${_escape(title)}"');
    if (artist != null && artist.isNotEmpty) q.write(' AND artist:"${_escape(artist)}"');
    final res = await _dio.get<Map<String, dynamic>>('/recording',
        queryParameters: {'query': q.toString(), 'fmt': 'json', 'limit': 8});
    final recs = ((res.data?['recordings'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return [
      for (final r in recs)
        () {
          final credits = (r['artist-credit'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
          final artistName = credits
              .map((c) => '${c['name'] ?? ''}${c['joinphrase'] ?? ''}')
              .join()
              .trim();
          final releases = (r['releases'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
          final release = releases.isEmpty ? null : releases.first;
          final date = (release?['date'] ?? r['first-release-date']) as String?;
          return MusicBrainzMatch(
            recordingId: r['id'] as String,
            title: r['title'] as String? ?? title,
            artist: artistName.isEmpty ? (artist ?? '') : artistName,
            album: release?['title'] as String?,
            year: date == null || date.length < 4 ? null : int.tryParse(date.substring(0, 4)),
            lengthMs: r['length'] as int?,
            score: (r['score'] as num?)?.toInt() ?? 0,
          );
        }()
    ];
  }
}
