const API_CONTRACT_VERSION = 'v1';

const API_ROUTES = Object.freeze({
  healthVersion: '/api/v1/health',
  profile: '/api/v1/profile',
  dashboard: '/api/v1/dashboard',
  categoriesSources: '/api/v1/categories/sources',
  gameStart: '/api/v1/game/start',
  gameActive: '/api/v1/game/active',
  sseEvents: '/api/v1/events/stream'
});

const PROFILE_ERROR_CODES = Object.freeze({
  profileNotFound: 'profile_not_found',
  nameTaken: 'name_taken'
});

const GAME_ERROR_CODES = Object.freeze({
  gameInProgress: 'game_in_progress',
  roundClosed: 'round_closed'
});

const UX_COPY = Object.freeze({
  nameTaken: 'that name is taken.',
  gameInProgress: 'Game in progress. Please wait.'
});

const GAME_STATE = Object.freeze({
  idle: 'idle',
  gatheringCategories: 'gathering_categories',
  inRound: 'in_round',
  finished: 'finished'
});

const GAME_START_STATUS = Object.freeze({
  gatheringCategories: GAME_STATE.gatheringCategories
});

const ROUND_STATUS = Object.freeze({
  active: 'active',
  expired: 'expired',
  closed: 'closed'
});

const EVENT_TYPES = Object.freeze({
  userJoined: 'user.joined',
  userNameReserved: 'user.name_reserved',
  gameStartRequested: 'game.start_requested',
  gameLockAcquired: 'game.lock_acquired',
  categoriesGenerationStarted: 'categories.generation.started',
  categoriesGenerationCompleted: 'categories.generation.completed',
  categoriesGenerationFailed: 'categories.generation.failed',
  roundStarted: 'round.started',
  roundRoleAssigned: 'round.role_assigned',
  guessCorrect: 'guess.correct',
  roundEnded: 'round.ended',
  gameEnded: 'game.ended',
  leaderboardUpdated: 'leaderboard.updated'
});

const CATEGORY_GENERATION_PIPELINE_STATUS = Object.freeze({
  completed: 'completed',
  partial: 'partial',
  failed: 'failed'
});

const CATEGORY_SOURCE_INPUT_CONTRACT = Object.freeze({
  sourceId: 'string',
  url: 'https-url',
  enabled: 'boolean?'
});

const CATEGORY_GENERATION_SOURCE_REQUEST_CONTRACT = Object.freeze({
  requestId: 'string',
  gameId: 'string?',
  correlationId: 'string?',
  mode: '"foundry"|"mock"?',
  maxConcurrency: 'integer>=1?',
  sources: 'array<{sourceId,url,enabled?}>'
});

const CATEGORY_GENERATION_SOURCE_RESULT_CONTRACT = Object.freeze({
  sourceId: 'string',
  url: 'https-url',
  status: '"completed"|"failed"',
  categories: 'array<{name,terms:string[]}>',
  candidateStats: '{wordsExamined,keywordCount,phraseCount}',
  warnings: 'string[]',
  errors: 'string[]'
});

const CATEGORY_GENERATION_PIPELINE_RESULT_CONTRACT = Object.freeze({
  requestId: 'string',
  gameId: 'string?',
  correlationId: 'string?',
  status: Object.values(CATEGORY_GENERATION_PIPELINE_STATUS),
  mode: '"foundry"|"mock"',
  startedAt: 'iso-timestamp',
  completedAt: 'iso-timestamp',
  sourceResults: 'array<CategoryGenerationSourceResult>',
  summary: '{totalSources,succeeded,failed}',
  warnings: 'string[]',
  errors: 'string[]'
});

function validationError(code, path, message) {
  const error = new Error(message);
  error.code = code;
  error.details = { path };
  return error;
}

function isObject(value) {
  return Boolean(value) && Object.prototype.toString.call(value) === '[object Object]';
}

