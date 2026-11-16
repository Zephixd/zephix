import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../../data/database/app_database.dart';
import '../../domain/entities/track_x.dart';
import '../constants/app_info.dart';

/// Playback engine. Owns the [AudioPlayer], mirrors its state to the Android
/// media session / notification through audio_service, records listening
/// history and restores the last queue after a restart.
class ZephixAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  ZephixAudioHandler(
    this._db, {
    Future<Uri> Function(String persistedUri)? uriResolver,
    Future<List<TrackRow>> Function(TrackRow current)? autoplay,
  })  : _remoteUriResolver = uriResolver,
        _autoplayFetcher = autoplay {
    _init();
  }

  final AppDatabase _db;

  /// Resolves persisted remote URIs whose underlying URL expires (YouTube).
  /// Null when the app has no expiring sources configured.
  final Future<Uri> Function(String persistedUri)? _remoteUriResolver;

  /// Spotify-style autoplay: when playback reaches the last track of an
  /// online-source queue, this fetches similar tracks to keep the music
  /// going. Best-effort; null disables it.
  final Future<List<TrackRow>> Function(TrackRow current)? _autoplayFetcher;
  bool _autoplayBusy = false;

  /// Android system equalizer, attached to the player pipeline. Availability
  /// depends on the device; the UI checks [equalizerParameters].
  final AndroidEqualizer equalizer = AndroidEqualizer();

  late final AudioPlayer player = AudioPlayer(
    userAgent: AppInfo.userAgent,
    audioPipeline: defaultTargetPlatform == TargetPlatform.android
        ? AudioPipeline(androidAudioEffects: [equalizer])
        : null,
    maxSkipsOnError: 3,
  );

  final _tracks = BehaviorSubject<List<TrackRow>>.seeded(const []);
  final _sleepAt = BehaviorSubject<DateTime?>.seeded(null);
  final _sleepAtEndOfTrack = BehaviorSubject<bool>.seeded(false);
  final _errors = PublishSubject<String>();
  Timer? _sleepTimer;

  /// Mirrors Ajustes → Privacidad → Historial de escucha.
  bool recordHistory = true;
  Timer? _persistTimer;

  // Listening-session tracking.
  final Stopwatch _listened = Stopwatch();
  TrackRow? _sessionTrack;
  DateTime? _sessionStart;
  bool _sessionReachedEnd = false;

  Stream<List<TrackRow>> get tracksStream => _tracks.stream;
  List<TrackRow> get tracks => _tracks.value;
  Stream<DateTime?> get sleepAtStream => _sleepAt.stream;
  Stream<bool> get sleepAtEndOfTrackStream => _sleepAtEndOfTrack.stream;
  Stream<String> get errorMessages => _errors.stream;

  Stream<TrackRow?> get currentTrackStream =>
      Rx.combineLatest2<int?, List<TrackRow>, TrackRow?>(player.currentIndexStream, _tracks.stream,
          (i, list) => (i != null && i >= 0 && i < list.length) ? list[i] : null).distinct(
          (a, b) => a?.id == b?.id && a?.durationMs == b?.durationMs);

  TrackRow? get currentTrack {
    final i = player.currentIndex;
    final list = _tracks.value;
    return (i != null && i >= 0 && i < list.length) ? list[i] : null;
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    // Pause when headphones are unplugged.
    session.becomingNoisyEventStream.listen((_) => pause());

    player.playbackEventStream.listen(_broadcast, onError: (Object e, StackTrace st) {
      _errors.add('No se pudo reproducir la pista.');
    });
    player.playingStream.listen((_) => _broadcast(player.playbackEvent));
    player.shuffleModeEnabledStream.listen((_) => _broadcast(player.playbackEvent));
    player.loopModeStream.listen((_) => _broadcast(player.playbackEvent));
    player.errorStream.listen((e) {
      _errors.add(e.message ?? 'Error de reproducción (${e.code}).');
    });

    player.playingStream.listen((playing) {
      if (playing) {
        _listened.start();
      } else {
        _listened.stop();
        _persistState();
      }
    });

    player.currentIndexStream.distinct().listen((_) {
      _closeSession();
      final t = currentTrack;
      if (t != null) {
        mediaItem.add(t.toMediaItem());
        _openSession(t);
        unawaited(_maybeAutoplay(t));
      }
      _persistState();
    });

    player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _sessionReachedEnd = true;
        _closeSession();
        if (_sleepAtEndOfTrack.value) cancelSleepTimer();
      }
    });

    // Learn durations that tags did not provide and store them.
    player.durationStream.listen((d) async {
      final t = currentTrack;
      if (d == null || t == null || t.durationMs > 0) return;
      await (_db.update(_db.tracks)..where((x) => x.id.equals(t.id)))
          .write(TracksCompanion(durationMs: Value(d.inMilliseconds)));
      final updated = t.copyWith(durationMs: d.inMilliseconds);
      final list = [..._tracks.value];
      final i = list.indexWhere((x) => x.id == t.id);
      if (i >= 0) {
        list[i] = updated;
        _tracks.add(list);
        queue.add([for (final x in list) x.toMediaItem()]);
      }
      mediaItem.add(updated.toMediaItem());
    });

    // "End of track" sleep: pause as the current item finishes.
    player.positionStream.listen((pos) {
      if (!_sleepAtEndOfTrack.value) return;
      final d = player.duration;
      if (d != null && d - pos < const Duration(milliseconds: 400) && player.playing) {
        pause();
        cancelSleepTimer();
      }
    });

    _persistTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (player.playing) _persistState();
    });

    await _restoreState();
  }

  void _broadcast(PlaybackEvent event) {
    final playing = player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.skipToQueueItem,
        MediaAction.setShuffleMode,
        MediaAction.setRepeatMode,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[player.processingState]!,
      playing: playing,
      updatePosition: player.position,
      bufferedPosition: player.bufferedPosition,
      speed: player.speed,
      queueIndex: event.currentIndex,
      shuffleMode: player.shuffleModeEnabled ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
      repeatMode: switch (player.loopMode) {
        LoopMode.off => AudioServiceRepeatMode.none,
        LoopMode.one => AudioServiceRepeatMode.one,
        LoopMode.all => AudioServiceRepeatMode.all,
      },
    ));
  }

  // --------------------------------------------------------------- history

  void _openSession(TrackRow t) {
    _sessionTrack = t;
    _sessionStart = DateTime.now();
    _sessionReachedEnd = false;
    _listened
      ..reset()
      ..stop();
    if (player.playing) _listened.start();
  }

  void _closeSession() {
    final t = _sessionTrack;
    final start = _sessionStart;
    final ms = _listened.elapsedMilliseconds;
    _sessionTrack = null;
    _sessionStart = null;
    _listened.reset();
    if (!recordHistory || t == null || start == null || ms < 5000) return;
    final dur = t.durationMs > 0 ? t.durationMs : (player.duration?.inMilliseconds ?? 0);
    final completed = _sessionReachedEnd || (dur > 0 && ms >= dur * 0.8);
    final skipped = !completed && ms < (dur > 0 ? (dur * 0.5).clamp(0, 30000) : 30000);
    unawaited(_db.recordPlay(
      trackId: t.id,
      playedAt: start,
      listenedMs: ms,
      completed: completed,
      skipped: skipped,
    ));
  }

  // ----------------------------------------------------------------- queue

  /// When the queue is about to run dry on an online-source track, fetches
  /// similar tracks and appends them, never duplicating what is queued.
  Future<void> _maybeAutoplay(TrackRow t) async {
    final fetch = _autoplayFetcher;
    if (fetch == null || _autoplayBusy) return;
    final i = player.currentIndex ?? -1;
    if (i < 0 || i != _tracks.value.length - 1) return;
    if (t.source != 'ytm') return;
    _autoplayBusy = true;
    try {
      final rows = await fetch(t);
      final queued = _tracks.value.map((x) => x.uri).toSet();
      final fresh = rows.where((r) => !queued.contains(r.uri)).toList();
      // Still at the tail? If the user skipped meanwhile, drop the fill.
      if (fresh.isNotEmpty && (player.currentIndex ?? -1) >= _tracks.value.length - 1) {
        await enqueue(fresh);
      }
    } catch (_) {
      // Autoplay is best-effort; failures never interrupt playback.
    } finally {
      _autoplayBusy = false;
    }
  }

  Future<AudioSource> _sourceFor(TrackRow t) async {
    final tag = t.toMediaItem();
    if (!t.isRemote) return AudioSource.file(t.filePath ?? Uri.parse(t.uri).toFilePath(), tag: tag);
    final uri = Uri.parse(t.uri);
    if (_remoteUriResolver != null && uri.scheme != 'http' && uri.scheme != 'https') {
      // Persisted URI with an expiring backing URL: resolve on load.
      return ResolvedAudioSource(
        tag: tag,
        resolve: () => _remoteUriResolver(t.uri),
        onError: (message) => _errors.add(message),
      );
    }
    return AudioSource.uri(uri, tag: tag);
  }

  /// Replaces the queue and starts playing [tracks] from [index].
  Future<void> playTracks(List<TrackRow> list, {int index = 0, bool shuffle = false, Duration? position}) async {
    if (list.isEmpty) return;
    _closeSession();
    _tracks.add(List.unmodifiable(list));
    queue.add([for (final t in list) t.toMediaItem()]);
    try {
      await player.setShuffleModeEnabled(false);
      final sources = [for (final t in list) await _sourceFor(t)];
      await player.setAudioSources(
        sources,
        initialIndex: index.clamp(0, list.length - 1),
        initialPosition: position ?? Duration.zero,
      );
      if (shuffle) {
        await player.shuffle();
        await player.setShuffleModeEnabled(true);
      }
      unawaited(player.play());
    } on PlayerException catch (e) {
      _errors.add(e.message ?? 'No se pudo abrir el archivo.');
    } on PlayerInterruptedException {
      // A newer request replaced this one.
    }
  }

  Future<void> playNext(List<TrackRow> items) async {
    if (_tracks.value.isEmpty) return playTracks(items);
    final at = (player.currentIndex ?? -1) + 1;
    await player.insertAudioSources(at, [for (final t in items) await _sourceFor(t)]);
    final list = [..._tracks.value]..insertAll(at, items);
    _publish(list);
  }

  Future<void> enqueue(List<TrackRow> items) async {
    if (_tracks.value.isEmpty) return playTracks(items);
    await player.addAudioSources([for (final t in items) await _sourceFor(t)]);
    _publish([..._tracks.value, ...items]);
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    if (index < 0 || index >= _tracks.value.length) return;
    await player.removeAudioSourceAt(index);
    _publish([..._tracks.value]..removeAt(index));
  }

  Future<void> moveQueueItem(int from, int to) async {
    final list = [..._tracks.value];
    if (from < 0 || from >= list.length) return;
    final target = to.clamp(0, list.length - 1);
    await player.moveAudioSource(from, target);
    list.insert(target, list.removeAt(from));
    _publish(list);
  }

  Future<void> clearQueue() async {
    _closeSession();
    await player.stop();
    await player.clearAudioSources();
    _publish(const []);
    mediaItem.add(null);
  }

  void _publish(List<TrackRow> list) {
    _tracks.add(List.unmodifiable(list));
    queue.add([for (final t in list) t.toMediaItem()]);
    _persistState();
  }

  /// Keeps queue metadata in sync when a track row changes (e.g. after a
  /// MusicBrainz correction or a download replaces a stream with a file).
  void refreshTrack(TrackRow updated) {
    final list = [..._tracks.value];
    var changed = false;
    for (var i = 0; i < list.length; i++) {
      if (list[i].id == updated.id) {
        list[i] = updated;
        changed = true;
      }
    }
    if (!changed) return;
    _tracks.add(List.unmodifiable(list));
    queue.add([for (final t in list) t.toMediaItem()]);
    if (currentTrack?.id == updated.id) mediaItem.add(updated.toMediaItem());
  }

  // -------------------------------------------------------------- controls

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _tracks.value.length) return;
    await player.seek(Duration.zero, index: index);
    if (!player.playing) unawaited(player.play());
  }

  @override
  Future<void> skipToNext() => player.seekToNext();

  @override
  Future<void> skipToPrevious() async {
    if (player.position > const Duration(seconds: 3) || !player.hasPrevious) {
      await player.seek(Duration.zero);
    } else {
      await player.seekToPrevious();
    }
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enable = shuffleMode != AudioServiceShuffleMode.none;
    if (enable) await player.shuffle();
    await player.setShuffleModeEnabled(enable);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) => player.setLoopMode(switch (repeatMode) {
        AudioServiceRepeatMode.none => LoopMode.off,
        AudioServiceRepeatMode.one => LoopMode.one,
        AudioServiceRepeatMode.all || AudioServiceRepeatMode.group => LoopMode.all,
      });

  Future<void> toggleShuffle() =>
      setShuffleMode(player.shuffleModeEnabled ? AudioServiceShuffleMode.none : AudioServiceShuffleMode.all);

  Future<void> cycleRepeat() => player.setLoopMode(switch (player.loopMode) {
        LoopMode.off => LoopMode.all,
        LoopMode.all => LoopMode.one,
        LoopMode.one => LoopMode.off,
      });

  @override
  Future<void> stop() async {
    _closeSession();
    await _persistState();
    await player.stop();
    await super.stop();
  }

  @override
  Future<void> onTaskRemoved() async {
    if (!player.playing) await stop();
  }

  // ----------------------------------------------------------- sleep timer

  void setSleepTimer(Duration d) {
    _sleepTimer?.cancel();
    _sleepAtEndOfTrack.add(false);
    _sleepAt.add(DateTime.now().add(d));
    _sleepTimer = Timer(d, () async {
      // Short fade-out so the stop is not abrupt.
      final v = player.volume;
      for (var i = 10; i > 0; i--) {
        await player.setVolume(v * i / 10);
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      await pause();
      await player.setVolume(v);
      _sleepAt.add(null);
    });
  }

  void setSleepAtEndOfTrack() {
    _sleepTimer?.cancel();
    _sleepAt.add(null);
    _sleepAtEndOfTrack.add(true);
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepAt.add(null);
    _sleepAtEndOfTrack.add(false);
  }

  // ------------------------------------------------------------ settings

  Future<void> applyPlaybackSettings({required bool skipSilence, required bool eqEnabled, List<double>? eqGains}) async {
    try {
      await player.setSkipSilenceEnabled(skipSilence);
    } catch (_) {/* not supported on this platform */}
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await equalizer.setEnabled(eqEnabled);
      if (eqGains != null) {
        final params = await equalizer.parameters.timeout(const Duration(seconds: 2));
        for (var i = 0; i < params.bands.length && i < eqGains.length; i++) {
          await params.bands[i].setGain(eqGains[i].clamp(params.minDecibels, params.maxDecibels));
        }
      }
    } catch (_) {/* equalizer unavailable until audio is loaded, or unsupported */}
  }

  Future<AndroidEqualizerParameters?> equalizerParameters() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await equalizer.parameters.timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------- persistence

  Future<void> _persistState() async {
    final list = _tracks.value;
    try {
      await _db.setPreference(
          'player.state',
          jsonEncode({
            'ids': [for (final t in list.take(1000)) t.id],
            'index': player.currentIndex ?? 0,
            'position': player.position.inMilliseconds,
          }));
    } catch (_) {/* database closed during shutdown */}
  }

  Future<void> _restoreState() async {
    try {
      final prefs = await _db.preferences();
      final raw = prefs['player.state'];
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final ids = (m['ids'] as List).cast<int>();
      final list = await _db.tracksByIds(ids);
      if (list.isEmpty) return;
      final index = (m['index'] as int).clamp(0, list.length - 1);
      _tracks.add(List.unmodifiable(list));
      queue.add([for (final t in list) t.toMediaItem()]);
      final sources = [for (final t in list) await _sourceFor(t)];
      await player.setAudioSources(
        sources,
        initialIndex: index,
        initialPosition: Duration(milliseconds: m['position'] as int? ?? 0),
        preload: false,
      );
      mediaItem.add(list[index].toMediaItem());
    } catch (_) {
      // Stale or corrupted state: start with an empty queue.
    }
  }

  Future<void> dispose() async {
    _persistTimer?.cancel();
    _sleepTimer?.cancel();
    await player.dispose();
  }
}

