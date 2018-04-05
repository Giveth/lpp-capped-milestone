const LPPCappedMilestoneAbi = require('../build/LPPCappedMilestone.sol').LPPCappedMilestoneAbi;
const LPPCappedMilestoneByteCode = require('../build/LPPCappedMilestone.sol').LPPCappedMilestoneByteCode;
const generateClass = require('eth-contract-class').default;

const LPPCappedMilestone = generateClass(LPPCappedMilestoneAbi, LPPCappedMilestoneByteCode);

module.exports = LPPCappedMilestone;
