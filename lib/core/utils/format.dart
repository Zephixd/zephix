String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

String formatMs(int ms) => formatDuration(Duration(milliseconds: ms));

String formatMinutes(int ms) {
  final minutes = (ms / 60000).round();
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m min';
}

String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

String greetingFor(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 12) return 'Buenos días';
  if (h >= 12 && h < 20) return 'Buenas tardes';
  return 'Buenas noches';
}

const _weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const _months = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

String weekdayShort(DateTime d) => _weekdays[d.weekday - 1];
String monthName(int month) => _months[month - 1];

DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
