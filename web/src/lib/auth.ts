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
const SCOPES = 'read';

// password は API call の直前まで sessionStorage に乗るが、call の
// 直後(成功も失敗も)`clearSignupPassword` で消して、username +
// invite_code だけが残る形にしている。retry のとき再入力で済むのは
// 招待コードと ID、合言葉は毎回打ち直し ─ XSS で password が
// snapshot される窓を最小にするための取り決め。
export type SignupDraft = {
  username: string;
  password?: string;
  invite_code: string;
  email?: string;
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

export function isLoggedIn(): boolean {
  return !!loadToken();
}

async function loadOrRegisterClient(): Promise<ClientCreds> {
  if (!browser) throw new Error('no browser');
  const raw = localStorage.getItem(CLIENT_KEY);
  if (raw) {
    try {
      return JSON.parse(raw) as ClientCreds;
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
    redirect_uri
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

// Sign up via POST /api/v1/accounts. Called from `/check` AFTER Anubis
// has set its cookie ─ never directly from the form, so the PoW is
// always done before an account row is created.
export async function signup(input: Required<Pick<SignupDraft, 'username' | 'password' | 'invite_code'>> & Pick<SignupDraft, 'email'>): Promise<TokenSet> {
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
