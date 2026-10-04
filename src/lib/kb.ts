/**
 * Kalóriabázis (kaloriabazis.hu) API client.
 *
 * Everything here is verified against the live site (see the project's API
 * report). Key facts the client relies on:
 *
 *  - Session cookie: `myPHP83SESSID` (Secure; HttpOnly). The app keeps a small
 *    cookie jar in JS and sends it as a `Cookie` header — reliable on every
 *    platform, and persisted with expo-secure-store between launches.
 *  - Every request must look like the real frontend: a browser User-Agent,
 *    `X-Requested-With: XMLHttpRequest` and a plausible `Referer` for the
 *    page that would have issued the call, otherwise the server answers
 *    `die_with_text arjrjkrk`.
 *  - A cold session is rejected — the session must be "warmed up" by visiting
 *    a page (we fetch /fooldal) before the first AJAX call.
 *  - Bursting requests trips a rate-limit tarpit (connection accepted, no
 *    response). The client therefore serialises requests with a minimum
 *    interval between calls.
 *  - Expired sessions: text responses contain `###TIMEOUT###`, JSON
 *    responses `{"type":"1","error":"Nem vagy bejelentkezve!"}`.
 *  - Diary dates are sent in dot format (`2026.10.04`).
 */

import * as SecureStore from 'expo-secure-store';

export const BASE = 'https://kaloriabazis.hu';

const USER_AGENT =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

/** Anonymous warm-up cookies the site sets; values are constant, so we just send them. */
const WARMUP_COOKIES = 'LANGID=1; CLANGCODE=HU; UNITLANGID=1; BWEIGHT_UNIT=1; BHEIGHT_UNIT=1; mob_for_a=0';

const SESSION_KEY = 'kb_session_cookie';
const MIN_INTERVAL_MS = 3500;

/** Thrown when the session has expired or was never established. */
export class SessionExpiredError extends Error {
  constructor() {
    super('Session expired — log in again');
  }
}

/** Thrown when the anti-abuse guard answers (bad headers / unknown action). */
export class GuardedError extends Error {
  constructor() {
    super('Blocked by the site guard (arjrjkrk) — wrong headers or unknown action');
  }
}

/** Meal-of-day slots (boxdayoftime). Slot 0 is a trap: stored but never rendered. */
export const MEALS: { id: number; label: string }[] = [
  { id: 1, label: 'Reggeli' },
  { id: 2, label: 'Tízórai' },
  { id: 3, label: 'Ebéd' },
  { id: 4, label: 'Uzsonna' },
  { id: 5, label: 'Vacsora' },
  { id: 6, label: 'Nassolás' },
];

// ---------------------------------------------------------------------------
// Cookie jar
// ---------------------------------------------------------------------------

let sessionCookie: string | null = null;

function getSetCookie(res: Response): string {
  // react-native exposes headers case-insensitively; some stacks join multiple
  // set-cookie values, others expose only the first. The session cookie has a
  // unique name, so regexing the raw string is the robust route.
  const anyRes = res as unknown as {
    headers: { get: (n: string) => string | null; map?: Record<string, string> };
  };
  return (
    anyRes.headers.get('set-cookie') ||
    anyRes.headers.get('Set-Cookie') ||
    anyRes.headers.map?.['set-cookie'] ||
    ''
  );
}

export function captureSession(res: Response): void {
  const m = getSetCookie(res).match(/myPHP83SESSID=([^;\s]+)/);
  if (m) {
    sessionCookie = m[1];
    // Persisted only after a successful login (see login()) — an anonymous
    // warm-up session must not outlive the process.
  }
}

function persistSession(): void {
  if (sessionCookie) void SecureStore.setItemAsync(SESSION_KEY, sessionCookie);
}

export function getSession(): string | null {
  return sessionCookie;
}

export function logout(): void {
  sessionCookie = null;
  void SecureStore.deleteItemAsync(SESSION_KEY);
}

export async function loadPersistedSession(): Promise<boolean> {
  if (sessionCookie) return true;
  sessionCookie = await SecureStore.getItemAsync(SESSION_KEY);
  return sessionCookie != null;
}

// ---------------------------------------------------------------------------
// Request plumbing: serialised queue with a minimum interval (tarpit guard)
// ---------------------------------------------------------------------------

let queue: Promise<void> = Promise.resolve();

function sleep(ms: number): Promise<void> {
  return new Promise((r) => setTimeout(r, ms));
}

interface FetchOptions {
  referer: string;
  /** POST with url-encoded body instead of GET */
  post?: Record<string, string>;
  /** skip the tarpit interval (only for the login warm-up GET) */
  paced?: boolean;
}

