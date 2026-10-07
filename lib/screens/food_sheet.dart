import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/kb_client.dart';
import '../api/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// What the sheet is opened for: a new food, or an existing diary entry.
class FoodSheetArgs {
  FoodSheetArgs({
    required this.foodRef,
    required this.name,
    required this.meal,
    this.subtitle,
    this.pic,
    this.unitId,
    this.quantity,
    this.entry,
  });

  final String foodRef;
  final String name;
  final String? subtitle;
  final PicRef? pic;
  final Meal meal;
  final int? unitId;
  final double? quantity;

  /// Non-null in edit mode.
  final DiaryEntry? entry;
}

/// Opens the sheet. Resolves to a short message for a snackbar, or null.
Future<String?> showFoodSheet(BuildContext context, FoodSheetArgs args) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FoodSheet(args),
    );

class _FoodSheet extends StatefulWidget {
  const _FoodSheet(this.args);
  final FoodSheetArgs args;

  @override
  State<_FoodSheet> createState() => _FoodSheetState();
}

class _FoodSheetState extends State<_FoodSheet> {
  FoodInfo? info;
  String? error;
  FoodUnit? unit;
  late Meal meal = widget.args.meal;
  final qtyCtl = TextEditingController();
  bool busy = false;

  /// Server-side value for units without a gram weight.
  Macros? serverMacros;
  Timer? _calcDebounce;

  bool get editing => widget.args.entry != null;

