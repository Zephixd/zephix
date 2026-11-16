import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/sources/music_source_provider.dart';
import '../../features/albums/collection_screens.dart';
import '../../features/explore/remote_item_screen.dart';
import '../../features/explore/explore_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/library/library_screen.dart';
import '../../features/player/equalizer_screen.dart';
import '../../features/player/now_playing_screen.dart';
import '../../features/playlists/playlist_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/search/search_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/statistics/statistics_screen.dart';
import '../shell.dart';
import 'routes.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Slide-up page used for the full player and lyrics.
Page<void> _modalPage(GoRouterState state, Widget child) => CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 360),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      transitionsBuilder: (context, a, _, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero)
            .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
        child: child,
      ),
    );

/// Detail routes are pushed inside the current tab so the mini-player and
/// bottom navigation stay visible.
List<RouteBase> _detailRoutes() => [
      GoRoute(
        path: 'album',
        builder: (_, s) => AlbumScreen(
          title: s.uri.queryParameters['title'] ?? '',
          artist: s.uri.queryParameters['artist'] ?? '',
        ),
      ),
      GoRoute(path: 'artist', builder: (_, s) => ArtistScreen(name: s.uri.queryParameters['name'] ?? '')),
      GoRoute(path: 'playlist/:id', builder: (_, s) => PlaylistScreen(id: int.parse(s.pathParameters['id']!))),
      GoRoute(path: 'folder', builder: (_, s) => FolderScreen(path: s.uri.queryParameters['path'] ?? '')),
      GoRoute(path: 'genre', builder: (_, s) => GenreScreen(name: s.uri.queryParameters['name'] ?? '')),
      GoRoute(path: 'mix', builder: (_, s) => MixScreen(id: s.uri.queryParameters['id'] ?? '')),
      GoRoute(path: 'list', builder: (_, s) => LibraryListScreen(kind: s.uri.queryParameters['kind'] ?? '')),
      GoRoute(
        path: 'remote',
        builder: (_, s) {
          final id = s.uri.queryParameters['id'] ?? '';
          final c = s.extra is RemoteCollection
              ? s.extra! as RemoteCollection
              : RemoteCollection(
                  sourceId: 'ytm',
                  externalId: id,
                  title: id,
                  creator: '',
                );
          return RemoteItemScreen(collection: c);
        },
      ),
    ];

GoRouter buildRouter() {
  // Every tab gets its own copy of the detail routes, e.g. /home/album.
  // The top-level redirect maps absolute detail locations (/album?...) onto
  // the active tab so `context.push(Routes.album(...))` works everywhere.
  const detailPrefixes = ['/album', '/artist', '/playlist', '/folder', '/genre', '/mix', '/list', '/remote'];
  final tabs = [Routes.home, Routes.explore, Routes.search, Routes.library, Routes.profile];

  late final GoRouter router;
  router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.home,
    redirect: (context, state) {
      final path = state.uri.path;
      if (detailPrefixes.any((p) => path == p || path.startsWith('$p/'))) {
        final config = router.routerDelegate.currentConfiguration;
        final current = config.isEmpty ? Routes.home : config.uri.path;
        final tab = tabs.firstWhere((t) => current.startsWith(t), orElse: () => Routes.home);
        return '$tab${state.uri}';
      }
      return null;
    },
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen(), routes: _detailRoutes()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.explore, builder: (_, _) => const ExploreScreen(), routes: _detailRoutes()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.search, builder: (_, _) => const SearchScreen(), routes: _detailRoutes()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.library, builder: (_, _) => const LibraryScreen(), routes: _detailRoutes()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen(), routes: _detailRoutes()),
          ]),
        ],
      ),
      GoRoute(
        path: Routes.player,
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, s) => _modalPage(s, const NowPlayingScreen()),
      ),
      GoRoute(
        path: Routes.lyrics,
        parentNavigatorKey: _rootKey,
        pageBuilder: (_, s) => _modalPage(s, const LyricsScreen()),
      ),
      GoRoute(path: Routes.stats, parentNavigatorKey: _rootKey, builder: (_, _) => const StatisticsScreen()),
      GoRoute(
        path: Routes.settings,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const SettingsScreen(),
        routes: [
          GoRoute(path: 'equalizer', builder: (_, _) => const EqualizerScreen()),
          GoRoute(path: 'sources', builder: (_, _) => const SourcesScreen()),
          GoRoute(path: 'privacy', builder: (_, _) => const PrivacyScreen()),
          GoRoute(path: 'folders', builder: (_, _) => const FoldersScreen()),
          GoRoute(path: 'about', builder: (_, _) => const AboutScreen()),
        ],
      ),
    ],
  );
  return router;
}
