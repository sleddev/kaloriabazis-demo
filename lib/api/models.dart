/// Data models for the kaloriabazis.hu API.
///
/// The server sends most numbers as strings ("28.60"), sometimes as numbers,
/// and unit names as translation keys ("UNIT_dkg"). Everything here parses
/// defensively.
library;

double numOf(Object? v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}'.trim().replaceAll(',', '.')) ?? 0;
}

int intOf(Object? v) => numOf(v).round();

String? strOf(Object? v) {
  final s = v?.toString().trim();
  return (s == null || s.isEmpty) ? null : s;
}

/// Strips the `<b>` highlight tags the search endpoint wraps matches in.
String stripTags(String s) =>
    s.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('&amp;', '&').trim();

/// Meal slots (`boxdayoftime` / `nDayoftimeRef`). Slot 0 exists server-side
/// but is never rendered by the site, so it is never used.
enum Meal {
  breakfast(1, 'Reggeli', '☕'),
  morningSnack(2, 'Tízórai', '🍎'),
  lunch(3, 'Ebéd', '🍲'),
  afternoonSnack(4, 'Uzsonna', '🥨'),
  dinner(5, 'Vacsora', '🍽️'),
  lateSnack(6, 'Nassolás', '🍫');

  const Meal(this.id, this.label, this.emoji);
  final int id;
  final String label;
  final String emoji;

  static Meal byId(int id) =>
      Meal.values.firstWhere((m) => m.id == id, orElse: () => Meal.lateSnack);

  /// Best guess for the current meal from the time of day.
  static Meal forTime(DateTime t) {
    final h = t.hour;
    if (h < 10) return breakfast;
    if (h < 12) return morningSnack;
    if (h < 15) return lunch;
    if (h < 18) return afternoonSnack;
    if (h < 21) return dinner;
    return lateSnack;
  }
}

const _unitNames = {
  'g': 'g',
  'dkg': 'dkg',
  'kg': 'kg',
  'ml': 'ml',
  'cl': 'cl',
  'dl': 'dl',
  'l': 'l',
  'darab': 'darab',
  'db': 'darab',
  'kozepes': 'közepes',
  'kicsi': 'kicsi',
  'nagy': 'nagy',
  'kiskanal': 'kiskanál',
  'evokanal': 'evőkanál',
  'kaveskanal': 'kávéskanál',
  'bogre': 'bögre',
  'pohar': 'pohár',
  'csesze': 'csésze',
  'szelet': 'szelet',
  'adag': 'adag',
  'marek': 'marék',
  'csipet': 'csipet',
  'gerezd': 'gerezd',
  'szem': 'szem',
  'unncia': 'uncia',
  'font': 'font',
  'tanyer': 'tányér',
  'tanyernyi': 'tányérnyi',
  'doboz': 'doboz',
  'csomag': 'csomag',
  'konzerv': 'konzerv',
  'uveg': 'üveg',
};

/// "UNIT_kozepes" → "közepes".
String unitLabel(String? key) {
  if (key == null || key.isEmpty) return '';
  var k = key.startsWith('UNIT_') ? key.substring(5) : key;
  final known = _unitNames[k.toLowerCase()];
  if (known != null) return known;
  return k.replaceAll('_', ' ').toLowerCase();
}

/// Global unit ids seen in diary data (the per-food list comes from getmenew).
const knownUnitLabels = {
  9: 'darab',
  11: 'adag',
  15: 'közepes',
  18: 'kicsi',
  22: 'nagy',
  24: 'g',
  25: 'dkg',
  26: 'kg',
};

/// Builds the site's food-picture URL from a `pic_id` + `clear_name` pair
/// (port of `mbf_create_pic_name` in the site's func JS).
String? foodPicUrl(int? picId, String? clearName, {bool big = false}) {
  if (picId == null || picId <= 0) return null;
  final c = picId % 10;
  final b = (picId ~/ 10) % 10;
  final a = (picId ~/ 100) % 10;
  final name = (clearName == null || clearName.isEmpty) ? '' : '_$clearName';
  return 'https://kaloriabazis.hu/p/$a/$b/$c/$picId$name'
      '${big ? '_big.png' : '_icon.png'}';
}

class PicRef {
  const PicRef(this.id, this.clearName);
  final int id;
  final String clearName;

  String? get icon => foodPicUrl(id, clearName);
  String? get big => foodPicUrl(id, clearName, big: true);

