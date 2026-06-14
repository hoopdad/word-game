function readRequiredString(env, key) {
  const value = env[key];
  if (typeof value !== 'string' || value.trim() === '') {
    throw new Error(`Missing required environment variable: ${key}`);
  }
  return value.trim();
}

function parseHttpsUrl(value, key) {
  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    throw new Error(`Invalid URL for ${key}`);
  }

  if (parsed.protocol !== 'https:') {
    throw new Error(`${key} must use https`);
  }

  return parsed.toString();
}

function parsePort(value) {
  if (value === undefined) {
    return 3001;
  }

  const port = Number.parseInt(value, 10);
  if (!Number.isInteger(port) || port <= 0 || port > 65535) {
    throw new Error('PORT must be a valid integer between 1 and 65535');
  }

  return port;
}

function loadConfig(env = process.env) {
  return {
    port: parsePort(env.PORT),
    auth: {
      issuer: parseHttpsUrl(readRequiredString(env, 'ENTRA_JWT_ISSUER'), 'ENTRA_JWT_ISSUER'),
      audience: readRequiredString(env, 'ENTRA_JWT_AUDIENCE'),
      requiredScope: readRequiredString(env, 'ENTRA_REQUIRED_SCOPE'),
      jwksUri: parseHttpsUrl(readRequiredString(env, 'ENTRA_JWKS_URI'), 'ENTRA_JWKS_URI')
    }
  };
}

module.exports = {
  loadConfig
};
