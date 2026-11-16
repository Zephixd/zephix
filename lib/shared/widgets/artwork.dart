import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/zephix_colors.dart';
import '../../app/theme/zephix_theme.dart';

/// Artwork from a local file or URL with a generated, deterministic
/// placeholder when none exists. Decodes at display size to save memory.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    this.path,
    this.url,
    required this.seed,
    this.size,
    this.radius = ZRadius.sm,
    this.circle = false,
    this.icon = Icons.music_note_rounded,
  });

  final String? path;
  final String? url;
  final String seed;
  final double? size;
  final double radius;
  final bool circle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final w = size ?? (c.maxWidth.isFinite ? c.maxWidth : 200);
      final cache = (w * dpr).round().clamp(64, 1200);
      Widget child;
      if (path != null) {
        child = Image.file(
          File(path!),
          fit: BoxFit.cover,
          cacheWidth: cache,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _Placeholder(seed: seed, icon: icon),
        );
      } else if (url != null) {
        child = CachedNetworkImage(
          imageUrl: url!,
          fit: BoxFit.cover,
          memCacheWidth: cache,
          fadeInDuration: ZMotion.fast,
          placeholder: (_, _) => _Placeholder(seed: seed, icon: icon),
          errorWidget: (_, _, _) => _Placeholder(seed: seed, icon: icon),
        );
      } else {
        child = _Placeholder(seed: seed, icon: icon);
      }
      final box = SizedBox(width: size, height: size, child: AspectRatio(aspectRatio: 1, child: child));
      return circle
          ? ClipOval(child: box)
          : ClipRRect(borderRadius: BorderRadius.circular(radius), child: box);
    });
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.seed, required this.icon});
  final String seed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final zc = context.zc;
    final h = seed.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0xFFFFFF);
    final hue = (h % 360).toDouble();
    final a = HSLColor.fromAHSL(1, hue, 0.35, 0.22).toColor();
    final b = HSLColor.fromAHSL(1, (hue + 50) % 360, 0.4, 0.12).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(a, zc.surfaceElevated, 0.35)!, Color.lerp(b, zc.background, 0.3)!],
        ),
      ),
      child: LayoutBuilder(
        builder: (_, c) => Center(
          child: Icon(icon, size: (c.maxWidth * 0.34).clamp(14, 64), color: zc.textPrimary.withValues(alpha: 0.55)),
        ),
      ),
    );
  }
}
