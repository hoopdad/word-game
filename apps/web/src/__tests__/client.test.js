import { beforeEach, describe, expect, it, vi } from 'vitest';

const { mockClient, PublicClientApplication } = vi.hoisted(() => {
  const client = {
    initialize: vi.fn(),
    handleRedirectPromise: vi.fn(),
    setActiveAccount: vi.fn(),
    getActiveAccount: vi.fn(),
    getAllAccounts: vi.fn(),
    loginRedirect: vi.fn(),
    logoutRedirect: vi.fn(),
  };

  return {
    mockClient: client,
    PublicClientApplication: vi.fn(() => client),
  };
});

vi.mock('@azure/msal-browser', () => ({
  PublicClientApplication,
}));

import {
  __resetMsalForTests,
  getActiveAccount,
  initializeAuth,
  isAuthenticated,
  login,
  logout,
  safeInitializeAuth,
} from '../auth/client';

describe('auth client', () => {
  beforeEach(() => {
    process.env.VITE_ENTRA_CLIENT_ID = 'client-id';
    process.env.VITE_ENTRA_POST_LOGOUT_REDIRECT_URI = 'http://localhost:5173/';

    Object.values(mockClient).forEach((fn) => {
      if (typeof fn.mockReset === 'function') {
        fn.mockReset();
      }
    });

    mockClient.initialize.mockResolvedValue(undefined);
    mockClient.handleRedirectPromise.mockResolvedValue(null);
    mockClient.getActiveAccount.mockReturnValue(null);
    mockClient.getAllAccounts.mockReturnValue([]);

    __resetMsalForTests();
    PublicClientApplication.mockClear();
  });

  it('sets active account from redirect success', async () => {
    const account = { username: 'person@example.com' };
    mockClient.handleRedirectPromise.mockResolvedValue({ account });

    const result = await initializeAuth();

    expect(result).toEqual(account);
    expect(mockClient.setActiveAccount).toHaveBeenCalledWith(account);
  });

  it('returns null on auth failure via safe initializer', async () => {
    mockClient.initialize.mockRejectedValue(new Error('boom'));

    const result = await safeInitializeAuth();

    expect(result).toBeNull();
  });

  it('blocks protected state when no account exists', () => {
    mockClient.getActiveAccount.mockReturnValue(null);
    mockClient.getAllAccounts.mockReturnValue([]);

    expect(getActiveAccount()).toBeNull();
    expect(isAuthenticated()).toBe(false);
  });

  it('delegates login and logout', async () => {
    const expectedRequest = { scopes: ['openid', 'profile', 'email'] };
    mockClient.loginRedirect.mockResolvedValue(undefined);
    mockClient.logoutRedirect.mockResolvedValue(undefined);

    await login();
    await logout();

    expect(mockClient.loginRedirect).toHaveBeenCalledWith(expectedRequest);
    expect(mockClient.logoutRedirect).toHaveBeenCalledWith({
      postLogoutRedirectUri: 'http://localhost:5173/',
    });
  });
});
