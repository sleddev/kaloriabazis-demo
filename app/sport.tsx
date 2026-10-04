import { useCallback, useState } from 'react';
import { ActivityIndicator, FlatList, StyleSheet, Text, TextInput, TouchableOpacity, View } from 'react-native';
import { addSport, searchSports, todayDot } from '../lib/api';

/** Sport search + add. NOTE: the sport search is ACCENT-SENSITIVE (verified
 *  live): 'fut' finds nothing, 'futás' does. Hint shown to the user. */
export default function Sport() {
  const [q, setQ] = useState('');
  const [items, setItems] = useState<any[]>([]);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState('');

  const run = useCallback(async () => {
    if (!q.trim()) return;
    setBusy(true); setMsg('');
    try {
      const res = await searchSports(q.trim(), todayDot());
      setItems(res?.results ?? []);
      if (!res?.results?.length) setMsg('Nincs találat. (A keresés ékezetérzékeny — próbáld "futás" formában.)');
    } catch (e: any) {
      setMsg(`Hiba: ${e?.message ?? e}`);
    } finally { setBusy(false); }
  }, [q]);

  const add = async (item: any) => {
    setMsg('');
    try {
      const [id, type] = String(item.id ?? '').split('_');
      await addSport({ date: todayDot(), id, quan: '1' });
      setMsg(`Hozzáadva: ${item.name}`);
    } catch (e: any) {
      setMsg(`Hiba: ${e?.message ?? e}`);
    }
  };

  return (
    <View style={{ flex: 1, padding: 12 }}>
      <View style={{ flexDirection: 'row', gap: 8 }}>
        <TextInput style={st.input} placeholder="pl. futás (ékezetekkel!)" value={q} onChangeText={setQ} onSubmitEditing={run} returnKeyType="search" />
        <TouchableOpacity style={st.btn} onPress={run}><Text style={{ color: '#fff', fontWeight: 'bold' }}>Keress</Text></TouchableOpacity>
      </View>
      {busy && <ActivityIndicator style={{ marginTop: 16 }} />}
      {msg ? <Text style={st.msg}>{msg}</Text> : null}
      <FlatList
        data={items}
        keyExtractor={(i) => String(i.id)}
        renderItem={({ item }) => (
          <TouchableOpacity style={st.row} onPress={() => add(item)}>
            <View style={{ flex: 1 }}>
              <Text style={{ fontWeight: '600' }}>{item.name}</Text>
              <Text style={st.meta}>{[item.piece, item.cal].filter(Boolean).join(' · ')}</Text>
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
  btn: { backgroundColor: '#1565c0', paddingHorizontal: 16, borderRadius: 8, justifyContent: 'center' },
  row: { flexDirection: 'row', alignItems: 'center', padding: 12, borderBottomWidth: StyleSheet.hairlineWidth, borderColor: '#ddd' },
  meta: { color: '#777', fontSize: 12 },
  plus: { fontSize: 24, color: '#1565c0', paddingHorizontal: 8 },
  msg: { color: '#c62828', textAlign: 'center', marginTop: 8 },
});
