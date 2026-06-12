// OAuth client + token storage for the SPA.
//
// Talks to the same Mastodon-compatible endpoints sukhi-fedi already
// serves: POST /api/v1/apps to register a client, /oauth/authorize for
// the user-facing consent (server-rendered), /oauth/token to exchange
// or refresh.
//
// Three keys live in localStorage:
//   sf.client   — { client_id, client_secret, redirect_uri }
//   sf.token    — { access_token, refresh_token, scope, created_at }
//   sf.state    — single-use CSRF guard for the authorize redirect
//
// Server is reached relative to window.location.origin so the same
// build runs against any sukhi-fedi instance.

import { browser } from '$app/environment';

export type ClientCreds = {
  client_id: string;
  client_secret: string;
  redirect_uri: string;
  // 登録時に申告した scope。SCOPES 定数が広がったとき (例: read →
  // read write follow)、ここを見て古い credentials を捨てて再登録する。
  // 古いブラウザに置いてある creds は scopes が無いので、その場合も
  // 「古い・狭い」と見なして再登録する。
  scopes?: string;
};

export type TokenSet = {
  access_token: string;
  refresh_token?: string | null;
  scope: string;
  created_at: number;
};

const CLIENT_KEY = 'sf.client';
const TOKEN_KEY = 'sf.token';
const STATE_KEY = 'sf.state';
const DRAFT_KEY = 'sf.signup_draft';
// 書き込み (投稿・プロフィール編集) と follow を含む。読み取りだけの
// 古い token を持っている人は、書き込み API で 401/403 を踏むので
// その時点で clearToken → 再ログインで広い token を取り直す形。
const SCOPES = 'read write follow';

// password は API call の直前まで sessionStorage に乗るが、call の
// 直後(成功も失敗も)`clearSignupPassword` で消して、username +
// invite_code だけが残る形にしている。retry のとき再入力で済むのは
// 招待コードと ID、合言葉は毎回打ち直し ─ XSS で password が
// snapshot される窓を最小にするための取り決め。
// email_proof は /signup/email/confirm が返す署名つきの「この
// メールボックスを開けた」証明(20分有効)。サーバはこれ無しでは
// アカウントを作らない。password はレガシー・任意。
export type SignupDraft = {
  username: string;
  password?: string;
  invite_code: string;
  // 表示用(どのアドレスを確認したか)。サーバに渡るのは proof のほう。
  email?: string;
  email_proof?: string;
};

export function saveSignupDraft(d: SignupDraft): void {
  if (!browser) return;
  sessionStorage.setItem(DRAFT_KEY, JSON.stringify(d));
}

export function loadSignupDraft(): SignupDraft | null {
  if (!browser) return null;
  const raw = sessionStorage.getItem(DRAFT_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as SignupDraft;
  } catch {
    return null;
  }
}

// password だけ落とした draft で上書きする。/check が API を呼んだ
// 直後に必ず呼ぶ ─ 成功した場合はそのあと clearSignupDraft で全消し、
// 失敗時は username + invite_code が残るので、retry は合言葉だけ
// 打ち直してもらえばいい。
export function clearSignupPassword(): void {
  if (!browser) return;
  const d = loadSignupDraft();
  if (!d) return;
  const { password: _password, ...rest } = d;
  sessionStorage.setItem(DRAFT_KEY, JSON.stringify(rest));
}

export function clearSignupDraft(): void {
  if (!browser) return;
  sessionStorage.removeItem(DRAFT_KEY);
}

export function loadToken(): TokenSet | null {
  if (!browser) return null;
  const raw = localStorage.getItem(TOKEN_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw) as TokenSet;
  } catch {
    return null;
  }
}

export function saveToken(t: TokenSet): void {
  if (!browser) return;
  localStorage.setItem(TOKEN_KEY, JSON.stringify(t));
}

export function clearToken(): void {
  if (!browser) return;
  localStorage.removeItem(TOKEN_KEY);
}

// RFC 7009 revoke: tell the server to invalidate the bearer token, then
// drop it locally. Best-effort — a failed/offline revoke still clears the
// local state, so sign-out always completes. Without this, "sign out" only
// removed the token from this browser while it stayed valid server-side.
export async function signOutServer(): Promise<void> {
  if (browser) {
    const t = loadToken();
    const raw = localStorage.getItem(CLIENT_KEY);
    if (t && raw) {
      try {
        const c = JSON.parse(raw) as ClientCreds;
        await fetch('/oauth/revoke', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({
            token: t.access_token,
            client_id: c.client_id,
            client_secret: c.client_secret
          })
        });
      } catch {
        /* best-effort: local logout proceeds regardless */
      }
    }
  }
  clearToken();
}

export function isLoggedIn(): boolean {
  return !!loadToken();
}

