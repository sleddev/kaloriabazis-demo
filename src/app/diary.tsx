import { useCallback, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { router, useFocusEffect } from 'expo-router';
import {
  DiaryEntry,
  DiaryDay,
  MEALS,
  SessionExpiredError,
  delFood,
  getDay,
  isStat,
  logout,
  num,
  unitLabel,
  shiftDots,
  todayDots,
} from '../lib/kb';

export default function DiaryScreen() {
  const [date, setDate] = useState(() => todayDots());
  const [day, setDay] = useState<DiaryDay | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const reload = useCallback(
    async (d: string) => {
      setBusy(true);
      setError(null);
      try {
        setDay(await getDay(d));
      } catch (e) {
        if (e instanceof SessionExpiredError) {
          setDay(null);
          setError('A session lejárt — jelentkezz be újra.');
        } else {
          setError(e instanceof Error ? e.message : String(e));
        }
      } finally {
        setBusy(false);
      }
    },
    []
  );

  useFocusEffect(
    useCallback(() => {
      void reload(date);
      // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [date])
  );

  function changeDate(delta: number) {
    const nd = shiftDots(date, delta);
    setDate(nd);
    void reload(nd);
  }

  function confirmDelete(e: DiaryEntry) {
    Alert.alert('Törlés', `${e.syn_name || e.f_name || '?'} törlése?`, [
      { text: 'Mégse', style: 'cancel' },
      {
        text: 'Törlés',
        style: 'destructive',
        onPress: () => {
          void delFood(e.nID, date)
            .then((d) => setDay(d))
            .catch((err) => setError(err instanceof Error ? err.message : String(err)));
        },
      },
    ]);
  }

  const totals = day
    ? { kcal: num(day.rfoodsum), p: num(day.rfoodsumProtein), c: num(day.rfoodsumCarbo), f: num(day.rfoodsumFat) }
    : null;

  return (
    <ScrollView
      style={s.wrap}
      refreshControl={<RefreshControl refreshing={busy} onRefresh={() => void reload(date)} />}
    >
      <View style={s.daterow}>
        <Pressable onPress={() => changeDate(-1)} style={s.arrow}>
          <Text style={s.arrowText}>◀</Text>
        </Pressable>
        <Text style={s.date}>{date}</Text>
        <Pressable onPress={() => changeDate(1)} style={s.arrow}>
          <Text style={s.arrowText}>▶</Text>
        </Pressable>
      </View>

      {totals ? (
        <View style={s.totals}>
          <Text style={s.totKcal}>{Math.round(totals.kcal)} kcal</Text>
          <Text style={s.totMacros}>
            P {Math.round(totals.p)} g · SzC {Math.round(totals.c)} g · Zsír {Math.round(totals.f)} g
          </Text>
        </View>
      ) : null}

      {error ? (
        <View style={s.errBox}>
          <Text style={s.err}>{error}</Text>
          <Pressable style={s.mini} onPress={() => router.replace('/')}>
            <Text style={s.miniText}>Bejelentkezés</Text>
          </Pressable>
        </View>
      ) : null}

      {MEALS.map((meal) => {
        const rows = (day?.results || []).filter(
          (r) => num(r.nDayoftimeRef) === meal.id
        );
        const entries = rows.filter((r) => !isStat(r)) as DiaryEntry[];
        const stat = rows.find((r) => isStat(r));
        if (entries.length === 0 && !stat) return null;
        return (
          <View key={meal.id} style={s.meal}>
            <Text style={s.mealName}>
              {meal.label}
              {stat ? <Text style={s.mealKcal}> · {Math.round(num(stat.nCalorie))} kcal</Text> : null}
            </Text>
            {entries.map((e) => (
              <Pressable key={String(e.nID)} style={s.row} onPress={() => confirmDelete(e)}>
                <View style={s.rowMain}>
                  <Text style={s.rowName}>{(e.syn_name || e.f_name || e.cDisplayName || '?').trim()}</Text>
                  <Text style={s.rowSub}>
                    {[String(e.nQuantity ?? '').replace(/\.00$/, ''), unitLabel(e.unitDisplayName), e.hour_min ? `· ${e.hour_min}` : '']
                      .filter(Boolean)
                      .join(' ')}
                  </Text>
                </View>
                <Text style={s.rowKcal}>{Math.round(num(e.nCalorie))} kcal</Text>
              </Pressable>
            ))}
          </View>
        );
      })}

      {day && (day.results || []).length === 0 ? (
        <Text style={s.empty}>Üres nap (ha ez nem stimmel, jelentkezz be újra).</Text>
      ) : null}

      <View style={s.actions}>
        <Pressable
          style={s.btn}
          onPress={() => router.push({ pathname: '/search', params: { date } })}
        >
          <Text style={s.btnText}>Étel keresés</Text>
        </Pressable>
        <Pressable
          style={[s.btn, s.btnAlt]}
          onPress={() => router.push({ pathname: '/sport', params: { date } })}
        >
          <Text style={s.btnText}>Sport</Text>
        </Pressable>
      </View>

      <Pressable style={s.linkBtn} onPress={() => { logout(); router.replace('/'); }}>
        <Text style={s.linkText}>Kijelentkezés</Text>
      </Pressable>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: '#fff' },
  daterow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', padding: 12, gap: 16 },
  arrow: { padding: 8 },
  arrowText: { fontSize: 18 },
  date: { fontSize: 17, fontWeight: '600' },
  totals: { alignItems: 'center', paddingBottom: 4 },
  totKcal: { fontSize: 24, fontWeight: '700' },
  totMacros: { fontSize: 13, color: '#666' },
  meal: { paddingHorizontal: 16, paddingTop: 12 },
  mealName: { fontSize: 15, fontWeight: '700', color: '#2f6f4f' },
  mealKcal: { color: '#888', fontWeight: '400' },
  row: { flexDirection: 'row', alignItems: 'center', paddingVertical: 8, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: '#eee' },
  rowMain: { flex: 1 },
  rowName: { fontSize: 15 },
  rowSub: { fontSize: 12, color: '#888' },
  rowKcal: { fontSize: 14, fontWeight: '600', color: '#333' },
  empty: { textAlign: 'center', color: '#999', padding: 24 },
  errBox: { margin: 16, padding: 12, borderRadius: 8, backgroundColor: '#fdecea', gap: 8 },
  err: { color: '#b00020' },
  actions: { flexDirection: 'row', gap: 10, padding: 16 },
  btn: { flex: 1, backgroundColor: '#2f6f4f', borderRadius: 8, paddingVertical: 12, alignItems: 'center' },
  btnAlt: { backgroundColor: '#345' },
  btnText: { color: '#fff', fontWeight: '600' },
  mini: { alignSelf: 'flex-start', borderWidth: 1, borderColor: '#b00020', borderRadius: 6, paddingHorizontal: 10, paddingVertical: 4 },
  miniText: { color: '#b00020', fontSize: 13 },
  linkBtn: { alignItems: 'center', padding: 16 },
  linkText: { color: '#888' },
});
