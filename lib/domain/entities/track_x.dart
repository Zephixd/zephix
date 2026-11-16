import 'package:audio_service/audio_service.dart';

import '../../data/database/app_database.dart';

/// Drift's immutable [TrackRow] is used directly as the Track entity: a
/// separate mapping layer would add code without adding meaning.
extension TrackX on TrackRow {
  Duration get duration => Duration(milliseconds: durationMs);
  /// Persisted YouTube URIs are opaque pseudo-URIs (`zephix-ytm:play/<id>`)
  /// whose backing URL is refreshed at load time.
  bool get isRemote => uri.startsWith('http') || uri.startsWith('zephix-ytm:');
  bool get isLocalFile => uri.startsWith('file:');
  String get displayArtist => albumArtist ?? artist;

  Uri? get artUri {
    if (artPath != null) return Uri.file(artPath!);
    if (artUrl != null) return Uri.tryParse(artUrl!);
    return null;
  }

  String? get filePath => isLocalFile ? Uri.parse(uri).toFilePath() : null;

  MediaItem toMediaItem() => MediaItem(
        id: uri,
        title: title,
        artist: artist,
        album: album,
        genre: genre,
        duration: durationMs > 0 ? duration : null,
        artUri: artUri,
        extras: {'trackId': id, 'source': source},
      );
}

extension MediaItemX on MediaItem {
  int? get trackId => extras?['trackId'] as int?;
}
