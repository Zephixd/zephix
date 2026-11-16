import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/app_info.dart';
import 'providers.dart';
import 'router/app_router.dart';
import 'theme/zephix_theme.dart';

final routerProvider = Provider<GoRouter>((ref) => buildRouter());

class ZephixApp extends ConsumerWidget {
  const ZephixApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp.router(
      title: AppInfo.commercialName,
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: ZephixTheme.build(Brightness.light, settings.accent),
      darkTheme: ZephixTheme.build(Brightness.dark, settings.accent),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
