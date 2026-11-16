import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../app/providers.dart';
import '../../app/theme/zephix_colors.dart';
import '../../app/theme/zephix_theme.dart';
import '../../shared/widgets/common.dart';

final _eqParamsProvider = FutureProvider.autoDispose<AndroidEqualizerParameters?>(
    (ref) => ref.watch(audioHandlerProvider).equalizerParameters());

/// Uses Android's built-in audio effect. Band count and range come from the
/// device, so this screen never invents bands that do not exist.
class EqualizerScreen extends ConsumerWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final params = ref.watch(_eqParamsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Ecualizador')),
      body: params.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const _Unavailable(),
        data: (p) {
          if (p == null || p.bands.isEmpty) return const _Unavailable();
          return ListView(
            padding: const EdgeInsets.only(bottom: 120),
            children: [
              SwitchListTile(
                title: const Text('Activar ecualizador'),
                subtitle: const Text('Efecto de audio del sistema Android'),
                value: settings.eqEnabled,
                onChanged: (v) => ref.read(settingsProvider.notifier).update((s) => s.copyWith(eqEnabled: v)),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: ZSpace.page, vertical: ZSpace.lg),
                child: SizedBox(
                  height: 260,
                  child: Row(
                    children: [
                      for (final band in p.bands)
                        Expanded(child: _Band(band: band, params: p, enabled: settings.eqEnabled)),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: ZSpace.page),
                child: OutlinedButton.icon(
                  onPressed: () async {
                    for (final b in p.bands) {
                      await b.setGain(0);
                    }
                    await ref.read(settingsProvider.notifier).update((s) => s.copyWith(eqGains: [for (final _ in p.bands) 0.0]));
                  },
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Restablecer'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Band extends ConsumerWidget {
  const _Band({required this.band, required this.params, required this.enabled});
  final AndroidEqualizerBand band;
  final AndroidEqualizerParameters params;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hz = band.centerFrequency;
    final label = hz >= 1000 ? '${(hz / 1000).toStringAsFixed(hz >= 10000 ? 0 : 1)}k' : hz.round().toString();
    return StreamBuilder<double>(
      stream: band.gainStream,
      builder: (context, snap) {
        final gain = snap.data ?? band.gain;
        return Column(
          children: [
            Text('${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(1)}', style: context.tt.labelMedium),
            Expanded(
              child: RotatedBox(
                quarterTurns: -1,
                child: Slider(
                  value: gain.clamp(params.minDecibels, params.maxDecibels),
                  min: params.minDecibels,
                  max: params.maxDecibels,
                  semanticFormatterCallback: (v) => '$label hercios, ${v.toStringAsFixed(1)} decibelios',
                  onChanged: enabled ? band.setGain : null,
                  onChangeEnd: (_) => ref.read(settingsProvider.notifier).update(
                        (s) => s.copyWith(eqGains: [for (final b in params.bands) b.gain]),
                      ),
                ),
              ),
            ),
            Text(label, style: context.tt.labelSmall?.copyWith(color: context.zc.textSecondary)),
          ],
        );
      },
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();
  @override
  Widget build(BuildContext context) => const EmptyState(
        icon: Icons.equalizer_rounded,
        title: 'Ecualizador no disponible',
        message: 'Este dispositivo no expone un ecualizador del sistema, o todavía no se cargó ninguna canción. '
            'Reproduce algo y vuelve a intentarlo.',
      );
}
