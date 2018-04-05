pragma solidity ^0.4.18;

import "./LPPCappedMilestone.sol";
import "minimetoken/contracts/MiniMeToken.sol";
import "@aragon/os/contracts/factory/AppProxyFactory.sol";
import "@aragon/os/contracts/kernel/Kernel.sol";
import "giveth-liquidpledging/contracts/LiquidPledging.sol";
import "giveth-liquidpledging/contracts/LPConstants.sol";
import "giveth-common-contracts/contracts/Escapable.sol";

contract LPPCappedMilestoneFactory is LPConstants, Escapable, AppProxyFactory {
    Kernel public kernel;
    MiniMeTokenFactory public tokenFactory;

    bytes32 constant public MILESTONE_APP_ID = keccak256("lpp-capped-milestone");
    bytes32 constant public MILESTONE_APP = keccak256(APP_BASES_NAMESPACE, MILESTONE_APP_ID);
    bytes32 constant public LP_APP_INSTANCE = keccak256(APP_ADDR_NAMESPACE, LP_APP_ID);

    event DeployCampaign(address milestone);

    function LPPCappedMilestoneFactory(address _kernel, address _tokenFactory, address _escapeHatchCaller, address _escapeHatchDestination)
        Escapable(_escapeHatchCaller, _escapeHatchDestination) public
    {
        // note: this contract will need CREATE_PERMISSIONS_ROLE on the ACL
        // and the PLUGIN_MANAGER_ROLE on liquidPledging,
        // the MILESTONE_APP and LP_APP_INSTANCE need to be registered with the kernel

        require(_kernel != 0x0);
        require(_tokenFactory != 0x0);
        kernel = Kernel(_kernel);
        tokenFactory = MiniMeTokenFactory(_tokenFactory);
    }

    function newMilestone(
        string name,
        string url,
        uint64 parentProject,
        address reviewer,
        string tokenName,
        string tokenSymbol,
        address escapeHatchCaller,
        address escapeHatchDestination,
        address recipient,
        address campaignReviewer,
        uint maxAmount
    ) public
    {
        address milestoneBase = kernel.getApp(MILESTONE_APP);
        require(milestoneBase != 0);
        address liquidPledging = kernel.getApp(LP_APP_INSTANCE);
        require(liquidPledging != 0);

        // TODO: could make MiniMeToken an AragonApp to save gas by deploying a proxy
        address token = new MiniMeToken(tokenFactory, 0x0, 0, tokenName, 18, tokenSymbol, false);

        LiquidPledging(liquidPledging).addValidPluginInstance(address(milestone));

        LPPCappedMilestone milestone = _init(name, url, parentProject, reviewer, escapeHatchDestination, recipient, campaignReviewer, maxAmount, liquidPledging, token);

        MiniMeToken(token).changeController(address(milestone));

        _setPermissions(milestone, reviewer, recipient, escapeHatchCaller);

        DeployCampaign(address(milestone));
    }

    function _setPermissions(
        LPPCappedMilestone milestone,
        address reviewer,
        address recipient,
        address escapeHatchCaller
    ) internal
    {
        ACL acl = ACL(kernel.acl());

        bytes32 hatchCallerRole = milestone.ESCAPE_HATCH_CALLER_ROLE();
        bytes32 reviewerRole = milestone.REVIEWER_ROLE();
        bytes32 recipientRole = milestone.RECIPIENT_ROLE();
        bytes32 adminRole = milestone.ADMIN_ROLE();

        acl.createPermission(reviewer, address(milestone), reviewerRole, address(milestone));
        acl.createPermission(recipient, address(milestone), recipientRole, address(milestone));
        acl.createPermission(escapeHatchCaller, address(milestone), hatchCallerRole, escapeHatchCaller);
        acl.createPermission(msg.sender, address(milestone), adminRole, msg.sender);
    }

    function _init(
        string name,
        string url,
        uint64 parentProject,
        address reviewer,
        address escapeHatchDestination,
        address recipient,
        address campaignReviewer,
        uint maxAmount,
        address liquidPledging,
        address token
    ) internal returns (LPPCappedMilestone)
    {
        LPPCappedMilestone milestone = LPPCappedMilestone(newAppProxy(kernel, MILESTONE_APP_ID));

        milestone.initializeLP(name, url, liquidPledging, parentProject);
        milestone.initialize(token, escapeHatchDestination, reviewer, campaignReviewer, recipient, maxAmount);

        return milestone;
    }
}