  static Map<String, PicRef> mapOf(Object? json) {
    if (json is! Map) return {};
    final out = <String, PicRef>{};
    json.forEach((k, v) {
      if (v is Map) {
        final id = intOf(v['pic_id']);
        if (id > 0) out['$k'] = PicRef(id, '${v['clear_name'] ?? ''}');
      }
    });
    return out;
  }
}

class Macros {
  const Macros(this.kcal, this.protein, this.carbs, this.fat);
  static const zero = Macros(0, 0, 0, 0);

  final double kcal;
  final double protein;
  final double carbs;
  final double fat;

  Macros operator +(Macros o) =>
      Macros(kcal + o.kcal, protein + o.protein, carbs + o.carbs, fat + o.fat);
}

/// One food row of a diary day.
class DiaryEntry {
  DiaryEntry({
    required this.id,
    required this.name,
    required this.macros,
    required this.quantity,
    required this.unitId,
    required this.unitText,
    required this.meal,
    required this.foodRef,
    required this.objId,
    required this.grams,
  });

  /// Diary entry id (`nID`) — used by delete / edit.
  final String id;
  final String name;
  final Macros macros;
  final double quantity;
  final int unitId;

  /// Server-rendered quantity, e.g. "1 közepes (182 g)".
  final String unitText;
  final Meal meal;

  /// `<obj id>_<synonym>` — what addfood/getmenew take.
  final String foodRef;
  final String objId;
  final double grams;

  factory DiaryEntry.fromJson(Map<String, dynamic> j) {
    final urlId = strOf(j['url_id']) ?? '${j['nFoodID']}_0';
    final qty = numOf(j['nQuantity']);
    final unitName =
        strOf(j['unitDisplayName2']) ?? unitLabel(strOf(j['unitDisplayName']));
    return DiaryEntry(
      id: '${j['nID']}',
      name: stripTags(
        strOf(j['cDisplayName']) ??
            strOf(j['f_name']) ??
            strOf(j['syn_name']) ??
            '?',
      ),
      macros: Macros(
        numOf(j['nCalorie']),
        numOf(j['nProtein']),
        numOf(j['nCarbo']),
        numOf(j['nFat']),
      ),
      quantity: qty,
      unitId: intOf(j['nFoodUnitRef']),
      unitText: strOf(j['unit_text']) ?? '${_fmtQty(qty)} $unitName',
      meal: Meal.byId(intOf(j['nDayoftimeRef'])),
      foodRef: urlId,
      objId: urlId.split('_').first,
      grams: numOf(j['sumWeight']),
    );
  }
}

String _fmtQty(double q) =>
    q == q.roundToDouble() ? q.toInt().toString() : q.toStringAsFixed(1);

/// A recently eaten food (`rlast_10`), for one-tap re-adding.
class RecentFood {
  RecentFood({
    required this.name,
    required this.foodRef,
    required this.quantity,
    required this.unitId,
    required this.meal,
    required this.kcal,
  });

  final String name;
  final String foodRef;
  final double quantity;
  final int unitId;
  final Meal meal;
  final double kcal;

  String get objId => foodRef.split('_').first;

  factory RecentFood.fromJson(Map<String, dynamic> j) => RecentFood(
    name: stripTags(strOf(j['syn_name']) ?? strOf(j['f_name']) ?? '?'),
    foodRef: '${j['f_nObjID']}_${intOf(j['nSynonymFoodRef'])}',
    quantity: numOf(j['nQuantity']),
    unitId: intOf(j['nFoodUnitRef']),
    meal: Meal.byId(intOf(j['nDayoftimeRef'])),
    kcal: numOf(j['nCalorie']),
  );
}

/// The full diary day (`getfoods` / every write with `return_json=1`).
class DiaryDay {
  DiaryDay({
    required this.date,
    required this.entries,
    required this.totals,
    required this.recent,
    required this.pics,
  });

  final DateTime date;
  final List<DiaryEntry> entries;
  final Macros totals;
  final List<RecentFood> recent;

  /// obj id → picture.
  final Map<String, PicRef> pics;

  List<DiaryEntry> forMeal(Meal m) =>
      entries.where((e) => e.meal == m).toList();

  Macros totalFor(Meal m) =>
      forMeal(m).fold(Macros.zero, (a, e) => a + e.macros);

