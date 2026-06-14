const { apiContractVersion } = require('../contracts');
const { typeMarkers } = require('../types');

function sharedStub() {
  return 'shared package stub';
}

module.exports = {
  apiContractVersion,
  sharedStub,
  typeMarkers
};