// scope を「順番のゆらぎ」「重複」「空白の数」に寛容に比べる。
// "read write follow" と "follow read write" を同じものとして扱いたい。
function sameScopes(a: string | undefined, b: string): boolean {
  if (!a) return false;
  const norm = (s: string) =>
    s.trim().split(/\s+/).filter(Boolean).sort().join(' ');
  return norm(a) === norm(b);
}

async function loadOrRegisterClient(): Promise<ClientCreds> {
  if (!browser) throw new Error('no browser');
  const raw = localStorage.getItem(CLIENT_KEY);
  if (raw) {
    try {
      const cached = JSON.parse(raw) as ClientCreds;
      // 登録済み app の scope が、いま要求したい SCOPES と一致して
      // いればそのまま使う。一致しなければ、サーバ側の app 行は
      // 古い(狭い)ままなので /oauth/authorize で invalid_scope を
      // 食らう ─ creds を捨てて新しい app を登録しなおす。
      // 同じ理由で、scope 情報を持っていない古いキャッシュも捨てる。
      if (sameScopes(cached.scopes, SCOPES)) return cached;
      localStorage.removeItem(CLIENT_KEY);
      // 古い app に紐づく token も無効になるはずなので、ここで一緒に
      // 落としておく。再ログインで広い token を取り直してもらう。
      localStorage.removeItem(TOKEN_KEY);
    } catch {
      /* fallthrough — re-register */
    }
  }

  const redirect_uri = `${window.location.origin}/app/callback`;
  const res = await fetch('/api/v1/apps', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      client_name: 'sukhi-fedi web',
      redirect_uris: redirect_uri,
      scopes: SCOPES,
      website: window.location.origin
    })
  });

  if (!res.ok) {
    throw new Error(`app registration failed: ${res.status}`);
  }

  const body = await res.json();
  const creds: ClientCreds = {
    client_id: body.client_id,
    client_secret: body.client_secret,
    redirect_uri,
    scopes: SCOPES
  };
  localStorage.setItem(CLIENT_KEY, JSON.stringify(creds));
  return creds;
}

// Begin the Authorization Code flow. Generates a state, stores it,
// and navigates to /oauth/authorize. The server-rendered /login
// catches the unauthenticated case and bounces back here on success.
export async function startLogin(): Promise<void> {
  const client = await loadOrRegisterClient();
  const state = crypto.randomUUID();
  localStorage.setItem(STATE_KEY, state);

  const params = new URLSearchParams({
    response_type: 'code',
    client_id: client.client_id,
    redirect_uri: client.redirect_uri,
    scope: SCOPES,
    state
  });

  window.location.assign(`/oauth/authorize?${params.toString()}`);
}

// Called on /app/callback. Verifies state, exchanges the code, persists
// the token. Throws on any check that fails.
export async function completeLogin(code: string, state: string): Promise<TokenSet> {
  const expected = localStorage.getItem(STATE_KEY);
  if (!expected || expected !== state) {
    throw new Error('state mismatch');
  }
  localStorage.removeItem(STATE_KEY);

  const client = await loadOrRegisterClient();

  const res = await fetch('/oauth/token', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      grant_type: 'authorization_code',
      code,
      client_id: client.client_id,
      client_secret: client.client_secret,
      redirect_uri: client.redirect_uri
    })
  });

  if (!res.ok) {
    throw new Error(`token exchange failed: ${res.status}`);
  }

  const t = (await res.json()) as TokenSet;
  saveToken(t);
  return t;
}

// 加入前のメールボックス証明。request はコードを送り、confirm は
// 正しいコードと引き換えに署名つき email_proof を返す。これを
// signup() に渡す ─ password は無くてもいい(レガシー・任意)。
export async function requestSignupEmailCode(email: string): Promise<void> {
  const res = await fetch('/signup/email/request', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email })
  });
  if (res.ok) return;
  const body = await res.json().catch(() => ({}));
  throw new Error((body as { error?: string })?.error ?? `signup_email_failed_${res.status}`);
}

export async function confirmSignupEmailCode(email: string, code: string): Promise<string> {
  const res = await fetch('/signup/email/confirm', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ email, code })
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error((body as { error?: string })?.error ?? `signup_email_failed_${res.status}`);
  }
  return (body as { email_proof: string }).email_proof;
}

