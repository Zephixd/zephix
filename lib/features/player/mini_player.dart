import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/routes.dart';
import '../../app/theme/zephix_colors.dart';
import '../../app/theme/zephix_theme.dart';
import '../../shared/widgets/artwork.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider).value;
    return AnimatedSwitcher(
      duration: ZMotion.medium,
      transitionBuilder: (child, a) => SizeTransition(sizeFactor: a, alignment: Alignment.topCenter, child: child),
      child: track == null ? const SizedBox.shrink() : _MiniPlayerBody(key: const ValueKey('mini')),
    );
  }
}

class _MiniPlayerBody extends ConsumerWidget {
  const _MiniPlayerBody({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zc = context.zc;
    final track = ref.watch(currentTrackProvider).value;
    if (track == null) return const SizedBox.shrink();
    final playing = ref.watch(playingProvider).value ?? false;
    final handler = ref.read(audioHandlerProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(ZSpace.sm, 0, ZSpace.sm, ZSpace.sm),
      child: Material(
        color: zc.surfaceElevated,
        borderRadius: BorderRadius.circular(ZRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(Routes.player),
          child: GestureDetector(
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v < -300) handler.skipToNext();
              if (v > 300) handler.skipToPrevious();
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 4, 6),
                  child: Row(
                    children: [
                      Hero(
                        tag: 'now-playing-art',
                        child: AnimatedSwitcher(
                          duration: ZMotion.medium,
                          child: SizedBox(
                            key: ValueKey(track.id),
                            width: 44,
                            height: 44,
                            child: Artwork(
                                path: track.artPath, url: track.artUrl, seed: '${track.album}${track.artist}', size: 44),
                          ),
                        ),
                      ),
                      const SizedBox(width: ZSpace.md),
                      Expanded(
                        child: Semantics(
                          label: 'Reproduciendo ${track.title} de ${track.artist}. Toca para abrir el reproductor.',
                          child: AnimatedSwitcher(
                            duration: ZMotion.fast,
                            child: Column(
                              key: ValueKey(track.id),
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleSmall),
                                Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall),
                              ],
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: playing ? 'Pausar' : 'Reproducir',
                        iconSize: 30,
                        onPressed: playing ? handler.pause : handler.play,
                        icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      ),
                      IconButton(
                        tooltip: 'Siguiente',
                        onPressed: handler.skipToNext,
                        icon: const Icon(Icons.skip_next_rounded),
                      ),
                    ],
                  ),
                ),
                const _MiniProgress(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniProgress extends ConsumerWidget {
  const _MiniProgress();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final dur = ref.watch(durationProvider).value;
    final v = (dur == null || dur.inMilliseconds == 0) ? 0.0 : pos.inMilliseconds / dur.inMilliseconds;
    return LinearProgressIndicator(
      value: v.clamp(0, 1),
      minHeight: 2,
      backgroundColor: context.zc.border,
      color: context.zc.primary,
    );
  }
}
