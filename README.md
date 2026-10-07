# kalóri.

An unofficial Flutter calorie counter for [kaloriabazis.hu](https://kaloriabazis.hu)
that talks to the site's web API directly — no backend of its own.

- **Napló (diary)** — animated calorie ring against your daily goal, macro bars,
  week strip with per-day mini rings, six meal slots, swipe to delete (with undo),
  tap to edit quantity / unit / meal.
- **Étel hozzáadása (add food)** — debounced, paged search with the site's food
  photos and macros; recently eaten foods with one-tap re-add; a detail sheet that
  computes kcal and macros live from the per-gram values for any unit.
- **Statisztika** — last 7 days bar chart with goal line, daily average, days under
  goal, macro split and the week's biggest calorie sources.
- **Profil** — daily calorie goal and body weight (both saved to your
  kaloriabazis.hu account), light/dark/system theme, logout.

The UI is in Hungarian, like the service.

## Structure

```
lib/api/kb_client.dart   HTTP client: cookie jar, login flow, paced request queue, endpoints
lib/api/models.dart      tolerant parsers for the server's JSON (strings-as-numbers, UNIT_* keys)
lib/state/app_state.dart session persistence, diary-day cache, settings (ChangeNotifier)
lib/screens/             today, add food, food sheet, insights, profile, login
lib/widgets/common.dart  calorie ring, macro bars, food avatar, …
```

## API notes (beyond the reverse-engineering report)

Verified live while building this app:

- The anonymous homepage also contains the word "Kijelentkez" (in scripts), so
  "logged in" is detected by the `href=".../kijelentkezes"` link; the nickname is in
  `<span class="nick">`.
- A session started with a mobile User-Agent gets `mob_for_a=1`, and then
  `getdaily` answers `{"type":"1"}`. The client uses a desktop UA and pins
  `mob_for_a=0`.
- `savemodeitemfood` needs `getmenew_food_id` from the `getmenew` response, which
  can differ from the object id in the diary/search ref (e.g. *Főtt tojás*:
  ref `1589063_0`, food id `2620125`). Sending the object id silently swaps the entry
  to a different food.
- `getmenew` returns per-gram kcal/protein/carbs/fat and each unit's gram weight, so
  the sheet calculates locally; `calcfooddetail` is the fallback for weightless units.
- Daily goal: `food.php?show=setDaily&boxdaily=1&boxdailytype=1&dailyquan=<kcal>`.
- Body weight: `food.php?show=addweight&date=YYYY.MM.DD&weight=<kg>`; current value is
  read from the `getmetrics` HTML form.
- Food pictures: `/p/{d3}/{d2}/{d1}/{pic_id}_{clear_name}_icon.png` (and `_big.png`),
  where d1/d2/d3 are the last three digits of `pic_id`, last digit first
  (port of the site's `mbf_create_pic_name`).
- All requests go through a serial token bucket (burst 4, then one per 1.8 s) to
  stay clear of the site's tarpit.

## Development

```bash
flutter pub get
flutter run                          # Android
flutter test test/models_test.dart   # offline parser tests (fixtures are real responses)
```

Live API round-trip (login → search → add → edit → delete on a test account):

```bash
printf 'KB_USER=...\nKB_PASS=...\n' > .env.test   # git-ignored
flutter test test/live_api_test.dart
```
