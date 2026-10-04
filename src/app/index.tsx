import { useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { router } from 'expo-router';
import { GuardedError, SessionExpiredError, loadPersistedSession, login } from '../lib/kb';

export default function LoginScreen() {
  const [user, setUser] = useState('');
  const [pw, setPw] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    void loadPersistedSession().then((has) => {
      if (alive && has) router.replace('/diary');
    });
    return () => {
      alive = false;
    };
  }, []);

  async function doLogin() {
    if (!user.trim() || !pw) {
      setError('Felhasználónév és jelszó kell');
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const ok = await login(user.trim(), pw);
      if (ok) {
        setPw('');
        router.replace('/diary');
      } else {
        setError('Bejelentkezés nem sikerült — ellenőrizd a nevet és a jelszót');
      }
    } catch (e) {
      if (e instanceof SessionExpiredError) {
        setError('A session lejárt — próbáld újra');
      } else if (e instanceof GuardedError) {
        setError('A szerver blokkolta a kérést (guard). Várj egy percet, és próbáld újra.');
      } else {
        setError(e instanceof Error ? e.message : String(e));
      }
    } finally {
      setBusy(false);
    }
  }

  return (
    <View style={s.wrap}>
      <Text style={s.title}>Kalóriabázis</Text>
      <Text style={s.sub}>kaloriabazis.hu napló — demó kliens</Text>

      <TextInput
        style={s.input}
        placeholder="Felhasználónév"
        autoCapitalize="none"
        autoCorrect={false}
        value={user}
        onChangeText={setUser}
      />
      <TextInput
        style={s.input}
        placeholder="Jelszó"
        secureTextEntry
        value={pw}
        onChangeText={setPw}
      />

      <Pressable style={s.btn} onPress={() => void doLogin()} disabled={busy}>
        {busy ? (
          <ActivityIndicator color="#fff" />
        ) : (
          <Text style={s.btnText}>Bejelentkezés</Text>
        )}
      </Pressable>

      {error ? <Text style={s.err}>{error}</Text> : null}

      <Text style={s.note}>
        A bejelentkezés három kérést csinál (oldal → login → post), a kliens a
        kérésritmust a szerver tarpitja miatt lassítja. A session-cookie a
        SecureStore-ban marad, amíg kijelentkezel.
      </Text>
    </View>
  );
}

const s = StyleSheet.create({
  wrap: { flex: 1, padding: 24, justifyContent: 'center', gap: 12, backgroundColor: '#fff' },
  title: { fontSize: 28, fontWeight: '700' },
  sub: { fontSize: 14, color: '#666', marginBottom: 16 },
  input: { borderWidth: 1, borderColor: '#ccc', borderRadius: 8, paddingHorizontal: 12, paddingVertical: 10, fontSize: 16 },
  btn: { backgroundColor: '#2f6f4f', borderRadius: 8, paddingVertical: 12, alignItems: 'center' },
  btnText: { color: '#fff', fontSize: 16, fontWeight: '600' },
  err: { color: '#b00020' },
  note: { fontSize: 12, color: '#888', marginTop: 8 },
});
