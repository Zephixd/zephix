import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/player/mini_player.dart';
import '../shared/widgets/common.dart';
import 'providers.dart';
import 'theme/zephix_colors.dart';
import 'theme/zephix_theme.dart';

/// Root layout: page content, persistent mini-player and bottom navigation.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  @override
  void initState() {
    super.initState();
    // Surface playback errors (missing file, network) instead of failing silently.
    ref.read(audioHandlerProvider).errorMessages.listen((m) {
      if (mounted) showSnack(context, m);
    });
  }

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Inicio'),
    (Icons.explore_outlined, Icons.explore_rounded, 'Explorar'),
    (Icons.search_rounded, Icons.manage_search_rounded, 'Buscar'),
    (Icons.library_music_outlined, Icons.library_music_rounded, 'Biblioteca'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Perfil'),
  ];

  @override
  Widget build(BuildContext context) {
    final zc = context.zc;
    return Scaffold(
      body: widget.shell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          DecoratedBox(
            decoration: BoxDecoration(
              color: zc.background,
              border: Border(top: BorderSide(color: zc.border)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 64,
                child: Row(
                  children: [
                    for (final (i, it) in _items.indexed)
                      Expanded(
                        child: _NavItem(
                          icon: it.$1,
                          activeIcon: it.$2,
                          label: it.$3,
                          selected: widget.shell.currentIndex == i,
                          onTap: () => widget.shell.goBranch(i, initialLocation: i == widget.shell.currentIndex),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final zc = context.zc;
    final color = selected ? zc.textPrimary : zc.textSecondary;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 36,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: ZMotion.medium,
              curve: ZMotion.curve,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: selected ? zc.primary.withValues(alpha: 0.16) : Colors.transparent,
                borderRadius: BorderRadius.circular(ZRadius.pill),
              ),
              child: Icon(selected ? activeIcon : icon, color: selected ? zc.primary : color, size: 24),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: context.tt.labelMedium?.copyWith(color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
