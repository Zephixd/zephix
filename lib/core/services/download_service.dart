import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../data/database/app_database.dart';
import '../constants/app_info.dart';

/// Downloads open-licensed streams (only sources that declare the
/// `download` capability) into app storage and turns them into local tracks.
class DownloadService {
  DownloadService(this._db, {Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(headers: {'User-Agent': AppInfo.userAgent}));

  final AppDatabase _db;
  final Dio _dio;

  /// trackId → progress 0..1 for active downloads.
  final ValueNotifier<Map<int, double>> active = ValueNotifier(const {});

  static Future<Directory> downloadsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'Descargas'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<TrackRow> download(TrackRow track) async {
    if (!track.uri.startsWith('http')) return track;
    if (active.value.containsKey(track.id)) throw StateError('Ya se está descargando.');
    final dir = await downloadsDir();
    final ext = p.extension(Uri.parse(track.uri).path).isEmpty ? '.mp3' : p.extension(Uri.parse(track.uri).path);
    final safe = '${track.artist} - ${track.title}'.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
    final target = File(p.join(dir.path, '${safe.length > 120 ? safe.substring(0, 120) : safe}_${track.id}$ext'));
    final tmp = File('${target.path}.part');
    _set(track.id, 0);
    try {
      await _dio.download(track.uri, tmp.path, onReceiveProgress: (r, t) {
        if (t > 0) _set(track.id, r / t);
      });
      await tmp.rename(target.path);
      final stat = await target.stat();
      await (_db.update(_db.tracks)..where((t) => t.id.equals(track.id))).write(TracksCompanion(
        uri: Value(Uri.file(target.path).toString()),
        folder: Value(dir.path),
        fileSize: Value(stat.size),
        fileModified: Value(stat.modified),
      ));
      return (await _db.trackById(track.id))!;
    } catch (_) {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    } finally {
      final m = {...active.value}..remove(track.id);
      active.value = m;
    }
  }

  void _set(int id, double v) => active.value = {...active.value, id: v};
}
