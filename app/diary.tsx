import { useCallback, useEffect, useState } from 'react';
import { Alert, FlatList, StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { useRouter } from 'expo-router';
import { addDiaryFood, deleteDiaryFood, getDiaryDay, todayDot } from '../lib/api';

/** Rows of the day object. The day payload mixes foods and sport entries;
 *  we render both, with a delete button on each (ids verified live). */
interface Row { id: string | number; label: string; kcal: string; kind: 'food' | 'sport' }

function rowsOf(day: any): Row[] {
  const rows: Row[] = [];
  const foods = day?.rfoods ?? day?.rfood ?? day?.foods ?? [];
  for (const f of Array.isArray(foods) ? foods : []) {
    rows.push({ id: f.nID ?? f.nId ?? f.id, label: f.sName ?? f.name ?? '?', kcal: String(f.cal ?? f.kcal ?? ''), kind: 'food' });
  }
  const sports = day?.rsports ?? day?.sports ?? [];
  for (const f of Array.isArray(sports) ? sports : []) {
    rows.push({ id: f.nID ?? f.nId ?? f.id, label: `🏃 ${f.sName ?? f.name ?? '?'}`, kcal: String(f.cal ?? ''), kind: 'sport' });
  }
  return rows;
}

export default function Diary() {
  const router = useRouter();
  const [date] = useState(todayDot());
  const [rows, setRows] = useState<Row[]>([]);
  const [msg, setMsg] = useState('');

  const load = useCallback(async () => {
    try {
      const day = await getDiaryDay(date);
      setRows(rowsOf(day));
      setMsg(rows.length ? '' : 'Nincs bejegyzés erre a napra.');
    } catch (e: any) {
      setMsg(`Hiba: ${e?.message ?? e}`);
    }
  }, [date]);

  useEffect(() => { load(); }, [load]);

  const del = (r: Row) =>
    Alert.alert('Törlés', `${r.label} törlése?`, [
      { text: 'Mégse', style: 'cancel' },
      { text: 'Törlés', style: 'destructive', onPress: async () => { await deleteDiaryFood(date, Number(r.id)); load(); } },
    ]);

  return (
    <View style={{ flex: 1, padding: 12 }}>
      <View style={{ flexDirection: 'row', gap: 8, marginBottom: 12 }}>
        <TouchableOpacity style={st.btn} onPress={() => router.push({ pathname: '/search' })}>
          <Text style={st.btnText}>+ Étel</Text>
        </TouchableOpacity>
        <TouchableOpacity style={[st.btn, { backgroundColor: '#1565c0' }]} onPress={() => router.push({ pathname: '/sport' })}>
          <Text style={st.btnText}>+ Sport</Text>
        </TouchableOpacity>
      </View>
      <FlatList
        data={rows}
        keyExtractor={(r) => `${r.kind}-${r.id}`}
        renderItem={({ item }) => (
          <TouchableOpacity style={st.row} onLongPress={() => del(item)}>
            <Text style={{ flex: 1 }}>{item.label}</Text>
            <Text style={st.kcal}>{item.kcal} kcal</Text>
          </TouchableOpacity>
        )}
        ListEmptyComponent={<Text style={{ textAlign: 'center', marginTop: 32, color: '#777' }}>{msg}</Text>}
      />
    </View>
  );
}
const st = StyleSheet.create({
  btn: { backgroundColor: '#2e7d32', padding: 10, borderRadius: 8, flex: 1, alignItems: 'center' },
  btnText: { color: '#fff', fontWeight: 'bold' },
  row: { flexDirection: 'row', padding: 12, borderBottomWidth: StyleSheet.hairlineWidth, borderColor: '#ddd', alignItems: 'center' },
  kcal: { color: '#666', marginLeft: 8 },
});
