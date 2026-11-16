import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/routes.dart';
import '../../app/theme/zephix_colors.dart';
import '../../app/theme/zephix_theme.dart';
import '../../core/constants/app_info.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/zephix_logo.dart';

/// Profile without an account: everything here lives on the device.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zc = context.zc;
    final tracks = ref.watch(tracksProvider).value?.length ?? 0;
    final favs = ref.watch(favoriteIdsProvider).value?.length ?? 0;
    final playlists = ref.watch(playlistsProvider).value?.length ?? 0;
    final month = ref.watch(statsProvider(StatsRange.month)).value;
    final all = ref.watch(statsProvider(StatsRange.all)).value;
    final topArtist = all?.topArtists.firstOrNull;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: 140),
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.xl, ZSpace.page, ZSpace.lg),
              child: Row(
                children: [
                  ZephixMark(size: 64, background: zc.surfaceElevated),
                  const SizedBox(width: ZSpace.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Tu perfil', style: context.tt.headlineMedium),
                        Text('Sin cuenta · Todo se guarda en este dispositivo', style: context.tt.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZSpace.page),
            child: Row(
              children: [
                _Count(value: '$tracks', label: 'canciones'),
                _Count(value: '$favs', label: 'favoritos'),
                _Count(value: '$playlists', label: 'playlists'),
              ],
            ),
          ),
          if (month != null && !month.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.xl, ZSpace.page, 0),
              child: InkWell(
                onTap: () => context.push(Routes.stats),
                borderRadius: BorderRadius.circular(ZRadius.lg),
                child: Container(
                  padding: const EdgeInsets.all(ZSpace.xl),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(ZRadius.lg),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [zc.primary.withValues(alpha: 0.22), zc.secondary.withValues(alpha: 0.14)],
                    ),
                    border: Border.all(color: zc.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${monthName(DateTime.now().month).toUpperCase()} EN MÚSICA', style: context.tt.labelSmall),
                      const SizedBox(height: 6),
                      Text(formatMinutes(month.listenedMs), style: context.tt.displaySmall),
                      const SizedBox(height: 4),
                      Text(
                        topArtist == null
                            ? '${month.plays} reproducciones'
                            : '${month.plays} reproducciones · Tu artista: ${topArtist.label}',
                        style: context.tt.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: ZSpace.lg),
          _Link(Icons.insights_rounded, 'Estadísticas', () => context.push(Routes.stats)),
          _Link(Icons.tune_rounded, 'Ajustes', () => context.push(Routes.settings)),
          _Link(Icons.equalizer_rounded, 'Ecualizador', () => context.push(Routes.equalizer)),
          _Link(Icons.folder_rounded, 'Carpetas de música', () => context.push(Routes.folders)),
          _Link(Icons.hub_rounded, 'Fuentes musicales', () => context.push(Routes.sources)),
          _Link(Icons.shield_outlined, 'Privacidad', () => context.push(Routes.privacy)),
          _Link(Icons.info_outline_rounded, 'Acerca de ${AppInfo.commercialName}', () => context.push(Routes.about)),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: context.tt.headlineMedium),
          Text(label, style: context.tt.bodySmall),
        ],
      ),
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
}
