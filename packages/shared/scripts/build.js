const shared = require('../src');

const requiredExports = [
  'API_CONTRACT_VERSION',
  'API_ROUTES',
  'CATEGORY_GENERATION_PIPELINE_STATUS',
  'CATEGORY_GENERATION_SOURCE_REQUEST_CONTRACT',
  'CATEGORY_GENERATION_PIPELINE_RESULT_CONTRACT',
  'normalizeCategoryGenerationSourceRequest',
  'validateCategoryGenerationPipelineResult',
  'validateCreateProfileRequest',
  'validateCreateCategoriesSourceRequest'
];

for (const key of requiredExports) {
  if (!Object.prototype.hasOwnProperty.call(shared, key)) {
    throw new Error(`Build contract check failed: missing export "${key}"`);
  }
}

shared.normalizeCategoryGenerationSourceRequest({
  requestId: 'req-build',
  mode: 'mock',
  sources: [{ sourceId: 's1', url: 'https://example.com/source' }]
});

shared.validateCategoryGenerationPipelineResult({
  requestId: 'req-build',
  status: shared.CATEGORY_GENERATION_PIPELINE_STATUS.completed,
  mode: 'mock',
  startedAt: '2026-06-13T23:17:33Z',
  completedAt: '2026-06-13T23:17:34Z',
  sourceResults: [
    {
      sourceId: 's1',
      url: 'https://example.com/source',
      status: 'completed',
      categories: [{ name: 'keywords', terms: ['foundry'] }],
      candidateStats: { wordsExamined: 10, keywordCount: 1, phraseCount: 0 },
      warnings: [],
      errors: []
    }
  ],
  summary: { totalSources: 1, succeeded: 1, failed: 0 },
  warnings: [],
  errors: []
});

console.log('Build contract checks passed.');