// Sign up via POST /api/v1/accounts. Called from `/check` AFTER Anubis
// has set its cookie ─ never directly from the form, so the PoW is
// always done before an account row is created.
export async function signup(
  input: Required<Pick<SignupDraft, 'username' | 'invite_code' | 'email_proof'>> &
    Pick<SignupDraft, 'password'>
): Promise<TokenSet> {
  const client = await loadOrRegisterClient();

  const ccRes = await fetch('/oauth/token', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      grant_type: 'client_credentials',
      client_id: client.client_id,
      client_secret: client.client_secret,
      scope: SCOPES
    })
  });

  if (!ccRes.ok) {
    throw new Error(`client_credentials failed: ${ccRes.status}`);
  }

  const appToken = (await ccRes.json()) as TokenSet;

  const res = await fetch('/api/v1/accounts', {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${appToken.access_token}`
    },
    body: JSON.stringify(input)
  });

  const body = await res.json().catch(() => ({}));

  if (!res.ok) {
    const reason = body?.error ?? `signup_failed_${res.status}`;
    const err = new Error(reason);
    // validation_failed は details に
    // `{username: ["は小文字英数字..."], ...}` が入っていることがある。
    // /check 側で field 名 + メッセージを出すために括って渡す。
    (err as Error & { details?: Record<string, string[]> }).details = body?.details;
    throw err;
  }

  saveToken(body as TokenSet);
  return body as TokenSet;
}

// 一段目(パスワード or メールコード)が通ったあとのサーバの返事。
// cookie が立って終わりか、アプリ 2FA の二段目が要るかの二択。
export type FirstFactorResult = { ok: true } | { second_factor: 'totp'; pending: string };

// First-party credential login. POSTs username + password to `/login`,
// which validates them and sets the `session_token` cookie that
// `/oauth/authorize` later consumes. Cookie-based, NOT the OAuth bearer
// the rest of the SPA uses ─ this only opens the door; the caller then
// walks through `/check` (Anubis) → `/oauth/authorize` to get a token.
// アプリ 2FA が有効な人には cookie は立たず、`/login/totp` 用の
// pending トークンが返る ─ 呼び元が二段目の画面を出す。
export async function loginWithPassword(
  username: string,
  password: string
): Promise<FirstFactorResult> {
  const res = await fetch('/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    credentials: 'same-origin',
    body: JSON.stringify({ username, password })
  });
  if (res.status === 401) throw new Error('invalid');
  if (!res.ok) throw new Error(`login_failed_${res.status}`);
  return (await res.json()) as FirstFactorResult;
}

// 二段目: /login で受け取った pending と、認証アプリの 6 桁。
// 通れば session_token cookie が立つ。
export async function submitTotp(pending: string, code: string): Promise<void> {
  const res = await fetch('/login/totp', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    credentials: 'same-origin',
    body: JSON.stringify({ pending, code })
  });
  if (res.ok) return;
  const body = await res.json().catch(() => ({}));
  throw new Error(body?.error ?? `totp_failed_${res.status}`);
}

// メール認証コードでのログイン。request は、知らないアドレスにも
// 200 を返す(居る/居ないを言わない)ので、送った前提で次の画面へ。
export async function requestEmailLoginCode(email: string): Promise<void> {
  const res = await fetch('/login/email/request', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    credentials: 'same-origin',
    body: JSON.stringify({ email })
  });
  if (res.ok) return;
  const body = await res.json().catch(() => ({}));
  throw new Error(body?.error ?? `email_request_failed_${res.status}`);
}

export async function loginWithEmailCode(
  email: string,
  code: string
): Promise<FirstFactorResult> {
  const res = await fetch('/login/email', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    credentials: 'same-origin',
    body: JSON.stringify({ email, code })
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body?.error ?? `email_login_failed_${res.status}`);
  }
  return (await res.json()) as FirstFactorResult;
}

// パスキーでのログイン。options → ブラウザの認証器 → submit まで
// 一息にやる。成功すれば cookie が立つ(2FA の二段目は無し ─
// 認証器の本人確認がその役)。
export async function loginWithPasskey(): Promise<void> {
  const { getPasskeyAssertion } = await import('./webauthn');

  const optRes = await fetch('/login/passkey/options', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    credentials: 'same-origin',
    body: '{}'
  });
  if (!optRes.ok) throw new Error('passkey');
  const { ref, publicKey } = await optRes.json();

  const assertion = await getPasskeyAssertion(publicKey);

  const res = await fetch('/login/passkey', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    credentials: 'same-origin',
    body: JSON.stringify({ ref, ...assertion })
  });
  if (!res.ok) throw new Error('passkey');
}

// Set or change the signed-in account's password. Cookie-gated like
// /login (the session_token minted at login), not the bearer.
// 初回設定(これまであいことば無し)は current 不要で、サーバは
// {initial: true} を返しセッションも生きたまま。変更のときは全
// セッションが失効するので、呼び元は clearToken() して /login へ。
// Throws 'current' | 'mismatch' | 'short' | 'unauthorized'.
export async function changePassword(
  current: string,
  newPassword: string,
  confirm: string
): Promise<{ initial: boolean }> {
  const res = await fetch('/settings/password', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    credentials: 'same-origin',
    body: JSON.stringify({
      current_password: current,
      new_password: newPassword,
      confirm_password: confirm
    })
  });
  if (res.ok) {
    const body = await res.json().catch(() => ({}));
    return { initial: !!(body as { initial?: boolean })?.initial };
  }
  const body = await res.json().catch(() => ({}));
  throw new Error(body?.error ?? `password_failed_${res.status}`);
}

// ── ログイン要素の管理 (settings/security と EmailNudge が使う) ──────
//
// 変更系は session cookie 専用(サーバ側の決め: bearer は第三者アプリ
// にも渡るから、ログイン要素には触らせない)。/auth/state だけは
// bearer でも読める ─ 加入直後(cookie がまだ無いことがある)でも
// ポップアップの出す/出さないを決められるように。

export type AuthState = {
  // false のときは cookie が無い(または切れた)ので、変更系を呼ぶ前に
  // もう一度 /login を通ってもらう必要がある。
  manageable: boolean;
  email: string | null;
  email_verified: boolean;
  // false = パスワード無し(いまの標準)。要素を外す操作の本人確認は
  // password の代わりに reauth コード(メール)で行う。
  has_password: boolean;
  totp_enabled: boolean;
  totp_pending: boolean;
  passkeys: {
    id: number;
    nickname: string | null;
    created_at: string;
    last_used_at: string | null;
  }[];
};

// 要素を外す操作の本人確認。あいことばを持つ人は password、
// 持たない人は requestReauthCode() で届く 6 桁を reauth_code に。
export type Reauth = { password?: string; reauth_code?: string };

function bearerHeaders(): Record<string, string> {
  const t = loadToken();
  return t ? { authorization: `Bearer ${t.access_token}` } : {};
}

async function settingsPost(path: string, body: unknown): Promise<unknown> {
  const res = await fetch(path, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    credentials: 'same-origin',
    body: JSON.stringify(body ?? {})
  });
  const parsed = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error((parsed as { error?: string })?.error ?? `failed_${res.status}`);
  }
  return parsed;
}

export async function fetchAuthState(): Promise<AuthState | null> {
  const res = await fetch('/auth/state', {
    credentials: 'same-origin',
    headers: bearerHeaders()
  });
  if (res.status === 401) return null;
  if (!res.ok) throw new Error(`auth_state_failed_${res.status}`);
  return (await res.json()) as AuthState;
}

// 本人確認コードを、登録ずみの確認済みメールへ送る。
export async function requestReauthCode(): Promise<void> {
  await settingsPost('/settings/reauth/request', {});
}

// メール登録/変更: コードを送る。すでに確認済みアドレスがある人が
// 別のアドレスへ変えるときだけ reauth(password か reauth_code)が要る。
export async function requestEmailCode(email: string, reauth?: Reauth): Promise<void> {
  await settingsPost('/settings/email/request', { email, ...(reauth ?? {}) });
}

export async function confirmEmailCode(code: string): Promise<void> {
  await settingsPost('/settings/email/confirm', { code });
}

export async function totpSetup(): Promise<{ secret: string; otpauth: string }> {
  return (await settingsPost('/settings/totp/setup', {})) as { secret: string; otpauth: string };
}

export async function totpEnable(code: string): Promise<void> {
  await settingsPost('/settings/totp/enable', { code });
}

export async function totpDisable(reauth: Reauth): Promise<void> {
  await settingsPost('/settings/totp/disable', reauth);
}

// レガシーのあいことば: 初回設定(currentなし) / 退役。変更は
// changePassword のまま。
export async function removePassword(password: string): Promise<void> {
  await settingsPost('/settings/password/remove', { password });
}

// パスキー登録: options → 認証器 → 登録、まで。
export async function registerPasskey(nickname: string): Promise<void> {
  const { createPasskey } = await import('./webauthn');

  const { ref, publicKey } = (await settingsPost('/settings/passkeys/options', {})) as {
    ref: string;
    publicKey: Parameters<typeof createPasskey>[0];
  };

  const payload = await createPasskey(publicKey);
  await settingsPost('/settings/passkeys', { ref, nickname, ...payload });
}

export async function deletePasskey(id: number, reauth: Reauth): Promise<void> {
  await settingsPost(`/settings/passkeys/${id}/delete`, reauth);
}

// Navigate to the shared check page. Anubis challenges this path; the
// page picks up `intent` and finishes the flow on the other side.
//
// Single entry point used by both doors ─ keeps the homepage's "入る"
// click handler and the signup form's submit short and uniform.
export function goToCheck(intent: 'login' | 'signup', next?: string): void {
  const params = new URLSearchParams({ intent });
  if (next) params.set('next', next);
  window.location.assign(`/check?${params.toString()}`);
}
