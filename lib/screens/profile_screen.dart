import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/kb_client.dart';
import '../state/app_state.dart';
import '../theme.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _editGoal(BuildContext context, AppState app) async {
    final v = await showModalBottomSheet<int>(
      context: context,
      builder: (_) => _GoalSheet(initial: app.goal),
    );
    if (v == null || !context.mounted) return;
    try {
      await app.setGoal(v);
      if (context.mounted) _snack(context, 'Napi cél: $v kcal');
    } on KbException catch (e) {
      if (context.mounted) _snack(context, e.message);
    }
  }

  Future<void> _editWeight(BuildContext context, AppState app) async {
    final ctl = TextEditingController(
      text: app.weight == null ? '' : app.weight!.toStringAsFixed(1),
    );
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mai testsúly'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          style: numberStyle(28),
          decoration: const InputDecoration(suffixText: 'kg'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Mégse'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: () => Navigator.pop(
              ctx,
              double.tryParse(ctl.text.replaceAll(',', '.')),
            ),
            child: const Text('Mentés'),
          ),
        ],
      ),
    );
    if (v == null || v < 20 || v > 400 || !context.mounted) return;
    try {
      await app.setWeight(v);
      if (context.mounted)
        _snack(context, 'Testsúly rögzítve: ${v.toStringAsFixed(1)} kg');
    } on KbException catch (e) {
      if (context.mounted) _snack(context, e.message);
    }
  }

  void _snack(BuildContext context, String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final initial = app.nick.isEmpty
        ? '?'
        : app.nick.characters.first.toUpperCase();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 24, 16, 32),
          children: [
            Center(
              child: Container(
                width: 92,
                height: 92,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [Palette.carbs, Palette.ember, Color(0xFFFF2E63)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Text(
                  initial,
                  style: numberStyle(40, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Center(child: Text(app.nick, style: context.text.headlineMedium)),
            Center(
              child: Text(
                'kaloriabazis.hu fiók',
                style: TextStyle(color: context.surfaces.muted),
              ),
            ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: _BigTile(
                    icon: Icons.flag_rounded,
                    color: Palette.ember,
                    label: 'Napi cél',
                    value: '${app.goal}',
                    unit: 'kcal',
                    onTap: () => _editGoal(context, app),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _BigTile(
                    icon: Icons.monitor_weight_rounded,
                    color: Palette.protein,
                    label: 'Testsúly',
                    value: app.weight == null
                        ? '–'
                        : app.weight!.toStringAsFixed(1),
                    unit: 'kg',
                    onTap: () => _editWeight(context, app),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Megjelenés', style: context.text.titleMedium),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text('Rendszer'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('Világos'),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('Sötét'),
                          ),
                        ],
                        selected: {app.themeMode},
                        onSelectionChanged: (s) => app.setThemeMode(s.first),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 6,
                ),
                leading: const Icon(Icons.logout_rounded, color: Palette.over),
                title: const Text(
                  'Kijelentkezés',
                  style: TextStyle(
                    color: Palette.over,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onTap: () => app.logout(),
              ),
            ),
            const SizedBox(height: 28),
            Center(
              child: Text(
                'Nem hivatalos kliens.\nAz adatok a kaloriabazis.hu-ról jönnek.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.surfaces.muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BigTile extends StatelessWidget {
  const _BigTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.unit,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                const Spacer(),
                Icon(
                  Icons.edit_rounded,
                  size: 18,
                  color: context.surfaces.muted,
                ),
              ],
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
    ),
  );
}

class _GoalSheet extends StatefulWidget {
  const _GoalSheet({required this.initial});
  final int initial;

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  late double v = widget.initial.clamp(1000, 5000).toDouble();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Napi kalóriacél', style: context.text.titleLarge),
        const SizedBox(height: 4),
        Text(
          'A kaloriabazis.hu fiókodba is mentjük.',
          style: TextStyle(color: context.surfaces.muted),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${v.round()}', style: numberStyle(56, color: Palette.ember)),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'kcal',
                style: TextStyle(
                  color: context.surfaces.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: v,
          min: 1000,
          max: 5000,
          divisions: 80,
          activeColor: Palette.ember,
          onChanged: (x) {
            if (x.round() != v.round()) HapticFeedback.selectionClick();
            setState(() => v = x);
          },
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => Navigator.pop(context, v.round()),
          child: const Text('Mentés'),
        ),
      ],
    ),
  );
}
