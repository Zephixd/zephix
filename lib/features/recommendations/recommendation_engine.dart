import 'dart:math';

import '../../data/database/app_database.dart';

/// A generated mix. Mixes are computed on demand and never stored, so they
/// always reflect the current library and history.
class SmartMix {
  const SmartMix({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tracks,
  });
  final String id;
  final String title;
  final String subtitle;
  final List<TrackRow> tracks;

  String? get artPath => tracks.map((t) => t.artPath).firstWhere((a) => a != null, orElse: () => null);
}

class TasteSignals {
  TasteSignals({
    required this.playCount,
    required this.skipCount,
    required this.lastPlayed,
    required this.favorites,
    required this.artistAffinity,
    required this.genreAffinity,
  });

  final Map<int, int> playCount;
  final Map<int, int> skipCount;
  final Map<int, DateTime> lastPlayed;
  final Set<int> favorites;
  final Map<String, double> artistAffinity;
  final Map<String, double> genreAffinity;

  bool get hasHistory => playCount.isNotEmpty || favorites.isNotEmpty;
}

/// Pluggable recommendation strategy. A future engine (embeddings, audio
/// features, collaborative data) only needs to implement this interface.
abstract interface class RecommendationEngine {
  List<SmartMix> buildMixes(List<TrackRow> library, TasteSignals signals, {DateTime? now});
}

TasteSignals buildSignals(List<HistoryRow> history, Set<int> favorites, Map<int, TrackRow> tracks) {
  final plays = <int, int>{}, skips = <int, int>{};
  final last = <int, DateTime>{};
  final artist = <String, double>{}, genre = <String, double>{};

  for (final h in history) {
    final t = tracks[h.trackId];
    if (h.skipped) {
      skips[h.trackId] = (skips[h.trackId] ?? 0) + 1;
    } else {
      plays[h.trackId] = (plays[h.trackId] ?? 0) + 1;
    }
    final prev = last[h.trackId];
    if (prev == null || h.playedAt.isAfter(prev)) last[h.trackId] = h.playedAt;
    if (t == null) continue;
    final w = h.skipped ? -0.5 : (h.completed ? 1.0 : 0.6);
    artist[t.artist] = (artist[t.artist] ?? 0) + w;
    if (t.genre != null) genre[t.genre!] = (genre[t.genre!] ?? 0) + w;
  }
  for (final id in favorites) {
    final t = tracks[id];
    if (t == null) continue;
    artist[t.artist] = (artist[t.artist] ?? 0) + 2;
    if (t.genre != null) genre[t.genre!] = (genre[t.genre!] ?? 0) + 2;
  }
  Map<String, double> normalize(Map<String, double> m) {
    final maxV = m.values.fold<double>(0, max);
    return maxV <= 0 ? {} : {for (final e in m.entries) if (e.value > 0) e.key: e.value / maxV};
  }

  return TasteSignals(
    playCount: plays,
    skipCount: skips,
    lastPlayed: last,
    favorites: favorites,
    artistAffinity: normalize(artist),
    genreAffinity: normalize(genre),
  );
}

/// Weighted scoring over history, favourites, skips, artist and genre
/// affinity, with a freshness term so mixes rotate from day to day.
class LocalScoringEngine implements RecommendationEngine {
  const LocalScoringEngine({this.mixSize = 25});
  final int mixSize;

  double score(TrackRow t, TasteSignals s, DateTime now) {
    final plays = s.playCount[t.id] ?? 0;
    final skips = s.skipCount[t.id] ?? 0;
    final fav = s.favorites.contains(t.id) ? 1.0 : 0.0;
    final artist = s.artistAffinity[t.artist] ?? 0;
    final genre = t.genre == null ? 0.0 : (s.genreAffinity[t.genre!] ?? 0);
    final last = s.lastPlayed[t.id];
    final hoursSince = last == null ? 1e4 : now.difference(last).inMinutes / 60;
    // Recently heard tracks are pushed back so mixes do not repeat themselves.
    final freshness = hoursSince < 6 ? -1.2 : (hoursSince < 48 ? -0.3 : 0.0);
    final skipPenalty = skips == 0 ? 0.0 : -0.8 * skips / (skips + plays);
    return 1.4 * fav + 0.9 * log(1 + plays) + 1.6 * artist + 0.9 * genre + freshness + skipPenalty;
  }

