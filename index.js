const generateClass = require('eth-contract-class').default;

const factoryArtifact = require('./build/LPPCappedMilestoneFactory.json');
const milestoneArtifact = require('./build/LPPCappedMilestone.json');

module.exports = {
  LPPCappedMilestone: generateClass(
    milestoneArtifact.compilerOutput.abi,
    milestoneArtifact.compilerOutput.evm.bytecode.object,
  ),
  LPPCappedMilestoneFactory: generateClass(
    factoryArtifact.compilerOutput.abi,
    factoryArtifact.compilerOutput.evm.bytecode.object,
  ),
};