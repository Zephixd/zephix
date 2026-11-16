import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../app/theme/zephix_colors.dart';
import '../../app/theme/zephix_theme.dart';
import 'artwork.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle, this.action, this.onAction});
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.xl, ZSpace.sm, ZSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.tt.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: context.tt.bodySmall),
                ],
              ],
            ),
          ),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    );
  }
}

/// Horizontally scrolling row of cards.
class Shelf extends StatelessWidget {
  const Shelf({super.key, required this.itemCount, required this.itemBuilder, this.height = 214, this.itemWidth = 150});
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double height;
  final double itemWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: ZSpace.page),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: ZSpace.md),
        itemBuilder: (c, i) => SizedBox(width: itemWidth, child: itemBuilder(c, i)),
      ),
    );
  }
}

/// Square artwork card with two lines of text.
class MediaCard extends StatelessWidget {
  const MediaCard({
    super.key,
    required this.title,
    this.subtitle,
    this.artPath,
    this.artUrl,
    this.onTap,
    this.circle = false,
    this.icon = Icons.album_rounded,
  });

  final String title;
  final String? subtitle;
  final String? artPath;
  final String? artUrl;
  final VoidCallback? onTap;
  final bool circle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: subtitle == null ? title : '$title, $subtitle',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZRadius.md),
        child: Column(
          crossAxisAlignment: circle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Artwork(path: artPath, url: artUrl, seed: title, radius: ZRadius.md, circle: circle, icon: icon),
            const SizedBox(height: ZSpace.sm),
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleSmall,
                textAlign: circle ? TextAlign.center : TextAlign.start),
            if (subtitle != null)
              Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall,
                  textAlign: circle ? TextAlign.center : TextAlign.start),
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action, this.onAction});
  final IconData icon;
  final String title;
  final String? message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final zc = context.zc;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ZSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: zc.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(color: zc.border),
              ),
              child: Icon(icon, size: 32, color: zc.primary),
            ),
            const SizedBox(height: ZSpace.lg),
            Text(title, style: context.tt.titleLarge, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: ZSpace.sm),
              Text(message!, style: context.tt.bodyMedium?.copyWith(color: zc.textSecondary), textAlign: TextAlign.center),
            ],
            if (action != null) ...[
              const SizedBox(height: ZSpace.xl),
              FilledButton(onPressed: onAction, child: Text(action!)),
            ],
          ],
        ).animate().fadeIn(duration: ZMotion.medium).slideY(begin: 0.04, end: 0, curve: ZMotion.curve),
      ),
    );
  }
}

/// Large header used by album, artist, playlist and mix screens.
class CollectionHeader extends StatelessWidget {
  const CollectionHeader({
    super.key,
    required this.title,
    required this.seed,
    this.kicker,
    this.subtitle,
    this.artPath,
    this.artUrl,
    this.circle = false,
    this.actions = const [],
    this.icon = Icons.album_rounded,
  });

  final String title;
  final String seed;
  final String? kicker;
  final String? subtitle;
  final String? artPath;
  final String? artUrl;
  final bool circle;
  final List<Widget> actions;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final zc = context.zc;
    final width = MediaQuery.sizeOf(context).width;
    final art = (width * 0.56).clamp(160.0, 280.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.sm, ZSpace.page, ZSpace.lg),
      child: Column(
        children: [
          Hero(
            tag: 'art:$seed',
            child: Artwork(path: artPath, url: artUrl, seed: seed, size: art, radius: ZRadius.lg, circle: circle, icon: icon),
          ),
          const SizedBox(height: ZSpace.xl),
          if (kicker != null)
            Text(kicker!.toUpperCase(), style: context.tt.labelSmall?.copyWith(color: zc.primary)),
          const SizedBox(height: ZSpace.xs),
          Text(title, style: context.tt.headlineLarge, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
          if (subtitle != null) ...[
            const SizedBox(height: ZSpace.xs),
            Text(subtitle!, style: context.tt.bodyMedium?.copyWith(color: zc.textSecondary), textAlign: TextAlign.center),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: ZSpace.lg),
            Wrap(spacing: ZSpace.sm, runSpacing: ZSpace.sm, alignment: WrapAlignment.center, children: actions),
          ],
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.zc.secondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(ZRadius.pill),
      ),
      child: Text(label, style: context.tt.labelSmall?.copyWith(color: c, letterSpacing: 0.4, fontSize: 10)),
    );
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
