import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/router/routes.dart';
import '../../app/theme/zephix_colors.dart';
import '../../app/theme/zephix_theme.dart';
import '../../core/utils/format.dart';
import '../../shared/widgets/artwork.dart';
import '../../shared/widgets/common.dart';
import 'stats_engine.dart';

class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});
  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  StatsRange _range = StatsRange.week;

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(statsProvider(_range));
    final now = DateTime.now();
    final label = switch (_range) {
      StatsRange.week => 'Últimos 7 días',
      StatsRange.month => 'Resumen de ${monthName(now.month)}',
      StatsRange.year => 'Tu ${now.year}',
      StatsRange.all => 'Desde el principio',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Estadísticas')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZSpace.page),
            child: SegmentedButton<StatsRange>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: StatsRange.week, label: Text('Semana')),
                ButtonSegment(value: StatsRange.month, label: Text('Mes')),
                ButtonSegment(value: StatsRange.year, label: Text('Año')),
                ButtonSegment(value: StatsRange.all, label: Text('Todo')),
              ],
              selected: {_range},
              onSelectionChanged: (s) => setState(() => _range = s.first),
            ),
          ),
          Expanded(
            child: stats.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => EmptyState(icon: Icons.error_outline_rounded, title: 'Error', message: '$e'),
              data: (s) => s.isEmpty
                  ? const EmptyState(
                      icon: Icons.insights_rounded,
                      title: 'Aún no hay estadísticas',
                      message: 'Escucha música y aquí verás tus minutos, artistas y álbumes más escuchados. '
                          'Todo se calcula y guarda solo en este dispositivo.',
                    )
                  : _StatsBody(stats: s, label: label, range: _range),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.stats, required this.label, required this.range});
  final ListeningStats stats;
  final String label;
  final StatsRange range;

  @override
  Widget build(BuildContext context) {
    final zc = context.zc;
    final busiest = stats.busiestDay;
    return ListView(
      padding: const EdgeInsets.only(bottom: 140),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.xl, ZSpace.page, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: context.tt.labelSmall?.copyWith(color: zc.primary)),
              const SizedBox(height: 6),
              Text(formatMinutes(stats.listenedMs), style: context.tt.displayMedium),
              Text('de música escuchada', style: context.tt.bodyMedium?.copyWith(color: zc.textSecondary)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.xl, ZSpace.page, 0),
          child: Row(
            children: [
              _Metric(value: '${stats.plays}', label: 'reproducciones'),
              _Metric(value: '${stats.uniqueTracks}', label: 'canciones distintas'),
              _Metric(value: '${(stats.skipRate * 100).round()}%', label: 'omitidas'),
            ],
          ),
        ),
        if (stats.daily.length > 1 && stats.daily.length <= 62) ...[
          const SectionHeader('Actividad', subtitle: 'Minutos por día'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZSpace.page),
            child: SizedBox(height: 180, child: _DailyChart(days: stats.daily)),
          ),
        ] else if (stats.daily.length > 62) ...[
          const SectionHeader('Actividad', subtitle: 'Minutos por mes'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: ZSpace.page),
            child: SizedBox(height: 180, child: _DailyChart(days: _byMonth(stats.daily), monthly: true)),
          ),
        ],
        if (busiest != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(ZSpace.page, ZSpace.md, ZSpace.page, 0),
            child: Text(
              'Tu día más musical: ${weekdayShort(busiest.day)} ${busiest.day.day} de ${monthName(busiest.day.month)} '
              '(${formatMinutes(busiest.listenedMs)})',
              style: context.tt.bodySmall,
            ),
          ),
        if (stats.topArtists.isNotEmpty) ...[
          const SectionHeader('Artistas más escuchados'),
          for (final (i, a) in stats.topArtists.indexed)
            _RankTile(rank: i + 1, item: a, circle: true, onTap: () => context.push(Routes.artist(a.label))),
        ],
        if (stats.topTracks.isNotEmpty) ...[
          const SectionHeader('Canciones favoritas del periodo'),
          for (final (i, t) in stats.topTracks.indexed) _RankTile(rank: i + 1, item: t),
        ],
        if (stats.topAlbums.isNotEmpty) ...[
          const SectionHeader('Álbumes más escuchados'),
          for (final (i, a) in stats.topAlbums.indexed)
            _RankTile(rank: i + 1, item: a, onTap: () => context.push(Routes.album(a.label, a.subtitle ?? ''))),
        ],
        Padding(
          padding: const EdgeInsets.all(ZSpace.page),
          child: Text('Estas estadísticas se calculan en tu dispositivo y nunca se envían a terceros.',
              style: context.tt.bodySmall),
        ),
      ],
    );
  }

  static List<DayActivity> _byMonth(List<DayActivity> days) {
    final m = <DateTime, (int, int)>{};
    for (final d in days) {
      final k = DateTime(d.day.year, d.day.month);
      final v = m[k] ?? (0, 0);
      m[k] = (v.$1 + d.listenedMs, v.$2 + d.plays);
    }
    final keys = m.keys.toList()..sort();
    return [for (final k in keys) DayActivity(k, m[k]!.$1, m[k]!.$2)];
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final zc = context.zc;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: ZSpace.sm),
        padding: const EdgeInsets.all(ZSpace.md),
        decoration: BoxDecoration(
          color: zc.surface,
          borderRadius: BorderRadius.circular(ZRadius.md),
          border: Border.all(color: zc.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: context.tt.headlineSmall),
            Text(label, style: context.tt.bodySmall, maxLines: 2),
          ],
        ),
      ),
    );
  }
}

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.days, this.monthly = false});
  final List<DayActivity> days;
  final bool monthly;

  @override
  Widget build(BuildContext context) {
    final zc = context.zc;
    final maxMin = days.fold<double>(1, (a, d) => d.listenedMs / 60000 > a ? d.listenedMs / 60000 : a);
    final labelEvery = (days.length / 7).ceil().clamp(1, 31);
    return Semantics(
      label: 'Gráfico de minutos escuchados',
      child: BarChart(
        BarChartData(
          maxY: maxMin * 1.15,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: (maxMin / 3).clamp(1, double.infinity),
            getDrawingHorizontalLine: (_) => FlLine(color: zc.border, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= days.length || i % labelEvery != 0) return const SizedBox.shrink();
                  final d = days[i].day;
                  final text = monthly
                      ? monthName(d.month).substring(0, 3)
                      : (days.length <= 7 ? weekdayShort(d) : '${d.day}');
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(text, style: context.tt.labelSmall),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => zc.surfaceElevated,
              getTooltipItem: (g, _, rod, _) =>
                  BarTooltipItem('${rod.toY.round()} min', context.tt.labelLarge!),
            ),
          ),
          barGroups: [
            for (final (i, d) in days.indexed)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                  toY: d.listenedMs / 60000,
                  width: days.length > 20 ? 6 : 16,
                  borderRadius: BorderRadius.circular(4),
                  color: zc.primary,
                ),
              ]),
          ],
        ),
      ),
    );
  }
}

class _RankTile extends StatelessWidget {
  const _RankTile({required this.rank, required this.item, this.circle = false, this.onTap});
  final int rank;
  final RankedItem item;
  final bool circle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final zc = context.zc;
    return ListTile(
      onTap: onTap,
      leading: SizedBox(
        width: 84,
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text('$rank', style: context.tt.titleMedium?.copyWith(color: rank <= 3 ? zc.primary : zc.textSecondary)),
            ),
            SizedBox(
              width: 48,
              height: 48,
              child: Artwork(path: item.artPath, seed: item.label, size: 48, circle: circle),
            ),
          ],
        ),
      ),
      title: Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [if (item.subtitle != null) item.subtitle!, plural(item.plays, 'reproducción', 'reproducciones'), formatMinutes(item.listenedMs)]
            .join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
