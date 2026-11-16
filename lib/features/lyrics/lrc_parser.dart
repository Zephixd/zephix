class LyricLine {
  const LyricLine(this.time, this.text);
  final Duration time;
  final String text;
}

class Lyrics {
  const Lyrics({this.lines = const [], this.plain, this.instrumental = false, this.source});

  /// Timed lines, sorted. Empty when only plain lyrics exist.
  final List<LyricLine> lines;
  final String? plain;
  final bool instrumental;

  /// Where the lyrics came from: `embedded`, `lrclib`.
  final String? source;

  bool get isSynced => lines.isNotEmpty;
  bool get isEmpty => lines.isEmpty && (plain == null || plain!.trim().isEmpty) && !instrumental;

  /// Index of the line active at [position], or -1 before the first line.
  int indexAt(Duration position) {
    var lo = 0, hi = lines.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].time <= position) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }
}

final _tag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
final _offset = RegExp(r'^\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false);

/// Parses LRC text. Supports multiple timestamps per line, centisecond and
/// millisecond fractions and the `[offset:]` header. Returns an empty list
/// when the text has no timestamps (plain lyrics).
List<LyricLine> parseLrc(String text) {
  var offsetMs = 0;
  final out = <LyricLine>[];
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    final off = _offset.firstMatch(line);
    if (off != null) {
      offsetMs = int.parse(off.group(1)!);
      continue;
    }
    final matches = _tag.allMatches(line).toList();
    if (matches.isEmpty) continue;
    final lyric = line.substring(matches.last.end).trim();
    for (final m in matches) {
      final min = int.parse(m.group(1)!);
      final sec = int.parse(m.group(2)!);
      final frac = m.group(3);
      var ms = 0;
      if (frac != null) {
        ms = switch (frac.length) {
          1 => int.parse(frac) * 100,
          2 => int.parse(frac) * 10,
          _ => int.parse(frac.substring(0, 3)),
        };
      }
      final t = Duration(minutes: min, seconds: sec, milliseconds: ms - offsetMs);
      out.add(LyricLine(t.isNegative ? Duration.zero : t, lyric));
    }
  }
  out.sort((a, b) => a.time.compareTo(b.time));
  return out;
}

Lyrics lyricsFromText({String? synced, String? plain, bool instrumental = false, String? source}) {
  final lines = synced == null ? const <LyricLine>[] : parseLrc(synced);
  var p = plain;
  if (lines.isEmpty && synced != null && (p == null || p.isEmpty)) p = synced;
  return Lyrics(lines: lines, plain: p, instrumental: instrumental, source: source);
}
