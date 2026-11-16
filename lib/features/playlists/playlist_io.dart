import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../app/router/routes.dart';
import '../../data/database/app_database.dart';
import '../../domain/entities/track_x.dart';
import '../../shared/widgets/common.dart';
import 'm3u.dart';

/// Imports an M3U/M3U8 file. Entries are matched against tracks already in
/// the library by path, then by "Artist - Title"; unmatched entries are
/// reported instead of being silently dropped.
Future<void> importM3uFlow(BuildContext context, WidgetRef ref) async {
  final picked = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['m3u', 'm3u8']);
  if (picked.isEmpty || picked.first.path == null) return;
  final file = File(picked.first.path!);
  final db = ref.read(databaseProvider);
  final text = await file.readAsString(encoding: const Utf8Codec(allowMalformed: true));
  final parsed = parseM3u(text, baseDir: p.dirname(file.path));
  final all = await db.allTracks();
  final byPath = {for (final t in all) (t.filePath ?? t.uri): t};
  final byName = {for (final t in all) p.basename(t.filePath ?? t.uri).toLowerCase(): t};
  final byLabel = {for (final t in all) '${t.artist} - ${t.title}'.toLowerCase(): t};

  final ids = <int>[];
  var missing = 0;
  for (final e in parsed.entries) {
    final t = byPath[e.location] ??
        byName[p.basename(e.location).toLowerCase()] ??
        (e.title == null ? null : byLabel[e.title!.toLowerCase()]);
    if (t == null) {
      missing++;
    } else {
      ids.add(t.id);
    }
  }
  final name = parsed.name ?? p.basenameWithoutExtension(file.path);
  final id = await db.createPlaylist(name);
  await db.addTracksToPlaylist(id, ids);
  if (!context.mounted) return;
  showSnack(
    context,
    missing == 0
        ? 'Playlist “$name” importada (${ids.length})'
        : 'Importadas ${ids.length} · $missing no están en tu biblioteca',
  );
  context.push(Routes.playlist(id));
}

Future<void> exportM3u(BuildContext context, String name, List<TrackRow> tracks) async {
  final content = writeM3u(name, [
    for (final t in tracks)
      M3uTrack(location: t.filePath ?? t.uri, title: t.title, artist: t.artist, durationMs: t.durationMs),
  ]);
  final dir = await getTemporaryDirectory();
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  final file = File(p.join(dir.path, '$safe.m3u8'));
  await file.writeAsString(content, flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'audio/x-mpegurl')], subject: name));
}
