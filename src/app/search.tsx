import { useCallback, useState } from 'react';
import {
  Alert,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import {
  DiaryDay,
  MEALS,
  SearchItem,
  SessionExpiredError,
  addFood,
  num,
  searchFood,
} from '../lib/kb';

/** Verified global unit ids (dimobj): 9 darab · 24 g · 25 dkg · 26 kg */
const FOOD_UNITS = [
  { id: 9, label: 'darab' },
  { id: 24, label: 'g' },
  { id: 25, label: 'dkg' },
  { id: 26, label: 'kg' },
];

/** Guess the meal slot from the current hour. */
function slotByHour(): number {
  const h = new Date().getHours();
  if (h < 11) return 1;
  if (h < 14) return 3;
  if (h < 17) return 4;
  if (h < 21) return 5;
  return 6;
}

export default function SearchScreen() {
  const params = useLocalSearchParams<{ date?: string }>();
  const date = params.date ?? '';

  const [q, setQ] = useState('');
  const [items, setItems] = useState<SearchItem[] | null>(null);
  const [favmeals, setFavmeals] = useState<SearchItem[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<SearchItem | null>(null);
  const [quan, setQuan] = useState('100');
  const [unit, setUnit] = useState(FOOD_UNITS[2].id);
  const [slot, setSlot] = useState(() => slotByHour());

  const doSearch = useCallback(
    async (term: string) => {
      if (!term.trim()) return;
      setBusy(true);
      setError(null);
      setSelected(null);
      try {
        const r = await searchFood(term.trim());
        setItems(r.results2 ?? []);
        setFavmeals(r.results1 ?? []);
      } catch (e) {
        if (e instanceof SessionExpiredError) setError('A session lejárt — jelentkezz be újra.');
        else setError(e instanceof Error ? e.message : String(e));
      } finally {
        setBusy(false);
      }
    },
    []
  );

  async function doAdd(item: SearchItem) {
    setBusy(true);
    setError(null);
    try {
      const updated: DiaryDay = await addFood({
        id: item.id,
        boxme: unit,
        quan: Number(quan.replace(',', '.')) || 0,
        date,
        boxdayoftime: slot,
      });
      Alert.alert('Hozzáadva', `${item.name || item.cName} → ${Math.round(num(updated.rfoodsum))} kcal napösszesen`);
      router.back();
    } catch (e) {
      if (e instanceof SessionExpiredError) setError('A session lejárt — jelentkezz be újra.');
      else setError(e instanceof Error ? e.message : String(e));
      setBusy(false);
    }
  }

  return (
    <ScrollView style={s.wrap} contentContainerStyle={s.content} keyboardShouldPersistTaps="handled">
      <View style={s.searchRow}>
        <TextInput
          style={s.input}
          placeholder="pl. tojás, kenyér, alma"
          value={q}
          onChangeText={setQ}
          onSubmitEditing={() => void doSearch(q)}
          returnKeyType="search"
        />
        <Pressable style={s.go} onPress={() => void doSearch(q)} disabled={busy}>
          <Text style={s.goText}>{busy ? '…' : 'Keresés'}</Text>
        </Pressable>
      </View>

      {error ? <Text style={s.err}>{error}</Text> : null}

      {favmeals.length > 0 ? (
        <>
          <Text style={s.section}>Kedvencek</Text>
          {favmeals.map((it) => (
            <View key={`fav-${it.id}`} style={s.item}>
              <Text style={s.itemName}>⭐ {String(it.name || it.cName || 'kedvenc étel')}</Text>
              <Text style={s.itemSub}>kedvenc étel — hozzáadás a weben</Text>
            </View>
          ))}
        </>
      ) : null}

      {items?.length ? (
        <>
          <Text style={s.section}>Ételek</Text>
          {items.map((it) =>
            selected?.id === it.id ? (
              <View key={it.id} style={s.editor}>
                <Text style={s.itemName}>{String(it.name || it.cName || '?')}</Text>
                <View style={s.units}>
                  {FOOD_UNITS.map((u) => (
                    <Pressable
                      key={u.id}
                      style={[s.chip, unit === u.id && s.chipOn]}
                      onPress={() => setUnit(u.id)}
                    >
                      <Text style={unit === u.id ? s.chipTextOn : s.chipText}>{u.label}</Text>
                    </Pressable>
                  ))}
                </View>
                <View style={s.units}>
                  {MEALS.map((m) => (
                    <Pressable
                      key={m.id}
                      style={[s.chip, slot === m.id && s.chipOn]}
                      onPress={() => setSlot(m.id)}
                    >
                      <Text style={slot === m.id ? s.chipTextOn : s.chipText}>{m.label}</Text>
                    </Pressable>
                  ))}
                </View>
                <View style={s.addRow}>
                  <TextInput style={s.quan} keyboardType="numbers-and-punctuation" value={quan} onChangeText={setQuan} />
                  <Text style={s.unitHint}>{FOOD_UNITS.find((u) => u.id === unit)?.label}</Text>
                  <Pressable style={s.addBtn} disabled={busy} onPress={() => void doAdd(it)}>
                    <Text style={s.addText}>{busy ? '…' : 'Hozzáadás'}</Text>
                  </Pressable>
                </View>
              </View>
            ) : (
              <Pressable key={it.id} style={s.item} onPress={() => { setSelected(it); setQuan('100'); }}>
                <Text style={s.itemName}>{String(it.name || it.cName || '?')}</Text>
                <Text style={s.itemSub}>
                  {[it.piece && it.piece !== '100 g' ? it.piece : '', it.cal || it.kcal_and_unit || '']
                    .filter(Boolean)
                    .join(' · ') || 'részletek'}
                </Text>
              </Pressable>
            )
          )}
        </>
      ) : items && items.length === 0 ? (
        <Text style={s.empty}>Nincs találat.</Text>
      ) : null}
    </ScrollView>
  );
}

const s = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: '#fff' },
  content: { padding: 16, gap: 4 },
  searchRow: { flexDirection: 'row', gap: 8 },
  input: { flex: 1, borderWidth: 1, borderColor: '#ccc', borderRadius: 8, paddingHorizontal: 12, paddingVertical: 10, fontSize: 16 },
  go: { backgroundColor: '#2f6f4f', borderRadius: 8, paddingHorizontal: 16, justifyContent: 'center' },
  goText: { color: '#fff', fontWeight: '600' },
  section: { fontWeight: '700', color: '#2f6f4f', marginTop: 12 },
  item: { paddingVertical: 10, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: '#eee' },
  itemName: { fontSize: 15 },
  itemSub: { fontSize: 12, color: '#888' },
  editor: { marginVertical: 8, padding: 12, borderRadius: 8, backgroundColor: '#f4f8f5', gap: 10 },
  units: { flexDirection: 'row', flexWrap: 'wrap', gap: 6 },
  chip: { borderWidth: 1, borderColor: '#bbb', borderRadius: 16, paddingHorizontal: 12, paddingVertical: 5 },
  chipOn: { backgroundColor: '#2f6f4f', borderColor: '#2f6f4f' },
  chipText: { color: '#333', fontSize: 13 },
  chipTextOn: { color: '#fff', fontSize: 13 },
  addRow: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  quan: { width: 90, borderWidth: 1, borderColor: '#ccc', borderRadius: 8, paddingHorizontal: 10, paddingVertical: 8, fontSize: 16 },
  unitHint: { color: '#555', width: 40 },
  addBtn: { flex: 1, backgroundColor: '#2f6f4f', borderRadius: 8, paddingVertical: 10, alignItems: 'center' },
  addText: { color: '#fff', fontWeight: '600' },
  err: { color: '#b00020', marginTop: 8 },
  empty: { textAlign: 'center', color: '#999', padding: 24 },
});