async function http(
  path: string,
  opts: FetchOptions = { referer: BASE + '/' }
): Promise<{ res: Response; text: string }> {
  const run = async (): Promise<{ res: Response; text: string }> => {
    const headers: Record<string, string> = {
      'User-Agent': USER_AGENT,
      'X-Requested-With': 'XMLHttpRequest',
      Referer: opts.referer,
      Cookie: WARMUP_COOKIES + (sessionCookie ? `; myPHP83SESSID=${sessionCookie}` : ''),
    };
    const method = opts.post ? 'POST' : 'GET';
    if (opts.post) {
      headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }
    const res = await fetch(BASE + path, {
      method,
      headers,
      body: opts.post
        ? new URLSearchParams(opts.post).toString()
        : undefined,
    });
    captureSession(res);
    const text = await res.text();
    if (text.trim() === 'die_with_text arjrjkrk') throw new GuardedError();
    return { res, text };
  };

  if (opts.paced === false) return run();

  const next = queue.then(
    async () => {
      await sleep(MIN_INTERVAL_MS);
      return run();
    },
    // never poison the queue with a previous failure
    async () => {
      await sleep(MIN_INTERVAL_MS);
      return run();
    }
  );
  queue = next.then(() => undefined, () => undefined);
  return next;
}

function assertSession(text: string): void {
  if (text.includes('###TIMEOUT###') || text.includes('Nem vagy bejelentkezve')) {
    logout();
    throw new SessionExpiredError();
  }
}

function parseJson(text: string): unknown {
  const trimmed = text.trim();
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
    throw new Error('Unexpected response: ' + trimmed.slice(0, 120));
  }
  return JSON.parse(trimmed);
}

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

