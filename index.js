const generateClass = require('eth-contract-class').default;

const factoryArtifact = require('./dist/contracts/LPPCappedMilestoneFactory.json');
const milestoneArtifact = require('./dist/contracts/LPPCappedMilestone.json');

module.exports = {
  LPPCappedMilestone: generateClass(milestoneArtifact.abiDefinition, milestoneArtifact.code),
  LPPCappedMilestoneFactory: generateClass(factoryArtifact.abiDefinition, factoryArtifact.code),
};
