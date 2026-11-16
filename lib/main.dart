import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'core/services/zephix_audio_handler.dart';
import 'data/database/app_database.dart';
import 'data/remote_tracks.dart';
import 'data/sources/ytm_source.dart';
import 'features/settings/app_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final db = AppDatabase();
  final prefs = await db.preferences();

  // Spotify-style tail: when a YouTube queue runs dry, feed it related tracks.
  Future<List<TrackRow>> autoplayFor(TrackRow current) async {
    final id = YtmSource.videoIdOf(current.uri);
    if (id == null) return const [];
    final related = await YtmSource.relatedTracks(id, limit: 10);
    return materializeRemote(db, related);
  }

  final handler = await AudioService.init<ZephixAudioHandler>(
    builder: () => ZephixAudioHandler(
      db,
      uriResolver: YtmSource.resolveUri,
      autoplay: autoplayFor,
    ),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.greenknow.zephix.playback',
      androidNotificationChannelName: 'Reproducción',
      androidNotificationChannelDescription: 'Controles de reproducción de Zephix',
      androidNotificationIcon: 'drawable/ic_stat_zephix',
      androidStopForegroundOnPause: true,
    ),
  );

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      audioHandlerProvider.overrideWithValue(handler),
      initialPreferencesProvider.overrideWithValue(prefs),
    ],
  );
  final settings = AppSettings.fromPrefs(prefs);
  await container.read(settingsProvider.notifier).applyToPlayer(settings);

  runApp(UncontrolledProviderScope(container: container, child: const ZephixApp()));

  if (!settings.onboarded) {
    // First launch: ask for notifications (media controls on Android 13+)
    // and scan the default music folders.
    if (Platform.isAndroid) await Permission.notification.request();
    await container.read(settingsProvider.notifier).update((s) => s.copyWith(onboarded: true));
    await container.read(scanProvider.notifier).scan();
  }
}
