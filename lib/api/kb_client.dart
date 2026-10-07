/// Client for the kaloriabazis.hu web API (see `Kaloriabazis API Report.md`).
///
/// Facts the client relies on, all verified live:
///  - Auth is a PHP session cookie (`myPHP83SESSID`). We keep our own cookie
///    jar and send it as a `Cookie` header, following redirects manually so
///    no `Set-Cookie` is lost.
///  - Requests must look like the real frontend (browser User-Agent,
///    `X-Requested-With`, a plausible `Referer`), otherwise the server answers
///    `die_with_text arjrjkrk`.
///  - Bursts trip a tarpit (connection accepted, no response). All requests
///    go through a serial token-bucket limiter.
///  - Expired sessions: `###TIMEOUT###` in text, or
///    `{"type":"1","error":"Nem vagy bejelentkezve!"}` in JSON.
///  - Diary dates use the dot format (`2026.10.07`).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

const kBase = 'https://kaloriabazis.hu';
const _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';
const _diaryReferer = '$kBase/naplo';

class KbException implements Exception {
  KbException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SessionExpired extends KbException {
  SessionExpired() : super('A munkamenet lejárt — jelentkezz be újra.');
}

class GuardBlocked extends KbException {
  GuardBlocked() : super('A szerver blokkolta a kérést (arjrjkrk).');
}

class LoginFailed extends KbException {
  LoginFailed() : super('Hibás felhasználónév vagy jelszó.');
}

/// Serial token bucket: up to [burst] quick calls, then one per [refill].
class _Pacer {
  static const burst = 4;
  static const refill = Duration(milliseconds: 1800);

  late double _tokens = burst.toDouble();
  DateTime _last = DateTime.now();
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then((_) async {
      await _take();
      return task();
    });
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _take() async {
    final now = DateTime.now();
    _tokens =
        (_tokens + now.difference(_last).inMilliseconds / refill.inMilliseconds)
            .clamp(0, burst.toDouble());
    _last = now;
    if (_tokens < 1) {
      final waitMs = ((1 - _tokens) * refill.inMilliseconds).ceil();
      await Future.delayed(Duration(milliseconds: waitMs));
      _tokens = 1;
      _last = DateTime.now();
    }
    _tokens -= 1;
  }
}

String dotDate(DateTime d) =>
    '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

class KbClient {
  KbClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final _pacer = _Pacer();

  /// Cookie jar. The anonymous cookies are constant site preferences.
  final Map<String, String> cookies = {
    'LANGID': '1',
    'CLANGCODE': 'HU',
    'UNITLANGID': '1',
    'BWEIGHT_UNIT': '1',
    'BHEIGHT_UNIT': '1',
    'mob_for_a': '0',
  };

  bool get hasSession => cookies.containsKey('myPHP83SESSID');

  void clearSession() => cookies.remove('myPHP83SESSID');

  // ---------------------------------------------------------------------------
  // Plumbing
  // ---------------------------------------------------------------------------

  static final _cookieRe = RegExp(r'(?:^|,\s*)([A-Za-z0-9_\-]+)=([^;,]*)');

  void _absorbCookies(http.BaseResponse res) {
    final raw = res.headers['set-cookie'];
    if (raw == null) return;
    for (final m in _cookieRe.allMatches(raw)) {
      final name = m.group(1)!;
      final value = m.group(2)!;
      // Ignore attribute look-alikes that can follow a comma in `expires`.
      // `mob_for_a` is pinned: a mobile-flagged session makes some endpoints
      // (e.g. getdaily) answer `{"type":"1"}`.
      if (const {
        'expires',
        'path',
        'domain',
        'Max-Age',
        'SameSite',
        'mob_for_a',
      }.contains(name)) {
        continue;
      }
      if (value.isEmpty || value == 'deleted') {
        cookies.remove(name);
      } else {
        cookies[name] = value;
      }
    }
  }

