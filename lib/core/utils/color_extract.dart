import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

final _cache = <String, Color?>{};

/// Computes a muted dominant colour from an artwork file by decoding a tiny
/// 16×16 thumbnail. Cheap enough to run on every track change.
Future<Color?> dominantColorFromFile(String? path) async {
  if (path == null) return null;
  if (_cache.containsKey(path)) return _cache[path];
  try {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 16, targetHeight: 16);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    codec.dispose();
    if (data == null) return null;
    var r = 0, g = 0, b = 0, n = 0;
    for (var i = 0; i < data.lengthInBytes; i += 4) {
      final pr = data.getUint8(i), pg = data.getUint8(i + 1), pb = data.getUint8(i + 2);
      final hi = pr > pg ? (pr > pb ? pr : pb) : (pg > pb ? pg : pb);
      final lo = pr < pg ? (pr < pb ? pr : pb) : (pg < pb ? pg : pb);
      // Weight saturated pixels so the result is not always grey.
      final weight = 1 + (hi - lo) ~/ 32;
      r += pr * weight;
      g += pg * weight;
      b += pb * weight;
      n += weight;
    }
    final hsl = HSLColor.fromColor(Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n));
    final tuned = hsl
        .withLightness(hsl.lightness.clamp(0.16, 0.38))
        .withSaturation(hsl.saturation.clamp(0.0, 0.5))
        .toColor();
    if (_cache.length > 200) _cache.clear();
    return _cache[path] = tuned;
  } catch (_) {
    return _cache[path] = null;
  }
}
