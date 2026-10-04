import { useCallback, useState } from 'react';
import { ActivityIndicator, FlatList, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';
import { searchFoods, todayDot, addDiaryFood } from '../lib/api';

/** Food search + one-tap add to diary. The site's search is accent-insensitive
 *  (verified live) but results improve with full word forms. */
export default function Search() {
  const [q, setQ] = useState('');
  const [items, setItems] = useState<any[]>([]);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');

  const run = useCallback(async () => {
    if (!q.trim()) return;
    setBusy(true); setMsg('');
    try {
      const res = await searchFoods(q.trim());
      const found = [...(res?.results2 ?? []), ...(res?.results1 ?? [])];
      setItems(found);
      if (!found.length) setMsg('Nincs találat.');
    } catch (e: any) {
      setMsg(`Hiba: ${e?.message ?? e}`);
    } finally { setBusy(false); }
  }, [q]);

  const add = async (item: any) => {
    setMsg('');
    try {
      // boxme=24 (g) as a safe default quantity unit; adjust in the diary later.
      await addDiaryFood({ date: todayDot(), id: item.nId, quan: '100', boxme: 24, boxdayoftime: 1 });
      setMsg(`Hozzáadva: ${item.sName}`);
    } catch (e: any) {
      setMsg(`Hiba: ${e?.message ?? e}`);
    }
  };

  return (
    <View style={{ flex: 1, padding: 12 }}>
      <View style={{ flexDirection: 'row', gap: 8 }}>
        <TextInput style={st.input} placeholder="pl. tojás, kenyér" value={q} onChangeText={setQ} onSubmitEditing={run} returnKeyType="search" />
        <TouchableOpacity style={st.btn} onPress={run}><Text style={{ color: '#fff', fontWeight: 'bold' }}>Keress</Text></TouchableOpacity>
      </View>
      {busy && <ActivityIndicator style={{ marginTop: 16 }} />}
      {msg ? <Text style={st.msg}>{msg}</Text> : null}
      <FlatList
        data={items}
        keyExtractor={(i) => String(i.nId)}
        renderItem={({ item }) => (
          <TouchableOpacity style={st.row} onPress={() => add(item)}>
            <View style={{ flex: 1 }}>
              <Text style={{ fontWeight: '600' }}>{item.sName}</Text>
              <Text style={st.meta}>{[item.cal, item.carb, item.prot, item.fat].filter(Boolean).join(' · ')}</Text>
            </View>
            <Text style={st.plus}>+</Text>
          </TouchableOpacity>
        )}
      />
    </View>
  );
}
const st = StyleSheet.create({
  input: { flex: 1, borderWidth: 1, borderColor: '#bbb', borderRadius: 8, padding: 10, backgroundColor: '#fff' },
  btn: { backgroundColor: '#2e7d32', paddingHorizontal: 16, borderRadius: 8, justifyContent: 'center' },
  row: { flexDirection: 'row', alignItems: 'center', padding: 12, borderBottomWidth: StyleSheet.hairlineWidth, borderColor: '#ddd' },
  meta: { color: '#777', fontSize: 12 },
  plus: { fontSize: 24, color: '#2e7d32', paddingHorizontal: 8 },
  msg: { color: '#c62828', textAlign: 'center', marginTop: 8 },
});
