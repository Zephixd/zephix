// language: Dart, file: ytm_source.dart, target: Flutter (Zephix)
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_music_explode_dart/youtube_music_explode_dart.dart';

import 'innertube.dart';
import 'music_source_provider.dart';

/// YouTube Music as a direct-audio source. Tracks are resolved through the
/// media-client interfaces (InnerTube), never the web player page, so the
/// audio served to Zephix contains no ad segments — there is no ad insertion
/// to block, and no adblock/DNS layer is required. No key, no account.
///
/// Engine: the vendored `youtube_explode_dart` fork maintained by Musify
/// (stable page parsers + stream clients) for search and stream manifests,
/// plus its `WEB_REMIX` `MusicClient` for the YouTube Music catalogue
/// (albums). The in-repo `Innertube` client covers related-video lookahead.
const ytmSourceInfo = SourceInfo(
  id: 'ytm',
  name: 'YouTube Music',
  description:
      'Catálogo completo de YouTube Music —canciones y álbumes— reproducido '
      'como audio directo (formato mp4/webm que entrega el propio servidor), '
      'sin anuncios.',
  capabilities: {SourceCapability.search, SourceCapability.stream},
  restrictions: [
    'Solo reproducción en streaming: el catálogo no permite guardar los archivos.',
    'Las URLs de audio caducan a las pocas horas; se renuevan automáticamente al reproducir.',
    'Requiere conexión. Los vídeos privados, de pago o con restricción de edad no se reproducen.',
  ],
  homepage: 'https://music.youtube.com',
);

/// One query's outcome: playable songs plus full catalogue albums.
class YtmSearchResults {
  const YtmSearchResults({required this.songs, required this.albums});
  final List<RemoteCollection> songs;
  final List<RemoteCollection> albums;
}

class YtmSource implements MusicSourceProvider {
  YtmSource();

  /// One shared engine for the whole app (catalogue + player resolution).
  static final YoutubeExplode _yt = YoutubeExplode();
  static final YoutubeMusicExplode _music = YoutubeMusicExplode();
  static final Innertube _api = Innertube();

  /// Empty query for Explore → current hits.
  static const _featuredQuery = 'música en tendencia';

  /// Album browse ids (`MPRE…`) route to the album-page resolver.
  static bool isAlbumId(String externalId) => externalId.startsWith('MPRE');

  /// Canonical URI stored in the database: `zephix-ytm:play/<videoId>`.
  /// Deliberately not `http`: googlevideo URLs expire, so the player
  /// resolves a fresh one at load time via [resolveUri]. Opaque scheme (no
  /// `//`) so nothing is parsed as authority: with `zephix-ytm://play/<id>`
  /// Dart would treat `play` as a lowercase host and hide the id in the
  /// wrong path position.
  static String trackUri(String videoId) => 'zephix-ytm:play/$videoId';

  static String? videoIdOf(String persistedUri) {
    final segments = Uri.parse(persistedUri).pathSegments;
    return segments.length == 2 && segments[0] == 'play' ? segments[1] : null;
  }

