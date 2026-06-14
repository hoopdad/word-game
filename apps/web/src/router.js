const LANDING_ROUTE = '/';
const PROTECTED_PREFIX = '/app';

export function normalizePath(pathname) {
  if (!pathname || pathname === '/') {
    return '/';
  }

  return pathname.endsWith('/') ? pathname.slice(0, -1) : pathname;
}

export function resolveRoute(pathname, authenticated) {
  const path = normalizePath(pathname);

  if (path === LANDING_ROUTE) {
    return { type: 'public', path: LANDING_ROUTE };
  }

  if (path === PROTECTED_PREFIX || path.startsWith(`${PROTECTED_PREFIX}/`)) {
    if (authenticated) {
      return { type: 'protected', path };
    }

    return { type: 'blocked', path, redirectTo: LANDING_ROUTE };
  }

  return { type: 'public', path: LANDING_ROUTE, redirectTo: LANDING_ROUTE };
}