  double get qty => double.tryParse(qtyCtl.text.replaceAll(',', '.')) ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
    qtyCtl.addListener(_onQtyChanged);
  }

  @override
  void dispose() {
    _calcDebounce?.cancel();
    qtyCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => error = null);
    try {
      final app = AppScope.read(context);
      final i = await app.guard(() => app.kb.foodInfo(widget.args.foodRef));
      if (!mounted) return;
      FoodUnit? u;
      if (widget.args.unitId != null) {
        u = i.units.where((x) => x.id == widget.args.unitId).firstOrNull;
      }
      // Default: grams if available, otherwise the first unit.
      u ??=
          i.units.where((x) => x.grams == 1).firstOrNull ?? i.units.firstOrNull;
      setState(() {
        info = i;
        unit = u;
        qtyCtl.text = _fmt(widget.args.quantity ?? _defaultQty(u));
      });
    } on KbException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  double _defaultQty(FoodUnit? u) {
    if (u == null) return 1;
    if (u.grams == 1) return 100;
    if (u.grams == 10) return 10;
    if (u.grams == 1000) return 0.1;
    return 1;
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  void _onQtyChanged() {
    setState(() {});
    if (unit != null && unit!.grams <= 0) {
      _calcDebounce?.cancel();
      _calcDebounce = Timer(const Duration(milliseconds: 700), _serverCalc);
    }
  }

  Future<void> _serverCalc() async {
    final u = unit;
    if (u == null || qty <= 0) return;
    try {
      final m = await AppScope.read(context).kb
          .calcFood(widget.args.foodRef, u.id, qty);
      if (mounted) setState(() => serverMacros = m);
    } catch (_) {}
  }

  Macros get macros {
    final i = info, u = unit;
    if (i == null || u == null) return Macros.zero;
    if (u.grams <= 0) return serverMacros ?? Macros.zero;
    return i.macrosFor(u, qty);
  }

  void _setUnit(FoodUnit u) {
    HapticFeedback.selectionClick();
    final old = unit;
    setState(() {
      unit = u;
      serverMacros = null;
      // Keep the amount roughly the same when switching between mass units.
      if (old != null &&
          old.grams > 0 &&
          u.grams > 0 &&
          old.isMass &&
          u.isMass) {
        final g = old.grams * qty;
        final q = g / u.grams;
        qtyCtl.text = _fmt(double.parse(q.toStringAsFixed(q < 1 ? 2 : 1)));
      } else {
        qtyCtl.text = _fmt(_defaultQty(u));
      }
    });
    if (u.grams <= 0) _serverCalc();
  }

  void _step(int dir) {
    HapticFeedback.lightImpact();
    final u = unit;
    final step = u == null
        ? 1.0
        : u.grams == 1
        ? 10.0
        : u.grams == 1000
        ? 0.1
        : u.grams == 10
        ? 1.0
        : 0.5;
    final v = (qty + dir * step).clamp(0, 100000).toDouble();
    qtyCtl.text = _fmt(double.parse(v.toStringAsFixed(2)));
  }

  Future<void> _submit() async {
    final u = unit;
    if (u == null || qty <= 0) return;
    setState(() => busy = true);
    final app = AppScope.read(context);
    try {
      if (editing) {
        await app.editEntry(
          widget.args.entry!,
          foodId: info!.foodId,
          unitId: u.id,
          quantity: qty,
          meal: meal,
        );
        if (mounted) Navigator.pop(context, 'Mentve');
      } else {
        await app.addFood(
          foodRef: widget.args.foodRef,
          unitId: u.id,
          quantity: qty,
          meal: meal,
        );
        HapticFeedback.mediumImpact();
        if (mounted) {
          Navigator.pop(
            context,
            '${widget.args.name} → ${meal.label} · ${fmtKcal(macros.kcal)} kcal',
          );
        }
      }
    } on KbException catch (e) {
      if (mounted) {
        setState(() => busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _delete() async {
    setState(() => busy = true);
    try {
      await AppScope.read(context).deleteEntry(widget.args.entry!);
      if (mounted) Navigator.pop(context, 'Törölve');
    } on KbException catch (e) {
      if (mounted) {
        setState(() => busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.args;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                FoodAvatar(
                  name: a.name,
                  url: a.pic?.big,
                  fallbackUrl: a.pic?.icon,
                  size: 76,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.name,
                        style: context.text.titleLarge,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (a.subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          a.subtitle!,
                          style: TextStyle(color: context.surfaces.muted),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            if (error != null)
              ErrorPanel(message: error!, onRetry: _load)
            else if (info == null)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _summary(context),
              const SizedBox(height: 22),
              _label(context, 'Mennyiség'),
              _quantityRow(context),
              const SizedBox(height: 14),
              _unitChips(context),
              const SizedBox(height: 20),
              _label(context, 'Étkezés'),
              _mealChips(context),
              const SizedBox(height: 26),
              Row(
                children: [
                  if (editing) ...[
                    SizedBox(
                      height: 56,
                      width: 56,
                      child: IconButton.filledTonal(
                        onPressed: busy ? null : _delete,
                        icon: const Icon(Icons.delete_outline_rounded),
                        style: IconButton.styleFrom(
                          foregroundColor: Palette.over,
                          backgroundColor: Palette.over.withValues(alpha: 0.12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: busy || qty <= 0 ? null : _submit,
                      child: busy
                          ? const SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              editing
                                  ? 'Mentés'
                                  : 'Hozzáadás · ${fmtKcal(macros.kcal)} kcal',
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String t) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      t,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        color: context.surfaces.muted,
        fontSize: 13,
        letterSpacing: 0.3,
      ),
    ),
  );

  Widget _summary(BuildContext context) {
    final m = macros;
    final total = m.protein * 4 + m.carbs * 4 + m.fat * 9;
    Widget seg(double v, Color c) => Expanded(
      flex: total <= 0 ? 1 : (v * 1000 / total).round().clamp(1, 1000000),
      child: Container(height: 8, color: c),
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.surfaces.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(end: m.kcal),
                duration: const Duration(milliseconds: 350),
                builder: (_, v, _) => Text(
                  fmtKcal(v),
                  style: numberStyle(44, color: Palette.ember),
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  'kcal',
                  style: TextStyle(
                    color: context.surfaces.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              if (unit != null && unit!.grams > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    '${fmtG(unit!.grams * qty)} g',
                    style: TextStyle(
                      color: context.surfaces.muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Row(
              children: [
                seg(m.protein * 4, Palette.protein),
                const SizedBox(width: 3),
                seg(m.carbs * 4, Palette.carbs),
                const SizedBox(width: 3),
                seg(m.fat * 9, Palette.fat),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _macroCell('Fehérje', m.protein, Palette.protein),
              _macroCell('Szénhidrát', m.carbs, Palette.carbs),
              _macroCell('Zsír', m.fat, Palette.fat),
            ],
          ),
        ],
      ),
    );
  }

  Widget _macroCell(String label, double v, Color c) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MacroDot(c, label),
      const SizedBox(height: 2),
      Text(
        '${fmtG(v)} g',
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
    ],
  );

  Widget _quantityRow(BuildContext context) {
    Widget stepBtn(IconData icon, int dir) => SizedBox(
      width: 56,
      height: 56,
      child: IconButton.filledTonal(
        onPressed: () => _step(dir),
        icon: Icon(icon),
        style: IconButton.styleFrom(
          backgroundColor: context.colors.surfaceContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
    return Row(
      children: [
        stepBtn(Icons.remove_rounded, -1),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: qtyCtl,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: numberStyle(26),
            decoration: InputDecoration(
              suffixText: unit?.label,
              suffixStyle: TextStyle(
                color: context.surfaces.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        stepBtn(Icons.add_rounded, 1),
      ],
    );
  }

  Widget _unitChips(BuildContext context) {
    final units = info!.units;
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: units.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final u = units[i];
          final sel = u.id == unit?.id;
          final extra = u.grams > 0 && !u.isMass ? ' · ${fmtG(u.grams)} g' : '';
          return ChoiceChip(
            label: Text('${u.label}$extra'),
            selected: sel,
            onSelected: (_) => _setUnit(u),
          );
        },
      ),
    );
  }

  Widget _mealChips(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final m in Meal.values)
        ChoiceChip(
          label: Text('${m.emoji}  ${m.label}'),
          selected: meal == m,
          onSelected: (_) {
            HapticFeedback.selectionClick();
            setState(() => meal = m);
          },
        ),
    ],
  );
}
