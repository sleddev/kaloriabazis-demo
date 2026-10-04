/**
 * Unofficial kaloriabazis.hu client.
 *
 * Auth: the site uses an HTML login page with a CSRF token (`myt` hidden field)
 * and a `myPHP83SESSID` session cookie. We fetch the login page, scrape the
 * hidden form fields, re-post them with the credentials, and carry the cookie
 * on every subsequent request. Cookie is persisted in SecureStore.
 */
import * as SecureStore from 'expo-secure-store';

export const BASE = 'https://kaloriabazis.hu';
const COOKIE_KEY = 'kb_session_cookie';

let cookie = '';

function cookieFrom(resHeaders: Headers): void {
  const set = resHeaders.get('set-cookie');
  if (!set) return;
  const m = /myPHP83SESSID=([^;]+)/.exec(set);
  if (m) cookie = `myPHP83SESSID=${m[1]}`;
}

async function raw(path: string, init?: RequestInit): Promise<Response> {
  const res = await fetch(BASE + path, {
    ...init,
    headers: {
      ...(init?.headers ?? {}),
      ...(cookie ? { Cookie: cookie } : {}),
      'User-Agent': 'kaloriabazis-demo/0.1 (unofficial client)',
    },
    redirect: 'follow',
  });
  cookieFrom(res.headers);
  return res;
}

/** GET an HTML page (also used to grab the CSRF token). */
export async function getPage(path: string): Promise<string> {
  const res = await raw(path);
  return res.text();
}

/** POST form data. */
export async function postForm(path: string, body: Record<string, string>): Promise<string> {
  const form = Object.entries(body).map(([k, v]) => `${k}=${encodeURIComponent(v)}`).join('&');
  const res = await raw(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: form,
  });
  return res.text();
}

/** GET a JSON endpoint. Returns parsed JSON or null for empty bodies. */
export async function getJson<T = any>(path: string): Promise<T | null> {
  const text = await raw(path).then((r) => r.text());
  if (!text.trim()) return null;
  return JSON.parse(text) as T;
}

/** Scrape every hidden input of the login form (includes the `myt` CSRF token). */
function hiddenInputs(html: string): Record<string, string> {
  const out: Record<string, string> = {};
  const re = /<input[^>]*type=["']?hidden["']?[^>]*>/gi;
  for (const tag of html.match(re) ?? []) {
    const name = /name=["']?([\w-]+)/.exec(tag)?.[1];
    const value = /value=["']?([^"']*)/.exec(tag)?.[1];
    if (name) out[name] = value ?? '';
  }
  return out;
}

export async function login(username: string, password: string): Promise<void> {
  const html = await getPage('/login'); // login page carries the myt CSRF field
  const fields = hiddenInputs(html);
  if (!fields['myt']) throw new Error('No CSRF token found — login page format changed?');
  await postForm('/login', { ...fields, user: username, pass: password, login: '1' });
  if (!cookie) throw new Error('No session cookie received — wrong credentials?');
  await SecureStore.setItemAsync(COOKIE_KEY, cookie);
}

export async function restoreSession(): Promise<boolean> {
  const saved = await SecureStore.getItemAsync(COOKIE_KEY);
  if (!saved) return false;
  cookie = saved;
  try {
    const html = await getPage('/food.php');
    return /kilepes|logout|kijelentkez/i.test(html); // logged-in marker
  } catch {
    return false;
  }
}

export async function logout(): Promise<void> {
  cookie = '';
  await SecureStore.deleteItemAsync(COOKIE_KEY);
}

// ---------- Diary ----------
export interface FoodResult {
  nId: number;
  sName: string;
  sUnit?: string;
  cal?: number | string;
  carb?: number | string;
  prot?: number | string;
  fat?: number | string;
  [k: string]: any;
}
export interface SearchResponse {
  results1?: FoodResult[]; // favourite meals
  results2?: FoodResult[]; // foods & recipes
  [k: string]: any;
}

/** Main food search. Note: the query is effectively accent-insensitive, but
 *  partial words work better than prefixes for some words (verified live). */
export function searchFoods(q: string, p = 1): Promise<SearchResponse | null> {
  return getJson<SearchResponse>(`/getfood.php?show=getfood&q=${encodeURIComponent(q)}&p=${p}&s=&all_public_food=1`);
}

export interface DiaryDay { [k: string]: any }

/** Whole diary day as JSON (verified live). Date on the wire is yyyy.mm.dd. */
export async function getDiaryDay(date: string): Promise<DiaryDay | null> {
  return getJson<DiaryDay>(`/food.php?show=getfoods&date=${encodeURIComponent(date)}&return_json=1`);
}

/** Add a food entry. Returns the full updated day object (verified live). */
export function addDiaryFood(params: {
  date: string; id: number; quan: string; boxme: number; boxdayoftime: number;
}): Promise<DiaryDay | null> {
  const [year, month, day] = params.date.split('.');
  const qs = new URLSearchParams({
    show: 'addfood',
    date: params.date,
    year: year.trim(), month: month.trim(), day: day.trim(),
    id: String(params.id), quan: params.quan, boxme: String(params.boxme),
    boxdayoftime: String(params.boxdayoftime),
    hour_min: '12:00', is_from_speachrecog: '0', return_json: '1',
  }).toString();
  return getJson<DiaryDay>(`/food.php?${qs}`);
}

/** Delete a diary entry by its entry id. Echoes the updated day (verified live). */
export function deleteDiaryFood(date: string, id: number): Promise<DiaryDay | null> {
  return getJson<DiaryDay>(`/food.php?show=delfood&id=${id}&date=${encodeURIComponent(date)}&return_json=1`);
}

// ---------- Sport ----------
export interface SportResult {
  id: string; // "548_0"
  name: string;
  cal?: string; // "627 kcal"
  piece?: string; // "1 óra"
  type?: string;
  [k: string]: any;
}
export interface SportSearchResponse { results: SportResult[]; weight?: number; total?: number }

/** Sport search. NOTE: ACCENT-SENSITIVE (verified live): 'fut' → 0 hits, 'futás' → hits. */
export function searchSports(q: string, date: string): Promise<SportSearchResponse | null> {
  return getJson<SportSearchResponse>(`/getsport.php?q=${encodeURIComponent(q)}&p=1&s=&date=${encodeURIComponent(date)}`);
}

/** Add a sport entry by its id ("548_0") and quantity. */
export function addSport(params: { date: string; id: string; quan: string }): Promise<DiaryDay | null> {
  const qs = new URLSearchParams({ show: 'addsport', ...params as any, return_json: '1' }).toString();
  return getJson<DiaryDay>(`/food.php?${qs}`);
}

/** yyyy.mm.dd for the site's dot-format dates. */
export function todayDot(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}.${p(d.getMonth() + 1)}.${p(d.getDate())}`;
}
