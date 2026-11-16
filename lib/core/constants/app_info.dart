/// Product constants. Kept in one place so branding is consistent.
abstract final class AppInfo {
  static const name = 'Zephix';
  static const commercialName = 'Zephix Music';
  static const developer = 'GreenKnow Systems';
  static const packageId = 'com.greenknow.zephix';
  static const version = '0.1.0';

  /// Sent to LRCLIB, MusicBrainz and the Internet Archive, which ask clients
  /// to identify themselves. Contains no user data.
  static const userAgent = 'ZephixMusic/$version ($packageId)';

  static const audioExtensions = {
    'mp3', 'flac', 'wav', 'aac', 'm4a', 'ogg', 'oga', 'opus', 'aiff', 'aif', 'mka', 'mp4',
  };
}
