import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme/zephix_colors.dart';
import '../../app/theme/zephix_theme.dart';

/// Shows library scan progress or the last scan message.
class ScanBanner extends ConsumerWidget {
  const ScanBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(scanProvider);
    final zc = context.zc;
    if (!scan.running && scan.message == null) return const SizedBox.shrink();
    final done = !scan.running;
    return AnimatedSize(
      duration: ZMotion.medium,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.lg, ZSpace.page, 0),
        child: Container(
          padding: const EdgeInsets.all(ZSpace.lg),
          decoration: BoxDecoration(
            color: zc.surface,
            borderRadius: BorderRadius.circular(ZRadius.md),
            border: Border.all(color: zc.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(done ? Icons.check_circle_rounded : Icons.radar_rounded, color: zc.primary, size: 20),
                  const SizedBox(width: ZSpace.sm),
                  Expanded(
                    child: Text(
                      done ? (scan.message ?? 'Listo') : 'Analizando tu música…',
                      style: context.tt.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ZSpace.sm),
              Text(
                done
                    ? '${scan.added} actualizadas · ${scan.removed} quitadas${scan.errors > 0 ? ' · ${scan.errors} sin etiquetas legibles' : ''}'
                    : '${scan.processed} de ${scan.found} archivos',
                style: context.tt.bodySmall,
              ),
              if (!done) ...[
                const SizedBox(height: ZSpace.sm),
                LinearProgressIndicator(value: scan.fraction, minHeight: 3, borderRadius: BorderRadius.circular(2)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
