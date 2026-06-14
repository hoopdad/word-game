const {
  createCategoryAgentService,
  createFoundryCategoryAdapter,
  createLocalCategoryAdapter
} = require('../src');

const service = createCategoryAgentService({
  adapter: createFoundryCategoryAdapter({
    fallbackAdapter: createLocalCategoryAdapter({ mode: 'mock' })
  })
});

if (!service || typeof service.generate !== 'function') {
  throw new Error('Build check failed: service interface is invalid');
}

console.log('build ok');
