import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../../data/database/app_database.dart';

class BackupResult {
  const BackupResult({this.playlists = 0, this.favorites = 0, this.history = 0, this.unmatched = 0});
  final int playlists;
  final int favorites;
  final int history;
  final int unmatched;
}

/// JSON backup of user data. Tracks are referenced by uri, so a backup can
/// be restored after reinstalling once the same music has been rescanned.
class BackupService {
  BackupService(this._db);
  final AppDatabase _db;

  static const formatVersion = 1;

  Future<String> export() async {
    final tracks = {for (final t in await _db.allTracks()) t.id: t.uri};
    final playlists = await _db.select(_db.playlists).get();
    final out = <String, Object?>{
      'app': 'zephix',
      'version': formatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'preferences': await _db.preferences()..remove('player.state'),
      'favorites': [for (final id in await _db.favoriteIds()) ?tracks[id]],
      'playlists': [
        for (final p in playlists)
          {
            'name': p.name,
            'description': p.description,
            'createdAt': p.createdAt.toIso8601String(),
            'tracks': [for (final t in await _db.playlistTracksOnce(p.id)) t.uri],
          }
      ],
      'history': [
        for (final h in await _db.historySince(DateTime.fromMillisecondsSinceEpoch(0)))
          if (tracks[h.trackId] != null)
            {
              'uri': tracks[h.trackId],
              'playedAt': h.playedAt.toIso8601String(),
              'listenedMs': h.listenedMs,
              'completed': h.completed,
              'skipped': h.skipped,
            }
      ],
    };
    return const JsonEncoder.withIndent(' ').convert(out);
  }

  /// Merges a backup into the current database. Existing data is kept.
  Future<BackupResult> import(String json) async {
    final data = jsonDecode(json) as Map<String, dynamic>;
    if (data['app'] != 'zephix') throw const FormatException('No es una copia de seguridad de Zephix.');
    final byUri = {for (final t in await _db.allTracks()) t.uri: t.id};
    var unmatched = 0, favs = 0, pls = 0, hist = 0;

    await _db.transaction(() async {
      final prefs = (data['preferences'] as Map?)?.cast<String, dynamic>() ?? const {};
      for (final e in prefs.entries) {
        await _db.setPreference(e.key, '${e.value}');
      }

      final existingFavs = await _db.favoriteIds();
      for (final uri in (data['favorites'] as List? ?? const []).cast<String>()) {
        final id = byUri[uri];
        if (id == null) {
          unmatched++;
        } else if (!existingFavs.contains(id)) {
          await _db.toggleFavorite(id);
          favs++;
        }
      }

      for (final p in (data['playlists'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        final ids = <int>[];
        for (final uri in (p['tracks'] as List? ?? const []).cast<String>()) {
          final id = byUri[uri];
          if (id == null) {
            unmatched++;
          } else {
            ids.add(id);
          }
        }
        final pid = await _db.createPlaylist(p['name'] as String, description: p['description'] as String?);
        await _db.addTracksToPlaylist(pid, ids);
        pls++;
      }

      final existing = {
        for (final h in await _db.historySince(DateTime.fromMillisecondsSinceEpoch(0)))
          '${h.trackId}@${h.playedAt.millisecondsSinceEpoch}'
      };
      await _db.batch((b) {
        for (final h in (data['history'] as List? ?? const []).cast<Map<String, dynamic>>()) {
          final id = byUri[h['uri']];
          if (id == null) continue;
          final at = DateTime.parse(h['playedAt'] as String);
          if (existing.contains('$id@${at.millisecondsSinceEpoch}')) continue;
          b.insert(
            _db.listeningHistory,
            ListeningHistoryCompanion.insert(
              trackId: id,
              playedAt: at,
              listenedMs: h['listenedMs'] as int,
              completed: Value(h['completed'] as bool? ?? false),
              skipped: Value(h['skipped'] as bool? ?? false),
            ),
          );
          hist++;
        }
      });
    });
    return BackupResult(playlists: pls, favorites: favs, history: hist, unmatched: unmatched);
  }
}
