const { mapWithConcurrency } = require('../utils/bounded-concurrency');
const { groupCategories } = require('../utils/text-processing');
const {
  normalizeCategoryGenerationSourceRequest,
  validateCategoryGenerationPipelineResult,
  CATEGORY_GENERATION_PIPELINE_STATUS
} = require('../../../../packages/shared/contracts');

function createMockText(url) {
  const seedTerms = String(url || 'mock-source')
    .toLowerCase()
    .replace(/https?:\/\//g, '')
    .split(/[^a-z0-9]+/)
    .filter((token) => token.length >= 4)
    .slice(0, 3)
    .join(' ');

  const phraseSeed = seedTerms || 'foundry category';
  return [
    `${phraseSeed} taxonomy workflow supports domain-specific term extraction.`,
    `${phraseSeed} category generation pipeline derives key phrases for game rounds.`,
    `${phraseSeed} deterministic fallback keeps local tests reliable.`
  ].join(' ');
}

async function defaultFetcher(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`fetch failed with status ${response.status}`);
  }
  return response.text();
}

function normalizeRequest(request, adapterMode) {
  const safeRequest = request && typeof request === 'object' ? request : {};
  const options = safeRequest.options && typeof safeRequest.options === 'object' ? safeRequest.options : {};

  const contractRequest = {
    requestId: safeRequest.requestId || 'category-request',
    mode: options.mode || safeRequest.mode || adapterMode || 'foundry',
    sources: Array.isArray(safeRequest.sources)
      ? safeRequest.sources.map((source, index) => ({
          sourceId: source && (source.sourceId || source.id) ? (source.sourceId || source.id) : `source-${index + 1}`,
          url: source && source.url ? source.url : '',
          enabled: source && Object.prototype.hasOwnProperty.call(source, 'enabled') ? source.enabled : true
        }))
      : []
  };

  if (typeof safeRequest.gameId === 'string' && safeRequest.gameId.trim().length > 0) {
    contractRequest.gameId = safeRequest.gameId;
  }
  if (typeof safeRequest.correlationId === 'string' && safeRequest.correlationId.trim().length > 0) {
    contractRequest.correlationId = safeRequest.correlationId;
  }
  if (Number.isInteger(options.concurrency) && options.concurrency > 0) {
    contractRequest.maxConcurrency = options.concurrency;
  } else if (Number.isInteger(safeRequest.maxConcurrency) && safeRequest.maxConcurrency > 0) {
    contractRequest.maxConcurrency = safeRequest.maxConcurrency;
  }

  const normalized = normalizeCategoryGenerationSourceRequest(contractRequest);

  return {
    ...normalized,
    mockContentByUrl: safeRequest.mockContentByUrl && typeof safeRequest.mockContentByUrl === 'object'
      ? safeRequest.mockContentByUrl
      : {}
  };
}

function createLocalCategoryAdapter(config = {}) {
  const adapterMode = config.mode || 'foundry';
  const adapterFetcher = typeof config.fetcher === 'function' ? config.fetcher : defaultFetcher;

  return {
    async generateCategories(request, context = {}) {
      const normalized = normalizeRequest(request, adapterMode);
      const mode = normalized.mode;
      const startedAt = mode === 'mock' ? '2000-01-01T00:00:00.000Z' : new Date().toISOString();
      const fetcher = typeof context.fetcher === 'function' ? context.fetcher : adapterFetcher;

      const sourceResults = await mapWithConcurrency(normalized.sources, normalized.maxConcurrency, async (source) => {
        const warnings = [];
        const errors = [];

        try {
          const content = mode === 'mock'
            ? (normalized.mockContentByUrl[source.url] || createMockText(source.url))
            : await fetcher(source.url);

          const { categories, candidateStats } = groupCategories(content);
          if (candidateStats.keywordCount === 0 && candidateStats.phraseCount === 0) {
            warnings.push('No strong category candidates were extracted');
          }

          return {
            sourceId: source.sourceId,
            url: source.url,
            status: 'completed',
            categories,
            candidateStats,
            warnings,
            errors
          };
        } catch (error) {
          errors.push(error instanceof Error ? error.message : String(error));
          return {
            sourceId: source.sourceId,
            url: source.url,
            status: 'failed',
            categories: [],
            candidateStats: {
              wordsExamined: 0,
              keywordCount: 0,
              phraseCount: 0
            },
            warnings,
            errors
          };
        }
      });

      const failed = sourceResults.filter((result) => result.status === 'failed').length;
      const succeeded = sourceResults.length - failed;
      const warnings = sourceResults.flatMap((result) => result.warnings.map((item) => `${result.sourceId}: ${item}`));
      const errors = sourceResults.flatMap((result) => result.errors.map((item) => `${result.sourceId}: ${item}`));

      const result = {
        requestId: normalized.requestId,
        status: failed === 0
          ? CATEGORY_GENERATION_PIPELINE_STATUS.completed
          : (succeeded > 0 ? CATEGORY_GENERATION_PIPELINE_STATUS.partial : CATEGORY_GENERATION_PIPELINE_STATUS.failed),
        mode,
        startedAt,
        completedAt: mode === 'mock' ? '2000-01-01T00:00:00.000Z' : new Date().toISOString(),
        sourceResults,
        summary: {
          totalSources: normalized.sources.length,
          succeeded,
          failed
        },
        warnings,
        errors
      };

      if (normalized.gameId) {
        result.gameId = normalized.gameId;
      }
      if (normalized.correlationId) {
        result.correlationId = normalized.correlationId;
      }

      return validateCategoryGenerationPipelineResult(result);
    }
  };
}

module.exports = {
  createLocalCategoryAdapter,
  createMockText
};