  Future<String> _send(
    String path, {
    String referer = _diaryReferer,
    Map<String, String>? form,
    bool ajax = true,
  }) {
    return _pacer.run(() async {
      var uri = Uri.parse(path.startsWith('http') ? path : '$kBase$path');
      var method = form == null ? 'GET' : 'POST';
      var body = form;
      for (var hop = 0; hop < 6; hop++) {
        final req = http.Request(method, uri)
          ..followRedirects = false
          ..headers.addAll({
            'User-Agent': _userAgent,
            'Referer': referer,
            'Cookie': cookies.entries
                .map((e) => '${e.key}=${e.value}')
                .join('; '),
            if (ajax) 'X-Requested-With': 'XMLHttpRequest',
          });
        if (body != null) req.bodyFields = body;
        final http.StreamedResponse res;
        try {
          res = await _http.send(req).timeout(const Duration(seconds: 25));
        } on TimeoutException {
          throw KbException(
            'A szerver nem válaszol. Lehet, hogy túl sok kérés ment ki — '
            'próbáld újra pár perc múlva.',
          );
        } on Exception catch (e) {
          throw KbException('Hálózati hiba: $e');
        }
        _absorbCookies(res);
        if (res.isRedirect && res.headers['location'] != null) {
          await res.stream.drain<void>();
          uri = uri.resolve(res.headers['location']!);
          method = 'GET';
          body = null;
          continue;
        }
        final text = await res.stream.bytesToString();
        if (res.statusCode >= 400) {
          throw KbException('Szerverhiba (${res.statusCode}).');
        }
        if (text.trim() == 'die_with_text arjrjkrk') throw GuardBlocked();
        return text;
      }
      throw KbException('Túl sok átirányítás.');
    });
  }

  void _assertSession(String text) {
    if (text.contains('###TIMEOUT###') ||
        text.contains('Nem vagy bejelentkezve')) {
      clearSession();
      throw SessionExpired();
    }
  }

  Future<dynamic> _json(String path, {String referer = _diaryReferer}) async {
    final text = await _send(path, referer: referer);
    _assertSession(text);
    final t = text.trim();
    if (!t.startsWith('{') && !t.startsWith('[')) {
      throw KbException(
        'Váratlan válasz: ${t.length > 80 ? t.substring(0, 80) : t}',
      );
    }
    return jsonDecode(t);
  }

  static String _qs(Map<String, Object> p) => p.entries
      .map((e) => '${e.key}=${Uri.encodeQueryComponent('${e.value}')}')
      .join('&');

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  /// The logout link only renders for a logged-in user. (The bare word
  /// "Kijelentkez" also appears in the anonymous page's scripts.)
  static final _loggedInRe = RegExp(r'href="[^"]*kijelentkezes');
  static final _nickRe = RegExp(r'<span class="nick">\s*([^<]*?)\s*</span>');

  /// Nickname of the logged-in user, or null if [html] is an anonymous page.
  static String? _nickFrom(String html) {
    if (!_loggedInRe.hasMatch(html)) return null;
    return _nickRe.firstMatch(html)?.group(1) ?? '';
  }

  /// Warm-up → homepage (CSRF `myt`) → POST /bejelentkezes.
  /// Returns the user's nickname.
  Future<String> login(String user, String password) async {
    clearSession();
    await _send('/fooldal', referer: '$kBase/', ajax: false);
    final home = await _send('/', referer: '$kBase/', ajax: false);
    final m =
        RegExp(r'''id=["']myt["'][^>]*value=["']([^"']+)''').firstMatch(home) ??
        RegExp(r'''value=["']([^"']+)["'][^>]*id=["']myt["']''')
            .firstMatch(home);
    if (m == null) throw KbException('Nem található a bejelentkezési űrlap.');
    final page = await _send(
      '/bejelentkezes',
      referer: '$kBase/',
      ajax: false,
      form: {
        'mode': 'get',
        'myt': m.group(1)!,
        'txtusern': user,
        'txtpassw': password,
      },
    );
    final nick = _nickFrom(page);
    if (nick == null) {
      clearSession();
      throw LoginFailed();
    }
    return nick.isEmpty ? user : nick;
  }

  /// Checks a restored session by rendering the diary page.
  /// Returns the nickname, or null when the session is no longer valid.
  Future<String?> checkSession() async {
    if (!hasSession) return null;
    final nick = _nickFrom(
      await _send('/naplo', referer: '$kBase/', ajax: false),
    );
    if (nick == null) clearSession();
    return nick;
  }

  Future<void> logout() async {
    try {
      await _send('/kijelentkezes', referer: _diaryReferer, ajax: false);
    } finally {
      clearSession();
    }
  }

  // ---------------------------------------------------------------------------
  // Diary
  // ---------------------------------------------------------------------------

  Future<DiaryDay> _day(DateTime date, Map<String, Object> params) async {
    final j = await _json('/food.php?${_qs({...params, 'return_json': 1})}');
    if (j is! Map<String, dynamic>) throw KbException('Hibás napló válasz.');
    return DiaryDay.fromJson(date, j);
  }

