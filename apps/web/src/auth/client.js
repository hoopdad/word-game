import { PublicClientApplication } from '@azure/msal-browser';
import { createLoginRequest, createMsalConfig } from './msalConfig';

let msalInstance;

export function getMsalInstance() {
  if (!msalInstance) {
    msalInstance = new PublicClientApplication(createMsalConfig());
  }

  return msalInstance;
}

export async function initializeAuth() {
  const client = getMsalInstance();
  await client.initialize();

  const redirectResponse = await client.handleRedirectPromise();
  if (redirectResponse?.account) {
    client.setActiveAccount(redirectResponse.account);
    return redirectResponse.account;
  }

  const existingAccount = client.getActiveAccount() || client.getAllAccounts()[0] || null;
  if (existingAccount) {
    client.setActiveAccount(existingAccount);
  }

  return existingAccount;
}

export async function safeInitializeAuth() {
  try {
    return await initializeAuth();
  } catch {
    return null;
  }
}

export function getActiveAccount() {
  const client = getMsalInstance();
  return client.getActiveAccount() || client.getAllAccounts()[0] || null;
}

export function isAuthenticated() {
  return Boolean(getActiveAccount());
}

export async function login() {
  return getMsalInstance().loginRedirect(createLoginRequest());
}

export async function logout() {
  return getMsalInstance().logoutRedirect({
    postLogoutRedirectUri: createMsalConfig().auth.postLogoutRedirectUri,
  });
}

export function __resetMsalForTests() {
  msalInstance = undefined;
}
