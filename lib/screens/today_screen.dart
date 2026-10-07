import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../api/kb_client.dart';
import '../api/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'add_food_screen.dart';
import 'food_sheet.dart';

String dayTitle(DateTime d) {
  final today = dayOnly(DateTime.now());
  final diff = dayOnly(d).difference(today).inDays;
  if (diff == 0) return 'Ma';
  if (diff == -1) return 'Tegnap';
  if (diff == 1) return 'Holnap';
  return DateFormat('MMM d., EEEE', 'hu').format(d);
}

void showSnack(BuildContext context, String msg, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(msg), action: action, persist: false),
    );
}

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  Future<void> _openAdd(BuildContext context, Meal meal) async {
    final msg = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => AddFoodScreen(initialMeal: meal)),
    );
    if (msg != null && context.mounted) showSnack(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final day = app.today;
    final loading = app.isLoading(app.selectedDate);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAdd(context, Meal.forTime(DateTime.now())),
        backgroundColor: Palette.ember,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Étel',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: Palette.ember,
          onRefresh: () => app.loadDay(app.selectedDate, force: true),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _Header(app: app)),
              SliverToBoxAdapter(child: _WeekStrip(app: app)),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: _HeroCard(
                    totals: day?.totals ?? Macros.zero,
                    goal: app.goal.toDouble(),
                    loading: loading && day == null,
                  ),
                ),
              ),
              if (app.dayError != null && day == null)
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverToBoxAdapter(
                    child: ErrorPanel(
                      message: app.dayError!,
                      onRetry: () => app.loadDay(app.selectedDate, force: true),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                sliver: SliverList.separated(
                  itemCount: Meal.values.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final meal = Meal.values[i];
                    return _MealCard(
                      meal: meal,
                      day: day,
                      onAdd: () => _openAdd(context, meal),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final h = DateTime.now().hour;
    final greet = h < 10
        ? 'Jó reggelt'
        : h < 18
        ? 'Szia'
        : 'Jó estét';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$greet${app.nick.isEmpty ? '' : ', ${app.nick}'} 👋',
                  style: TextStyle(
                    color: context.surfaces.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    dayTitle(app.selectedDate),
                    key: ValueKey(app.selectedDate),
                    style: context.text.headlineMedium,
                  ),
                ),
              ],
            ),
          ),
          if (dayOnly(DateTime.now()) != app.selectedDate)
            TextButton(
              onPressed: () => app.selectDate(DateTime.now()),
              child: const Text('Ma'),
            ),
          IconButton(
            tooltip: 'Dátum választása',
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: app.selectedDate,
                firstDate: DateTime(2010),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (d != null) app.selectDate(d);
            },
          ),
        ],
      ),
    );
  }
}