  /// Returns a fresh, direct audio URL for a persisted track URI.
  static Future<Uri> resolveUri(String persistedUri) async {
    final id = videoIdOf(persistedUri);
    if (id == null) throw SourceException('URI de YouTube Music no reconocida.');
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(VideoId(id));
      // Prefer mp4/AAC for maximum decoder compatibility, else any audio.
      final mp4 = manifest.audioOnly
          .where((s) => s.audioCodec.toLowerCase().startsWith('mp4a'))
          .toList();
      final pool = mp4.isNotEmpty ? mp4 : manifest.audioOnly.toList();
      if (pool.isEmpty) {
        throw SourceException('El vídeo no tiene pista de audio reproducible.');
      }
      var best = pool.first;
      for (final s in pool.skip(1)) {
        if (s.bitrate.bitsPerSecond > best.bitrate.bitsPerSecond) best = s;
      }
      return best.url;
    } on YoutubeExplodeException catch (e) {
      throw SourceException('No se pudo resolver el audio de YouTube: ${e.message}');
    }
  }

  /// Related ("radio") tracks for the autoplay tail of the queue.
  static Future<List<RemoteTrack>> relatedTracks(String videoId, {int limit = 10}) async {
    final videos = await _api.related(videoId, limit: limit);
    return [for (final v in videos) _trackFromVideo(v)];
  }

  static RemoteTrack _trackFromVideo(InnertubeVideo v) => RemoteTrack(
        sourceId: ytmSourceInfo.id,
        externalId: v.videoId,
        title: v.title,
        artist: v.author,
        album: 'YouTube Music',
        durationMs: v.durationMs,
        streamUrl: trackUri(v.videoId),
        artUrl: v.thumbnail,
      );

  @override
  SourceInfo get info => ytmSourceInfo;

  /// Search: songs from the YouTube catalogue (fork client, durations
  /// included) plus albums from the WEB_REMIX catalogue shelf. Falls back to
  /// the in-repo InnerTube search if the fork path fails.
  Future<YtmSearchResults> search(String query) async {
    final q = query.trim().isEmpty ? _featuredQuery : query.trim();
    List<RemoteCollection> songs;
    try {
      final videos = await _yt.search.search(q);
      songs = [
        for (final v in videos)
          if ((v.duration?.inMilliseconds ?? 0) >= 45000)
            RemoteCollection(
              sourceId: ytmSourceInfo.id,
              externalId: v.id.value,
              title: v.title,
              creator: v.author,
              artUrl: v.thumbnails.highResUrl,
            )
      ];
    } on YoutubeExplodeException {
      final videos = await _api.search(q, limit: 20);
      songs = [
        for (final v in videos)
          RemoteCollection(
            sourceId: ytmSourceInfo.id,
            externalId: v.videoId,
            title: v.title,
            creator: v.author,
            artUrl: v.thumbnail,
          )
      ];
    }
    List<RemoteCollection> albums;
    try {
      albums = [
        for (final a in await _music.music.searchAlbums(q))
          RemoteCollection(
            sourceId: ytmSourceInfo.id,
            externalId: a.id,
            title: a.title,
            creator: a.artist ?? '',
            artUrl: a.thumbnailUrl,
          )
      ];
    } on YoutubeExplodeException {
      albums = const [];
    }
    return YtmSearchResults(songs: songs, albums: albums);
  }

  /// Converts a search result set straight into playable remote tracks with
  /// no per-track manifest fetch: the player resolves each URL lazily on
  /// load, so tapping a result starts in well under a second.
  List<RemoteTrack> tracksFromCollections(List<RemoteCollection> collections) => [
        for (final c in collections)
          RemoteTrack(
            sourceId: ytmSourceInfo.id,
            externalId: c.externalId,
            title: c.title,
            artist: c.creator,
            album: 'YouTube Music',
            durationMs: 0,
            streamUrl: trackUri(c.externalId),
            artUrl: c.artUrl,
          ),
      ];

  @override
  Future<List<RemoteCollection>> searchCollections(String query, {int limit = 20}) async =>
      (await search(query)).songs.take(limit).toList();

  @override
  Future<List<RemoteTrack>> collectionTracks(RemoteCollection c) async {
    if (isAlbumId(c.externalId)) return albumTracks(c.externalId);
    try {
      final video = await _yt.videos.get(VideoId(c.externalId));
      final manifest = await _yt.videos.streamsClient.getManifest(video.id);
      if (manifest.audioOnly.isEmpty) {
        return [
          RemoteTrack(
            sourceId: ytmSourceInfo.id,
            externalId: video.id.value,
            title: video.title,
            artist: video.author,
            album: 'YouTube Music',
            unplayableReason: 'El vídeo no tiene pista de audio reproducible',
          )
        ];
      }
      return [
        RemoteTrack(
          sourceId: ytmSourceInfo.id,
          externalId: video.id.value,
          title: video.title,
          artist: video.author,
          album: 'YouTube Music',
          durationMs: video.duration?.inMilliseconds ?? 0,
          streamUrl: trackUri(video.id.value),
          artUrl: video.thumbnails.highResUrl,
        )
      ];
    } on YoutubeExplodeException catch (e) {
      throw SourceException('No se pudo cargar el vídeo: ${e.message}');
    }
  }

  /// Full YouTube Music release page (WEB_REMIX browse): real album name,
  /// credited artist and every track in order.
  Future<List<RemoteTrack>> albumTracks(String albumBrowseId) async {
    try {
      final page = await _music.music.getAlbum(albumBrowseId);
      return [
        for (final t in page.tracks)
          RemoteTrack(
            sourceId: ytmSourceInfo.id,
            externalId: t.id.value,
            title: t.title,
            artist: t.author.isNotEmpty ? t.author : (page.artist ?? ''),
            album: page.title,
            durationMs: t.duration?.inMilliseconds ?? 0,
            streamUrl: trackUri(t.id.value),
            artUrl: page.thumbnailUrl,
          )
      ];
    } on YoutubeExplodeException catch (e) {
      throw SourceException('No se pudo cargar el álbum: ${e.message}');
    }
  }
}
