import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/kb_client.dart';
import '../api/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'food_sheet.dart';

class AddFoodScreen extends StatefulWidget {
  const AddFoodScreen({super.key, required this.initialMeal});
  final Meal initialMeal;

  @override
  State<AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends State<AddFoodScreen> {
  late Meal meal = widget.initialMeal;
  final _q = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  String _query = '';
  List<FoodHit> _hits = [];
  int _total = 0;
  int _page = 0;
  bool _busy = false;
  String? _error;

  /// Bumped per new query so stale responses are dropped.
  int _gen = 0;

  /// Number of foods added in this visit, shown in the app bar.
  int _added = 0;

  static const _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        _more();
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    // Generous debounce: the site tarpits clients that burst requests.
    _debounce = Timer(const Duration(milliseconds: 650), () => _search(v));
  }

  Future<void> _search(String raw) async {
    final q = raw.trim();
    if (q == _query) return;
    final gen = ++_gen;
    setState(() {
      _query = q;
      _hits = [];
      _total = 0;
      _page = 0;
      _error = null;
    });
    if (q.length < 2) return;
    await _fetch(gen);
  }

  Future<void> _more() async {
    if (_busy || _query.length < 2 || _hits.length >= _total) return;
    await _fetch(_gen);
  }

  Future<void> _fetch(int gen) async {
    setState(() => _busy = true);
    try {
      final app = AppScope.read(context);
      final res = await app.guard(
        () => app.kb.search(_query, page: _page + 1, size: _pageSize),
      );
      if (!mounted || gen != _gen) return;
      setState(() {
        _page++;
        _total = res.total;
        _hits = [..._hits, ...res.hits];
      });
    } on KbException catch (e) {
      if (mounted && gen == _gen) setState(() => _error = e.message);
    } finally {
      if (mounted && gen == _gen) setState(() => _busy = false);
    }
  }

  Future<void> _open(FoodSheetArgs args) async {
    FocusScope.of(context).unfocus();
    final msg = await showFoodSheet(context, args);
    if (msg != null && mounted) _confirm(msg);
  }

  void _confirm(String msg) {
    setState(() => _added++);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 3),
          persist: false,
          action: SnackBarAction(
            label: 'Kész',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
      );
  }

  Future<void> _quickAdd(RecentFood f) async {
    HapticFeedback.mediumImpact();
    try {
      await AppScope.read(context).addFood(
        foodRef: f.foodRef,
        unitId: f.unitId,
        quantity: f.quantity,
        meal: meal,
      );
      if (mounted)
        _confirm('${f.name} → ${meal.label} · ${fmtKcal(f.kcal)} kcal');
    } on KbException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final showRecent = _query.length < 2;

    return Scaffold(
      appBar: AppBar(
        title: Text(_added == 0 ? 'Étel hozzáadása' : '$_added hozzáadva'),
        actions: [
          if (_added > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Kész'),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              controller: _q,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: (v) {
                _debounce?.cancel();
                _search(v);
              },
              decoration: InputDecoration(
                hintText: 'Keress ételt — pl. tojás, zabpehely…',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _q.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _q.clear();
                          _search('');
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: Meal.values.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final m = Meal.values[i];
                return ChoiceChip(
                  label: Text('${m.emoji}  ${m.label}'),
                  selected: m == meal,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => meal = m);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          AnimatedOpacity(
            opacity: _busy ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: const LinearProgressIndicator(
              minHeight: 2,
              color: Palette.ember,
              backgroundColor: Colors.transparent,
            ),
          ),
          Expanded(child: showRecent ? _recentList(app) : _resultList()),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
    child: Text(
      t,
      style: TextStyle(
        color: context.surfaces.muted,
        fontWeight: FontWeight.w700,
        fontSize: 13,
        letterSpacing: 0.3,
      ),
    ),
  );

  Widget _recentList(AppState app) {
    final recent = app.recent;
    if (recent.isEmpty) {
      return _EmptyHint(
        icon: Icons.manage_search_rounded,
        title: 'Mit ettél?',
        text:
            'Írd be az étel nevét. A kaloriabazis.hu több mint 100 000 '
            'ételt és receptet ismer.',
      );
    }
    final pics = app.today?.pics ?? const {};
    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _sectionTitle('LEGUTÓBBI ÉTELEK'),
        for (final f in recent)
          _FoodRow(
            name: f.name,
            subtitle: '${_qtyText(f)} · ${fmtKcal(f.kcal)} kcal',
            pic: pics[f.objId],
            trailing: IconButton.filledTonal(
              tooltip: 'Gyors hozzáadás',
              onPressed: () => _quickAdd(f),
              icon: const Icon(Icons.add_rounded),
              style: IconButton.styleFrom(
                backgroundColor: Palette.ember.withValues(alpha: 0.14),
                foregroundColor: Palette.ember,
              ),
            ),
            onTap: () => _open(
              FoodSheetArgs(
                foodRef: f.foodRef,
                name: f.name,
                pic: pics[f.objId],
                meal: meal,
                unitId: f.unitId,
                quantity: f.quantity,
              ),
            ),
          ),
      ],
    );
  }

  String _qtyText(RecentFood f) {
    final q = f.quantity == f.quantity.roundToDouble()
        ? '${f.quantity.toInt()}'
        : '${f.quantity}';
    final u = knownUnitLabels[f.unitId];
    return u == null ? '$q×' : '$q $u';
  }

  Widget _resultList() {
    if (_error != null && _hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: ErrorPanel(
            message: _error!,
            onRetry: () {
              final q = _query;
              _query = '';
              _search(q);
            },
          ),
        ),
      );
    }
    if (_hits.isEmpty) {
      return _busy
          ? const SizedBox.shrink()
          : _EmptyHint(
              icon: Icons.search_off_rounded,
              title: 'Nincs találat',
              text: 'Próbáld más szóval, vagy rövidebben.',
            );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: _hits.length + 1,
      itemBuilder: (_, i) {
        if (i == 0) {
          return _sectionTitle('$_total TALÁLAT');
        }
        final h = _hits[i - 1];
        return _FoodRow(
          name: h.name,
          verified: h.verified,
          subtitle: '${fmtKcal(h.kcal)} kcal / ${h.per}',
          macros: Macros(h.kcal, h.protein, h.carbs, h.fat),
          pic: h.pic,
          trailing: Icon(
            Icons.chevron_right_rounded,
            color: context.surfaces.muted,
          ),
          onTap: () => _open(
            FoodSheetArgs(
              foodRef: h.ref,
              name: h.name,
              subtitle: '${fmtKcal(h.kcal)} kcal / ${h.per}',
              pic: h.pic,
              meal: meal,
            ),
          ),
        );
      },
    );
  }
}

class _FoodRow extends StatelessWidget {
  const _FoodRow({
    required this.name,
    required this.subtitle,
    required this.onTap,
    this.pic,
    this.macros,
    this.trailing,
    this.verified = false,
  });

  final String name;
  final String subtitle;
  final VoidCallback onTap;
  final PicRef? pic;
  final Macros? macros;
  final Widget? trailing;
  final bool verified;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          FoodAvatar(name: name, url: pic?.icon, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (verified) ...[
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.verified_rounded,
                        size: 15,
                        color: Palette.good,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.surfaces.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (macros != null) ...[
                  const SizedBox(height: 4),
                  MacroLegend(macros!),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    ),
  );
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: Palette.ember.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: Palette.ember),
          ),
          const SizedBox(height: 18),
          Text(title, style: context.text.titleLarge),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.surfaces.muted),
          ),
        ],
      ),
    ),
  );
}