function assertString(value, path, code, { min = 0, max = Number.MAX_SAFE_INTEGER, trim = false } = {}) {
  const candidate = trim && typeof value === 'string' ? value.trim() : value;
  if (typeof candidate !== 'string' || candidate.length < min || candidate.length > max) {
    throw validationError(code, path, `${path} must be a string length ${min}-${max}`);
  }
}

function assertBoolean(value, path, code) {
  if (typeof value !== 'boolean') {
    throw validationError(code, path, `${path} must be boolean`);
  }
}

function assertArray(value, path, code) {
  if (!Array.isArray(value)) {
    throw validationError(code, path, `${path} must be an array`);
  }
}

function assertInteger(value, path, code, min = 0) {
  if (!Number.isInteger(value) || value < min) {
    throw validationError(code, path, `${path} must be an integer >= ${min}`);
  }
}

function assertEnum(value, allowed, path, code) {
  if (!allowed.includes(value)) {
    throw validationError(code, path, `${path} must be one of: ${allowed.join(', ')}`);
  }
}

function assertIsoTimestamp(value, path, code) {
  assertString(value, path, code, { min: 1 });
  if (Number.isNaN(Date.parse(value))) {
    throw validationError(code, path, `${path} must be an ISO timestamp`);
  }
}

function assertHttpsUrl(value, path, code) {
  assertString(value, path, code, { min: 1, trim: true });
  let parsed;
  try {
    parsed = new URL(value);
  } catch {
    throw validationError(code, path, `${path} must be a valid URL`);
  }

  if (parsed.protocol !== 'https:') {
    throw validationError(code, path, `${path} must use https`);
  }
}

function validateCreateProfileRequest(request) {
  if (!isObject(request)) {
    throw validationError('ERR_INVALID_PROFILE_CREATE_REQUEST', 'request', 'request must be an object');
  }
  assertString(request.displayName, 'displayName', 'ERR_INVALID_PROFILE_CREATE_REQUEST', { min: 3, max: 32, trim: true });
  return request;
}

function validateProfileResponse(response) {
  if (!isObject(response)) {
    throw validationError('ERR_INVALID_PROFILE_RESPONSE', 'response', 'response must be an object');
  }
  assertString(response.userId, 'userId', 'ERR_INVALID_PROFILE_RESPONSE', { min: 1 });
  assertString(response.displayName, 'displayName', 'ERR_INVALID_PROFILE_RESPONSE', { min: 1 });
  assertString(response.createdAt, 'createdAt', 'ERR_INVALID_PROFILE_RESPONSE', { min: 1 });
  return response;
}

function validateDashboardResponse(response) {
  if (!isObject(response)) {
    throw validationError('ERR_INVALID_DASHBOARD_RESPONSE', 'response', 'response must be an object');
  }

  assertArray(response.activeUsers, 'activeUsers', 'ERR_INVALID_DASHBOARD_RESPONSE');
  assertArray(response.topAllTime, 'topAllTime', 'ERR_INVALID_DASHBOARD_RESPONSE');
  assertArray(response.topToday, 'topToday', 'ERR_INVALID_DASHBOARD_RESPONSE');

  if (!Number.isInteger(response.totalGamesPlayed) || response.totalGamesPlayed < 0) {
    throw validationError('ERR_INVALID_DASHBOARD_RESPONSE', 'totalGamesPlayed', 'totalGamesPlayed must be >= 0 integer');
  }

  if (response.gameState !== undefined && !Object.values(GAME_STATE).includes(response.gameState)) {
    throw validationError('ERR_INVALID_DASHBOARD_RESPONSE', 'gameState', 'invalid gameState');
  }

  return response;
}

function validateGameStartResponse(response) {
  if (!isObject(response)) {
    throw validationError('ERR_INVALID_GAME_START_RESPONSE', 'response', 'response must be an object');
  }
  assertString(response.gameId, 'gameId', 'ERR_INVALID_GAME_START_RESPONSE', { min: 1 });
  if (!Object.values(GAME_START_STATUS).includes(response.status)) {
    throw validationError('ERR_INVALID_GAME_START_RESPONSE', 'status', 'invalid game start status');
  }
  return response;
}

