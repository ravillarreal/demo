const ZITADEL_ISSUER = 'http://zitadel:8080'; // tu Zitadel local dentro de docker mapeado al host
const CLIENT_ID = '365571974988103684'; // puedes crear otro client_id específico para SPA
const REDIRECT_URI = 'http://localhost:5173/callback';
const SCOPES = 'openid profile email urn:zitadel:iam:user:resourceowner';

function base64UrlEncode(buffer: ArrayBuffer): string {
  return btoa(String.fromCharCode(...new Uint8Array(buffer)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

async function sha256(input: string): Promise<ArrayBuffer> {
  const encoder = new TextEncoder();
  const data = encoder.encode(input);
  return crypto.subtle.digest('SHA-256', data);
}

export async function createPkce(): Promise<{ verifier: string; challenge: string }> {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  const verifier = base64UrlEncode(array.buffer);
  const hash = await sha256(verifier);
  const challenge = base64UrlEncode(hash);
  return { verifier, challenge };
}

export function saveVerifier(verifier: string) {
  sessionStorage.setItem('pkce_verifier', verifier);
}

export function loadVerifier(): string | null {
  return sessionStorage.getItem('pkce_verifier');
}

export function clearVerifier() {
  sessionStorage.removeItem('pkce_verifier');
}

export function buildAuthUrl(challenge: string): string {
  const params = new URLSearchParams({
    client_id: CLIENT_ID,
    response_type: 'code',
    redirect_uri: REDIRECT_URI,
    scope: SCOPES,
    code_challenge: challenge,
    code_challenge_method: 'S256'
  });

  return `${ZITADEL_ISSUER}/oauth/v2/authorize?${params.toString()}`;
}

export async function exchangeCodeForTokens(code: string): Promise<any> {
  const verifier = loadVerifier();
  if (!verifier) {
    throw new Error('Missing PKCE verifier in sessionStorage');
  }

  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    client_id: CLIENT_ID,
    code,
    redirect_uri: REDIRECT_URI,
    code_verifier: verifier
  });

  const resp = await fetch(`${ZITADEL_ISSUER}/oauth/v2/token`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded'
    },
    body
  });

  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`Token endpoint error: ${resp.status} ${text}`);
  }

  const tokens = await resp.json();
  clearVerifier();
  sessionStorage.setItem('tokens', JSON.stringify(tokens));
  return tokens;
}

export function getTokens(): any | null {
  const raw = sessionStorage.getItem('tokens');
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

export function logoutLocal() {
  sessionStorage.removeItem('tokens');
  clearVerifier();
}

