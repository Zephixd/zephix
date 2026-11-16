import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/theme/zephix_colors.dart';

enum StreamQuality { standard, lossless }

/// User preferences, persisted in the `user_preferences` table.
@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.accent = AccentChoice.mint,
    this.onlineLyrics = true,
    this.openCatalogs = true,
    this.streamQuality = StreamQuality.standard,
    this.skipSilence = false,
    this.eqEnabled = false,
    this.eqGains = const [],
    this.minTrackSeconds = 20,
    this.showStatsOnHome = true,
    this.historyEnabled = true,
    this.onboarded = false,
  });

  final ThemeMode themeMode;
  final AccentChoice accent;

  /// Fetch lyrics from LRCLIB when a track has none embedded.
  final bool onlineLyrics;

  /// Show the online source (YouTube Music) in Explore and Search.
  final bool openCatalogs;
  final StreamQuality streamQuality;
  final bool skipSilence;
  final bool eqEnabled;
  final List<double> eqGains;

  /// Files shorter than this are ignored by the scanner (ringtones, notifications).
  final int minTrackSeconds;
  final bool showStatsOnHome;

  /// When false, no listening history is recorded.
  final bool historyEnabled;
  final bool onboarded;

  static AppSettings fromPrefs(Map<String, String> p) {
    bool b(String k, bool d) => p[k] == null ? d : p[k] == 'true';
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere((m) => m.name == p['themeMode'], orElse: () => ThemeMode.dark),
      accent: AccentChoice.fromName(p['accent']),
      onlineLyrics: b('onlineLyrics', true),
      openCatalogs: b('openCatalogs', true),
      streamQuality: StreamQuality.values
          .firstWhere((q) => q.name == p['streamQuality'], orElse: () => StreamQuality.standard),
      skipSilence: b('skipSilence', false),
      eqEnabled: b('eqEnabled', false),
      eqGains: p['eqGains'] == null
          ? const []
          : (jsonDecode(p['eqGains']!) as List).map((e) => (e as num).toDouble()).toList(),
      minTrackSeconds: int.tryParse(p['minTrackSeconds'] ?? '') ?? 20,
      showStatsOnHome: b('showStatsOnHome', true),
      historyEnabled: b('historyEnabled', true),
      onboarded: b('onboarded', false),
    );
  }

  Map<String, String> toPrefs() => {
        'themeMode': themeMode.name,
        'accent': accent.name,
        'onlineLyrics': '$onlineLyrics',
        'openCatalogs': '$openCatalogs',
        'streamQuality': streamQuality.name,
        'skipSilence': '$skipSilence',
        'eqEnabled': '$eqEnabled',
        'eqGains': jsonEncode(eqGains),
        'minTrackSeconds': '$minTrackSeconds',
        'showStatsOnHome': '$showStatsOnHome',
        'historyEnabled': '$historyEnabled',
        'onboarded': '$onboarded',
      };

  AppSettings copyWith({
    ThemeMode? themeMode,
    AccentChoice? accent,
    bool? onlineLyrics,
    bool? openCatalogs,
    StreamQuality? streamQuality,
    bool? skipSilence,
    bool? eqEnabled,
    List<double>? eqGains,
    int? minTrackSeconds,
    bool? showStatsOnHome,
    bool? historyEnabled,
    bool? onboarded,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        accent: accent ?? this.accent,
        onlineLyrics: onlineLyrics ?? this.onlineLyrics,
        openCatalogs: openCatalogs ?? this.openCatalogs,
        streamQuality: streamQuality ?? this.streamQuality,
        skipSilence: skipSilence ?? this.skipSilence,
        eqEnabled: eqEnabled ?? this.eqEnabled,
        eqGains: eqGains ?? this.eqGains,
        minTrackSeconds: minTrackSeconds ?? this.minTrackSeconds,
        showStatsOnHome: showStatsOnHome ?? this.showStatsOnHome,
        historyEnabled: historyEnabled ?? this.historyEnabled,
        onboarded: onboarded ?? this.onboarded,
      );
}
