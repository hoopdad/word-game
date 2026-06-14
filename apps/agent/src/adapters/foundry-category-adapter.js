const { createLocalCategoryAdapter } = require('./local-category-adapter');
const { validateCategoryGenerationPipelineResult } = require('../../../../packages/shared/contracts');

function createFoundryCategoryAdapter(config = {}) {
  const fallbackAdapter = config.fallbackAdapter || createLocalCategoryAdapter({ mode: 'mock' });

  if (!fallbackAdapter || typeof fallbackAdapter.generateCategories !== 'function') {
    throw new TypeError('fallbackAdapter must implement generateCategories(request, context)');
  }

  return {
    async generateCategories(request, context = {}) {
      const invokeFoundry = config.invokeFoundry;
      const requestedMode = (request && request.options && request.options.mode) || request.mode;
      const mockRequest = {
        ...request,
        mode: 'mock',
        options: { ...(request && request.options ? request.options : {}), mode: 'mock' }
      };

      if (requestedMode === 'mock') {
        return fallbackAdapter.generateCategories(mockRequest, context);
      }

      if (typeof invokeFoundry !== 'function') {
        return fallbackAdapter.generateCategories(mockRequest, context);
      }

      try {
        const result = await invokeFoundry(request, context);
        return validateCategoryGenerationPipelineResult(result);
      } catch (error) {
        if (context.disableFallback) {
          throw error;
        }

        return fallbackAdapter.generateCategories(mockRequest, context);
      }
    }
  };
}

module.exports = {
  createFoundryCategoryAdapter
};
