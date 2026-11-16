// language: Dart, file: remote_tracks.dart, target: Flutter (Zephix)
import 'package:drift/drift.dart' show Value;

import 'database/app_database.dart';
import 'sources/music_source_provider.dart';

/// Stores remote tracks so they can be queued, favourited and counted in
/// statistics. Returns rows in the same order (playable ones only).
/// Used by search, the item detail screen and the player's autoplay tail.
Future<List<TrackRow>> materializeRemote(AppDatabase db, List<RemoteTrack> tracks) async {
  final out = <TrackRow>[];
  for (final t in tracks.where((t) => t.playable)) {
    final existing = await db.trackByUri(t.streamUrl!);
    if (existing != null) {
      out.add(existing);
      continue;
    }
    final id = await db.upsertTrack(TracksCompanion.insert(
      uri: t.streamUrl!,
      title: t.title,
      artist: Value(t.artist),
      album: Value(t.album),
      durationMs: Value(t.durationMs),
      trackNumber: Value(t.trackNumber),
      artUrl: Value(t.artUrl),
      source: Value(t.sourceId),
      license: Value(t.license),
    ));
    out.add((await db.trackById(id))!);
  }
  return out;
}
