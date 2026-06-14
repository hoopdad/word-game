const test = require('node:test');
const assert = require('node:assert/strict');

const contracts = require('../contracts');

test('normalizeCategoryGenerationSourceRequest trims and filters disabled sources', () => {
  const normalized = contracts.normalizeCategoryGenerationSourceRequest({
    requestId: ' req-source-1 ',
    gameId: ' game-7 ',
    correlationId: ' corr-9 ',
    mode: 'mock',
    maxConcurrency: 4,
    sources: [
      { sourceId: ' docs ', url: ' https://example.com/docs ', enabled: true },
      { sourceId: ' skip ', url: ' https://example.com/skip ', enabled: false }
    ]
  });

  assert.deepEqual(normalized, {
    requestId: 'req-source-1',
    gameId: 'game-7',
    correlationId: 'corr-9',
    mode: 'mock',
    maxConcurrency: 4,
    sources: [{ sourceId: 'docs', url: 'https://example.com/docs', enabled: true }]
  });
});

test('validateCategoryGenerationSourceRequest rejects missing sources', () => {
  assert.throws(
    () => contracts.validateCategoryGenerationSourceRequest({ requestId: 'req-1', sources: [] }),
    (error) => error.code === 'ERR_INVALID_CATEGORY_GENERATION_SOURCE_REQUEST' && error.details.path === 'sources'
  );
});

test('validateCategoryGenerationPipelineResult accepts orchestration payload', () => {
  const dto = {
    requestId: 'req-10',
    gameId: 'game-10',
    correlationId: 'corr-10',
    status: contracts.CATEGORY_GENERATION_PIPELINE_STATUS.partial,
    mode: 'mock',
    startedAt: '2026-06-13T23:17:33Z',
    completedAt: '2026-06-13T23:17:34Z',
    sourceResults: [
      {
        sourceId: 's1',
        url: 'https://example.com/s1',
        status: 'completed',
        categories: [{ name: 'keywords', terms: ['foundry', 'taxonomy'] }],
        candidateStats: { wordsExamined: 120, keywordCount: 5, phraseCount: 3 },
        warnings: [],
        errors: []
      }
    ],
    summary: { totalSources: 1, succeeded: 1, failed: 0 },
    warnings: [],
    errors: []
  };

  assert.equal(contracts.validateCategoryGenerationPipelineResult(dto), dto);
});
