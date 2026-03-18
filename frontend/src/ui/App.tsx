import React, { useEffect, useState } from 'react';
import {
  buildAuthUrl,
  createPkce,
  exchangeCodeForTokens,
  getTokens,
  logoutLocal,
  saveVerifier
} from '../auth';

type Tokens = {
  access_token: string;
  id_token?: string;
  refresh_token?: string;
};

export const App: React.FC = () => {
  const [tokens, setTokens] = useState<Tokens | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const existing = getTokens();
    if (existing) {
      setTokens(existing);
    }

    const url = new URL(window.location.href);
    const code = url.searchParams.get('code');
    const err = url.searchParams.get('error');

    if (err) {
      setError(`OIDC error: ${err}`);
    }

    if (code && !existing) {
      exchangeCodeForTokens(code)
        .then((t) => {
          setTokens(t);
          url.searchParams.delete('code');
          url.searchParams.delete('state');
          window.history.replaceState({}, '', url.toString());
        })
        .catch((e: any) => setError(String(e)));
    }
  }, []);

  const handleLogin = async () => {
    setError(null);
    const { verifier, challenge } = await createPkce();
    saveVerifier(verifier);
    const url = buildAuthUrl(challenge);
    window.location.href = url;
  };

  const handleLogout = () => {
    logoutLocal();
    setTokens(null);
  };

  return (
    <div style={{ fontFamily: 'system-ui, sans-serif', padding: '2rem', maxWidth: 800, margin: '0 auto' }}>
      <h1>Zitadel PKCE Frontend Demo</h1>
      <p>Simple SPA using Authorization Code + PKCE against your local Zitadel.</p>

      {!tokens ? (
        <button onClick={handleLogin} style={{ padding: '0.5rem 1rem', fontSize: '1rem' }}>
          Login with Zitadel
        </button>
      ) : (
        <>
          <button onClick={handleLogout} style={{ padding: '0.5rem 1rem', fontSize: '1rem' }}>
            Logout (local)
          </button>
          <h2 style={{ marginTop: '2rem' }}>Tokens (from Zitadel)</h2>
          <pre
            style={{
              background: '#111',
              color: '#eee',
              padding: '1rem',
              borderRadius: 8,
              overflowX: 'auto'
            }}
          >
            {JSON.stringify(tokens, null, 2)}
          </pre>
        </>
      )}

      {error && (
        <p style={{ marginTop: '1rem', color: 'red' }}>
          {error}
        </p>
      )}
    </div>
  );
};

