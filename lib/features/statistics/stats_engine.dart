import '../../core/utils/format.dart';
import '../../data/database/app_database.dart';

class RankedItem {
  const RankedItem(this.label, this.subtitle, this.plays, this.listenedMs, {this.artPath, this.trackId});
  final String label;
  final String? subtitle;
  final int plays;
  final int listenedMs;
  final String? artPath;
  final int? trackId;
}

class DayActivity {
  const DayActivity(this.day, this.listenedMs, this.plays);
  final DateTime day;
  final int listenedMs;
  final int plays;
}

class ListeningStats {
  const ListeningStats({
    required this.from,
    required this.to,
    required this.plays,
    required this.listenedMs,
    required this.uniqueTracks,
    required this.skips,
    required this.topTracks,
    required this.topArtists,
    required this.topAlbums,
    required this.daily,
  });

  final DateTime from;
  final DateTime to;
  final int plays;
  final int listenedMs;
  final int uniqueTracks;
  final int skips;
  final List<RankedItem> topTracks;
  final List<RankedItem> topArtists;
  final List<RankedItem> topAlbums;

  /// One entry per calendar day in the range, oldest first, zero-filled.
  final List<DayActivity> daily;

  bool get isEmpty => plays == 0;
  double get skipRate => plays == 0 ? 0 : skips / plays;

  DayActivity? get busiestDay {
    if (daily.isEmpty) return null;
    final sorted = [...daily]..sort((a, b) => b.listenedMs.compareTo(a.listenedMs));
    return sorted.first.listenedMs == 0 ? null : sorted.first;
  }
}

/// Pure function: aggregates [history] for the days between [from] and [to].
ListeningStats computeStats({
  required List<HistoryRow> history,
  required Map<int, TrackRow> tracks,
  required DateTime from,
  required DateTime to,
  int top = 5,
}) {
  final rows = history.where((h) => !h.playedAt.isBefore(from) && !h.playedAt.isAfter(to)).toList();

  final byTrack = <int, (int, int)>{};
  final byArtist = <String, (int, int, String?)>{};
  final byAlbum = <String, (int, int, String?, String)>{};
  final byDay = <DateTime, (int, int)>{};
  var total = 0, skips = 0;

  for (final h in rows) {
    total += h.listenedMs;
    if (h.skipped) skips++;
    final t = tracks[h.trackId];
    final bt = byTrack[h.trackId] ?? (0, 0);
    byTrack[h.trackId] = (bt.$1 + 1, bt.$2 + h.listenedMs);
    final day = startOfDay(h.playedAt);
    final bd = byDay[day] ?? (0, 0);
    byDay[day] = (bd.$1 + 1, bd.$2 + h.listenedMs);
    if (t == null) continue;
    final ba = byArtist[t.artist] ?? (0, 0, t.artPath);
    byArtist[t.artist] = (ba.$1 + 1, ba.$2 + h.listenedMs, ba.$3 ?? t.artPath);
    final albumKey = '${t.album}\u0001${t.albumArtist ?? t.artist}';
    final bl = byAlbum[albumKey] ?? (0, 0, t.artPath, t.albumArtist ?? t.artist);
    byAlbum[albumKey] = (bl.$1 + 1, bl.$2 + h.listenedMs, bl.$3 ?? t.artPath, bl.$4);
  }

  int cmp(RankedItem a, RankedItem b) {
    final c = b.plays.compareTo(a.plays);
    return c != 0 ? c : b.listenedMs.compareTo(a.listenedMs);
  }

  final topTracks = [
    for (final e in byTrack.entries)
      if (tracks[e.key] != null)
        RankedItem(tracks[e.key]!.title, tracks[e.key]!.artist, e.value.$1, e.value.$2,
            artPath: tracks[e.key]!.artPath, trackId: e.key)
  ]..sort(cmp);
  final topArtists = [
    for (final e in byArtist.entries) RankedItem(e.key, null, e.value.$1, e.value.$2, artPath: e.value.$3)
  ]..sort(cmp);
  final topAlbums = [
    for (final e in byAlbum.entries)
      RankedItem(e.key.split('\u0001').first, e.value.$4, e.value.$1, e.value.$2, artPath: e.value.$3)
  ]..sort(cmp);

  final daily = <DayActivity>[];
  for (var d = startOfDay(from); !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
    final v = byDay[d] ?? (0, 0);
    daily.add(DayActivity(d, v.$2, v.$1));
  }

  return ListeningStats(
    from: from,
    to: to,
    plays: rows.length,
    listenedMs: total,
    uniqueTracks: byTrack.length,
    skips: skips,
    topTracks: topTracks.take(top).toList(),
    topArtists: topArtists.take(top).toList(),
    topAlbums: topAlbums.take(top).toList(),
    daily: daily,
  );
}