function validateGameActiveResponse(response) {
  if (!isObject(response)) {
    throw validationError('ERR_INVALID_GAME_ACTIVE_RESPONSE', 'response', 'response must be an object');
  }

  if (!Object.values(GAME_STATE).includes(response.status)) {
    throw validationError('ERR_INVALID_GAME_ACTIVE_RESPONSE', 'status', 'invalid game status');
  }

  if (response.categories !== undefined) {
    assertArray(response.categories, 'categories', 'ERR_INVALID_GAME_ACTIVE_RESPONSE');
  }

  return response;
}

function validateCategoriesSourcesResponse(response) {
  if (!isObject(response)) {
    throw validationError('ERR_INVALID_CATEGORIES_SOURCES_RESPONSE', 'response', 'response must be an object');
  }
  assertArray(response.sources, 'sources', 'ERR_INVALID_CATEGORIES_SOURCES_RESPONSE');
  return response;
}

function validateCreateCategoriesSourceRequest(request) {
  if (!isObject(request)) {
    throw validationError('ERR_INVALID_CATEGORIES_SOURCE_CREATE_REQUEST', 'request', 'request must be an object');
  }

  assertHttpsUrl(request.url, 'url', 'ERR_INVALID_CATEGORIES_SOURCE_CREATE_REQUEST');
  assertBoolean(request.enabled, 'enabled', 'ERR_INVALID_CATEGORIES_SOURCE_CREATE_REQUEST');
  return request;
}

function validateHealthVersionResponse(response) {
  if (!isObject(response)) {
    throw validationError('ERR_INVALID_HEALTH_VERSION_RESPONSE', 'response', 'response must be an object');
  }
  assertString(response.version, 'version', 'ERR_INVALID_HEALTH_VERSION_RESPONSE', { min: 1 });
  assertString(response.status, 'status', 'ERR_INVALID_HEALTH_VERSION_RESPONSE', { min: 1 });
  return response;
}

function validateRoundGuessCorrectRequest(request) {
  if (!isObject(request)) {
    throw validationError('ERR_INVALID_ROUND_GUESS_CORRECT_REQUEST', 'request', 'request must be an object');
  }
  assertString(request.guesserUserId, 'guesserUserId', 'ERR_INVALID_ROUND_GUESS_CORRECT_REQUEST', { min: 1 });
  assertString(request.word, 'word', 'ERR_INVALID_ROUND_GUESS_CORRECT_REQUEST', { min: 1, trim: true });
  assertString(request.judgedBy, 'judgedBy', 'ERR_INVALID_ROUND_GUESS_CORRECT_REQUEST', { min: 1 });
  return request;
}

function validateRoundGuessCorrectResponse(response) {
  if (!isObject(response)) {
    throw validationError('ERR_INVALID_ROUND_GUESS_CORRECT_RESPONSE', 'response', 'response must be an object');
  }
  if (!Number.isInteger(response.awardedPoints) || response.awardedPoints < 0) {
    throw validationError('ERR_INVALID_ROUND_GUESS_CORRECT_RESPONSE', 'awardedPoints', 'awardedPoints must be >= 0 integer');
  }
  assertBoolean(response.nextWordAvailable, 'nextWordAvailable', 'ERR_INVALID_ROUND_GUESS_CORRECT_RESPONSE');
  return response;
}

function validateRoundExpireRequest(request) {
  if (!isObject(request)) {
    throw validationError('ERR_INVALID_ROUND_EXPIRE_REQUEST', 'request', 'request must be an object');
  }
  assertString(request.roundId, 'roundId', 'ERR_INVALID_ROUND_EXPIRE_REQUEST', { min: 1 });
  return request;
}

