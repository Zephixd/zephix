import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/routes.dart';
import '../../app/theme/zephix_colors.dart';
import '../../app/theme/zephix_theme.dart';
import '../../core/utils/format.dart';
import '../../data/sources/music_source_provider.dart';
import '../../shared/widgets/common.dart';

/// Featured picks (current hits) for the online source.
final ytmFeaturedProvider = FutureProvider<List<RemoteCollection>>((ref) async {
  return ref.watch(ytmSourceProvider).searchCollections('', limit: 18);
});

class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genres = ref.watch(genresProvider).value ?? const [];
    final albums = ref.watch(albumsProvider).value ?? const [];
    final artists = ref.watch(artistsProvider).value ?? const [];
    final openCatalogs = ref.watch(settingsProvider.select((s) => s.openCatalogs));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            titleSpacing: ZSpace.page,
            title: Text('Explorar', style: context.tt.headlineMedium),
          ),
          if (genres.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader('Géneros', subtitle: 'De tu biblioteca')),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: ZSpace.page),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisExtent: 76,
                  mainAxisSpacing: ZSpace.sm,
                  crossAxisSpacing: ZSpace.sm,
                ),
                itemCount: genres.length.clamp(0, 12),
                itemBuilder: (c, i) => _GenreTile(
                  name: genres[i].$1,
                  count: genres[i].$2,
                  onTap: () => context.push(Routes.genre(genres[i].$1)),
                ),
              ),
            ),
          ],
          if (artists.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader('Artistas', action: 'Ver todo', onAction: () => context.push(Routes.libraryList('artists'))),
            ),
            SliverToBoxAdapter(
              child: Shelf(
                itemCount: artists.length.clamp(0, 20),
                itemWidth: 120,
                height: 170,
                itemBuilder: (c, i) => MediaCard(
                  title: artists[i].name,
                  subtitle: plural(artists[i].trackCount, 'canción', 'canciones'),
                  artPath: artists[i].artPath,
                  circle: true,
                  icon: Icons.person_rounded,
                  onTap: () => context.push(Routes.artist(artists[i].name)),
                ),
              ),
            ),
          ],
          if (albums.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: SectionHeader('Álbumes', action: 'Ver todo', onAction: () => context.push(Routes.libraryList('albums'))),
            ),
            SliverToBoxAdapter(
              child: Shelf(
                itemCount: albums.length.clamp(0, 20),
                itemBuilder: (c, i) => MediaCard(
                  title: albums[i].title,
                  subtitle: albums[i].artist,
                  artPath: albums[i].artPath,
                  onTap: () => context.push(Routes.album(albums[i].title, albums[i].artist)),
                ),
              ),
            ),
          ],
          if (openCatalogs) ...[
            const SliverToBoxAdapter(
              child: SectionHeader('YouTube Music',
                  subtitle: 'Catálogo completo · sin anuncios'),
            ),
            const SliverToBoxAdapter(child: _YtmShelf()),
          ] else if (genres.isEmpty && albums.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.explore_rounded,
                title: 'Nada para explorar todavía',
                message: 'Añade música a tu biblioteca o activa YouTube Music en Ajustes.',
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
    );
  }
}

class _GenreTile extends StatelessWidget {
  const _GenreTile({required this.name, required this.count, required this.onTap});
  final String name;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zc = context.zc;
    final hue = (name.codeUnits.fold<int>(0, (a, b) => a + b) * 37) % 360;
    final tint = HSLColor.fromAHSL(1, hue.toDouble(), 0.45, 0.45).toColor();
    return Material(
      color: Color.lerp(zc.surface, tint, 0.18),
      borderRadius: BorderRadius.circular(ZRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(ZRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(ZSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleMedium),
              Text(plural(count, 'canción', 'canciones'), style: context.tt.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _YtmShelf extends ConsumerWidget {
  const _YtmShelf();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(ytmFeaturedProvider);
    return items.when(
      loading: () => const SizedBox(
        height: 214,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.md, ZSpace.page, 0),
        child: Row(
          children: [
            Expanded(child: Text(e.toString(), style: context.tt.bodySmall)),
            TextButton(
              onPressed: () => ref.invalidate(ytmFeaturedProvider),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
      data: (list) => list.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: ZSpace.page),
              child: Text('Sin resultados en este momento.', style: context.tt.bodySmall),
            )
          : Shelf(
              itemCount: list.length,
              itemBuilder: (c, i) => MediaCard(
                title: list[i].title,
                subtitle: list[i].creator,
                artUrl: list[i].artUrl,
                onTap: () => context.push(Routes.remoteItem(list[i].externalId), extra: list[i]),
              ),
            ),
    );
  }
}
