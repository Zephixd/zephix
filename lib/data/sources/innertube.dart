// language: Dart, file: innertube.dart, target: Flutter (Zephix)
import 'package:dio/dio.dart';

/// Minimal InnerTube client (ANDROID media client) for the two read
/// endpoints Zephix needs: catalogue search and related-video lookahead.
///
/// youtube_explode's HTML page parsers broke against YouTube's current
/// markup (NoSuchMethodError in SearchPage); these endpoints return stable
/// JSON, parsed here defensively against the shapes measured in 2026:
///  - search → maps with `videoId` + `title`, author in `longBylineText`,
///    duration in `lengthText` (absent for live streams).
///  - next (related) → `videoWithContextModel` wrappers: id in the
///    `onTap` watchEndpoint, title in `lockupMetadata`, duration in
///    `timestampText`.
class Innertube {
  Innertube({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://www.youtube.com',
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              headers: {
                'User-Agent':
                    'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
                'X-Youtube-Client-Name': 'ANDROID',
                'X-Youtube-Client-Version': '20.10.38',
              },
            ));

  final Dio _dio;

  static const _ctx = {
    'context': {
      'client': {
        'clientName': 'ANDROID',
        'clientVersion': '20.10.38',
        'osName': 'Android',
        'osVersion': '11',
        'hl': 'es',
      },
    },
  };

  /// One resolved search result or related video: [InnertubeVideo].
  /// [InnertubeVideo.durationMs] is 0 when unknown (the player learns it at
  /// load time).

  Future<List<InnertubeVideo>> search(String query, {int limit = 20}) async {
    final data = await _post('search', {..._ctx, 'query': query});
    final out = <InnertubeVideo>[];
    final seen = <String>{};
    _walk(data, (m) {
      if (out.length >= limit) return;
      final id = m['videoId'] as String?;
      if (id == null || !seen.add(id)) return;
      final title = _runsText(m['title']);
      if (title == null || title.isEmpty) return;
      final ms = _timestampMs(_runsText(m['lengthText']));
      // No duration ⇒ live stream or upcoming premiere: not playable as a track.
      if (ms == null || ms < 45000) return;
      out.add(InnertubeVideo(
        videoId: id,
        title: title,
        author: _runsText(m['longBylineText']) ?? _runsText(m['shortBylineText']) ?? '',
        durationMs: ms,
        thumbnail: _thumb(m['thumbnail']),
      ));
    });
    return out;
  }

  /// Related ("radio") videos for one video id.
  Future<List<InnertubeVideo>> related(String videoId, {int limit = 20}) async {
    final data = await _post('next', {..._ctx, 'videoId': videoId});
    final out = <InnertubeVideo>[];
    final seen = <String>{videoId};
    _walkFor(data, 'videoWithContextModel', (m) {
      if (out.length >= limit) return;
      final v = _videoFromContextModel(m);
      if (v == null || !seen.add(v.videoId) || v.durationMs < 45000) return;
      out.add(v);
    });
    return out;
  }

  // --------------------------------------------------------------- helpers