function validateCategorySourceInput(source, path = 'source', code = 'ERR_INVALID_CATEGORY_GENERATION_SOURCE_REQUEST') {
  if (!isObject(source)) {
    throw validationError(code, path, `${path} must be an object`);
  }

  assertString(source.sourceId, `${path}.sourceId`, code, { min: 1, trim: true });
  assertHttpsUrl(source.url, `${path}.url`, code);

  if (Object.prototype.hasOwnProperty.call(source, 'enabled')) {
    assertBoolean(source.enabled, `${path}.enabled`, code);
  }

  return source;
}

function validateCategoryGenerationSourceRequest(request) {
  const code = 'ERR_INVALID_CATEGORY_GENERATION_SOURCE_REQUEST';
  if (!isObject(request)) {
    throw validationError(code, 'request', 'request must be an object');
  }

  assertString(request.requestId, 'requestId', code, { min: 1, trim: true });

  if (Object.prototype.hasOwnProperty.call(request, 'gameId')) {
    assertString(request.gameId, 'gameId', code, { min: 1, trim: true });
  }
  if (Object.prototype.hasOwnProperty.call(request, 'correlationId')) {
    assertString(request.correlationId, 'correlationId', code, { min: 1, trim: true });
  }
  if (Object.prototype.hasOwnProperty.call(request, 'mode')) {
    assertEnum(request.mode, ['foundry', 'mock'], 'mode', code);
  }
  if (Object.prototype.hasOwnProperty.call(request, 'maxConcurrency')) {
    assertInteger(request.maxConcurrency, 'maxConcurrency', code, 1);
  }

  assertArray(request.sources, 'sources', code);
  if (request.sources.length === 0) {
    throw validationError(code, 'sources', 'sources must include at least one source');
  }

  for (let index = 0; index < request.sources.length; index += 1) {
    validateCategorySourceInput(request.sources[index], `sources[${index}]`, code);
  }

  return request;
}

function normalizeCategoryGenerationSourceRequest(request) {
  validateCategoryGenerationSourceRequest(request);

  const normalized = {
    requestId: request.requestId.trim(),
    mode: request.mode || 'foundry',
    maxConcurrency: request.maxConcurrency || 3,
    sources: request.sources
      .map((source) => ({
        sourceId: source.sourceId.trim(),
        url: source.url.trim(),
        enabled: Object.prototype.hasOwnProperty.call(source, 'enabled') ? source.enabled : true
      }))
      .filter((source) => source.enabled)
  };

  if (request.gameId) {
    normalized.gameId = request.gameId.trim();
  }
  if (request.correlationId) {
    normalized.correlationId = request.correlationId.trim();
  }

  if (normalized.sources.length === 0) {
    throw validationError('ERR_INVALID_CATEGORY_GENERATION_SOURCE_REQUEST', 'sources', 'at least one source must be enabled');
  }

  return normalized;
}

function validateCategoryGenerationSourceResult(sourceResult, path = 'sourceResults[]', code = 'ERR_INVALID_CATEGORY_GENERATION_PIPELINE_RESULT') {
  if (!isObject(sourceResult)) {
    throw validationError(code, path, `${path} must be an object`);
  }

  assertString(sourceResult.sourceId, `${path}.sourceId`, code, { min: 1, trim: true });
  assertHttpsUrl(sourceResult.url, `${path}.url`, code);
  assertEnum(sourceResult.status, ['completed', 'failed'], `${path}.status`, code);
  assertArray(sourceResult.categories, `${path}.categories`, code);

  for (let categoryIndex = 0; categoryIndex < sourceResult.categories.length; categoryIndex += 1) {
    const categoryPath = `${path}.categories[${categoryIndex}]`;
    const category = sourceResult.categories[categoryIndex];
    if (!isObject(category)) {
      throw validationError(code, categoryPath, `${categoryPath} must be an object`);
    }
    assertString(category.name, `${categoryPath}.name`, code, { min: 1, trim: true });
    assertArray(category.terms, `${categoryPath}.terms`, code);
    for (let termIndex = 0; termIndex < category.terms.length; termIndex += 1) {
      assertString(category.terms[termIndex], `${categoryPath}.terms[${termIndex}]`, code, { min: 1, trim: true });
    }
  }

  if (!isObject(sourceResult.candidateStats)) {
    throw validationError(code, `${path}.candidateStats`, `${path}.candidateStats must be an object`);
  }
  assertInteger(sourceResult.candidateStats.wordsExamined, `${path}.candidateStats.wordsExamined`, code, 0);
  assertInteger(sourceResult.candidateStats.keywordCount, `${path}.candidateStats.keywordCount`, code, 0);
  assertInteger(sourceResult.candidateStats.phraseCount, `${path}.candidateStats.phraseCount`, code, 0);

  assertArray(sourceResult.warnings, `${path}.warnings`, code);
  assertArray(sourceResult.errors, `${path}.errors`, code);

  return sourceResult;
}

