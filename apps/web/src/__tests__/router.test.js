import { describe, expect, it } from 'vitest';
import { normalizePath, resolveRoute } from '../router';

describe('router protection', () => {
  it('keeps landing route public', () => {
    expect(resolveRoute('/', false)).toEqual({ type: 'public', path: '/' });
  });

  it('blocks unauthenticated protected route', () => {
    expect(resolveRoute('/app', false)).toEqual({
      type: 'blocked',
      path: '/app',
      redirectTo: '/',
    });
  });

  it('allows authenticated protected route', () => {
    expect(resolveRoute('/app/game', true)).toEqual({
      type: 'protected',
      path: '/app/game',
    });
  });

  it('normalizes trailing slash', () => {
    expect(normalizePath('/app/')).toBe('/app');
  });
});
