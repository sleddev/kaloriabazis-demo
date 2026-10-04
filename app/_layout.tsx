import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';

export default function Layout() {
  return (
    <>
      <StatusBar style="dark" />
      <Stack screenOptions={{ headerStyle: { backgroundColor: '#2e7d32' }, headerTintColor: '#fff', headerTitleStyle: { fontWeight: 'bold' } }}>
        <Stack.Screen name="index" options={{ title: 'Kalóriabázis' }} />
        <Stack.Screen name="diary" options={{ title: 'Napló' }} />
        <Stack.Screen name="search" options={{ title: 'Keresés' }} />
        <Stack.Screen name="sport" options={{ title: 'Sport' }} />
      </Stack>
    </>
  );
}