function validateCategoryGenerationPipelineResult(result) {
  const code = 'ERR_INVALID_CATEGORY_GENERATION_PIPELINE_RESULT';
  if (!isObject(result)) {
    throw validationError(code, 'result', 'result must be an object');
  }

  assertString(result.requestId, 'requestId', code, { min: 1, trim: true });
  if (Object.prototype.hasOwnProperty.call(result, 'gameId')) {
    assertString(result.gameId, 'gameId', code, { min: 1, trim: true });
  }
  if (Object.prototype.hasOwnProperty.call(result, 'correlationId')) {
    assertString(result.correlationId, 'correlationId', code, { min: 1, trim: true });
  }

  assertEnum(result.status, Object.values(CATEGORY_GENERATION_PIPELINE_STATUS), 'status', code);
  assertEnum(result.mode, ['foundry', 'mock'], 'mode', code);
  assertIsoTimestamp(result.startedAt, 'startedAt', code);
  assertIsoTimestamp(result.completedAt, 'completedAt', code);

  assertArray(result.sourceResults, 'sourceResults', code);
  for (let index = 0; index < result.sourceResults.length; index += 1) {
    validateCategoryGenerationSourceResult(result.sourceResults[index], `sourceResults[${index}]`, code);
  }

  if (!isObject(result.summary)) {
    throw validationError(code, 'summary', 'summary must be an object');
  }
  assertInteger(result.summary.totalSources, 'summary.totalSources', code, 0);
  assertInteger(result.summary.succeeded, 'summary.succeeded', code, 0);
  assertInteger(result.summary.failed, 'summary.failed', code, 0);

  assertArray(result.warnings, 'warnings', code);
  assertArray(result.errors, 'errors', code);

  return result;
}

module.exports = {
  API_CONTRACT_VERSION,
  API_ROUTES,
  PROFILE_ERROR_CODES,
  GAME_ERROR_CODES,
  UX_COPY,
  GAME_STATE,
  GAME_START_STATUS,
  ROUND_STATUS,
  EVENT_TYPES,
  CATEGORY_GENERATION_PIPELINE_STATUS,
  CATEGORY_SOURCE_INPUT_CONTRACT,
  CATEGORY_GENERATION_SOURCE_REQUEST_CONTRACT,
  CATEGORY_GENERATION_SOURCE_RESULT_CONTRACT,
  CATEGORY_GENERATION_PIPELINE_RESULT_CONTRACT,
  validateCreateProfileRequest,
  validateProfileResponse,
  validateDashboardResponse,
  validateGameStartResponse,
  validateGameActiveResponse,
  validateCategoriesSourcesResponse,
  validateCreateCategoriesSourceRequest,
  validateHealthVersionResponse,
  validateRoundGuessCorrectRequest,
  validateRoundGuessCorrectResponse,
  validateRoundExpireRequest,
  validateCategorySourceInput,
  validateCategoryGenerationSourceRequest,
  normalizeCategoryGenerationSourceRequest,
  validateCategoryGenerationSourceResult,
  validateCategoryGenerationPipelineResult
};
