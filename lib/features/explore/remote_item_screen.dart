// language: Dart, file: remote_item_screen.dart, target: Flutter (Zephix)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/zephix_colors.dart';
import '../../app/theme/zephix_theme.dart';
import '../../core/utils/format.dart';
import '../../data/remote_tracks.dart';
import '../../data/sources/music_source_provider.dart';
import '../../data/sources/source_registry.dart';
import '../../data/sources/ytm_source.dart';
import '../../shared/widgets/common.dart';

/// Loads tracks for the online source by dispatching on the collection's
/// `sourceId`, so every provider shares this detail screen.
final remoteTracksProvider = FutureProvider.autoDispose.family<List<RemoteTrack>, RemoteCollection>(
    (ref, c) async {
  final source = ref.watch(ytmSourceProvider).info.id == c.sourceId ? ref.watch(ytmSourceProvider) : null;
  if (source == null) throw SourceException('Fuente desconocida: ${c.sourceId}');
  return source.collectionTracks(c);
});

class RemoteItemScreen extends ConsumerWidget {
  const RemoteItemScreen({super.key, required this.collection});
  final RemoteCollection collection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zc = context.zc;
    final tracks = ref.watch(remoteTracksProvider(collection));
    final db = ref.read(databaseProvider);
    final handler = ref.read(audioHandlerProvider);
    final sourceName = collection.sourceId == ytmSourceInfo.id && YtmSource.isAlbumId(collection.externalId)
        ? 'Álbum · YouTube Music'
        : sourceInfoById(collection.sourceId)?.name ?? 'Fuente externa';
    final bannerText = collection.license != null
        ? 'Licencia: ${collection.license}. Respeta sus condiciones de atribución y uso.'
        : collection.sourceId == ytmSourceInfo.id
            ? 'El audio se obtiene directamente del servidor sin el reproductor web, '
                'por lo que no incluye anuncios. El contenido pertenece a sus autores.'
            : 'Origen: $sourceName. Comprueba los términos de uso del catálogo.';

    Future<void> play(List<RemoteTrack> list, int index) async {
      final target = list[index];
      final rows = await materializeRemote(db, list);
      final start = rows.indexWhere((r) => r.uri == target.streamUrl);
      await handler.playTracks(rows, index: start < 0 ? 0 : start);
    }

    return Scaffold(
      appBar: AppBar(),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: CollectionHeader(
              title: collection.title,
              seed: collection.externalId,
              kicker: sourceName,
              subtitle: [collection.creator, if (collection.year != null) '${collection.year}']
                  .join(' · '),
              artUrl: collection.artUrl,
              actions: [
                if (tracks.value?.any((t) => t.playable) ?? false)
                  FilledButton.icon(
                    onPressed: () => play(tracks.value!, tracks.value!.indexWhere((t) => t.playable)),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Reproducir'),
                  ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(ZSpace.page, 0, ZSpace.page, ZSpace.md),
              child: Container(
                padding: const EdgeInsets.all(ZSpace.md),
                decoration: BoxDecoration(
                  color: zc.surface,
                  borderRadius: BorderRadius.circular(ZRadius.md),
                  border: Border.all(color: zc.border),
                ),
                child: Row(
                  children: [
                    Icon(
                      collection.sourceId == ytmSourceInfo.id
                          ? Icons.music_note_rounded
                          : Icons.verified_outlined,
                      color: zc.secondary,
                      size: 20,
                    ),
                    const SizedBox(width: ZSpace.sm),
                    Expanded(
                      child: Text(bannerText, style: context.tt.bodySmall),
                    ),
                  ],
                ),
              ),
            ),
          ),
          tracks.when(
            loading: () => const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
            error: (e, _) => SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'No se pudo cargar',
                message: e.toString(),
                action: 'Reintentar',
                onAction: () => ref.invalidate(remoteTracksProvider(collection)),
              ),
            ),
            data: (list) => list.isEmpty
                ? const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.music_off_rounded,
                      title: 'Sin pistas de audio',
                      message: 'Este elemento no contiene archivos de audio compatibles.',
                    ),
                  )
                : SliverList.builder(
                    itemCount: list.length,
                    itemBuilder: (c, i) {
                      final t = list[i];
                      return ListTile(
                        enabled: t.playable,
                        onTap: t.playable ? () => play(list, i) : null,
                        leading: SizedBox(
                          width: 28,
                          child: Text('${t.trackNumber ?? i + 1}',
                              textAlign: TextAlign.center, style: context.tt.bodyMedium?.copyWith(color: zc.textSecondary)),
                        ),
                        title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          t.playable
                              ? '${t.artist}${t.durationMs > 0 ? ' · ${formatMs(t.durationMs)}' : ''}'
                              : 'No reproducible: ${t.unplayableReason}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: t.playable
                            ? IconButton(
                                tooltip: 'Añadir a la cola',
                                icon: const Icon(Icons.add_rounded),
                                onPressed: () async {
                                  final rows = await materializeRemote(db, [t]);
                                  await handler.enqueue(rows);
                                  if (context.mounted) showSnack(context, 'Añadido a la cola');
                                },
                              )
                            : const Icon(Icons.block_rounded),
                      );
                    },
                  ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
    );
  }
}