/// Mon–Sun strip of the selected week with a tiny progress ring per day.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final sel = app.selectedDate;
    final monday = sel.subtract(Duration(days: sel.weekday - 1));
    final today = dayOnly(DateTime.now());
    final names = ['H', 'K', 'Sze', 'Cs', 'P', 'Szo', 'V'];

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() < 200) return;
        app.selectDate(sel.add(Duration(days: v < 0 ? 7 : -7)));
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: _DayPill(
                  date: monday.add(Duration(days: i)),
                  label: names[i],
                  selected: monday.add(Duration(days: i)) == sel,
                  isToday: monday.add(Duration(days: i)) == today,
                  kcal: app.dayFor(monday.add(Duration(days: i)))?.totals.kcal,
                  goal: app.goal.toDouble(),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    app.selectDate(monday.add(Duration(days: i)));
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayPill extends StatelessWidget {
  const _DayPill({
    required this.date,
    required this.label,
    required this.selected,
    required this.isToday,
    required this.kcal,
    required this.goal,
    required this.onTap,
  });

  final DateTime date;
  final String label;
  final bool selected;
  final bool isToday;
  final double? kcal;
  final double goal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.onSurface;
    final fg = selected ? context.colors.surface : ink;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? ink : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? fg.withValues(alpha: 0.7)
                    : context.surfaces.muted,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox.square(
              dimension: 30,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (kcal != null && kcal! > 0)
                    CalorieRing(
                      eaten: kcal!,
                      goal: goal,
                      size: 30,
                      stroke: 3,
                      track: selected ? Colors.white24 : context.surfaces.track,
                    ),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: isToday && !selected ? Palette.ember : fg,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.totals,
    required this.goal,
    required this.loading,
  });
  final Macros totals;
  final double goal;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final left = goal - totals.kcal;
    final over = left < 0;
    // Macro targets from the goal: 25% protein, 50% carbs, 25% fat (by kcal).
    final pT = goal * 0.25 / 4, cT = goal * 0.5 / 4, fT = goal * 0.25 / 9;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Palette.inkCard2, Palette.inkCard],
        ),
        boxShadow: [
          BoxShadow(
            color: Palette.ember.withValues(alpha: 0.18),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CalorieRing(
                eaten: totals.kcal,
                goal: goal,
                size: 150,
                stroke: 14,
                child: loading
                    ? const CircularProgressIndicator(color: Colors.white54)
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TweenAnimationBuilder<double>(
                            tween: Tween(end: left.abs()),
                            duration: const Duration(milliseconds: 900),
                            curve: Curves.easeOutCubic,
                            builder: (_, v, _) => Text(
                              fmtKcal(v),
                              style: numberStyle(34, color: Colors.white),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            over ? 'kcal felett' : 'kcal maradt',
                            style: TextStyle(
                              color: over
                                  ? const Color(0xFFFF8A8A)
                                  : Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _stat(
                      'Bevitt',
                      totals.kcal,
                      Icons.restaurant_rounded,
                      Palette.ember,
                    ),
                    const SizedBox(height: 16),
                    _stat('Napi cél', goal, Icons.flag_rounded, Colors.white70),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: MacroBar(
                  label: 'Fehérje',
                  value: totals.protein,
                  target: pT,
                  color: Palette.protein,
                  onDark: true,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: MacroBar(
                  label: 'Szénhidrát',
                  value: totals.carbs,
                  target: cT,
                  color: Palette.carbs,
                  onDark: true,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: MacroBar(
                  label: 'Zsír',
                  value: totals.fat,
                  target: fT,
                  color: Palette.fat,
                  onDark: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, double v, IconData icon, Color c) => Row(
    children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: c, size: 19),
      ),
      const SizedBox(width: 10),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${fmtKcal(v)} kcal',
            style: numberStyle(18, color: Colors.white),
          ),
        ],
      ),
    ],
  );
}

class _MealCard extends StatelessWidget {
  const _MealCard({required this.meal, required this.day, required this.onAdd});
  final Meal meal;
  final DiaryDay? day;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final entries = day?.forMeal(meal) ?? const <DiaryEntry>[];
    final total = day?.totalFor(meal) ?? Macros.zero;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: onAdd,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      meal.emoji,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(meal.label, style: context.text.titleMedium),
                        Text(
                          entries.isEmpty
                              ? 'Még semmi'
                              : '${entries.length} tétel · ${fmtKcal(total.kcal)} kcal',
                          style: TextStyle(
                            color: context.surfaces.muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '${meal.label} hozzáadása',
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_circle_rounded),
                    color: Palette.ember,
                    iconSize: 30,
                  ),
                ],
              ),
            ),
          ),
          for (final e in entries) ...[
            const Divider(indent: 16, endIndent: 16),
            _EntryTile(entry: e, pic: day!.pics[e.objId]),
          ],
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, this.pic});
  final DiaryEntry entry;
  final PicRef? pic;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    return Dismissible(
      key: ValueKey('entry-${entry.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Palette.over,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      onDismissed: (_) async {
        HapticFeedback.mediumImpact();
        final messenger = ScaffoldMessenger.of(context);
        try {
          await app.deleteEntry(entry);
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text('${entry.name} törölve'),
                persist: false,
                action: SnackBarAction(
                  label: 'Visszavonás',
                  onPressed: () => app.addFood(
                    foodRef: entry.foodRef,
                    unitId: entry.unitId,
                    quantity: entry.quantity,
                    meal: entry.meal,
                  ),
                ),
              ),
            );
        } on KbException catch (err) {
          messenger.showSnackBar(SnackBar(content: Text(err.message)));
        }
      },
      child: InkWell(
        onTap: () async {
          final msg = await showFoodSheet(
            context,
            FoodSheetArgs(
              foodRef: entry.foodRef,
              name: entry.name,
              subtitle: entry.unitText,
              pic: pic,
              meal: entry.meal,
              unitId: entry.unitId,
              quantity: entry.quantity,
              entry: entry,
            ),
          );
          if (msg != null && context.mounted) showSnack(context, msg);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              FoodAvatar(name: entry.name, url: pic?.icon, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.unitText,
                      style: TextStyle(
                        color: context.surfaces.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                fmtKcal(entry.macros.kcal),
                style: numberStyle(16, weight: FontWeight.w700),
              ),
              Text(
                ' kcal',
                style: TextStyle(color: context.surfaces.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
