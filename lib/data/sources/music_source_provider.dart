/// Extensible music-source architecture.
///
/// Every provider declares what it can do and what it may not do. The UI
/// reads these declarations: a result whose provider cannot stream is shown
/// as not playable instead of pretending it can be played.
library;

enum SourceCapability {
  /// Text search across the provider's catalogue.
  search,

  /// Direct audio streaming that the provider explicitly permits.
  stream,

  /// Saving the audio file on the device, permitted by the content licence.
  download,

  /// Works with no network connection.
  offline,
}

class SourceInfo {
  const SourceInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.capabilities,
    this.restrictions = const [],
    this.requiresNetwork = true,
    this.homepage,
  });

  final String id;
  final String name;
  final String description;
  final Set<SourceCapability> capabilities;

  /// Human-readable restrictions shown in Ajustes → Fuentes.
  final List<String> restrictions;
  final bool requiresNetwork;
  final String? homepage;

  bool can(SourceCapability c) => capabilities.contains(c);
}

/// A collection (album, release, archive item) offered by a remote provider.
class RemoteCollection {
  const RemoteCollection({
    required this.sourceId,
    required this.externalId,
    required this.title,
    required this.creator,
    this.artUrl,
    this.license,
    this.licenseUrl,
    this.year,
  });

  final String sourceId;
  final String externalId;
  final String title;
  final String creator;
  final String? artUrl;
  final String? license;
  final String? licenseUrl;
  final int? year;

  @override
  bool operator ==(Object other) =>
      other is RemoteCollection && other.sourceId == sourceId && other.externalId == externalId;

  @override
  int get hashCode => Object.hash(sourceId, externalId);
}

class RemoteTrack {
  const RemoteTrack({
    required this.sourceId,
    required this.externalId,
    required this.title,
    required this.artist,
    required this.album,
    this.durationMs = 0,
    this.streamUrl,
    this.artUrl,
    this.license,
    this.licenseUrl,
    this.trackNumber,
    this.unplayableReason,
  });

  final String sourceId;
  final String externalId;
  final String title;
  final String artist;
  final String album;
  final int durationMs;

  /// Null when the provider does not allow direct playback.
  final String? streamUrl;
  final String? artUrl;
  final String? license;
  final String? licenseUrl;
  final int? trackNumber;
  final String? unplayableReason;

  bool get playable => streamUrl != null;
}

abstract interface class MusicSourceProvider {
  SourceInfo get info;

  Future<List<RemoteCollection>> searchCollections(String query, {int limit = 20});

  Future<List<RemoteTrack>> collectionTracks(RemoteCollection collection);
}

class SourceException implements Exception {
  SourceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Declaration for the on-device library. Its search is implemented by the
/// database, so it does not implement [MusicSourceProvider].
const localSourceInfo = SourceInfo(
  id: 'local',
  name: 'Biblioteca local',
  description: 'Archivos de audio guardados en este dispositivo.',
  capabilities: {SourceCapability.search, SourceCapability.stream, SourceCapability.offline},
  requiresNetwork: false,
  restrictions: ['Solo archivos a los que concedas acceso.'],
);