  @override
  List<SmartMix> buildMixes(List<TrackRow> library, TasteSignals s, {DateTime? now}) {
    if (library.isEmpty) return const [];
    final t0 = now ?? DateTime.now();
    final seed = t0.year * 1000 + t0.month * 40 + t0.day;
    final rnd = Random(seed);
    final mixes = <SmartMix>[];

    List<TrackRow> rank(Iterable<TrackRow> pool) {
      // Small daily jitter keeps equal scores from always sorting the same.
      final scored = [for (final t in pool) (t, score(t, s, t0) + rnd.nextDouble() * 0.25)]
        ..sort((a, b) => b.$2.compareTo(a.$2));
      return [for (final e in scored) e.$1];
    }

    List<TrackRow> spread(List<TrackRow> ranked) {
      // Avoid more than two consecutive songs by the same artist.
      final out = <TrackRow>[];
      final rest = [...ranked];
      while (rest.isNotEmpty && out.length < mixSize) {
        final i = rest.indexWhere((t) =>
            out.length < 2 || !(out[out.length - 1].artist == t.artist && out[out.length - 2].artist == t.artist));
        out.add(rest.removeAt(i < 0 ? 0 : i));
      }
      return out;
    }

    if (s.hasHistory) {
      mixes.add(SmartMix(
        id: 'for-you',
        title: 'Mezcla para ti',
        subtitle: 'Según lo que más escuchas y tus favoritos',
        tracks: spread(rank(library)),
      ));

      final unheard = library.where((t) => !s.playCount.containsKey(t.id) && !s.skipCount.containsKey(t.id));
      final discovery = rank(unheard.where((t) =>
              (s.artistAffinity[t.artist] ?? 0) > 0 ||
              (t.genre != null && (s.genreAffinity[t.genre!] ?? 0) > 0)))
          .take(mixSize)
          .toList();
      if (discovery.length >= 5) {
        mixes.add(SmartMix(
          id: 'discover',
          title: 'Descubre en tu biblioteca',
          subtitle: 'Canciones que aún no escuchaste de lo que te gusta',
          tracks: discovery,
        ));
      }

      final forgotten = library.where((t) {
        final last = s.lastPlayed[t.id];
        return last != null && t0.difference(last).inDays >= 30 && (s.playCount[t.id] ?? 0) >= 2;
      });
      final rediscover = rank(forgotten).take(mixSize).toList();
      if (rediscover.length >= 5) {
        mixes.add(SmartMix(
          id: 'rediscover',
          title: 'Vuelve a escuchar',
          subtitle: 'Favoritas que no suenan desde hace un mes',
          tracks: rediscover,
        ));
      }

      final topArtists = (s.artistAffinity.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
          .take(3)
          .map((e) => e.key);
      for (final a in topArtists) {
        final pool = library.where((t) => t.artist == a).toList();
        if (pool.length < 4) continue;
        mixes.add(SmartMix(
          id: 'artist:$a',
          title: 'Mezcla de $a',
          subtitle: 'Tus canciones de $a',
          tracks: rank(pool).take(mixSize).toList(),
        ));
      }
    }

    final genres = <String, List<TrackRow>>{};
    for (final t in library) {
      if (t.genre != null) (genres[t.genre!] ??= []).add(t);
    }
    final genreOrder = genres.keys.toList()
      ..sort((a, b) {
        final c = (s.genreAffinity[b] ?? 0).compareTo(s.genreAffinity[a] ?? 0);
        return c != 0 ? c : genres[b]!.length.compareTo(genres[a]!.length);
      });
    for (final g in genreOrder.take(3)) {
      if (genres[g]!.length < 5) continue;
      mixes.add(SmartMix(
        id: 'genre:$g',
        title: 'Mezcla $g',
        subtitle: 'Lo mejor de $g en tu biblioteca',
        tracks: spread(rank(genres[g]!)),
      ));
    }

    if (mixes.isEmpty) {
      final shuffled = [...library]..shuffle(rnd);
      mixes.add(SmartMix(
        id: 'shuffle',
        title: 'Mezcla del día',
        subtitle: 'Una selección al azar de tu biblioteca',
        tracks: shuffled.take(mixSize).toList(),
      ));
    }
    return mixes;
  }
}
