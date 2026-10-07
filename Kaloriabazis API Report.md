# KalóriaBázis API — reverse-engineering report

**Site:** [kaloriabazis.hu](https://kaloriabazis.hu) — the most-used Hungarian calorie-counting service (~600k users, server-rendered Hungarian frontend + Android/iOS app)
**Deliverable:** [kaloriabazis-openapi.yaml](rool-machine:/rool-drive/kaloriabazis-api/kaloriabazis-openapi.yaml) — OpenAPI 3.1, 117 paths, 8 tags, 26 schemas
**Date:** 2026-10-03, updated 2026-10-04
**Method:** JavaScript bundle analysis + live probing (see caveats in §8)

---

## 1. Architecture overview

The site is a classic one-endpoint-many-actions PHP API. There is no REST, no versioning, no API keys. Almost everything is `GET` requests dispatched by a `show=<action>` parameter:

| Endpoint | Purpose | # actions | Anonymous? |
|---|---|---|---|
| `food.php` | Diary CRUD, food/sport entries, calculations, favourites, metrics, water, weights, premium, share | ~70 | mostly no |
| `food2.php` | Food datasheets, top-300 list, moderation, settings, account deletion, mobile/ads hooks | ~30 | mostly no |
| `food_operations.php` | Bulk food ops, cookie consent, bonus points | 4 | mixed |
| `getfood.php` | Search engine (autocomplete + paged list) | — | yes |
| `PCC_pie.php` / `PCC_pie2.php` | Pie-chart data (sports calories / food macros) | — | token-protected |
| `PCC_weight.php` / `PCC_weight2.php` | Weight tracking chart data | — | token-protected |
| `triplet_build.php` | Build a "triplet" (composed food) | — | yes |
| `vote_ajax.php` | Community translation voting system | 6 | no |
| `price_ajax.php` | Crowd-sourced shop prices | 4 | no |
| `barcode_ajax.php` | Barcode/EAN lookup + linking | 6 | mixed |
| `cardcancel_234786583.php` | Obfuscated endpoint to cancel a stored payment card | — | no |

All calls carry `X-Requested-With: XMLHttpRequest` and hit `https://kaloriabazis.hu` with a PHP session cookie (`myPHP83SESSID`).

## 2. Session & the anti-abuse guard

This is the most interesting (and most fragile) part of the API. Three layers protect it:

1. **Session warm-up.** Before the first AJAX call you must visit any page (e.g. `/fooldal`) so the PHP session exists. A cold session gets rejected.
2. **The `die_with_text arjrjkrk` guard.** Requests that don't look like the real frontend get HTTP 200 with the body `die_with_text arjrjkrk`. In practice it fires when the request misses a browser-like `User-Agent`, the `X-Requested-With` header, or a plausible `Referer` — each AJAX action is tied to the page that calls it (e.g. diary calls expect `https://kaloriabazis.hu/naplo`, datasheet calls expect the matching `/etel/…` page).
3. **Rate-limit tarpit.** Bursting requests (≈40+ rapid calls) trips a tarpit: the server accepts the TCP connection but never responds (curl sees `HTTP 000` after ~25 s). The lockout is on the order of tens of minutes. Unknown `show` values are tarpitted the same way — a cheap honeypot against scanners.

Practical limits for a client: keep a session cookie jar, mimic the headers, and stay at a few requests per minute. With that, anonymous reads work fine.

**Session-expiry responses:** text responses contain `###TIMEOUT###`; JSON responses contain `{"type":"1","error":"Nem vagy bejelentkezve!"}` ("You are not logged in!").

## 3. Verified public endpoints (live-tested)

### 3.1 Search — `GET /getfood.php`

```
GET /getfood.php?q=tojas&p=1&s=1
```

```json
{
  "total1": 0,
  "results1": [],
  "total2": 16,
  "results2": [
    {
      "id": "2088_0",
      "eaten_food": 0,
      "food_id": 2088,
      "obj_id": 2088,
      "kuktalink": "etellink",
      "kuktapic": "",
      "kuktatitle": "Tojás",
      "votedpic": "",
      "votedpictitle": "",
      "name": "tojás",
      "cal": 154.0
    }
  ],
  "food_id_2_fav": { "2088": "1" }
}
```

- `results1` = the user's favourite meals matching the query (empty when anonymous)
- `results2` = all foods and recipes; approved and "grey" (unapproved) public ones can be mixed with `all_public_food=1`
- `q` is accent-insensitive; "kinder bueno" matches the real product
- `s` (page size) is 15 in the frontend; `p` is 1-based
- Nutrient filters: `expropsearch_id=910&expropsearch_inc=1` = only foods that have calories data
- `id` is `"<foodId>_<unitId>"` — parse before the `_`

### 3.2 Name/id resolution — `food.php`

```
GET /food.php?show=getid&id=2088_0        → {"id":"2088"}
GET /food.php?show=getname&id=2088_0      → "tojas"              (text/plain)
GET /food.php?show=getname2&id=2088_0     → {"url":"etel","cleanedname":"tojas","id":"2088"}
```

`getname2` builds the public datasheet URL: `/{url}/{cleanedname}_kcal/{id}`.

### 3.3 Units — `food.php`

```
GET /food.php?show=getme&id=1147_0
→ [{"ID":"15","Name":"UNIT_kozepes"},{"ID":"25","Name":"UNIT_dkg"},...]
```

Unit names are translation keys (`UNIT_g`, `UNIT_dkg`, `UNIT_darab`, `UNIT_kozepes`, `UNIT_nagy`, `UNIT_kiskanal`, `UNIT_unncia`, …) rendered into Hungarian client-side. `nWeight` gives the gram weight where applicable.

### 3.4 Datasheet — `food2.php`

```
GET /food2.php?show=getfoodinfo&id=1147_0
Referer: https://kaloriabazis.hu/etel/<slug>_kcal/1147
```

```json
{
  "boxes": [
    {"box_id": 1, "title": "", "lines": [
      {"prop_id": 910, "prop_id_txt": "Kalória (Energy)", "unit": "kcal", "prop_val": null, "from_usda": null},
      {"prop_id": 930, "prop_id_txt": "Zsír (Fat)", "unit": "g", "prop_val": null, "from_usda": null},
      ...
    ]},
    {"box_id": 2, "title": "Ásványok",  "lines": [ ... 7 rows  ]},
    {"box_id": 3, "title": "Vitaminok", "lines": [ ... 13 rows ]},
    {"box_id": 4, "title": "Zsírok",    "lines": [ ... 7 rows  ]}
  ],
  "fds_data": {
    "name": "Coca-Cola",
    "food_id": "2625297",
    "nCalorie": "45.000", "nProtein": "0.000", "nCarbo": "11.200", "nFat": "0.000",
    "food_approved": 1,
    "is_imported_usda": "0",
    "cUsdaLink": "https://ndb.nal.usda.gov/ndb/foods/show/45375007...",
    "cUsdaName": "Coca-Cola Bottle, 1.75 Liters, PREPARED, GTIN: ...",
    "infoline_kat": "Kategória: Ital",
    "infoline_letrehoz": "Létrehozta: Admin",
    "infoline_utmodos": "Utoljára módosította: drisztina",
    "infoline_ennyisz": "Ennyiszer választották: 655315",
    ...
  },
  "rating_block_obj": { ... }
}
```

Note the two id systems: the request id (1147) and the canonical `fds_data.food_id` differ — the object-level `obj_id` from search is what the site uses for diary entries.

### 3.5 Calculations — `food.php`

```
GET /food.php?show=calcme&id=1147_0&quan=100&boxme=25
→ [{ "ID": 15, "Name": "UNIT_kozepes", "nWeight": 55 }, { "cal": 45.0 }]
```

`calcfooddetail` returns the same four macro numbers as an object. `calcsportme` does the same for sports (kcal burned).

### 3.6 Charts — `PCC_*.php`

```
GET /PCC_pie2.php?id=1147_0&gui=42
→ [["MAIN_feherje","13.5"],["MAIN_szenhidrat","0.6"],["MAIN_zsir","12"]]
```

Pairs of `[translation-key, kcal-number]`. The `X` token (generated client-side in `PCC_img2()` from date+id+size) protects the same data when written by other clients — anonymous chart reads work.

### 3.7 Statistics — `food2.php`

```
GET /food2.php?show=getsumstat
→ {"osszfogyas":4520449,"fogyasztas":0,"aktivtagok":0,"kereshetoetelek":...}
```

(all-time logged foods, today's total, active members, searchable-food count)

### 3.8 Top-300 list — `food2.php`

```
GET /food2.php?show=ct_get_top300_ajax&categ_id=16   → 269 items
GET /food2.php?show=ct_get_top300_ajax&categ_id=18   → 430 items
```

Each item: `{id, name, cal}` (kcal/100 g).

### 3.9 Barcode — `barcode_ajax.php`

```
GET /barcode_ajax.php?show=get_food_info_from_bcode&bcode=86311649
→ {"no_result_found":"1"}
```

### 3.10 Daily evaluation — `food.php`

```
GET /food.php?show=calckiertekel&date=2026-10-03
→ {"type":"1","error":"Nem vagy bejelentkezve!"}   (anonymous)
```

With a session it returns net calories, % of the daily frame, week/month/half-year averages, BMR and deficit values.

## 4. Data model conventions

- **Id strings** everywhere: `"1147_0"` = food/recipe id + unit id (0 = default unit). `getid` strips it for you.
- **Dates:** `YYYY-MM-DD` in AJAX parameters (the web pages render Hungarian dots format for humans).
- **Meal slots (`tod` / `boxdayoftime`):** 0 breakfast · 1 morning snack · 2 lunch · 3 afternoon snack · 4 dinner · 5 late snack.
- **Unit keys:** `UNIT_*` translation keys; `nWeight` carries grams.
- **Nutrient property ids** (stable site-wide, used by search filters, datasheet boxes and settings):

| box | ids | meaning |
|---|---|---|
| 1 — macros | 910, 920, 930, 940, 1010, 1015, 1020 | kcal, protein, fat, carbo, fiber, fruit %, sugars |
| 2 — minerals | 1100–1160 | Ca, Fe, Mg, P, K, Na, Zn |
| 3 — vitamins | 1200–1320 | C, B1, B2, niacin, B6, pantothenic acid, biotin, B12, D, A, E, K |
| 4 — fats | 1400–1460 | saturated, mono- and poly-unsaturated, cholesterol, Ω-3, Ω-6 |

Units per property: `kcal`, `g`, `mg`, `µg`, `IU`, `%`.

- **Errors:** `{"type":"1"}` (anonymous/expired), `###TIMEOUT###` (expired HTML), `die_with_text arjrjkrk` (guard).

## 5. The full action catalogue

The OpenAPI file ([kaloriabazis-openapi.yaml](rool-machine:/rool-drive/kaloriabazis-api/kaloriabazis-openapi.yaml)) documents all **112 actions** with their parameters. Highlights beyond the sections above:

- **Diary:** `addfood` (also takes `hour_min`, `is_from_speachrecog` — speech recognition is built in), `savemodeitemfood`, `delfood`, `delfoodtod`, `delfoodall`, `additional_eating`, `copykaja*`, `refreshfood`, `calcdailyframe`, `getPropNutrient`, `setPropNutrient`
- **Sport:** `addsport`, `addnewsport`, `savemodeitemsport`, `delsport`, `calcsportme`
- **Favourites & quick-buttons:** `addfavfood`, `addfavsport`, `addfavmeal` (whole meal snapshots), quick-button assignment
- **Own foods/recipes:** `addnewfood`, `addnewrecfood`, `addrecfood`, `savefoodinfo`, `delownfood`, `usda_load` (imports from the USDA database)
- **Health data:** `addweight`, `addsizes`, `addwater`/`setwater`/`resetwater`, diet-group join/leave
- **Monetisation:** premium-week activation, `get_admob_bigp_refresh_data` (Forint per thousand ad impressions), hidden AdMob panel calls, obfuscated `cardcancel_234786583.php`
- **Community:** translation voting (`vote_ajax.php`), shop prices + incorrect-price reports + bonus points (`price_ajax.php`), food rating, error reports for approved/grey foods, moderation queue (`corrector_food_del`)
- **Account:** `big_delete` (account deletion), `moveuser` (legacy login/register), `keepcon` keep-alive
- **Misc:** share-message builder, cookie-consent acknowledgement, speech-recognition settings

## 6. Notable findings

- The **Android/iOS apps** talk to the same endpoints (the AdMob and speech-recognition hooks prove it) — there is no separate mobile API.
- Community-driven **data quality pipeline**: users create foods → "grey" (unapproved) state → community/volunteer approval (`food_approved` in `fds_data`) → error reports → correction queue. Recipes can be imported from the **USDA database** with one call.
- **Crowd-sourced shop prices** with bonus-point rewards, including discount windows (`start_date`/`stop_date`).
- The **translation system is gamified**: users vote on terms, get bonus points, and the vote box can be disabled per user.
- The site counts ~4.5M logged food entries all-time (`osszfogyas`).

## 7. Security observations

- The API has **no CSRF protection at all** on the observed write actions — everything is a plain `GET` with session-cookie auth. Combined with the same-origin SPA pattern, a malicious page could trigger diary writes via `<img>`/`fetch` with credentials.
- The `X` token on chart data is a custom client-side hash, not a real CSRF token.
- The payment-card-cancel endpoint uses an obfuscated name (`234786583`), indicating deliberate obscurity rather than security.
- The `die_with_text arjrjkrk` guard is only a light scraper deterrent — it does not authenticate anything.

## 8. Caveats & remaining unverified areas

Updated after the 2026-10-04 morning session (§7.8): the login flow, diary writes (`addfood`/`delfood`/`savemodeitemfood`), favourites (`addfavfood`/`delfavfood`/`addfavmeal`/`delfavmeal`), sport diary, water, body metrics and ~25 read endpoints are now **live-verified against a real test account**. What remains:

- **Recipe creation** happens through the dedicated pages (`/receptszerkesztes/`, `/etelszerkesztes/`), not the legacy ajax endpoints — the page POST flow is unmapped.
- **`favfood_button_assign`** returned 200 but the assigned quick-button did not appear in `getfoods.favbuts` — the button list is probably populated by the mobile app; effect unverified.
- **`calcreccal2`** and **`addsizes`** verified only at probe level (need a real recipe id / mobile app payload respectively).
- The PCC `X` anti-abuse token algorithm is still a black box (server-side).
- `usda_load` is legacy (no JS caller, empty response).
- Vote-dialog reads were captured; the **vote write** (`vote` with `vote_points`) was not exercised — it requires a food the test account has rated, and creating ratings pollutes real dataset rows.

## 9. Reproducing the probes

```bash
# 1. warm up: get a session
curl -c jar -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/126" https://kaloriabazis.hu/fooldal

# 2. call with session + headers
curl -b jar -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/126" \
  -H "X-Requested-With: XMLHttpRequest" \
  -H "Referer: https://kaloriabazis.hu/naplo" \
  "https://kaloriabazis.hu/getfood.php?q=tojas&p=1&s=1"
```

Keep the pace at a few requests per minute — the tarpit (§2.3) is otherwise unavoidable.

---

## 7. Live verification round — 2026-10-03 afternoon (session supplied)

### 7.1 Session

The owner supplied the session cookie of a **test account**. Verification performed against a live logged-in session, capped to a few calls per minute to respect the tarpit.

| Check | Result |
|---|---|
| Session validity (`/naplo` page) | ✔ logged in — logout link present, login form absent |
| `getfoods` (`food.php`, `return_json=1`) | ✔ JSON day blob returned |
| `calckiertekel` (`food2.php`) | ✔ `{"type":1,...}` DayEvaluation shape confirmed exactly as in §5.2 |
| `getmetrics` (`food2.php`) | ✔ `{"type":0, id1..id5, unitid1..unitid5, txtnum1..txtnum5}` confirmed |
| `getdaily`, `getme`, `getmeisfav`, `get_exprop_settings` | response shapes confirmed **from the site JS** (`js_food.js`, `js_func3.js`) — see §7.3 |

### 7.2 Site outage (16:00–… UTC+2)

Mid-verification **the whole site began returning nginx 404 for every path** (apex, static assets, `food.php`, everything). A third-party uptime checker (isitdownrightnow) from a different IP saw the same 404 — so this was **a server-side outage, not a rate-limit ban**. `www.` still answered with a redirect, but the apex (the site itself) served nothing. The remaining live probes had to be paused — they were completed later in §7.6 and §7.8 once the site recovered.

### 7.3 Corrections applied to the spec during verification (from live calls + JS)

- `getfoods` / `addfood` / `delfood` / `delfoodall` / `delfoodtod` with `return_json=1` all respond with the **full refreshed diary day** (DiaryDayJson schema) — the mobile client simply re-renders from this.
- `delfood`'s `id` in JSON mode is the **diary entry id** (`nID`/fooduser id), not the food id.
- `delfoodall` and `delfoodtod` are served by **`food.php`**, not `food2.php` (spec corrected).
- `addfavfood` takes an optional `synonym` (synonym id) parameter; `delfavfood` takes only `id` ("<id>_<unit>").
- New response schemas added: `DiaryEntry`, `MealStat`, `DiaryDayJson`, `DailySettings`, `IsFav`, `ExpropSettings`.
- `getdaily` → `{type, error, boxdailySet, txtdailyquan, boxdailyType}`; `getmeisfav` → `{isfav, nFoodUnitRef, nQuantity}`; `getme` → array of `{ID, Name}` units.

### 7.4 Post-outage session (2026-10-03, ~22:45)

The site came back at ~17:25 local (outage duration ≈ 1h25m, monitor log recorded 000/timeouts between 17:09–17:25, i.e. the whole web server was briefly unreachable, then HTTP 200).

**The redeploy changed the session cookie**: the server now issues `myPHP83SESSID` (PHP 8.3 session name) instead of `PHPSESSID`, with `Secure; HttpOnly; SameSite=Lax`. Anonymous warm-up cookies are unchanged (`LANGID=1`, `CLANGCODE=HU`, `UNITLANGID=1`, `BWEIGHT_UNIT=1`, `BHEIGHT_UNIT=1`, `mob_for_a=0` — ten-year expiry).

The replacement session ID supplied afterwards (`NVSmUk2OFz0eJn5kMQIAAU3zAH`) was **rejected by the server**: every request presenting it gets a fresh session issued (`set-cookie: myPHP83SESSID=<new>` — PHP's response to an unknown/expired session ID) and the diary page renders in its anonymous variant (login form present). It is also one character shorter (26 vs 27 chars) than the morning's known-good ID, so a truncated copy is the likely cause. Verification of authenticated actions is paused pending a re-copy.

### 7.5 Additional public verifications (post-outage)

- `getfood.php?q=X&p=N&s=M`: `p` = 1-based page, **`s` = page size** (s=1→1 result, s=2→2, s=3→3, s=0→0). Spec corrected.
- Full `SearchResultItem` field list captured (25 fields: composite id, food_id, obj_id, kuktalink/votedpic/pictrash class slots, name, cDesc, piece, weight, cal, protein/carbo/fat, link slots, datasheetlink, kcal_and_unit) — spec updated.
- Response envelope confirmed: `rownum1`/`total1`/`results1` (matches eaten today; empty anonymously), `total2`/`results2` (food matches), `usdaLinks_arr`, `rec_usda_empty_arr`, `food_id_2_barcode_pic`, `food_id_2_fav`, `food_id_2_pic_id`, `prices`, `discounts`.

### 7.6 Authenticated session (2026-10-03 22:47) — login from the machine

Dávid supplied the test account credentials (`test67`), so the full login flow could be verified for the first time:

- `GET /login` (hun login page) → CSRF token `myt` present in the page.
- `GET /login` → **302 to `/`** (changed after the 2026-10 redeploy; it used to serve the login page directly). The login form lives on the **homepage**.
- Homepage form (`#loginForm`) POSTs to **`/bejelentkezes`** with `mode=get`, `myt` (CSRF), `txtusern`, `txtpassw` → 200, logout link (`Kijelentkezés`) present; issues `myPHP83SESSID` with `Secure; HttpOnly; SameSite=Lax`. Verified live 2026-10-04.
- Logout: `GET /kijelentkezes` → 302, session destroyed (homepage shows the login form again; `getme` returns `[]`, `getfoods` a guest-level empty day). Verified live 2026-10-04.
- Legacy `POST /login` with `myuser`, `mypw`, `myt` still returns a logged-in page (verified live), but it does **not** re-issue the session cookie — it upgrades the session the GET warm-up created. Prefer the form-faithful flow.
- Subsequent `food.php` / `food2.php` / `getfood.php` calls with this cookie all work.

**Verified live this session (all on the test account):**

| Endpoint | Result |
|---|---|
| `addfood` (`food.php`) | ✔ entry added; response echoes the **whole updated day list** (`results` = all entries incl. the new one, plus `rfoodsum*` totals) — not just the new entry |
| `addfood` with `boxdayoftime=0` | ⚠ entry is stored but **never rendered** (JS skips `nDayoftimeRef==0`); always pass a real slot (1–6) |
| `delfood` (`food.php`) | ✔ entry removed (`id` = diary entry id, `date` = dot-format) |
| `addfavfood` / `delfavfood` | ✔ `{"fav_id":2532663}` / `Törlés sikerült!` |
| `getrecfood_b` | returns HTML (ingredient list); only takes recipe food_ids — see recipe module note below |
| `calcfooddetail` | ✔ `{cal, zsir, feherje, szen, weight}` for unit × quantity (boxme=9 darab ×2 → 104 g, 148.72 kcal) |
| `getname3` | ✔ treats the id as an **own-food row id**, not a base food id |
| `get_bonus_points` | ✔ `{"points":0}` (on `price_ajax.php`, not `food.php` — spec corrected) |
| `addweight` | ✔ saved; `getmetrics` reflects it immediately |
| `addwater` / `resetwater` | ✔ `2` (dl) / `0` |
| `getmenew` | ✔ richer unit list (`nWeight`, `is_food`, `bDefGen`, …) |
| `getsportme` with bad id | ✔ `err_2678567868` — documents the `err_<n>` error convention |
| `getsumfogyasztas` | ✔ **site-wide** consumption ticker (`#numFogyasztas`), not user data — spec corrected |
| `id_2_pic_id` | ✔ `{pic_id, clear_name}` |
| `keepcon` | ✔ `ok` |
| vote dialogs (`getvote_top_popup` etc.) | ✔ shapes captured |
| `getsport.php?q=...` | ✔ **new endpoint added to spec**; requires accented query ("futás" hits, "fut" doesn't) |
| `calcsportme` + `addsport` + `delsport` | ✔ sport round-trip (627.29 kcal → deleted) |
| `copykaja` | ✔ copies an existing diary entry (`nID` source) to another date/tod; new id returned |
| `getmesu` (`food.php`) | ✔ unit list for sport/time units |
| `addfavmeal` (`food2.php`) | ✔ `{"ok":1}` — saved current breakfast slot as favourite meal |
| `getfoods` envelope | ✔ new keys: `favbuts`, `prices`, `discounts`, `food_id_2_barcode`, `obj_id_2_pic_id`, `intermittent`, `seconds_to_midnight`, `needed_start_added_food_adv` |

### 7.7 Second outage wave (2026-10-03 ~23:00–23:55)

- **CORRECTION (2026-10-04):** the "static assets 404" observation in this section was a probe error — the assets live under `/tpls/_inc/` and `/js/` (`/js/food.js?615`, `/js/func2.js?615` etc.), and they served fine all along; the probe had used wrong paths (`/food.js`, `/css/style.css`). The site was **not** half-broken.
- `getfood.php` (search) **hung** (>60–110 s) in repeated attempts while `food.php` stayed fast; it recovered fully by 2026-10-04 05:50 (0.17–0.2 s).
- `addnewrecfood`/`addrecfood` on `food.php` return **nginx 404**, but this is **not breakage**: neither endpoint is referenced anywhere in the current frontend JS — the modern flow creates/edits recipes via the dedicated pages `/receptszerkesztes/<name>/<id>_0` and `/etelszerkesztes/<name>/<id>_0` (see `ppp_edit` in func2.js). The ajax recipe endpoints are legacy. `food2.php?show=addnewrecfood` returns an empty 200.

Consequences: the `addfood`→`delfood` and favourites round-trips **are verified**; the favmeal deletion round-trip was completed on 2026-10-04 (see below).

### 7.8 Favmeal deletion + remaining endpoints (verified 2026-10-04 05:50–06:00)

1. **`delfavmeal` (food2.php)** ✔ — the favmeal "Teszt Reggeli" was found via search (`results1` carries `nId: 46935`, `cName`, `nTod`, `dDate`) and deleted. Note: calling `delfavmeal` on `food.php` returns an empty 200 **without deleting** — it must go to `food2.php`. Test account is now clean.
2. **`savemodeitemfood`** ✔ full round-trip — edits an existing diary entry. Params: `return_json=1`, `plusminus`, `boxme=<unit dimobj>`, `boxdayoftimemod=<meal slot>`, `quan`, `id=<diary nID>`, `date`, `hour_min` (-1 = no time), `getmenew_food_id=<obj id>`. Response = the updated day list (same envelope as `addfood`). Live test: 1 darab egg (74.36 kcal) → edited to 100 g → 170 kcal, reflected in `getfoods` immediately, then deleted.
3. **`calcmeitemmod`** ✔ — takes the *diary entry id* (`id`), plus `boxme`/`quan`; returns a bare number: the recalculated total kcal for that entry with the new quantity/unit (143 for 100 g egg). Returns `0` when the id isn't a diary entry.
4. **`additional_eating`** ✔ — voice-input "I ate more of the last item": takes `quan` + `date`, adds `quan` **in the last added entry's unit** (1 → 51 darab), and returns the updated fubox/day JSON.
5. **`setwater`** ✔ — params `waterGoal` (ml/day), `waterquan` (ml), `date`; empty 200; `resetwater` after it → `0`.
6. **`get_bcode_code_value` (barcode_ajax.php)** ✔ — `{"ok":1,"barcode_type":null,"selected_device":null}` (returns the live camera-scanner state; the quagga decoder path is commented out in func5.js).
7. **`usda_load`** — legacy: empty 200 with no params, **not called anywhere in the current JS**.
8. **`get_admob_bigp_refresh_data`** ✔ — empty 200 (no ad config on this account).
9. **`favfood_button_assign`** — 200 empty body; JS params: `fav_id`, `obj_id`, `unit_id`, `quan`, `col`, `button_id_arr` (one of 14 quick buttons). Assigning button 1 with a fresh fav did **not** show up in `getfoods.favbuts` — the button list is likely populated elsewhere (mobile); effect unverified.
10. **`delfavfood` param correction** — the JS sends `fav_id` + `obj_id` (not `id`); with `fav_id`+`obj_id` it returns `"Törlés sikerült!"` and the fav is gone from `food_id_2_fav` immediately. Bare `id=` returns `"no_rows"`.
11. **`calcreccal2`** — with a non-recipe id returns `{"zsir":0,"feherje":0,"szen":0,"cal":0}`; only meaningful for recipe ids, and recipe creation is page-flow now (no ajax path to make one), so left at probe level.
12. **`addsizes`** — returns `"Elmentve."` even with no params; the JSON `data` schema for real measurements is not referenced in the desktop JS (mobile-only dialog) — left at probe level.
13. **`getsportme`** — error convention confirmed: unknown id → `err_2678567868` (bare `err_<n>` text).