/// Audio source whose backing URL is resolved lazily, when just_audio first
/// loads it (or re-loads it after a seek). Used for YouTube tracks: their
/// googlevideo links expire after a few hours, but the video id stored in the
/// database never does, so an old queue or playlist keeps playing forever.
// The experimental annotation is deliberate: StreamAudioSource is the
// documented extension point of just_audio for proxied byte sources.
// ignore_for_file: experimental_member_use
class ResolvedAudioSource extends StreamAudioSource {
  ResolvedAudioSource({required super.tag, required this.resolve, this.onError});

  /// Fetches a fresh, playable URL. Called again after a 403.
  final Future<Uri> Function() resolve;

  /// Reports resolution failures with the real reason, so the UI can show
  /// something more useful than just_audio's generic "source error".
  final void Function(String message)? onError;

  Uri? _resolved;
  static final HttpClient _http = HttpClient()..userAgent = AppInfo.userAgent;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    var response = await _fetch(await _link(), start, end);
    if (response.statusCode == 403) {
      // Link expired between resolution and load: resolve once more.
      _resolved = null;
      unawaited(response.drain<void>().catchError((_) {}));
      response = await _fetch(await _link(), start, end);
    }
    if (response.statusCode >= 400) {
      throw Exception('El servidor rechazó la petición de audio (${response.statusCode}).');
    }
    final ranged = response.statusCode == 206;
    int? total;
    if (ranged) {
      // `content-range: bytes a-b/total` carries the whole-media length that
      // just_audio needs for progress and seeking; content-length does not.
      final range = response.headers.value(HttpHeaders.contentRangeHeader);
      final m = range == null ? null : RegExp(r'/(\d+)\s*$').firstMatch(range);
      total = m == null ? null : int.tryParse(m.group(1)!);
    }
    return StreamAudioResponse(
      rangeRequestsSupported: true,
      sourceLength: ranged ? total : null,
      contentLength: response.contentLength > 0 ? response.contentLength : null,
      offset: ranged ? start : null,
      stream: response,
      contentType: response.headers.value(HttpHeaders.contentTypeHeader) ?? 'audio/mp4',
    );
  }

  Future<Uri> _link() async {
    try {
      return _resolved ??= await resolve();
    } catch (e) {
      onError?.call('No se pudo resolver el audio: $e');
      rethrow;
    }
  }

  Future<HttpClientResponse> _fetch(Uri uri, int? start, int? end) async {
    final req = await _http.getUrl(uri);
    req.headers.set(HttpHeaders.userAgentHeader, AppInfo.userAgent);
    if (start != null || end != null) {
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=${start ?? 0}-${end == null ? '' : end - 1}');
    }
    return req.close();
  }
}
