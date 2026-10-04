import { useEffect, useState } from 'react';
import { ActivityIndicator, Button, KeyboardAvoidingView, Platform, StyleSheet, Text, TextInput, View } from 'react-native';
import { useRouter } from 'expo-router';
import { login, restoreSession } from '../lib/api';

export default function Login() {
  const router = useRouter();
  const [user, setUser] = useState('');
  const [pass, setPass] = useState('');
  const [busy, setBusy] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    restoreSession().then((ok) => {
      setBusy(false);
      if (ok) router.replace('/diary');
    });
  }, []);

  const submit = async () => {
    setError('');
    setBusy(true);
    try {
      await login(user.trim(), pass);
      router.replace('/diary');
    } catch (e: any) {
      setError(e?.message ?? 'Login failed');
    } finally {
      setBusy(false);
    }
  };

  if (busy) return <ActivityIndicator style={{ marginTop: 64 }} size="large" color="#2e7d32" />;

  return (
    <KeyboardAvoidingView style={s.wrap} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <Text style={s.title}>kaloriabazis.hu</Text>
      <Text style={s.sub}>Unofficial demo client — use your own account.</Text>
      <TextInput style={s.input} placeholder="Felhasználónév / e-mail" autoCapitalize="none" value={user} onChangeText={setUser} />
      <TextInput style={s.input} placeholder="Jelszó" secureTextEntry value={pass} onChangeText={setPass} />
      <Button title="Belépés" onPress={submit} disabled={!user || !pass} color="#2e7d32" />
      {error ? <Text style={s.err}>{error}</Text> : null}
    </KeyboardAvoidingView>
  );
}
const s = StyleSheet.create({
  wrap: { flex: 1, padding: 24, justifyContent: 'center', gap: 12 },
  title: { fontSize: 28, fontWeight: 'bold', color: '#2e7d32', textAlign: 'center' },
  sub: { textAlign: 'center', color: '#666', marginBottom: 16 },
  input: { borderWidth: 1, borderColor: '#bbb', borderRadius: 8, padding: 12, backgroundColor: '#fff' },
  err: { color: '#c62828', textAlign: 'center' },
});