/** Warm up a session, log the user in. Returns true on success. */
export async function login(user: string, pw: string): Promise<boolean> {
  // Start from a clean jar: a stale persisted cookie would make the homepage
  // render logged-in — with no `myt` form — and break the flow.
  logout();

  // 1. warm-up (paced=false: first call, nothing to space out)
  await http('/fooldal', { referer: BASE + '/', paced: false });

  // 2. homepage. NOTE: /login redirects (302) to / since the 2026-10 redeploy —
  //    the form with the `myt` CSRF token lives on the homepage and POSTs to
  //    /bejelentkezes with fields txtusern / txtpassw (verified live).
  const page = await http('/', { referer: BASE + '/' });
  if (page.text.includes('Kijelentkez')) {
    return true; // already logged in with this fresh jar
  }
  const m =
    page.text.match(/id=["']myt["'][^>]*value=["']([^"']+)["']/) ||
    page.text.match(/value=["']([^"']+)["'][^>]*id=["']myt["']/);
  if (!m) {
    // Diagnostic: surface what the server actually sent so a mismatch is
    // visible in the UI instead of a dead end.
    throw new Error(
      `No myt token (status ${page.res.status}, ${page.text.length} bytes). Start: ${page.text.slice(0, 200)}`
    );
  }

  // 3. POST the real login form
  const post = await http('/bejelentkezes', {
    referer: BASE + '/',
    post: { mode: 'get', myt: m[1], txtusern: user, txtpassw: pw },
  });
  assertSession(post.text);
  const ok = post.text.includes('Kijelentkez');
  if (ok) persistSession();
  return ok;
}

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/** Server numbers arrive as strings ("28.60") and units as i18n keys ("UNIT_dkg"). */
export function num(v: unknown): number {
  const n = typeof v === 'number' ? v : parseFloat(String(v ?? ''));
  return Number.isFinite(n) ? n : 0;
}

export function unitLabel(u: unknown): string {
  const s = String(u ?? '').trim();
  if (!s) return '';
  return s.startsWith('UNIT_') ? s.slice(5).toLowerCase() : s;
}

export interface SearchItem {
  id: string; // "2088_0"
  eaten_food: number;
  food_id: string;
  obj_id: string;
  name: string; // display name (verified: results2 rows use `name`)
  piece: string; // "100 g"
  cal: string; // "143 kcal"
  pic_id?: string;
  is_fav?: number;
  fav_id?: number;
  [key: string]: unknown;
}

export interface SearchResponse {
  total1: number;
  results1: SearchItem[]; // favourite meals matching the query
  total2: number;
  results2: SearchItem[]; // foods + recipes
}

export interface SportItem {
  id: string;
  name: string;
  cDesc: string;
  piece: string; // "1 óra"
  cal: string; // "627 kcal"
  [key: string]: unknown;
}

export interface SportSearchResponse {
  results: SportItem[];
  weight: number;
  total: number;
}

export interface DiaryEntry {
  nID: string; // server sends it as a string
  food_id: string;
  syn_name?: string;
  f_name?: string;
  cDisplayName?: string;
  nCalorie: string;
  nProtein?: string;
  nFat?: string;
  nCarbo?: string;
  nQuantity?: string;
  nFoodUnitRef?: number;
  unitDisplayName?: string; // i18n key, e.g. "UNIT_dkg" — use unitLabel()
  nDayoftimeRef: string; // "1".."6" — compare with Number()
  hour_min?: string;
  [key: string]: unknown;
}

export interface MealStat {
  bSum: number;
  nDayoftimeRef: string;
  nCalorie: string;
  nProtein?: string;
  nFat?: string;
  nCarbo?: string;
  [key: string]: unknown;
}

export interface DiaryDay {
  results: Array<DiaryEntry | MealStat>;
  rfoodsum: number;
  rfoodsumProtein: number;
  rfoodsumCarbo: number;
  rfoodsumFat: number;
  [key: string]: unknown;
}

export function isStat(row: DiaryEntry | MealStat): row is MealStat {
  return (row as MealStat).bSum === 1;
}

// ---------------------------------------------------------------------------
// Endpoints (all live-verified; see the API report)
// ---------------------------------------------------------------------------

/** Main food search. Call this with the diary page as referer. */
export async function searchFood(q: string, p = 1, s = 20): Promise<SearchResponse> {
  const r = await http(
    `/getfood.php?q=${encodeURIComponent(q)}&p=${p}&s=${s}`,
    { referer: BASE + '/naplo' }
  );
  assertSession(r.text);
  return parseJson(r.text) as SearchResponse;
}

/** Full diary day. date in dot format, e.g. 2026.10.04 */
export async function getDay(date: string): Promise<DiaryDay> {
  const r = await http(`/food.php?show=getfoods&return_json=1&date=${date}`, {
    referer: BASE + '/naplo',
  });
  assertSession(r.text);
  return parseJson(r.text) as DiaryDay;
}

/**
 * Add a diary entry. `id` is the food id in "<id>_<synonym>" form, boxme the
 * unit id (e.g. 18 for 1g unit row... see FoodInfoBox), quan the quantity.
 * boxdayoftime must be 1..6 — slot 0 is a hidden trap (stored, never rendered).
 */
export async function addFood(params: {
  id: string;
  boxme: number;
  quan: number;
  date: string;
  boxdayoftime: number;
}): Promise<DiaryDay> {
  const qs = new URLSearchParams({
    show: 'addfood',
    return_json: '1',
    id: params.id,
    boxme: String(params.boxme),
    quan: String(params.quan),
    date: params.date,
    boxdayoftime: String(params.boxdayoftime),
  }).toString();
  const r = await http(`/food.php?${qs}`, { referer: BASE + '/naplo' });
  assertSession(r.text);
  return parseJson(r.text) as DiaryDay;
}

/** Delete a diary entry (id = nID from getDay). */
export async function delFood(id: string | number, date: string): Promise<DiaryDay> {
  const r = await http(
    `/food.php?show=delfood&return_json=1&id=${id}&date=${date}`,
    { referer: BASE + '/naplo' }
  );
  assertSession(r.text);
  return parseJson(r.text) as DiaryDay;
}

/** Sport search. ACCENT-SENSITIVE: "fut" finds nothing, "futás" does. */
export async function searchSport(q: string, date: string, p = 1, s = 20): Promise<SportSearchResponse> {
  const r = await http(
    `/getsport.php?q=${encodeURIComponent(q)}&p=${p}&s=${s}&date=${date}`,
    { referer: BASE + '/naplo' }
  );
  assertSession(r.text);
  return parseJson(r.text) as SportSearchResponse;
}

/** Calories burned: id "<id>_<synonym>", quan in the item's own unit. */
export async function calcSport(id: string, quan: number): Promise<number> {
  const r = await http(
    `/food.php?show=calcsportme&id=${encodeURIComponent(id)}&quan=${quan}`,
    { referer: BASE + '/naplo' }
  );
  assertSession(r.text);
  return Number(r.text.trim());
}

/** Add a sport entry. boxme is the sport's unit id (getmesu). */
export async function addSport(params: {
  id: string;
  quan: number;
  date: string;
  boxme: number;
  boxdayoftime: number;
}): Promise<DiaryDay> {
  const qs = new URLSearchParams({
    show: 'addsport',
    return_json: '1',
    id: params.id,
    quan: String(params.quan),
    date: params.date,
    boxdayoftime: String(params.boxdayoftime),
  }).toString();
  const r = await http(`/food.php?${qs}`, { referer: BASE + '/naplo' });
  assertSession(r.text);
  return parseJson(r.text) as DiaryDay;
}

/** Unit list for a sport item (its duration units). Shape is legacy; fields are optional. */
export interface SportUnit {
  id?: number;
  nId?: number;
  name?: string;
  cName?: string;
  [key: string]: unknown;
}

export function sportUnitId(u: SportUnit): number | null {
  if (typeof u.id === 'number') return u.id;
  if (typeof u.nId === 'number') return u.nId;
  return null;
}

export function sportUnitName(u: SportUnit): string {
  return (u.name || u.cName || `unit ${sportUnitId(u) ?? '?'}`) as string;
}

export async function getSportUnits(sportId: string): Promise<SportUnit[]> {
  const r = await http(`/food.php?show=getmesu&id=${encodeURIComponent(sportId)}`, {
    referer: BASE + '/naplo',
  });
  assertSession(r.text);
  const j = parseJson(r.text);
  if (Array.isArray(j)) return j as SportUnit[];
  throw new Error('Unexpected unit list: ' + r.text.slice(0, 120));
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Today in the site's dot format: 2026.10.04 */
export function todayDots(d = new Date()): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${d.getFullYear()}.${pad(d.getMonth() + 1)}.${pad(d.getDate())}`;
}

export function shiftDots(dots: string, days: number): string {
  const [y, m, d] = dots.split('.').map(Number) as [number, number, number];
  const dt = new Date(y, m - 1, d + days);
  return todayDots(dt);
}
