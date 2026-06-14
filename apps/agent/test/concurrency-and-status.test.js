const test = require('node:test');
const assert = require('node:assert/strict');

const { createCategoryAgentService, createLocalCategoryAdapter, createFoundryCategoryAdapter } = require('../src');
const { CATEGORY_GENERATION_PIPELINE_STATUS } = require('../../../packages/shared/contracts');

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

test('bounded concurrency fetch flow and partial status for source failures', async () => {
  let active = 0;
  let maxActive = 0;

  const fetcher = async (url) => {
    active += 1;
    maxActive = Math.max(maxActive, active);

    try {
      if (url.includes('slow')) {
        await delay(20);
      } else {
        await delay(5);
      }

      if (url.includes('fail')) {
        throw new Error('simulated fetch failure');
      }

      return 'neural ranking model neural ranking model robust categorization';
    } finally {
      active -= 1;
    }
  };

  const service = createCategoryAgentService({
    adapter: createLocalCategoryAdapter({ fetcher })
  });

  const result = await service.generate({
    requestId: 'req-2',
    gameId: 'game-1',
    options: { concurrency: 2 },
    sources: [
      { sourceId: 's1', url: 'https://example.com/slow-1' },
      { sourceId: 's2', url: 'https://example.com/fast-2' },
      { sourceId: 's3', url: 'https://example.com/fail-3' },
      { sourceId: 's4', url: 'https://example.com/slow-4' }
    ]
  });

  assert.equal(result.status, CATEGORY_GENERATION_PIPELINE_STATUS.partial);
  assert.equal(result.summary.totalSources, 4);
  assert.equal(result.summary.succeeded, 3);
  assert.equal(result.summary.failed, 1);
  assert.ok(maxActive <= 2, `expected max concurrency <= 2, got ${maxActive}`);
  assert.deepEqual(result.sourceResults.map((source) => source.sourceId), ['s1', 's2', 's3', 's4']);
  assert.equal(result.sourceResults.find((item) => item.sourceId === 's3').status, 'failed');
});

test('foundry adapter falls back to deterministic mock mode when invokeFoundry is missing', async () => {
  const service = createCategoryAgentService({
    adapter: createFoundryCategoryAdapter()
  });

  const result = await service.generate({
    requestId: 'req-foundry-fallback',
    options: { mode: 'foundry' },
    sources: [{ sourceId: 's1', url: 'https://example.com/foundry/topic' }]
  });

  assert.equal(result.status, CATEGORY_GENERATION_PIPELINE_STATUS.completed);
  assert.equal(result.mode, 'mock');
  assert.equal(result.sourceResults.length, 1);
  assert.equal(result.sourceResults[0].status, 'completed');
});
