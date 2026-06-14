import { describe, expect, it } from 'vitest';
import { createLoginRequest, createMsalConfig } from '../auth/msalConfig';

describe('msal config', () => {
  it('uses sessionStorage cache only', () => {
    const config = createMsalConfig({
      VITE_ENTRA_CLIENT_ID: 'client-id',
      VITE_ENTRA_AUTHORITY: 'https://example.ciamlogin.com/example.onmicrosoft.com',
      VITE_ENTRA_REDIRECT_URI: 'http://localhost:5173/',
    });

    expect(config.cache.cacheLocation).toBe('sessionStorage');
    expect(config.cache.storeAuthStateInCookie).toBe(false);
  });

  it('throws when client id is missing', () => {
    expect(() => createMsalConfig({ VITE_ENTRA_CLIENT_ID: '' })).toThrow(
      /VITE_ENTRA_CLIENT_ID/,
    );
  });

  it('parses scope list from env', () => {
    const request = createLoginRequest({ VITE_ENTRA_SCOPES: 'openid, profile, api://scope' });
    expect(request.scopes).toEqual(['openid', 'profile', 'api://scope']);
  });
});
