const contracts = require('../contracts');
const { typeMarkers } = require('../types');

function sharedStub() {
  return 'shared package stub';
}

module.exports = {
  ...contracts,
  sharedStub,
  typeMarkers
};