  Future<DiaryDay> getDay(DateTime date) =>
      _day(date, {'show': 'getfoods', 'date': dotDate(date)});

  Future<DiaryDay> addFood({
    required DateTime date,
    required String foodRef,
    required int unitId,
    required double quantity,
    required Meal meal,
  }) => _day(date, {
    'show': 'addfood',
    'id': foodRef,
    'boxme': unitId,
    'quan': _numStr(quantity),
    'date': dotDate(date),
    'boxdayoftime': meal.id,
  });

  Future<DiaryDay> editEntry({
    required DateTime date,
    required DiaryEntry entry,
    required String foodId,
    required int unitId,
    required double quantity,
    required Meal meal,
  }) => _day(date, {
    'show': 'savemodeitemfood',
    'plusminus': 0,
    'boxme': unitId,
    'boxdayoftimemod': meal.id,
    'quan': _numStr(quantity),
    'id': entry.id,
    'date': dotDate(date),
    'hour_min': -1,
    'getmenew_food_id': foodId,
  });

  Future<DiaryDay> deleteEntry(DateTime date, String entryId) =>
      _day(date, {'show': 'delfood', 'id': entryId, 'date': dotDate(date)});

  // ---------------------------------------------------------------------------
  // Foods
  // ---------------------------------------------------------------------------

  Future<SearchPage> search(String q, {int page = 1, int size = 20}) async {
    final j = await _json(
      '/getfood.php?${_qs({'q': q, 'p': page, 's': size})}',
    );
    if (j is! Map<String, dynamic>) return SearchPage(0, []);
    final pics = PicRef.mapOf(j['food_id_2_pic_id']);
    final hits = [
      for (final r in (j['results2'] as List?) ?? const [])
        if (r is Map<String, dynamic>) FoodHit.fromJson(r, pics),
    ];
    return SearchPage(intOf(j['total2']), hits);
  }

  Future<FoodInfo> foodInfo(String foodRef) async {
    final j = await _json(
      '/food.php?${_qs({'show': 'getmenew', 'id': foodRef})}',
    );
    if (j is! Map<String, dynamic>) throw KbException('Nincs adat az ételhez.');
    return FoodInfo.fromJson(j);
  }

  /// Server-side calculation, for units without a known gram weight.
  Future<Macros> calcFood(String foodRef, int unitId, double qty) async {
    final j = await _json(
      '/food.php?${_qs({'show': 'calcfooddetail', 'id': foodRef, 'boxme': unitId, 'quan': _numStr(qty)})}',
    );
    if (j is! Map) return Macros.zero;
    return Macros(
      numOf(j['cal']),
      numOf(j['feherje']),
      numOf(j['szen']),
      numOf(j['zsir']),
    );
  }

  // ---------------------------------------------------------------------------
  // Goals & body
  // ---------------------------------------------------------------------------

  /// Daily calorie limit, or null when the user hasn't set one.
  Future<int?> getDailyGoal() async {
    final j = await _json('/food.php?show=getdaily');
    if (j is Map && j.length == 1 && '${j['type']}' == '1') {
      clearSession();
      throw SessionExpired();
    }
    if (j is Map && intOf(j['boxdailySet']) == 1) {
      final v = intOf(j['txtdailyquan']);
      return v > 0 ? v : null;
    }
    return null;
  }

  Future<void> setDailyGoal(int kcal) async {
    final t = await _send(
      '/food.php?${_qs({'show': 'setDaily', 'boxdaily': 1, 'boxdailytype': 1, 'dailyquan': kcal})}',
    );
    _assertSession(t);
  }

  /// Latest body weight in kg (from the metrics form), or null.
  Future<double?> getWeight(DateTime date) async {
    final t = await _send(
      '/food.php?${_qs({'show': 'getmetrics', 'date': dotDate(date)})}',
    );
    _assertSession(t);
    final m = RegExp(r"weight_and_height_w'\s+value='([0-9.,]*)'")
        .firstMatch(t);
    final v = numOf(m?.group(1));
    return v > 0 ? v : null;
  }

  Future<void> setWeight(DateTime date, double kg) async {
    final t = await _send(
      '/food.php?${_qs({'show': 'addweight', 'date': dotDate(date), 'weight': _numStr(kg)})}',
    );
    _assertSession(t);
  }

  static String _numStr(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}
