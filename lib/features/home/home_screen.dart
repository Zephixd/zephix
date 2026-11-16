import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/routes.dart';
import '../../app/theme/zephix_colors.dart';
import '../../app/theme/zephix_theme.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/artwork.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/track_actions.dart';
import '../../shared/widgets/zephix_logo.dart';
import '../library/scan_banner.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zc = context.zc;
    final tracks = ref.watch(tracksProvider);
    final recent = ref.watch(recentlyPlayedProvider).value ?? const [];
    final favorites = ref.watch(favoriteTracksProvider).value ?? const [];
    final albums = ref.watch(recentAlbumsProvider).value ?? const [];
    final mixes = ref.watch(smartMixesProvider).value ?? const [];
    final playlists = ref.watch(frequentPlaylistsProvider);
    final week = ref.watch(statsProvider(StatsRange.week)).value;
    final showStats = ref.watch(settingsProvider.select((s) => s.showStatsOnHome));

    final libraryEmpty = tracks.hasValue && tracks.value!.isEmpty;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            titleSpacing: ZSpace.page,
            title: const ZephixWordmark(size: 22),
            actions: [
              IconButton(
                tooltip: 'Estadísticas',
                icon: const Icon(Icons.insights_rounded),
                onPressed: () => context.push(Routes.stats),
              ),
              IconButton(
                tooltip: 'Ajustes',
                icon: const Icon(Icons.tune_rounded),
                onPressed: () => context.push(Routes.settings),
              ),
              const SizedBox(width: 4),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.md, ZSpace.page, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(greetingFor(DateTime.now()), style: context.tt.displaySmall),
                  if (showStats && week != null && !week.isEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Esta semana: ${formatMinutes(week.listenedMs)} de música · ${plural(week.uniqueTracks, 'canción', 'canciones')}',
                      style: context.tt.bodyMedium?.copyWith(color: zc.textSecondary),
                    ),
                  ],
                ],
              ).animate().fadeIn(duration: ZMotion.medium),
            ),
          ),
          const SliverToBoxAdapter(child: ScanBanner()),
          if (libraryEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.library_music_rounded,
                title: 'Tu biblioteca está vacía',
                message: 'Zephix reproduce la música guardada en tu dispositivo. '
                    'Busca archivos en tus carpetas de música o explora el catálogo abierto.',
                action: 'Buscar música en el dispositivo',
                onAction: () => ref.read(scanProvider.notifier).scan(),
              ),
            )
          else ...[
            if (recent.isNotEmpty)
              SliverToBoxAdapter(
                child: _QuickGrid(
                  items: [
                    for (final t in recent.take(6))
                      _QuickItem(t.title, t.artPath, t.artUrl, '${t.album}${t.artist}',
                          () => ref.playTracks(recent, index: recent.indexOf(t))),
                  ],
                ),
              ),
            if (mixes.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: SectionHeader('Mezclas inteligentes', subtitle: 'Creadas en tu dispositivo a partir de lo que escuchas'),
              ),
              SliverToBoxAdapter(
                child: Shelf(
                  itemCount: mixes.length,
                  itemWidth: 160,
                  height: 224,
                  itemBuilder: (c, i) => _MixCard(
                    title: mixes[i].title,
                    subtitle: mixes[i].subtitle,
                    artPath: mixes[i].artPath,
                    onTap: () => context.push(Routes.mix(mixes[i].id)),
                  ),
                ),
              ),
            ],
            if (recent.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SectionHeader('Escuchado recientemente')),
              SliverToBoxAdapter(
                child: Shelf(
                  itemCount: recent.length,
                  itemBuilder: (c, i) => MediaCard(
                    title: recent[i].title,
                    subtitle: recent[i].artist,
                    artPath: recent[i].artPath,
                    artUrl: recent[i].artUrl,
                    icon: Icons.music_note_rounded,
                    onTap: () => ref.playTracks(recent, index: i),
                  ),
                ),
              ),
            ],
            if (favorites.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader('Tus favoritos',
                    action: 'Ver todo', onAction: () => context.push(Routes.libraryList('favorites'))),
              ),
              SliverToBoxAdapter(
                child: Shelf(
                  itemCount: favorites.length.clamp(0, 15),
                  itemBuilder: (c, i) => MediaCard(
                    title: favorites[i].title,
                    subtitle: favorites[i].artist,
                    artPath: favorites[i].artPath,
                    artUrl: favorites[i].artUrl,
                    icon: Icons.favorite_rounded,
                    onTap: () => ref.playTracks(favorites, index: i),
                  ),
                ),
              ),
            ],
            if (playlists.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SectionHeader('Tus playlists')),
              SliverToBoxAdapter(
                child: Shelf(
                  itemCount: playlists.length,
                  itemBuilder: (c, i) => MediaCard(
                    title: playlists[i].playlist.name,
                    subtitle: plural(playlists[i].trackCount, 'canción', 'canciones'),
                    artPath: playlists[i].artPath,
                    icon: Icons.queue_music_rounded,
                    onTap: () => context.push(Routes.playlist(playlists[i].playlist.id)),
                  ),
                ),
              ),
            ],
            if (albums.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader('Añadidos recientemente',
                    action: 'Álbumes', onAction: () => context.go(Routes.library)),
              ),
              SliverToBoxAdapter(
                child: Shelf(
                  itemCount: albums.length,
                  itemBuilder: (c, i) => MediaCard(
                    title: albums[i].title,
                    subtitle: albums[i].artist,
                    artPath: albums[i].artPath,
                    onTap: () => context.push(Routes.album(albums[i].title, albums[i].artist)),
                  ),
                ),
              ),
            ],
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.xl, ZSpace.page, 0),
                child: _DiscoverCard(onTap: () => context.go(Routes.explore)),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 140)),
          ],
        ],
      ),
    );
  }
}

