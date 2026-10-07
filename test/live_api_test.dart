// Live round-trip against kaloriabazis.hu. Skipped unless `.env.test`
// (KB_USER / KB_PASS) exists. Run with: flutter test test/live_api_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kalori/api/kb_client.dart';
import 'package:kalori/api/models.dart';

Map<String, String> _env() {
  final f = File('.env.test');
  if (!f.existsSync()) return {};
  return {
    for (final l in f.readAsLinesSync())
      if (l.contains('=')) l.split('=').first: l.substring(l.indexOf('=') + 1),
  };
}

void main() {
  final env = _env();
  final skip = env['KB_USER'] == null ? 'no .env.test' : null;

  test(
    'login, search, add, edit, delete',
    () async {
      final kb = KbClient();
      await kb.login(env['KB_USER']!, env['KB_PASS']!);
      expect(kb.hasSession, isTrue);

      // 'főtt tojás': its object id and food id differ, which edit must handle.
      final res = await kb.search('főtt tojás', size: 5);
      expect(res.hits, isNotEmpty);
      final food = res.hits.first;
      print(
        'hit: ${food.name} ${food.kcal} kcal/${food.per} pic=${food.pic?.icon}',
      );

      final info = await kb.foodInfo(food.ref);
      expect(info.units, isNotEmpty);
      print(
        'units: ${info.units.map((u) => '${u.label}=${u.grams}g').join(', ')}',
      );

      final date = DateTime(2026, 10, 1);
      final gram = info.units.firstWhere((u) => u.grams == 1);
      var day = await kb.addFood(
        date: date,
        foodRef: food.ref,
        unitId: gram.id,
        quantity: 150,
        meal: Meal.lunch,
      );
      final added = day.entries.lastWhere((e) => e.foodRef == food.ref);
      print('added: ${added.name} ${added.unitText} ${added.macros.kcal} kcal');
      expect(added.macros.kcal, closeTo(info.macrosFor(gram, 150).kcal, 2));

      day = await kb.editEntry(
        date: date,
        entry: added,
        foodId: info.foodId,
        unitId: gram.id,
        quantity: 200,
        meal: Meal.dinner,
      );
      final edited = day.entries.firstWhere((e) => e.id == added.id);
      expect(edited.meal, Meal.dinner);
      expect(edited.quantity, 200);
      expect(edited.name, added.name);
      expect(edited.macros.kcal, closeTo(info.macrosFor(gram, 200).kcal, 2));

      day = await kb.deleteEntry(date, added.id);
      expect(day.entries.where((e) => e.id == added.id), isEmpty);

      print(
        'goal: ${await kb.getDailyGoal()}, weight: ${await kb.getWeight(date)}',
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
