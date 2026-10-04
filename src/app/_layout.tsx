import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';

export default function RootLayout() {
  return (
    <>
      <StatusBar style="dark" />
      <Stack>
        <Stack.Screen name="index" options={{ title: 'Kalóriabázis — belépés' }} />
        <Stack.Screen name="diary" options={{ title: 'Napló' }} />
        <Stack.Screen name="search" options={{ title: 'Étel keresés' }} />
        <Stack.Screen name="sport" options={{ title: 'Sport keresés' }} />
      </Stack>
    </>
  );
}
