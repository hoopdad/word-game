/** @typedef {{ userId: string, displayName: string }} UserProfile */

const typeMarkers = {
  userProfile: 'UserProfile',
  categoryGenerationSourceRequest: 'CategoryGenerationSourceRequest',
  categoryGenerationPipelineResult: 'CategoryGenerationPipelineResult'
};

module.exports = {
  typeMarkers
};
