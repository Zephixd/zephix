import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';

import '../../app/providers.dart';
import '../../app/router/routes.dart';
import '../../app/theme/zephix_colors.dart';
import '../../app/theme/zephix_theme.dart';
import '../../core/utils/color_extract.dart';
import '../../core/utils/format.dart';
import '../../data/database/app_database.dart';
import '../../domain/entities/track_x.dart';
import '../../shared/widgets/artwork.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/track_actions.dart';
import '../lyrics/lyrics_view.dart';
import 'queue_sheet.dart';
import 'sleep_timer_sheet.dart';

final _artColorProvider = FutureProvider.autoDispose.family<Color?, String?>((ref, path) => dominantColorFromFile(path));

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zc = context.zc;
    final track = ref.watch(currentTrackProvider).value;
    if (track == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.music_off_rounded, title: 'Nada en reproducción'),
      );
    }
    final tint = ref.watch(_artColorProvider(track.artPath)).value ?? zc.surfaceElevated;
    final size = MediaQuery.sizeOf(context);
    final artSize = (size.width - 56).clamp(200.0, size.height * 0.42);

    return Scaffold(
      body: AnimatedContainer(
        duration: ZMotion.slow,
        curve: ZMotion.curve,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color.lerp(tint, zc.background, 0.1)!, zc.background],
            stops: const [0, 0.78],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _TopBar(track: track),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) => SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: c.maxHeight),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            const SizedBox(height: 8),
                            _Cover(track: track, size: artSize),
                            const SizedBox(height: 20),
                            _TitleRow(track: track),
                            const SizedBox(height: 12),
                            const _SeekBar(),
                            const _Controls(),
                            const SizedBox(height: 8),
                            _BottomActions(track: track),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.track});
  final TrackRow track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Cerrar',
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
            onPressed: () => context.pop(),
          ),
          Expanded(
            child: Column(
              children: [
                Text('REPRODUCIENDO DESDE', style: context.tt.labelSmall),
                Text(track.album, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.titleSmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Más opciones',
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () => showTrackActions(context, ref, track),
          ),
        ],
      ),
    );
  }
}

class _Cover extends ConsumerWidget {
  const _Cover({required this.track, required this.size});
  final TrackRow track;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.read(audioHandlerProvider);
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -300) handler.skipToNext();
        if (v > 300) handler.skipToPrevious();
      },
      onDoubleTap: () => ref.read(databaseProvider).toggleFavorite(track.id),
      child: Hero(
        tag: 'now-playing-art',
        child: AnimatedSwitcher(
          duration: ZMotion.slow,
          switchInCurve: ZMotion.curve,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(a), child: child),
          ),
          child: Container(
            key: ValueKey(track.id),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(ZRadius.lg),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 40, offset: const Offset(0, 18)),
              ],
            ),
            child: Artwork(
              path: track.artPath,
              url: track.artUrl,
              seed: '${track.album}${track.artist}',
              size: size,
              radius: ZRadius.lg,
            ),
          ),
        ),
      ),
    );
  }
}

