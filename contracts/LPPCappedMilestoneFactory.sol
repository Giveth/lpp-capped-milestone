pragma solidity ^0.4.18;

import "./LPPCappedMilestone.sol";
import "@aragon/os/contracts/factory/AppProxyFactory.sol";
import "@aragon/os/contracts/kernel/Kernel.sol";
import "giveth-liquidpledging/contracts/LiquidPledging.sol";
import "giveth-liquidpledging/contracts/LPConstants.sol";
import "giveth-common-contracts/contracts/Escapable.sol";

contract LPPCappedMilestoneFactory is LPConstants, Escapable, AppProxyFactory {
    Kernel public kernel;

    bytes32 constant public MILESTONE_APP_ID = keccak256("lpp-capped-milestone");
    bytes32 constant public MILESTONE_APP = keccak256(APP_BASES_NAMESPACE, MILESTONE_APP_ID);
    bytes32 constant public LP_APP_INSTANCE = keccak256(APP_ADDR_NAMESPACE, LP_APP_ID);

    string name;
    string url;
    uint64 parentProject;
    address reviewer;
    address escapeHatchCaller;
    address escapeHatchDestination;
    address recipient;
    address campaignReviewer;
    address milestoneManager;
    uint maxAmount;
    address acceptedToken;
    uint reviewTimeoutSeconds;

    event DeployMilestone(address milestone);

    function LPPCappedMilestoneFactory(address _kernel, address _escapeHatchCaller, address _escapeHatchDestination)
        Escapable(_escapeHatchCaller, _escapeHatchDestination) public
    {
        // note: this contract will need CREATE_PERMISSIONS_ROLE on the ACL
        // and the PLUGIN_MANAGER_ROLE on liquidPledging,
        // the MILESTONE_APP and LP_APP_INSTANCE need to be registered with the kernel

        require(_kernel != 0x0);
        kernel = Kernel(_kernel);
    }

    function newMilestone(
        string _name,
        string _url,
        uint64 _parentProject,
        address _reviewer,
        address _escapeHatchCaller,
        address _escapeHatchDestination,
        address _recipient,
        address _campaignReviewer,
        address _milestoneManager,
        uint _maxAmount,
        address _acceptedToken,        
        uint _reviewTimeoutSeconds
    ) public
    {
        var (liquidPledging, milestone, idProject) = _deployMilestone(_name, _url, _parentProject);
        milestone.initialize(
            _escapeHatchDestination,
            _reviewer,
            _campaignReviewer,
            _recipient,
            _milestoneManager,
            _reviewTimeoutSeconds,
            _maxAmount,
            _acceptedToken,
            liquidPledging,
            idProject
        );

        _setPermissions(milestone, _reviewer, _recipient, _milestoneManager, _escapeHatchCaller);

        DeployMilestone(address(milestone));
    }

    function _deployMilestone(
        string _name, 
        string _url, 
        uint64 _parentProject
    ) internal returns(LiquidPledging liquidPledging, LPPCappedMilestone milestone, uint64 idProject) 
    {
        address milestoneBase = kernel.getApp(MILESTONE_APP);
        require(milestoneBase != 0);
        liquidPledging = LiquidPledging(kernel.getApp(LP_APP_INSTANCE));
        require(address(liquidPledging) != 0);

        milestone = LPPCappedMilestone(newAppProxy(kernel, MILESTONE_APP_ID));
        liquidPledging.addValidPluginInstance(address(milestone));

        idProject = liquidPledging.addProject(
            _name,
            _url,
            address(milestone),
            _parentProject,
            0,
            ILiquidPledgingPlugin(milestone)
        );  
    }

    function _setPermissions(
        LPPCappedMilestone milestone,
        address reviewer,
        address recipient,
        address milestoneManager,
        address escapeHatchCaller
    ) internal
    {
        ACL acl = ACL(kernel.acl());

        bytes32 hatchCallerRole = milestone.ESCAPE_HATCH_CALLER_ROLE();
        bytes32 reviewerRole = milestone.REVIEWER_ROLE();
        bytes32 recipientRole = milestone.RECIPIENT_ROLE();
        bytes32 manageRole = milestone.MANAGER_ROLE();

        acl.createPermission(reviewer, address(milestone), reviewerRole, address(milestone));
        acl.createPermission(recipient, address(milestone), recipientRole, address(milestone));
        acl.createPermission(escapeHatchCaller, address(milestone), hatchCallerRole, escapeHatchCaller);
        acl.createPermission(milestoneManager, address(milestone), manageRole, milestoneManager);
    }
}
