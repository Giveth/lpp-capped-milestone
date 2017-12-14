const LPPCappedMilestonesAbi = require('../build/LPPCappedMilestones.sol').LPPCappedMilestonesAbi;
const LPPCappedMilestonesByteCode = require('../build/LPPCappedMilestones.sol').LPPCappedMilestonesByteCode;
const generateClass = require('eth-contract-class').default;

const LPPCappedMilestones = generateClass(LPPCappedMilestonesAbi, LPPCappedMilestonesByteCode);

module.exports = LPPCappedMilestones;
