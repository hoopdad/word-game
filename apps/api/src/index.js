const http = require('http');
const {
  API_CONTRACT_VERSION,
  API_ROUTES,
  AUTH_ERROR_CODES,
  GAME_START_STATUS,
  GAME_STATE,
  PROTECTED_API_ROUTES,
  validateDashboardResponse,
  validateGameActiveResponse,
  validateGameStartResponse,
  validateHealthVersionResponse,
  validateProfileResponse
} = require('@word-game/shared');
const { AuthError, createAuthVerifier } = require('./auth');
const { loadConfig } = require('./config');

const PROTECTED_ROUTE_SET = new Set(PROTECTED_API_ROUTES);

function writeJson(res, statusCode, body) {
  res.writeHead(statusCode, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
}

function createUnauthorizedBody(code = AUTH_ERROR_CODES.invalidToken) {
  return {
    code,
    message: 'Unauthorized'
  };
}

function getPathname(url) {
  return new URL(url, 'http://localhost').pathname;
}

function createRequestHandler({ authVerifier }) {
  return async function requestHandler(req, res) {
    const pathname = getPathname(req.url || '/');
    let tokenPayload;

    if (PROTECTED_ROUTE_SET.has(pathname)) {
      try {
        tokenPayload = await authVerifier(req);
      } catch (error) {
        if (error instanceof AuthError) {
          writeJson(res, error.statusCode, createUnauthorizedBody(error.code));
          return;
        }

        writeJson(res, 401, createUnauthorizedBody(AUTH_ERROR_CODES.invalidToken));
        return;
      }
    }

    if (req.method === 'GET' && pathname === API_ROUTES.healthVersion) {
      const response = validateHealthVersionResponse({
        version: API_CONTRACT_VERSION,
        status: 'ok'
      });
      writeJson(res, 200, response);
      return;
    }

    if (req.method === 'GET' && pathname === API_ROUTES.profile) {
      const response = validateProfileResponse({
        userId: tokenPayload.sub || tokenPayload.oid || tokenPayload.upn || 'unknown-user',
        displayName: tokenPayload.name || tokenPayload.preferred_username || 'Player',
        createdAt: new Date(0).toISOString()
      });
      writeJson(res, 200, response);
      return;
    }

    if (req.method === 'GET' && pathname === API_ROUTES.dashboard) {
      const response = validateDashboardResponse({
        activeUsers: [],
        totalGamesPlayed: 0,
        topAllTime: [],
        topToday: [],
        gameState: GAME_STATE.idle
      });
      writeJson(res, 200, response);
      return;
    }

    if (req.method === 'POST' && pathname === API_ROUTES.gameStart) {
      const response = validateGameStartResponse({
        gameId: 'game-demo',
        status: GAME_START_STATUS.gatheringCategories
      });
      writeJson(res, 200, response);
      return;
    }

    if (req.method === 'GET' && pathname === API_ROUTES.gameActive) {
      const response = validateGameActiveResponse({
        status: GAME_STATE.idle,
        categories: []
      });
      writeJson(res, 200, response);
      return;
    }

    writeJson(res, 404, {
      code: 'not_found',
      message: 'Not Found'
    });
  };
}

function createServer({ config = loadConfig(), authVerifier = createAuthVerifier(config.auth) } = {}) {
  const handler = createRequestHandler({ authVerifier });
  return http.createServer((req, res) => {
    Promise.resolve(handler(req, res)).catch(() => {
      writeJson(res, 500, {
        code: 'internal_error',
        message: 'Internal Server Error'
      });
    });
  });
}

function startServer() {
  const config = loadConfig();
  const server = createServer({ config });
  server.listen(config.port, () => {
    console.log(`api listening on ${config.port}`);
  });
}

if (require.main === module) {
  startServer();
}

module.exports = {
  createRequestHandler,
  createServer,
  startServer
};
