import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kalori/api/models.dart';

/// Fixtures are real responses captured from kaloriabazis.hu.
Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('diary day parses entries, totals, recent and pictures', () {
    final day = DiaryDay.fromJson(DateTime(2026, 10, 7), _fixture('day.json'));
    expect(day.entries, hasLength(1));
    final e = day.entries.single;
    expect(e.name, 'Alma');
    expect(e.meal, Meal.breakfast);
    expect(e.macros.kcal, 78);
    expect(e.unitText, '150 g');
    expect(e.foodRef, '1696_0');
    expect(day.totals.carbs, closeTo(20.72, 0.001));
    expect(day.recent.first.foodRef, '1696_0');
    expect(
      day.pics['1696']?.icon,
      'https://kaloriabazis.hu/p/7/0/6/1006706_alma_icon.png',
    );
  });

  test('search hits strip highlight tags and parse kcal', () {
    final j = _fixture('search.json');
    final pics = PicRef.mapOf(j['food_id_2_pic_id']);
    final hits = [
      for (final r in j['results2'] as List)
        FoodHit.fromJson(r as Map<String, dynamic>, pics),
    ];
    expect(hits[1].name, 'Golden alma');
    expect(hits[0].kcal, 52);
    expect(hits[0].verified, isTrue);
    expect(hits[1].pic?.id, 1004374);
  });

  test('food info computes macros from per-gram values', () {
    final info = FoodInfo.fromJson(_fixture('getmenew.json'));
    final medium = info.units.firstWhere((u) => u.label == 'közepes');
    expect(medium.grams, 182);
    expect(info.macrosFor(medium, 1).kcal, closeTo(94.64, 0.01));
  });

  test('unit labels', () {
    expect(unitLabel('UNIT_kiskanal'), 'kiskanál');
    expect(unitLabel('UNIT_valami_uj'), 'valami uj');
  });
}
