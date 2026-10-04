# kaloriabazis-demo

Unofficial Expo (React Native) client demo for kaloriabazis.hu — a Hungarian
calorie-tracking site. Built against an independently documented API
([OpenAPI spec](https://kaloriabazis.hu/food.php?show=apidoc) mirrored from the
site's own `apidoc` page).

## What it does (v0.1)
- Login (account credentials are yours; stored on-device via expo-secure-store)
- Food search with add-to-diary
- Day diary view + delete entries
- Sport search + add entry

No credentials or personal data are included in this repo.

## Run

```bash
npm install
npx expo start
```

## Build (EAS)

```bash
npm i -g eas-cli
eas build -p android --profile preview
```

This is a demo/learning project, not affiliated with kaloriabazis.hu.
