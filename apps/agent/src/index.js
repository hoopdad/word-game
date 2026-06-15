const { version: AGENT_VERSION } = require('../package.json');
const { createCategoryAgentService } = require('./services/category-agent-service');
const { createLocalCategoryAdapter } = require('./adapters/local-category-adapter');
const { createFoundryCategoryAdapter } = require('./adapters/foundry-category-adapter');

module.exports = {
  createCategoryAgentService,
  createFoundryCategoryAdapter,
  createLocalCategoryAdapter
};

if (require.main === module) {
  console.log(`category-agent v${AGENT_VERSION} starting`);
  const service = createCategoryAgentService({
    adapter: createFoundryCategoryAdapter()
  });

  service
    .generate({
      requestId: 'local-dev',
      correlationId: 'local-dev',
      options: { mode: 'mock', concurrency: 2 },
      sources: [{ sourceId: 'demo', url: 'https://example.com/azure/foundry' }]
    })
    .then((result) => {
      console.log(JSON.stringify(result, null, 2));
    })
    .catch((error) => {
      console.error('category-agent failed', error);
      process.exitCode = 1;
    });
}
