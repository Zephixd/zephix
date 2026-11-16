import 'package:path/path.dart' as p;

class M3uEntry {
  const M3uEntry({required this.location, this.title, this.durationSeconds});
  final String location;
  final String? title;
  final int? durationSeconds;
}

class M3uTrack {
  const M3uTrack({required this.location, required this.title, required this.artist, this.durationMs = 0});
  final String location;
  final String title;
  final String artist;
  final int durationMs;
}

/// Writes an extended M3U (UTF-8, `.m3u8`) playlist with absolute paths.
String writeM3u(String name, List<M3uTrack> tracks) {
  final b = StringBuffer('#EXTM3U\n#PLAYLIST:${name.replaceAll('\n', ' ')}\n');
  for (final t in tracks) {
    final secs = t.durationMs > 0 ? (t.durationMs / 1000).round() : -1;
    b.writeln('#EXTINF:$secs,${t.artist} - ${t.title}'.replaceAll('\r', ''));
    b.writeln(t.location);
  }
  return b.toString();
}

/// Parses plain or extended M3U. Relative paths are resolved against
/// [baseDir] (the folder that contained the playlist file).
({String? name, List<M3uEntry> entries}) parseM3u(String text, {String? baseDir}) {
  String? name;
  String? pendingTitle;
  int? pendingDuration;
  final entries = <M3uEntry>[];
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim().replaceFirst('﻿', '');
    if (line.isEmpty) continue;
    if (line.startsWith('#PLAYLIST:')) {
      name = line.substring(10).trim();
    } else if (line.startsWith('#EXTINF:')) {
      final body = line.substring(8);
      final comma = body.indexOf(',');
      pendingDuration = int.tryParse((comma < 0 ? body : body.substring(0, comma)).trim().split(' ').first);
      pendingTitle = comma < 0 ? null : body.substring(comma + 1).trim();
    } else if (line.startsWith('#')) {
      continue;
    } else {
      var loc = line;
      if (loc.startsWith('file://')) {
        loc = Uri.parse(loc).toFilePath();
      } else if (!loc.contains('://') && !p.isAbsolute(loc) && baseDir != null) {
        loc = p.normalize(p.join(baseDir, loc.replaceAll('\\', '/')));
      }
      entries.add(M3uEntry(
        location: loc,
        title: pendingTitle,
        durationSeconds: (pendingDuration ?? -1) < 0 ? null : pendingDuration,
      ));
      pendingTitle = null;
      pendingDuration = null;
    }
  }
  return (name: name, entries: entries);
}
