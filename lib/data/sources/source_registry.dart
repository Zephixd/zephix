// language: Dart, file: source_registry.dart, target: Flutter (Zephix)
import 'music_source_provider.dart';
import 'ytm_source.dart';

/// Static catalogue of the built-in online audio sources, so widgets can read
/// capabilities straight from a persisted `track.source` id without a ref.
const audioSourceInfos = <SourceInfo>[ytmSourceInfo];

SourceInfo? sourceInfoById(String id) {
  for (final s in audioSourceInfos) {
    if (s.id == id) return s;
  }
  return null;
}
