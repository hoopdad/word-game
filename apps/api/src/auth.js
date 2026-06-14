const { createRemoteJWKSet, jwtVerify } = require('jose');
const { AUTH_ERROR_CODES } = require('@word-game/shared');

class AuthError extends Error {
  constructor(code, message = 'Unauthorized') {
    super(message);
    this.name = 'AuthError';
    this.code = code;
    this.statusCode = 401;
  }
}

function readBearerToken(authorizationHeader) {
  if (typeof authorizationHeader !== 'string' || authorizationHeader.trim() === '') {
    throw new AuthError(AUTH_ERROR_CODES.missingAuthorizationHeader);
  }

  const [scheme, token, ...remaining] = authorizationHeader.trim().split(/\s+/);
  if (scheme !== 'Bearer' || !token || remaining.length > 0) {
    throw new AuthError(AUTH_ERROR_CODES.invalidAuthorizationHeader);
  }

  return token;
}

function mapJoseError(error) {
  if (!error || typeof error !== 'object') {
    return new AuthError(AUTH_ERROR_CODES.invalidToken);
  }

  if (error.code === 'ERR_JWT_EXPIRED') {
    return new AuthError(AUTH_ERROR_CODES.tokenExpired);
  }

  if (error.code === 'ERR_JWT_CLAIM_VALIDATION_FAILED') {
    if (error.claim === 'iss') {
      return new AuthError(AUTH_ERROR_CODES.invalidIssuer);
    }
    if (error.claim === 'aud') {
      return new AuthError(AUTH_ERROR_CODES.invalidAudience);
    }
    if (error.claim === 'nbf') {
      return new AuthError(AUTH_ERROR_CODES.tokenNotActive);
    }
  }

  return new AuthError(AUTH_ERROR_CODES.invalidToken);
}

function tokenHasScope(scp, requiredScope) {
  if (typeof scp !== 'string') {
    return false;
  }

  return scp
    .split(/\s+/)
    .filter(Boolean)
    .includes(requiredScope);
}

function createAuthVerifier(authConfig, { verify = jwtVerify, jwksFactory } = {}) {
  const createJwks = jwksFactory || ((jwksUri) => createRemoteJWKSet(new URL(jwksUri)));
  const jwks = createJwks(authConfig.jwksUri);

  return async function verifyRequestAuth(request) {
    const token = readBearerToken(request.headers.authorization);

    let payload;
    try {
      ({ payload } = await verify(token, jwks, {
        issuer: authConfig.issuer,
        audience: authConfig.audience
      }));
    } catch (error) {
      throw mapJoseError(error);
    }

    if (!tokenHasScope(payload.scp, authConfig.requiredScope)) {
      throw new AuthError(AUTH_ERROR_CODES.missingRequiredScope);
    }

    return payload;
  };
}

module.exports = {
  AuthError,
  createAuthVerifier,
  mapJoseError,
  readBearerToken,
  tokenHasScope
};
