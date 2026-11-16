import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_info.dart';
import '../database/app_database.dart';

class ScanProgress {
  const ScanProgress({
    this.running = false,
    this.found = 0,
    this.processed = 0,
    this.added = 0,
    this.removed = 0,
    this.errors = 0,
    this.message,
  });

  final bool running;
  final int found;
  final int processed;
  final int added;
  final int removed;
  final int errors;
  final String? message;

  double? get fraction => found == 0 ? null : processed / found;

  ScanProgress copyWith({
    bool? running,
    int? found,
    int? processed,
    int? added,
    int? removed,
    int? errors,
    String? message,
  }) =>
      ScanProgress(
        running: running ?? this.running,
        found: found ?? this.found,
        processed: processed ?? this.processed,
        added: added ?? this.added,
        removed: removed ?? this.removed,
        errors: errors ?? this.errors,
        message: message ?? this.message,
      );
}

/// Plain data sent back from the parsing isolate.
class _Parsed {
  _Parsed(this.path, this.size, this.modified);
  final String path;
  final int size;
  final DateTime modified;
  String? title, artist, album, albumArtist, genre, lyrics;
  int? durationMs, track, disc, year;
  Uint8List? art;
  bool failed = false;
}

/// Scans folders for audio files and stores their tags in the database.
/// Incremental: unchanged files (same modification time) are skipped and
/// files that disappeared are pruned. Tag parsing runs in a background
/// isolate so the UI never janks.
class LocalLibraryScanner {
  LocalLibraryScanner(this._db, {this.minDurationMs = 0});
  final AppDatabase _db;

  /// Files with a known duration below this are skipped (ringtones, notification sounds).
  final int minDurationMs;

  static bool isAudio(String path) {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    return AppInfo.audioExtensions.contains(ext);
  }

  Stream<ScanProgress> scan(List<String> folders, {bool force = false}) async* {
    var progress = const ScanProgress(running: true, message: 'Buscando archivos…');
    yield progress;

    final known = await _db.localFileIndex();
    final artDir = Directory(p.join((await getApplicationSupportDirectory()).path, 'artwork'));
    await artDir.create(recursive: true);

    for (final folder in folders) {
      final dir = Directory(folder);
      if (!await dir.exists()) {
        progress = progress.copyWith(message: 'No se encontró $folder');
        yield progress;
        continue;
      }

      final files = <File>[];
      try {
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is File && isAudio(e.path) && !p.basename(e.path).startsWith('.')) files.add(e);
        }
      } on FileSystemException catch (e) {
        progress = progress.copyWith(errors: progress.errors + 1, message: e.message);
      }

      progress = progress.copyWith(found: progress.found + files.length, message: folder);
      yield progress;

      final keep = <String>{};
      final pending = <(String, int, DateTime)>[];
      for (final f in files) {
        final uri = Uri.file(f.path).toString();
        keep.add(uri);
        try {
          final stat = await f.stat();
          final prev = known[uri];
          if (!force && prev != null && prev.isAtSameMomentAs(stat.modified)) {
            progress = progress.copyWith(processed: progress.processed + 1);
          } else {
            pending.add((f.path, stat.size, stat.modified));
          }
        } on FileSystemException {
          progress = progress.copyWith(processed: progress.processed + 1, errors: progress.errors + 1);
        }
      }
      yield progress;

      const chunk = 20;
      for (var i = 0; i < pending.length; i += chunk) {
        final slice = pending.sublist(i, (i + chunk).clamp(0, pending.length));
        final parsed = await _parseInIsolate(slice);
        for (final r in parsed) {
          await _store(r, folder: p.dirname(r.path), artDir: artDir.path);
          progress = progress.copyWith(
            processed: progress.processed + 1,
            added: progress.added + 1,
            errors: progress.errors + (r.failed ? 1 : 0),
          );
        }
        yield progress;
      }

      final removed = await _db.pruneFolder(folder, keep);
      progress = progress.copyWith(removed: progress.removed + removed);
    }

    yield progress.copyWith(running: false, message: 'Biblioteca actualizada');
  }

  /// Adds individual files picked by the user.
  Future<int> addFiles(List<String> paths) async {
    final artDir = Directory(p.join((await getApplicationSupportDirectory()).path, 'artwork'));
    await artDir.create(recursive: true);
    final items = <(String, int, DateTime)>[];
    for (final path in paths.where(isAudio)) {
      final stat = await File(path).stat();
      items.add((path, stat.size, stat.modified));
    }
    final parsed = await _parseInIsolate(items);
    for (final r in parsed) {
      await _store(r, folder: p.dirname(r.path), artDir: artDir.path);
    }
    return parsed.length;
  }

  Future<void> _store(_Parsed r, {required String folder, required String artDir}) async {
    final d = r.durationMs ?? 0;
    if (minDurationMs > 0 && d > 0 && d < minDurationMs) return;
    String? artPath;
    if (r.art != null && r.art!.isNotEmpty) {
      final key = sha1.convert(r.art!.length > 4096 ? r.art!.sublist(0, 4096) : r.art!).toString();
      final file = File(p.join(artDir, '$key.img'));
      if (!await file.exists()) await file.writeAsBytes(r.art!, flush: false);
      artPath = file.path;
    }
    final fallbackTitle = p.basenameWithoutExtension(r.path);
    await _db.upsertTrack(TracksCompanion.insert(
      uri: Uri.file(r.path).toString(),
      title: _clean(r.title) ?? fallbackTitle,
      artist: Value(_clean(r.artist) ?? 'Artista desconocido'),
      album: Value(_clean(r.album) ?? p.basename(folder)),
      albumArtist: Value(_clean(r.albumArtist)),
      genre: Value(_clean(r.genre)),
      durationMs: Value(r.durationMs ?? 0),
      trackNumber: Value(r.track),
      discNumber: Value(r.disc),
      year: Value(r.year),
      artPath: Value(artPath),
      source: const Value('local'),
      folder: Value(folder),
      embeddedLyrics: Value(_clean(r.lyrics)),
      fileSize: Value(r.size),
      fileModified: Value(r.modified),
    ));
  }

  static String? _clean(String? s) {
    final t = s?.replaceAll('\u0000', '').trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}

_Parsed _parse((String, int, DateTime) item) {
  final (path, size, modified) = item;
  final out = _Parsed(path, size, modified);
  try {
    final m = readMetadata(File(path), getImage: true);
    out
      ..title = m.title
      ..artist = m.artist
      ..album = m.album
      ..albumArtist = m.albumArtist
      ..genre = m.genres.isEmpty ? null : m.genres.first
      ..lyrics = m.lyrics
      ..durationMs = m.duration?.inMilliseconds
      ..track = m.trackNumber
      ..disc = m.discNumber
      ..year = m.year?.year;
    if (m.pictures.isNotEmpty) {
      final front = m.pictures.firstWhere(
        (pic) => pic.pictureType == PictureType.coverFront,
        orElse: () => m.pictures.first,
      );
      out.art = front.bytes;
    }
  } catch (_) {
    // Unreadable tags: keep the file playable with filename-based metadata.
    out.failed = true;
  }
  return out;
}

/// Top-level so the isolate closure captures only [items], never `this`.
Future<List<_Parsed>> _parseInIsolate(List<(String, int, DateTime)> items) =>
    Isolate.run(() => items.map(_parse).toList());
