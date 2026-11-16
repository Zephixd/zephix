import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/zephix_colors.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/common.dart';

Future<void> showSleepTimerSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(context: context, builder: (_) => const _SleepSheet());
}

class _SleepSheet extends ConsumerStatefulWidget {
  const _SleepSheet();
  @override
  ConsumerState<_SleepSheet> createState() => _SleepSheetState();
}

class _SleepSheetState extends ConsumerState<_SleepSheet> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.read(audioHandlerProvider);
    final at = ref.watch(sleepAtProvider).value;
    final endOfTrack = ref.watch(sleepEndOfTrackProvider).value ?? false;
    final left = at?.difference(DateTime.now());

    void set(Duration d) {
      handler.setSleepTimer(d);
      Navigator.pop(context);
      showSnack(context, 'La música se detendrá en ${formatMinutes(d.inMilliseconds)}');
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Temporizador', style: context.tt.titleLarge),
          ),
          if (left != null || endOfTrack)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                endOfTrack ? 'Se detendrá al terminar la canción' : 'Se detendrá en ${formatDuration(left!.isNegative ? Duration.zero : left)}',
                style: context.tt.bodyMedium?.copyWith(color: context.zc.primary),
              ),
            ),
          for (final m in const [5, 15, 30, 45, 60, 90])
            ListTile(title: Text('$m minutos'), onTap: () => set(Duration(minutes: m))),
          ListTile(
            title: const Text('Al terminar la canción'),
            onTap: () {
              handler.setSleepAtEndOfTrack();
              Navigator.pop(context);
            },
          ),
          if (left != null || endOfTrack)
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: const Text('Desactivar temporizador'),
              onTap: () {
                handler.cancelSleepTimer();
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
