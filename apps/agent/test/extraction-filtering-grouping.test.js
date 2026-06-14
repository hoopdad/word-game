const test = require('node:test');
const assert = require('node:assert/strict');

const { extractWords, extractPhrases, groupCategories } = require('../src/utils/text-processing');
const { createCategoryAgentService, createLocalCategoryAdapter } = require('../src');

test('extractWords strips html and captures candidate words', () => {
  const words = extractWords('<h1>Azure AI Foundry</h1><p>Model deployment pipelines for AI.</p>');
  assert.ok(words.includes('azure'));
  assert.ok(words.includes('foundry'));
  assert.ok(words.includes('deployment'));
});

test('extractPhrases includes 2-3 word phrases with domain signal', () => {
  const phrases = extractPhrases(['azure', 'ai', 'foundry', 'model', 'deployment', 'pipeline']);
  assert.ok(phrases.includes('azure ai'));
  assert.ok(phrases.includes('model deployment'));
  assert.ok(phrases.includes('ai foundry model'));
});

test('groupCategories filters generic terms while preserving domain-specific categories', () => {
  const content = [
    'Azure AI Foundry model deployment pipeline improves reliability.',
    'Azure AI Foundry model deployment supports managed endpoints.',
    'This page contains information and content for deployment architecture.'
  ].join(' ');

  const grouped = groupCategories(content);
  const keywordCategory = grouped.categories.find((category) => category.name === 'keywords');
  const phraseCategory = grouped.categories.find((category) => category.name === 'key_phrases');

  assert.ok(keywordCategory.terms.includes('deployment'));
  assert.ok(keywordCategory.terms.includes('foundry'));
  assert.ok(!keywordCategory.terms.includes('information'));
  assert.ok(phraseCategory.terms.includes('model deployment'));
});

test('local adapter mock mode is deterministic for same request', async () => {
  const service = createCategoryAgentService({
    adapter: createLocalCategoryAdapter({ mode: 'mock' })
  });

  const request = {
    requestId: 'req-deterministic',
    options: { mode: 'mock' },
    sources: [{ sourceId: 's1', url: 'https://contoso.example.com/network/security' }]
  };

  const first = await service.generate(request);
  const second = await service.generate(request);

  assert.deepEqual(first, second);
});