class _TitleRow extends ConsumerWidget {
  const _TitleRow({required this.track});
  final TrackRow track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zc = context.zc;
    final isFav = ref.watch(favoriteIdsProvider.select((v) => v.value?.contains(track.id) ?? false));
    return Row(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: ZMotion.medium,
            child: Column(
              key: ValueKey(track.id),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.tt.headlineMedium),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => context.push(Routes.artist(track.artist)),
                  child: Text(track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.tt.titleMedium?.copyWith(color: zc.textSecondary)),
                ),
                if (track.license != null) ...[const SizedBox(height: 6), Pill(track.license!)],
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: isFav ? 'Quitar de favoritos' : 'Añadir a favoritos',
          iconSize: 28,
          onPressed: () => ref.read(databaseProvider).toggleFavorite(track.id),
          icon: AnimatedSwitcher(
            duration: ZMotion.fast,
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              key: ValueKey(isFav),
              color: isFav ? zc.primary : zc.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class _SeekBar extends ConsumerStatefulWidget {
  const _SeekBar();
  @override
  ConsumerState<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends ConsumerState<_SeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    final dur = ref.watch(durationProvider).value ?? Duration.zero;
    final buffered = ref.watch(bufferedProvider).value ?? Duration.zero;
    final max = dur.inMilliseconds.toDouble();
    final value = (_drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, max <= 0 ? 1.0 : max);
    final zc = context.zc;
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: LinearProgressIndicator(
                value: max <= 0 ? 0 : (buffered.inMilliseconds / max).clamp(0, 1),
                minHeight: 3,
                color: zc.textSecondary.withValues(alpha: 0.35),
                backgroundColor: Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Slider(
              value: value,
              max: max <= 0 ? 1 : max,
              semanticFormatterCallback: (v) => formatMs(v.round()),
              onChanged: max <= 0 ? null : (v) => setState(() => _drag = v),
              onChangeEnd: (v) {
                ref.read(audioHandlerProvider).seek(Duration(milliseconds: v.round()));
                setState(() => _drag = null);
              },
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatMs(value.round()), style: context.tt.labelMedium),
              Text(max <= 0 ? '--:--' : formatDuration(dur), style: context.tt.labelMedium),
            ],
          ),
        ),
      ],
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zc = context.zc;
    final handler = ref.read(audioHandlerProvider);
    final playing = ref.watch(playingProvider).value ?? false;
    final shuffle = ref.watch(shuffleProvider).value ?? false;
    final loop = ref.watch(loopModeProvider).value ?? LoopMode.off;
    final processing = ref.watch(processingProvider).value;
    final loading = processing == ProcessingState.loading || processing == ProcessingState.buffering;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: shuffle ? 'Desactivar aleatorio' : 'Activar aleatorio',
            onPressed: handler.toggleShuffle,
            icon: Icon(Icons.shuffle_rounded, color: shuffle ? zc.primary : zc.textSecondary),
          ),
          IconButton(
            tooltip: 'Anterior',
            iconSize: 40,
            onPressed: handler.skipToPrevious,
            icon: const Icon(Icons.skip_previous_rounded),
          ),
          Semantics(
            button: true,
            label: playing ? 'Pausar' : 'Reproducir',
            child: Material(
              color: zc.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: playing ? handler.pause : handler.play,
                child: SizedBox(
                  width: 76,
                  height: 76,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (loading)
                        SizedBox(
                          width: 76,
                          height: 76,
                          child: CircularProgressIndicator(strokeWidth: 2, color: zc.background.withValues(alpha: 0.5)),
                        ),
                      AnimatedSwitcher(
                        duration: ZMotion.fast,
                        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                        child: Icon(
                          playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          key: ValueKey(playing),
                          size: 42,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Siguiente',
            iconSize: 40,
            onPressed: handler.skipToNext,
            icon: const Icon(Icons.skip_next_rounded),
          ),
          IconButton(
            tooltip: switch (loop) {
              LoopMode.off => 'Repetir todo',
              LoopMode.all => 'Repetir una',
              LoopMode.one => 'Desactivar repetición',
            },
            onPressed: handler.cycleRepeat,
            icon: Icon(
              loop == LoopMode.one ? Icons.repeat_one_rounded : Icons.repeat_rounded,
              color: loop == LoopMode.off ? zc.textSecondary : zc.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomActions extends ConsumerWidget {
  const _BottomActions({required this.track});
  final TrackRow track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zc = context.zc;
    final sleepAt = ref.watch(sleepAtProvider).value;
    final sleepEnd = ref.watch(sleepEndOfTrackProvider).value ?? false;
    final sleeping = sleepAt != null || sleepEnd;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _Action(
          icon: Icons.lyrics_outlined,
          label: 'Letra',
          onTap: () => context.push(Routes.lyrics),
        ),
        _Action(
          icon: Icons.bedtime_outlined,
          label: sleeping ? (sleepEnd ? 'Fin pista' : 'Activo') : 'Temporizador',
          color: sleeping ? zc.primary : null,
          onTap: () => showSleepTimerSheet(context, ref),
        ),
        _Action(
          icon: Icons.queue_music_rounded,
          label: 'Cola',
          onTap: () => showQueueSheet(context),
        ),
      ],
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.zc.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ZRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: c),
            const SizedBox(height: 4),
            Text(label, style: context.tt.labelMedium?.copyWith(color: c)),
          ],
        ),
      ),
    );
  }
}

/// Full-screen lyrics page reached from the player.
class LyricsScreen extends ConsumerWidget {
  const LyricsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: track == null
            ? const Text('Letra')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(track.title, style: context.tt.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(track.artist, style: context.tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
      ),
      body: track == null
          ? const EmptyState(icon: Icons.lyrics_outlined, title: 'Nada en reproducción')
          : LyricsView(trackId: track.id, isRemote: track.isRemote),
    );
  }
}
