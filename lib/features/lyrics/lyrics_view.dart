import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/zephix_colors.dart';
import '../../app/theme/zephix_theme.dart';
import '../../shared/widgets/common.dart';
import 'lrc_parser.dart';

class LyricsView extends ConsumerWidget {
  const LyricsView({super.key, required this.trackId, this.isRemote = false});
  final int trackId;
  final bool isRemote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyrics = ref.watch(lyricsProvider(trackId));
    final online = ref.watch(settingsProvider.select((s) => s.onlineLyrics));
    return lyrics.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'No se pudo cargar la letra',
        message: 'LRCLIB no respondió. Comprueba tu conexión.',
        action: 'Reintentar',
        onAction: () => ref.invalidate(lyricsProvider(trackId)),
      ),
      data: (l) {
        if (l.instrumental) {
          return const EmptyState(icon: Icons.piano_rounded, title: 'Instrumental', message: 'Esta canción no tiene letra.');
        }
        if (l.isEmpty) {
          return EmptyState(
            icon: Icons.lyrics_outlined,
            title: 'Sin letra disponible',
            message: online
                ? 'No hay letra incrustada en el archivo ni en LRCLIB.'
                : 'Las letras en línea están desactivadas en Ajustes.',
          );
        }
        if (l.isSynced) return _SyncedLyrics(lyrics: l);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.lg, ZSpace.page, 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.plain!, style: context.tt.titleLarge?.copyWith(height: 1.6)),
              const SizedBox(height: ZSpace.xl),
              _SourceNote(l.source),
            ],
          ),
        );
      },
    );
  }
}

class _SourceNote extends StatelessWidget {
  const _SourceNote(this.source);
  final String? source;
  @override
  Widget build(BuildContext context) => Text(
        source == 'lrclib' ? 'Letra de LRCLIB' : 'Letra incrustada en el archivo',
        style: context.tt.bodySmall,
      );
}

class _SyncedLyrics extends ConsumerStatefulWidget {
  const _SyncedLyrics({required this.lyrics});
  final Lyrics lyrics;
  @override
  ConsumerState<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends ConsumerState<_SyncedLyrics> {
  final _keys = <int, GlobalKey>{};
  int _active = -2;
  bool _userScrolling = false;

  void _follow(int index) {
    if (index == _active) return;
    _active = index;
    if (_userScrolling || index < 0) return;
    final ctx = _keys[index]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: 0.35, duration: ZMotion.medium, curve: ZMotion.curve);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zc = context.zc;
    final pos = ref.watch(positionProvider).value ?? Duration.zero;
    // Show a line slightly early so it does not feel late.
    final index = widget.lyrics.indexAt(pos + const Duration(milliseconds: 250));
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow(index));
    final lines = widget.lyrics.lines;

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n is ScrollStartNotification && n.dragDetails != null) _userScrolling = true;
        if (n is ScrollEndNotification) {
          Future.delayed(const Duration(seconds: 3), () => _userScrolling = false);
        }
        return false;
      },
      child: ListView.builder(
        padding: EdgeInsets.fromLTRB(ZSpace.page, ZSpace.xl, ZSpace.page, MediaQuery.sizeOf(context).height * 0.4),
        itemCount: lines.length + 1,
        itemBuilder: (context, i) {
          if (i == lines.length) {
            return const Padding(padding: EdgeInsets.only(top: 24), child: _SourceNote('lrclib'));
          }
          final line = lines[i];
          final active = i == index;
          final past = i < index;
          return InkWell(
            key: _keys.putIfAbsent(i, GlobalKey.new),
            borderRadius: BorderRadius.circular(ZRadius.sm),
            onTap: () => ref.read(audioHandlerProvider).seek(line.time),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AnimatedDefaultTextStyle(
                duration: ZMotion.medium,
                style: context.tt.headlineSmall!.copyWith(
                  fontSize: active ? 26 : 22,
                  height: 1.3,
                  color: active
                      ? zc.textPrimary
                      : past
                          ? zc.textSecondary.withValues(alpha: 0.55)
                          : zc.textSecondary,
                ),
                child: Text(line.text.isEmpty ? '♪' : line.text),
              ),
            ),
          );
        },
      ),
    );
  }
}
