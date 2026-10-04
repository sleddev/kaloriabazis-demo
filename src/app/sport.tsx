import { useCallback, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { router, useLocalSearchParams } from 'expo-router';
import {
  SportItem,
  SportUnit,
  SessionExpiredError,
  addSport,
  getSportUnits,
  searchSport,
  sportUnitId,
  sportUnitName,
} from '../lib/kb';

export default function SportScreen() {
  const params = useLocalSearchParams<{ date?: string }>();
  const date = params.date ?? '';

  const [q, setQ] = useState('');
  const [items, setItems] = useState<SportItem[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<SportItem | null>(null);
  const [units, setUnits] = useState<SportUnit[]>([]);
  const [unitId, setUnitId] = useState<number | null>(null);
  const [quan, setQuan] = useState('1');
  const [adding, setAdding] = useState(false);

  const doSearch = useCallback(
    async (term: string) => {
      if (!term.trim()) return;
      setBusy(true);
      setError(null);
      setSelected(null);
      try {
        const r = await searchSport(term.trim(), date);
        setItems(r.results ?? []);
      } catch (e) {
        if (e instanceof SessionExpiredError) setError('A session lejárt — jelentkezz be újra.');
        else setError(e instanceof Error ? e.message : String(e));
      } finally {
        setBusy(false);
      }
    },
    [date]
  );

  async function pick(item: SportItem) {
    setSelected(item);
    setQuan('1');
    setBusy(true);
    setError(null);
    try {
      const list = await getSportUnits(item.id);
      setUnits(list);
      setUnitId(list.length ? sportUnitId(list[0]) : null);
      if (!list.length) setError('Nem sikerült beolvasni az egységeket (getmesu) — add meg kézzel.');
    } catch {
      setUnits([]);
      setUnitId(null);
      setError('Az egységlista (getmesu) hibásan jött — add meg kézzel a boxme-t.');
    } finally {
      setBusy(false);
    }
  }

  async function doAdd() {
    if (!selected) return;
    if (unitId == null) {
      setError('Nincs egység (boxme) kiválasztva.');
      return;
    }
    setAdding(true);
    setError(null);
    try {
      await addSport({
        id: selected.id,
        quan: Number(quan.replace(',', '.')) || 0,
        date,
        boxdayoftime: 1, // sport entries are day-level; the site shows them separately
        boxme: unitId,
      });
      router.back();
    } catch (e) {
      if (e instanceof SessionExpiredError) setError('A session lejárt — jelentkezz be újra.');
      else setError(e instanceof Error ? e.message : String(e));
      setAdding(false);
    }
  }

  return (
    <ScrollView style={s.wrap} contentContainerStyle={s.content} keyboardShouldPersistTaps="handled">
      <Text style={s.hint}>
        Figyi: a sportkeresés ékezetre érzékeny — „futás” talál, „fut” nem.
      </Text>
      <View style={s.searchRow}>
        <TextInput
          style={s.input}
          placeholder="pl. futás, kerékpár, úszás"
          value={q}
          onChangeText={setQ}
          onSubmitEditing={() => void doSearch(q)}
          returnKeyType="search"
        />
        <Pressable style={s.go} onPress={() => void doSearch(q)} disabled={busy}>
          <Text style={s.goText}>{busy ? <ActivityIndicator size="small" color="#fff" /> : 'Keresés'}</Text>
        </Pressable>
      </View>

      {error ? <Text style={s.err}>{error}</Text> : null}

      {items?.length ? (
        items.map((it) =>
          selected?.id === it.id ? (
            <View key={it.id} style={s.editor}>
              <Text style={s.itemName}>{it.name}</Text>
              {units.length > 0 ? (
                <View style={s.units}>
                  {units.map((u, i) => {
                    const id = sportUnitId(u);
                    if (id == null) return null;
                    return (
                      <Pressable
                        key={`${id}-${i}`}
                        style={[s.chip, unitId === id && s.chipOn]}
                        onPress={() => setUnitId(id)}
                      >
                        <Text style={unitId === id ? s.chipTextOn : s.chipText}>{sportUnitName(u)}</Text>
                      </Pressable>
                    );
                  })}
                </View>
              ) : (
                <TextInput
                  style={s.quan}
                  placeholder="boxme (unit id)"
                  keyboardType="numbers-and-punctuation"
                  value={unitId == null ? '' : String(unitId)}
                  onChangeText={(t) => setUnitId(Number(t) || null)}
                />
              )}
              <View style={s.addRow}>
                <TextInput style={s.quan} keyboardType="numbers-and-punctuation" value={quan} onChangeText={setQuan} />
                <Pressable style={s.addBtn} disabled={adding} onPress={() => void doAdd()}>
                  <Text style={s.addText}>{adding ? '…' : 'Hozzáadás'}</Text>
                </Pressable>
              </View>
            </View>
          ) : (
            <Pressable key={it.id} style={s.item} onPress={() => void pick(it)}>
              <Text style={s.itemName}>{it.name}</Text>
              <Text style={s.itemSub}>
                {it.piece}
                {it.cal ? ` · ${it.cal}` : ''}
              </Text>
            </Pressable>
          )
        )
      ) : items && items.length === 0 ? (
        <Text style={s.empty}>Nincs találat (próbáld ékezettel).</Text>
      ) : null}
    </ScrollView>
  );
}

const s = StyleSheet.create({
  wrap: { flex: 1, backgroundColor: '#fff' },
  content: { padding: 16, gap: 4 },
  hint: { fontSize: 12, color: '#888' },
  searchRow: { flexDirection: 'row', gap: 8 },
  input: { flex: 1, borderWidth: 1, borderColor: '#ccc', borderRadius: 8, paddingHorizontal: 12, paddingVertical: 10, fontSize: 16 },
  go: { backgroundColor: '#345', borderRadius: 8, paddingHorizontal: 16, justifyContent: 'center' },
  goText: { color: '#fff', fontWeight: '600' },
  item: { paddingVertical: 10, borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: '#eee' },
  itemName: { fontSize: 15 },
  itemSub: { fontSize: 12, color: '#888' },
  editor: { marginVertical: 8, padding: 12, borderRadius: 8, backgroundColor: '#f2f4f8', gap: 10 },
  units: { flexDirection: 'row', flexWrap: 'wrap', gap: 6 },
  chip: { borderWidth: 1, borderColor: '#bbb', borderRadius: 16, paddingHorizontal: 12, paddingVertical: 5 },
  chipOn: { backgroundColor: '#345', borderColor: '#345' },
  chipText: { color: '#333', fontSize: 13 },
  chipTextOn: { color: '#fff', fontSize: 13 },
  addRow: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  quan: { flex: 1, borderWidth: 1, borderColor: '#ccc', borderRadius: 8, paddingHorizontal: 10, paddingVertical: 8, fontSize: 16 },
  addBtn: { backgroundColor: '#345', borderRadius: 8, paddingVertical: 10, paddingHorizontal: 20, alignItems: 'center' },
  addText: { color: '#fff', fontWeight: '600' },
  err: { color: '#b00020', marginTop: 8 },
  empty: { textAlign: 'center', color: '#999', padding: 24 },
});
