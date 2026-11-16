/// Typed helpers for building route locations.
abstract final class Routes {
  static const home = '/home';
  static const explore = '/explore';
  static const search = '/search';
  static const library = '/library';
  static const profile = '/profile';
  static const player = '/player';
  static const lyrics = '/lyrics';
  static const settings = '/settings';
  static const equalizer = '/settings/equalizer';
  static const sources = '/settings/sources';
  static const privacy = '/settings/privacy';
  static const folders = '/settings/folders';
  static const about = '/settings/about';
  static const stats = '/stats';

  static String album(String title, String artist) =>
      Uri(path: '/album', queryParameters: {'title': title, 'artist': artist}).toString();
  static String artist(String name) => Uri(path: '/artist', queryParameters: {'name': name}).toString();
  static String playlist(int id) => '/playlist/$id';
  static String folder(String path) => Uri(path: '/folder', queryParameters: {'path': path}).toString();
  static String genre(String name) => Uri(path: '/genre', queryParameters: {'name': name}).toString();
  static String mix(String id) => Uri(path: '/mix', queryParameters: {'id': id}).toString();
  static String remoteItem(String id) => Uri(path: '/remote', queryParameters: {'id': id}).toString();
  static String libraryList(String kind) => Uri(path: '/list', queryParameters: {'kind': kind}).toString();
}
