const DEFAULT_AUTHORITY = 'https://login.microsoftonline.com/common';
const DEFAULT_REDIRECT_URI = 'http://localhost:5173/';

function getRuntimeEnv() {
  const fromImportMeta = typeof import.meta !== 'undefined' && import.meta.env ? import.meta.env : {};
  const fromProcess = typeof process !== 'undefined' && process.env ? process.env : {};
  return { ...fromImportMeta, ...fromProcess };
}

function required(value, key) {
  if (!value || String(value).trim() === '') {
    throw new Error(`Missing required environment variable: ${key}`);
  }

  return value;
}

export function createMsalConfig(envOverride = {}) {
  const env = { ...getRuntimeEnv(), ...envOverride };

  return {
    auth: {
      clientId: required(env.VITE_ENTRA_CLIENT_ID, 'VITE_ENTRA_CLIENT_ID'),
      authority: env.VITE_ENTRA_AUTHORITY || DEFAULT_AUTHORITY,
      redirectUri: env.VITE_ENTRA_REDIRECT_URI || DEFAULT_REDIRECT_URI,
      postLogoutRedirectUri: env.VITE_ENTRA_POST_LOGOUT_REDIRECT_URI || DEFAULT_REDIRECT_URI,
      navigateToLoginRequestUrl: false,
    },
    cache: {
      cacheLocation: 'sessionStorage',
      storeAuthStateInCookie: false,
    },
  };
}

export function createLoginRequest(envOverride = {}) {
  const env = { ...getRuntimeEnv(), ...envOverride };
  const scopes = (env.VITE_ENTRA_SCOPES || 'openid,profile,email')
    .split(',')
    .map((scope) => scope.trim())
    .filter(Boolean);

  return { scopes };
}
