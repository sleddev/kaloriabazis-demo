import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Last-7-days overview built from the cached / fetched diary days.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  bool _loading = false;

  List<DateTime> get _days {
    final today = dayOnly(DateTime.now());
    return [for (var i = 6; i >= 0; i--) today.subtract(Duration(days: i))];
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load({bool force = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    final app = AppScope.read(context);
    // Sequential on purpose: the client paces requests anyway, and this
    // fills the chart day by day.
    for (final d in _days.reversed) {
      if (!mounted) return;
      await app.loadDay(d, force: force);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final days = _days;
    final loaded = [for (final d in days) app.dayFor(d)];
    final logged = loaded
        .whereType<DiaryDay>()
        .where((d) => d.entries.isNotEmpty)
        .toList();
    final goal = app.goal.toDouble();

    final avg = logged.isEmpty
        ? 0.0
        : logged.fold(0.0, (a, d) => a + d.totals.kcal) / logged.length;
    final onTarget = logged.where((d) => d.totals.kcal <= goal).length;
    final week = logged.fold(Macros.zero, (a, d) => a + d.totals);

    // Top foods by total kcal over the week.
    final byFood = <String, ({String name, double kcal, int n, PicRef? pic})>{};
    for (final d in logged) {
      for (final e in d.entries) {
        final cur = byFood[e.objId];
        byFood[e.objId] = (
          name: e.name,
          kcal: (cur?.kcal ?? 0) + e.macros.kcal,
          n: (cur?.n ?? 0) + 1,
          pic: d.pics[e.objId] ?? cur?.pic,
        );
      }
    }
    final top = byFood.values.toList()
      ..sort((a, b) => b.kcal.compareTo(a.kcal));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: Palette.ember,
          onRefresh: () => _load(force: true),
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Az elmúlt 7 nap',
                        style: context.text.headlineMedium,
                      ),
                    ),
                    if (_loading)
                      const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 20, 16, 12),
                  child: SizedBox(
                    height: 220,
                    child: _WeekChart(days: days, loaded: loaded, goal: goal),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Tile(
                      icon: Icons.local_fire_department_rounded,
                      color: Palette.ember,
                      value: fmtKcal(avg),
                      unit: 'kcal',
                      label: 'Napi átlag',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Tile(
                      icon: Icons.track_changes_rounded,
                      color: Palette.good,
                      value: '$onTarget/${logged.length}',
                      unit: 'nap',
                      label: 'Cél alatt',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: _MacroSplit(week),
                ),
              ),
              if (top.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                          child: Text(
                            'Legtöbb kalória innen jött',
                            style: context.text.titleMedium,
                          ),
                        ),
                        for (final (i, f) in top.take(5).indexed)
                          ListTile(
                            leading: FoodAvatar(
                              name: f.name,
                              url: f.pic?.icon,
                              size: 40,
                            ),
                            title: Text(
                              f.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text('${f.n}× a héten'),
                            trailing: Text(
                              '${fmtKcal(f.kcal)} kcal',
                              style: numberStyle(
                                15,
                                color: i == 0 ? Palette.ember : null,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({
    required this.days,
    required this.loaded,
    required this.goal,
  });
  final List<DateTime> days;
  final List<DiaryDay?> loaded;
  final double goal;

  @override
  Widget build(BuildContext context) {
    final maxKcal = loaded.fold<double>(goal, (m, d) {
      final k = d?.totals.kcal ?? 0;
      return k > m ? k : m;
    });
    final muted = context.surfaces.muted;
    return BarChart(
      BarChartData(
        maxY: maxKcal * 1.15,
        alignment: BarChartAlignment.spaceAround,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Palette.inkCard,
            getTooltipItem: (g, _, rod, _) => BarTooltipItem(
              '${fmtKcal(rod.toY)} kcal',
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            HorizontalLine(
              y: goal,
              color: muted.withValues(alpha: 0.6),
              strokeWidth: 1.5,
              dashArray: [6, 5],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topRight,
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                labelResolver: (_) => 'cél ${goal.round()}',
              ),
            ),
          ],
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          topTitles: const AxisTitles(),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, _) {
                final d = days[v.toInt()];
                final isToday = d == dayOnly(DateTime.now());
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    isToday ? 'ma' : DateFormat('E', 'hu').format(d),
                    style: TextStyle(
                      color: isToday ? Palette.ember : muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < days.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: loaded[i]?.totals.kcal ?? 0,
                  width: 22,
                  borderRadius: BorderRadius.circular(8),
                  gradient: (loaded[i]?.totals.kcal ?? 0) > goal
                      ? const LinearGradient(
                          colors: [Palette.over, Color(0xFFFF7A7E)],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        )
                      : const LinearGradient(
                          colors: [Palette.ember, Palette.carbs],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                  backDrawRodData: BackgroundBarChartRodData(
                    show: true,
                    toY: maxKcal * 1.15,
                    color: context.surfaces.track,
                  ),
                ),
              ],
            ),
        ],
      ),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.color,
    required this.value,
    required this.unit,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String unit;
  final String label;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(value, style: numberStyle(28)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  unit,
                  style: TextStyle(
                    color: context.surfaces.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: context.surfaces.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MacroSplit extends StatelessWidget {
  const _MacroSplit(this.m);
  final Macros m;

  @override
  Widget build(BuildContext context) {
    final p = m.protein * 4, c = m.carbs * 4, f = m.fat * 9;
    final total = p + c + f;
    String pct(double v) => total <= 0 ? '–' : '${(v / total * 100).round()}%';

    final sections = total <= 0
        ? [
            PieChartSectionData(
              value: 1,
              color: context.surfaces.track,
              radius: 18,
              showTitle: false,
            ),
          ]
        : [
            PieChartSectionData(
              value: p,
              color: Palette.protein,
              radius: 18,
              showTitle: false,
            ),
            PieChartSectionData(
              value: c,
              color: Palette.carbs,
              radius: 18,
              showTitle: false,
            ),
            PieChartSectionData(
              value: f,
              color: Palette.fat,
              radius: 18,
              showTitle: false,
            ),
          ];

    Widget row(String label, Color color, double grams, double kcal) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          MacroDot(color, label),
          const Spacer(),
          Text(
            '${fmtG(grams)} g',
            style: TextStyle(color: context.surfaces.muted, fontSize: 13),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 42,
            child: Text(
              pct(kcal),
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Makrók aránya', style: context.text.titleMedium),
        const SizedBox(height: 16),
        Row(
          children: [
            SizedBox.square(
              dimension: 110,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 34,
                  sectionsSpace: 3,
                  startDegreeOffset: -90,
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                children: [
                  row('Fehérje', Palette.protein, m.protein, p),
                  row('Szénhidrát', Palette.carbs, m.carbs, c),
                  row('Zsír', Palette.fat, m.fat, f),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