  factory DiaryDay.fromJson(DateTime date, Map<String, dynamic> j) {
    final rows = (j['results'] as List?) ?? const [];
    final entries = <DiaryEntry>[];
    for (final r in rows) {
      if (r is Map<String, dynamic> && intOf(r['bSum']) == 0) {
        final e = DiaryEntry.fromJson(r);
        if (intOf(r['nDayoftimeRef']) > 0) entries.add(e);
      }
    }
    final seen = <String>{};
    final recent = <RecentFood>[];
    for (final r in (j['rlast_10'] as List?) ?? const []) {
      if (r is Map<String, dynamic>) {
        final f = RecentFood.fromJson(r);
        if (seen.add(f.foodRef)) recent.add(f);
      }
    }
    return DiaryDay(
      date: date,
      entries: entries,
      totals: Macros(
        numOf(j['rfoodsum']),
        numOf(j['rfoodsumProtein']),
        numOf(j['rfoodsumCarbo']),
        numOf(j['rfoodsumFat']),
      ),
      recent: recent,
      pics: PicRef.mapOf(j['obj_id_2_pic_id']),
    );
  }
}

/// One food search hit (`getfood.php` → `results2`).
class FoodHit {
  FoodHit({
    required this.ref,
    required this.foodId,
    required this.name,
    required this.description,
    required this.kcal,
    required this.per,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.verified,
    this.pic,
  });

  /// `<obj id>_<synonym>`.
  final String ref;
  final String foodId;
  final String name;
  final String description;
  final double kcal;

  /// "100 g", "1 darab" …
  final String per;
  final double protein;
  final double carbs;
  final double fat;
  final bool verified;
  final PicRef? pic;

  factory FoodHit.fromJson(Map<String, dynamic> j, Map<String, PicRef> pics) {
    final foodId = '${j['food_id']}';
    return FoodHit(
      ref: '${j['id']}',
      foodId: foodId,
      name: stripTags('${j['name'] ?? j['cName'] ?? '?'}'),
      description: stripTags('${j['cDesc'] ?? ''}'),
      kcal: numOf('${j['cal'] ?? ''}'.replaceAll(RegExp(r'[^0-9.,]'), '')),
      per: strOf(j['piece']) ?? '100 g',
      protein: numOf(j['protein']),
      carbs: numOf(j['carbo']),
      fat: numOf(j['fat']),
      verified: strOf(j['votedpic']) != null,
      pic: pics[foodId],
    );
  }
}

class SearchPage {
  SearchPage(this.total, this.hits);
  final int total;
  final List<FoodHit> hits;
}

class FoodUnit {
  const FoodUnit(this.id, this.key, this.grams);
  final int id;
  final String key;

  /// Weight of one unit in grams (0 when unknown).
  final double grams;

  String get label => unitLabel(key);
  bool get isMass => grams == 1 || grams == 10 || grams == 1000;
}

/// Unit list + per-gram nutrients (`getmenew`).
class FoodInfo {
  FoodInfo({
    required this.foodId,
    required this.units,
    required this.kcalPerG,
    required this.proteinPerG,
    required this.carbsPerG,
    required this.fatPerG,
    required this.isFavourite,
  });

  /// Food row id (`getmenew_food_id`). Differs from the object id in the
  /// diary/search ref; `savemodeitemfood` needs this one.
  final String foodId;
  final List<FoodUnit> units;
  final double kcalPerG;
  final double proteinPerG;
  final double carbsPerG;
  final double fatPerG;
  final bool isFavourite;

  Macros macrosFor(FoodUnit u, double qty) {
    final g = u.grams * qty;
    return Macros(kcalPerG * g, proteinPerG * g, carbsPerG * g, fatPerG * g);
  }

  factory FoodInfo.fromJson(Map<String, dynamic> j) {
    final units = <FoodUnit>[];
    for (final u in (j['getme'] as List?) ?? const []) {
      if (u is Map) {
        units.add(
          FoodUnit(intOf(u['ID']), '${u['Name']}', numOf(u['nWeight'])),
        );
      }
    }
    final fav = j['fav'];
    return FoodInfo(
      foodId: '${j['getmenew_food_id'] ?? ''}',
      units: units,
      kcalPerG: numOf(j['calperg']),
      proteinPerG: numOf(j['protperg']),
      carbsPerG: numOf(j['carbperg']),
      fatPerG: numOf(j['fatperg']),
      isFavourite: fav is Map && intOf(fav['isfav']) == 1,
    );
  }
}