  Future<Map<String, dynamic>> _post(String endpoint, Map<String, dynamic> body) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/youtubei/v1/$endpoint?prettyPrint=false',
      data: body,
    );
    return res.data ?? const {};
  }

  /// Android "videoWithContextModel": flat view-model with the interesting
  /// bits scattered across three subtrees. Measured shape (2026):
  /// `videoData.thumbnail.timestampText` (duration), `videoData.thumbnail
  /// .image.sources` (art), `videoData.dragAndDropUrl` (video id), and
  /// `videoData.lockupMetadata.lockupMetadataViewModel` (title + author).
  static InnertubeVideo? _videoFromContextModel(Map<String, dynamic> m) {
    final v = (m['videoWithContextData'] as Map?)?.cast<String, dynamic>();
    final data = (v?['videoData'] as Map?)?.cast<String, dynamic>();
    if (data == null) return null;
    // Id: the watch endpoint under onTap when present; otherwise the
    // dragAndDropUrl's `v` parameter (stable in every observed shape).
    String? id;
    final onTap = ((m['onTap'] as Map?)?['innertubeCommand'] as Map?)
        ?.cast<String, dynamic>();
    id = ((((onTap?['watchNextWatchEndpointMutationCommand'] as Map?)
                ?.cast<String, dynamic>())?['watchEndpoint'] as Map?)
            ?.cast<String, dynamic>())?['videoId'] as String?;
    id ??= Uri.tryParse((data['dragAndDropUrl'] as String?) ?? '')
        ?.queryParameters['v'];
    if (id == null || id.isEmpty) return null;
    final lockup = ((data['lockupMetadata'] as Map?)?['lockupMetadataViewModel']
            as Map?)
        ?.cast<String, dynamic>();
    final title = lockup?['title']?['content'] as String?;
    if (title == null || title.isEmpty) return null;
    final thumbObj = (data['thumbnail'] as Map?)?.cast<String, dynamic>();
    final ms = _timestampMs(thumbObj?['timestampText'] as String?) ?? 0;
    String author = '';
    final rows = ((((lockup?['metadata'] as Map?)?['contentMetadataViewModel']
                    as Map?)?['metadataRows'] as List?) ??
            const [])
        .cast<Object?>();
    for (final row in rows) {
      final parts = (((row as Map?)?['metadataParts'] as List?) ?? const [])
          .cast<Object?>();
      for (final part in parts) {
        final text = (((part as Map?)?['text'] as Map?)?['content'] as String?)
            ?.trim();
        if (text != null && text.isNotEmpty) {
          author = text.split('·').first.trim();
          break;
        }
      }
      if (author.isNotEmpty) break;
    }
    String thumb = '';
    final sources = thumbObj?['image']?['sources'];
    if (sources is List && sources.isNotEmpty) {
      final urls = [
        for (final s in sources.cast<Object?>())
          if (s is Map) s['url'] as String?
      ].whereType<String>();
      thumb = urls.firstWhere((u) => u.contains('hqdefault'), orElse: () => urls.last);
    }
    return InnertubeVideo(
      videoId: id,
      title: title,
      author: author,
      durationMs: ms,
      thumbnail: thumb,
    );
  }

  /// Depth-first walk; calls [visit] for every map.
  static void _walk(Object? node, void Function(Map<String, dynamic>) visit) {
    if (node is List) {
      for (final n in node) {
        _walk(n, visit);
      }
    } else if (node is Map) {
      visit(node.cast<String, dynamic>());
      for (final v in node.values) {
        _walk(v, visit);
      }
    }
  }

  static void _walkFor(
      Object? node, String key, void Function(Map<String, dynamic>) visit) {
    if (node is List) {
      for (final n in node) {
        _walkFor(n, key, visit);
      }
    } else if (node is Map) {
      final hit = node[key];
      if (hit is Map) visit(hit.cast<String, dynamic>());
      for (final v in node.values) {
        _walkFor(v, key, visit);
      }
    }
  }

  /// Duration fields use both shapes: `lengthText` arrives as
  /// `{"runs":[{"text":"4:27"}]}`, `timestampText` as a plain string.
  static String? _runsText(Object? field) {
    if (field is String) return field;
    if (field is! Map) return null;
    final simple = field['simpleText'];
    if (simple is String && simple.isNotEmpty) return simple;
    final runs = field['runs'];
    if (runs is List && runs.isNotEmpty) {
      final t = ((runs.first as Map?)?['text'] as String?)?.trim();
      if (t != null && t.isNotEmpty) return t;
    }
    return null;
  }

  static int? _timestampMs(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split(':').map(int.tryParse).toList();
    if (parts.isEmpty || parts.contains(null)) return null;
    var seconds = 0;
    for (final p in parts) {
      seconds = seconds * 60 + p!;
    }
    return seconds * 1000;
  }

  static String _thumb(Object? thumbnail) {
    if (thumbnail is! Map) return '';
    final sources = thumbnail['thumbnails'];
    if (sources is! List || sources.isEmpty) return '';
    final urls = [
      for (final s in sources.cast<Object?>())
        if (s is Map) s['url'] as String?
    ].whereType<String>();
    return urls.firstWhere((u) => u.contains('hqdefault'), orElse: () => urls.last);
  }
}

class InnertubeVideo {
  const InnertubeVideo({
    required this.videoId,
    required this.title,
    required this.author,
    required this.durationMs,
    required this.thumbnail,
  });

  final String videoId;
  final String title;
  final String author;
  final int durationMs;
  final String thumbnail;
}
