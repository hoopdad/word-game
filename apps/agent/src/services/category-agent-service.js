function validateAdapter(adapter) {
  if (!adapter || typeof adapter.generateCategories !== 'function') {
    throw new TypeError('adapter must implement generateCategories(request, context)');
  }
}

function createCategoryAgentService({ adapter }) {
  validateAdapter(adapter);

  return {
    async generate(request, context = {}) {
      return adapter.generateCategories(request, context);
    }
  };
}

module.exports = {
  createCategoryAgentService
};