class _QuickItem {
  _QuickItem(this.title, this.artPath, this.artUrl, this.seed, this.onTap);
  final String title;
  final String? artPath;
  final String? artUrl;
  final String seed;
  final VoidCallback onTap;
}

/// "Continue" grid of the last tracks heard.
class _QuickGrid extends StatelessWidget {
  const _QuickGrid({required this.items});
  final List<_QuickItem> items;

  @override
  Widget build(BuildContext context) {
    final zc = context.zc;
    return Padding(
      padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.xl, ZSpace.page, 0),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: ZSpace.sm,
        crossAxisSpacing: ZSpace.sm,
        childAspectRatio: 3.1,
        children: [
          for (final (i, it) in items.indexed)
            Material(
              color: zc.surface,
              borderRadius: BorderRadius.circular(ZRadius.sm),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: it.onTap,
                child: Row(
                  children: [
                    AspectRatio(aspectRatio: 1, child: Artwork(path: it.artPath, url: it.artUrl, seed: it.seed, radius: 0)),
                    const SizedBox(width: ZSpace.sm),
                    Expanded(
                      child: Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.tt.labelLarge),
                    ),
                    const SizedBox(width: ZSpace.sm),
                  ],
                ),
              ),
            ).animate().fadeIn(delay: (40 * i).ms, duration: ZMotion.medium),
        ],
      ),
    );
  }
}

class _MixCard extends StatelessWidget {
  const _MixCard({required this.title, required this.subtitle, this.artPath, required this.onTap});
  final String title;
  final String subtitle;
  final String? artPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zc = context.zc;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ZRadius.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Artwork(path: artPath, seed: title, radius: ZRadius.md, icon: Icons.auto_awesome_rounded),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(ZRadius.md),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, zc.primaryDark.withValues(alpha: 0.85)],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Text(title,
                    maxLines: 2,
                    style: context.tt.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: ZSpace.sm),
          Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall),
        ],
      ),
    );
  }
}

class _DiscoverCard extends StatelessWidget {
  const _DiscoverCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zc = context.zc;
    return Material(
      borderRadius: BorderRadius.circular(ZRadius.lg),
      clipBehavior: Clip.antiAlias,
      color: zc.surface,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(ZSpace.xl),
          decoration: BoxDecoration(
            border: Border.all(color: zc.border),
            borderRadius: BorderRadius.circular(ZRadius.lg),
            gradient: LinearGradient(
              colors: [zc.secondary.withValues(alpha: 0.16), zc.primary.withValues(alpha: 0.08)],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DESCUBRIMIENTO', style: context.tt.labelSmall?.copyWith(color: zc.secondary)),
                    const SizedBox(height: 6),
                    Text('Música libre del Internet Archive', style: context.tt.titleLarge),
                    const SizedBox(height: 4),
                    Text('Obras con licencia Creative Commons y de dominio público.', style: context.tt.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: zc.secondary),
            ],
          ),
        ),
      ),
    );
  }
}
