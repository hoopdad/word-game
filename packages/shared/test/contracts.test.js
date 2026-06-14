const test = require('node:test');
const assert = require('node:assert/strict');

const contracts = require('../contracts');

test('exports required copy and route contracts', () => {
  assert.equal(contracts.API_CONTRACT_VERSION, 'v1');
  assert.equal(contracts.API_ROUTES.profile, '/api/v1/profile');
  assert.equal(contracts.UX_COPY.nameTaken, 'that name is taken.');
  assert.equal(contracts.UX_COPY.gameInProgress, 'Game in progress. Please wait.');
  assert.deepEqual(contracts.PUBLIC_API_ROUTES, ['/api/v1/health']);
  assert.equal(contracts.PROTECTED_API_ROUTES.includes('/api/v1/profile'), true);
});

test('exports auth error contracts', () => {
  assert.equal(contracts.AUTH_ERROR_CODES.invalidIssuer, 'invalid_issuer');
  assert.equal(contracts.AUTH_ERROR_CODES.missingRequiredScope, 'missing_required_scope');
  assert.equal(
    contracts.AUTH_UNAUTHORIZED_RESPONSE_CONTRACT.code.includes(contracts.AUTH_ERROR_CODES.invalidToken),
    true
  );
  assert.equal(contracts.AUTH_UNAUTHORIZED_RESPONSE_CONTRACT.message, 'string');
});

test('validates profile and category source request contracts', () => {
  const profile = { displayName: 'PlayerOne' };
  const source = { url: 'https://learn.microsoft.com', enabled: true };

  assert.equal(contracts.validateCreateProfileRequest(profile), profile);
  assert.equal(contracts.validateCreateCategoriesSourceRequest(source), source);
});

test('validates dashboard and game responses', () => {
  const dashboard = {
    activeUsers: [{ userId: 'u1', displayName: 'Alpha' }],
    totalGamesPlayed: 2,
    topAllTime: [{ displayName: 'Alpha', score: 10 }],
    topToday: [{ displayName: 'Alpha', score: 5 }],
    gameState: contracts.GAME_STATE.idle
  };

  const start = { gameId: 'g1', status: contracts.GAME_STATE.gatheringCategories };
  const active = { id: 'g1', status: contracts.GAME_STATE.inRound, categories: ['Space Objects'] };

  assert.equal(contracts.validateDashboardResponse(dashboard), dashboard);
  assert.equal(contracts.validateGameStartResponse(start), start);
  assert.equal(contracts.validateGameActiveResponse(active), active);
});

test('rejects invalid name and invalid categories source input', () => {
  assert.throws(() => contracts.validateCreateProfileRequest({ displayName: 'x' }));
  assert.throws(() => contracts.validateCreateCategoriesSourceRequest({ url: 'not-url', enabled: true }));
});
