const assert = require('node:assert/strict');
const http = require('node:http');
const test = require('node:test');
const { generateKeyPair, exportJWK, SignJWT } = require('jose');
const { API_ROUTES, AUTH_ERROR_CODES } = require('@word-game/shared');
const { createAuthVerifier } = require('../src/auth');
const { createServer } = require('../src/index');
const { version: apiVersion } = require('../package.json');

function listen(server) {
  return new Promise((resolve, reject) => {
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      resolve(`http://127.0.0.1:${address.port}`);
    });
    server.once('error', reject);
  });
}

function closeServer(server) {
  return new Promise((resolve, reject) => {
    server.close((error) => {
      if (error) {
        reject(error);
        return;
      }
      resolve();
    });
  });
}

function requestJson(baseUrl, path, { method = 'GET', headers = {} } = {}) {
  return new Promise((resolve, reject) => {
    const request = http.request(
      `${baseUrl}${path}`,
      {
        method,
        headers
      },
      (response) => {
        let body = '';
        response.setEncoding('utf8');
        response.on('data', (chunk) => {
          body += chunk;
        });
        response.on('end', () => {
          resolve({
            statusCode: response.statusCode,
            body: JSON.parse(body)
          });
        });
      }
    );
    request.on('error', reject);
    request.end();
  });
}

test('public health route is accessible without auth', async () => {
  const apiServer = createServer({
    config: { port: 0, auth: {} },
    authVerifier: async () => ({})
  });
  const apiBaseUrl = await listen(apiServer);

  try {
    const response = await requestJson(apiBaseUrl, API_ROUTES.healthVersion);
    assert.equal(response.statusCode, 200);
    assert.equal(response.body.status, 'ok');
    assert.equal(response.body.version, apiVersion);
  } finally {
    await closeServer(apiServer);
  }
});

test('protected routes enforce jwt claims and scope', async () => {
  const { publicKey, privateKey } = await generateKeyPair('RS256');
  const publicJwk = await exportJWK(publicKey);
  publicJwk.kid = 'test-key-id';
  publicJwk.alg = 'RS256';
  publicJwk.use = 'sig';

  const authConfig = {
    issuer: 'https://auth.example.com/tenant/v2.0',
    audience: 'api://word-game-api',
    requiredScope: 'game.read',
    jwksUri: ''
  };

  const jwksServer = http.createServer((req, res) => {
    if (req.url === '/.well-known/jwks.json') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ keys: [publicJwk] }));
      return;
    }
    res.writeHead(404).end();
  });
  const jwksBaseUrl = await listen(jwksServer);
  authConfig.jwksUri = `${jwksBaseUrl}/.well-known/jwks.json`;

  const authVerifier = createAuthVerifier(authConfig);
  const apiServer = createServer({
    config: { port: 0, auth: authConfig },
    authVerifier
  });
  const apiBaseUrl = await listen(apiServer);

  async function signAccessToken({
    issuer = authConfig.issuer,
    audience = authConfig.audience,
    scope = authConfig.requiredScope,
    expiresIn = '5m',
    notBefore = '0s'
  } = {}) {
    return new SignJWT({
      sub: 'user-123',
      name: 'Casey',
      scp: scope
    })
      .setProtectedHeader({ alg: 'RS256', kid: 'test-key-id' })
      .setIssuedAt()
      .setIssuer(issuer)
      .setAudience(audience)
      .setNotBefore(notBefore)
      .setExpirationTime(expiresIn)
      .sign(privateKey);
  }

  try {
    const noToken = await requestJson(apiBaseUrl, API_ROUTES.profile);
    assert.equal(noToken.statusCode, 401);
    assert.equal(noToken.body.code, AUTH_ERROR_CODES.missingAuthorizationHeader);

    const malformedAuthHeader = await requestJson(apiBaseUrl, API_ROUTES.profile, {
      headers: {
        authorization: 'Basic abc123'
      }
    });
    assert.equal(malformedAuthHeader.statusCode, 401);
    assert.equal(malformedAuthHeader.body.code, AUTH_ERROR_CODES.invalidAuthorizationHeader);

    const validToken = await signAccessToken();
    const validResponse = await requestJson(apiBaseUrl, API_ROUTES.profile, {
      headers: {
        authorization: `Bearer ${validToken}`
      }
    });
    assert.equal(validResponse.statusCode, 200);
    assert.equal(validResponse.body.userId, 'user-123');

    const wrongIssuerToken = await signAccessToken({ issuer: 'https://other.example.com/tenant/v2.0' });
    const wrongIssuer = await requestJson(apiBaseUrl, API_ROUTES.profile, {
      headers: {
        authorization: `Bearer ${wrongIssuerToken}`
      }
    });
    assert.equal(wrongIssuer.statusCode, 401);
    assert.equal(wrongIssuer.body.code, AUTH_ERROR_CODES.invalidIssuer);

    const wrongAudienceToken = await signAccessToken({ audience: 'api://other-api' });
    const wrongAudience = await requestJson(apiBaseUrl, API_ROUTES.profile, {
      headers: {
        authorization: `Bearer ${wrongAudienceToken}`
      }
    });
    assert.equal(wrongAudience.statusCode, 401);
    assert.equal(wrongAudience.body.code, AUTH_ERROR_CODES.invalidAudience);

    const expiredToken = await signAccessToken({ expiresIn: '-1m' });
    const expiredResponse = await requestJson(apiBaseUrl, API_ROUTES.profile, {
      headers: {
        authorization: `Bearer ${expiredToken}`
      }
    });
    assert.equal(expiredResponse.statusCode, 401);
    assert.equal(expiredResponse.body.code, AUTH_ERROR_CODES.tokenExpired);

    const notYetValidToken = await signAccessToken({ notBefore: '10m' });
    const notYetValidResponse = await requestJson(apiBaseUrl, API_ROUTES.profile, {
      headers: {
        authorization: `Bearer ${notYetValidToken}`
      }
    });
    assert.equal(notYetValidResponse.statusCode, 401);
    assert.equal(notYetValidResponse.body.code, AUTH_ERROR_CODES.tokenNotActive);

    const noScopeToken = await signAccessToken({ scope: 'profile.read' });
    const noScopeResponse = await requestJson(apiBaseUrl, API_ROUTES.profile, {
      headers: {
        authorization: `Bearer ${noScopeToken}`
      }
    });
    assert.equal(noScopeResponse.statusCode, 401);
    assert.equal(noScopeResponse.body.code, AUTH_ERROR_CODES.missingRequiredScope);
  } finally {
    await Promise.all([
      closeServer(apiServer),
      closeServer(jwksServer)
    ]);
  }
});
