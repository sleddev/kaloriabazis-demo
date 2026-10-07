import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/kb_client.dart';
import '../api/models.dart';

enum AuthStatus { unknown, loggedOut, loggedIn }

DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// App-wide state: session, the diary-day cache and user settings.
class AppState extends ChangeNotifier {
  AppState({KbClient? client}) : kb = client ?? KbClient();

  final KbClient kb;
  final _secure = const FlutterSecureStorage();
  SharedPreferences? _prefs;

  AuthStatus status = AuthStatus.unknown;
  String nick = '';

  /// Shown on the login screen after an automatic logout.
  String? authNotice;

  int goal = 2000;
  bool goalFromServer = false;
  double? weight;
  ThemeMode themeMode = ThemeMode.system;

  DateTime selectedDate = dayOnly(DateTime.now());
  final Map<DateTime, DiaryDay> _days = {};
  final Set<DateTime> _loading = {};
  String? dayError;

  DiaryDay? dayFor(DateTime d) => _days[dayOnly(d)];
  bool isLoading(DateTime d) => _loading.contains(dayOnly(d));
  DiaryDay? get today => dayFor(selectedDate);

  /// Most recently fetched list of recent foods.
  List<RecentFood> recent = const [];

  // ---------------------------------------------------------------------------
  // Session
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    goal = _prefs!.getInt('goal') ?? goal;
    themeMode = ThemeMode.values[_prefs!.getInt('theme') ?? 0];
    final sid = await _secure.read(key: 'sid');
    nick = await _secure.read(key: 'nick') ?? '';
    if (sid == null) {
      status = AuthStatus.loggedOut;
      notifyListeners();
      return;
    }
    kb.cookies['myPHP83SESSID'] = sid;
    // Optimistically show the app; a dead session flips back to login on
    // the first request.
    status = AuthStatus.loggedIn;
    notifyListeners();
    _afterLogin(validate: true);
  }

  Future<void> login(String user, String password) async {
    nick = await kb.login(user.trim(), password);
    await _secure.write(key: 'sid', value: kb.cookies['myPHP83SESSID']);
    await _secure.write(key: 'nick', value: nick);
    authNotice = null;
    _days.clear();
    selectedDate = dayOnly(DateTime.now());
    status = AuthStatus.loggedIn;
    notifyListeners();
    _afterLogin();
  }

  Future<void> _afterLogin({bool validate = false}) async {
    try {
      if (validate) {
        final n = await kb.checkSession();
        if (n == null) throw SessionExpired();
        if (n.isNotEmpty && n != nick) {
          nick = n;
          await _secure.write(key: 'nick', value: n);
        }
      }
      await loadDay(selectedDate);
      final g = await kb.getDailyGoal();
      if (g != null) {
        goal = g;
        goalFromServer = true;
        await _prefs?.setInt('goal', g);
      }
      notifyListeners();
      weight = await kb.getWeight(DateTime.now());
      notifyListeners();
      await prefetchWeek();
    } on SessionExpired {
      await _expire();
    } catch (_) {
      // Non-fatal: the screens show their own errors on retry.
    }
  }

  Future<void> logout() async {
    try {
      await kb.logout();
    } catch (_) {}
    await _expire(notice: null);
  }

  Future<void> _expire({
    String? notice = 'A munkamenet lejárt — jelentkezz be újra.',
  }) async {
    kb.clearSession();
    await _secure.delete(key: 'sid');
    _days.clear();
    authNotice = notice;
    status = AuthStatus.loggedOut;
    notifyListeners();
  }

  /// Runs an API call, routing an expired session to the login screen.
  Future<T> guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on SessionExpired {
      await _expire();
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Diary
  // ---------------------------------------------------------------------------

  void selectDate(DateTime d) {
    selectedDate = dayOnly(d);
    notifyListeners();
    loadDay(selectedDate).then((_) => prefetchWeek());
  }

  /// Fills the week strip's mini rings: loads the other (past) days of the
  /// selected week, one by one through the paced client.
  Future<void> prefetchWeek() async {
    final monday = selectedDate.subtract(
      Duration(days: selectedDate.weekday - 1),
    );
    final today = dayOnly(DateTime.now());
    for (var i = 0; i < 7; i++) {
      final d = monday.add(Duration(days: i));
      if (d.isAfter(today) || _days.containsKey(d)) continue;
      if (status != AuthStatus.loggedIn) return;
      await loadDay(d);
    }
  }

  Future<DiaryDay?> loadDay(DateTime d, {bool force = false}) async {
    final key = dayOnly(d);
    if (!force && (_days.containsKey(key) || _loading.contains(key))) {
      return _days[key];
    }
    _loading.add(key);
    dayError = null;
    notifyListeners();
    try {
      final day = await guard(() => kb.getDay(key));
      _store(day);
      return day;
    } on KbException catch (e) {
      if (key == selectedDate) dayError = e.message;
      return null;
    } finally {
      _loading.remove(key);
      notifyListeners();
    }
  }

  void _store(DiaryDay day) {
    _days[dayOnly(day.date)] = day;
    if (day.recent.isNotEmpty) recent = day.recent;
    notifyListeners();
  }

  Future<DiaryDay> addFood({
    required String foodRef,
    required int unitId,
    required double quantity,
    required Meal meal,
    DateTime? date,
  }) async {
    final day = await guard(
      () => kb.addFood(
        date: date ?? selectedDate,
        foodRef: foodRef,
        unitId: unitId,
        quantity: quantity,
        meal: meal,
      ),
    );
    _store(day);
    return day;
  }

  Future<void> editEntry(
    DiaryEntry e, {
    required String foodId,
    required int unitId,
    required double quantity,
    required Meal meal,
  }) async {
    _store(
      await guard(
        () => kb.editEntry(
          date: selectedDate,
          entry: e,
          foodId: foodId,
          unitId: unitId,
          quantity: quantity,
          meal: meal,
        ),
      ),
    );
  }

  Future<void> deleteEntry(DiaryEntry e) async {
    // Optimistic: hide the row right away, then take the server's day.
    final cur = today;
    if (cur != null) {
      _days[selectedDate] = DiaryDay(
        date: cur.date,
        entries: cur.entries.where((x) => x.id != e.id).toList(),
        totals: Macros(
          cur.totals.kcal - e.macros.kcal,
          cur.totals.protein - e.macros.protein,
          cur.totals.carbs - e.macros.carbs,
          cur.totals.fat - e.macros.fat,
        ),
        recent: cur.recent,
        pics: cur.pics,
      );
      notifyListeners();
    }
    try {
      _store(await guard(() => kb.deleteEntry(selectedDate, e.id)));
    } catch (_) {
      if (cur != null) _store(cur);
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------------

  Future<void> setGoal(int kcal) async {
    await guard(() => kb.setDailyGoal(kcal));
    goal = kcal;
    goalFromServer = true;
    await _prefs?.setInt('goal', kcal);
    notifyListeners();
  }

  Future<void> setWeight(double kg) async {
    await guard(() => kb.setWeight(DateTime.now(), kg));
    weight = kg;
    notifyListeners();
  }

  void setThemeMode(ThemeMode m) {
    themeMode = m;
    _prefs?.setInt('theme', m.index);
    notifyListeners();
  }
}

/// Makes [AppState] available to the widget tree.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Access without subscribing to rebuilds (for callbacks).
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
