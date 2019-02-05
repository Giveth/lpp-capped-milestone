pragma solidity ^0.4.24;

import "./LPPCappedMilestone.sol";
import "@aragon/os/contracts/common/VaultRecoverable.sol";
import "giveth-liquidpledging/contracts/LiquidPledging.sol";
import "giveth-liquidpledging/contracts/LPConstants.sol";
import "giveth-liquidpledging/contracts/lib/aragon/IKernelEnhanced.sol";


contract LPPCappedMilestoneFactory is LPConstants, VaultRecoverable {
    IKernelEnhanced public kernel;

    // bytes32 constant public MILESTONE_APP_ID = keccak256("lpp-capped-milestone");
    bytes32 constant public MILESTONE_APP_ID = 0x1812bee9ebd50582721cefa936103979ff5a674f0e4dd10bef1c1be9fe34bd68;

    event DeployMilestone(address milestone);

    constructor (address _kernel) public {
        // note: this contract will need CREATE_PERMISSIONS_ROLE on the ACL,
        // the PLUGIN_MANAGER_ROLE on liquidPledging,
        // and the APP_MANAGER_ROLE (KERNEL_APP_BASES_NAMESPACE, MILESTONE_APP_ID) on the Kernel.
        // the MILESTONE_APP and LP_APP_INSTANCE need to be registered with the kernel

        require(address(_kernel) != address(0));
        kernel = IKernelEnhanced(_kernel);
    }

    function newMilestone(
        string _name,
        string _url,
        uint64 _parentProject,
        address _reviewer,
        address _recipient,
        address _campaignReviewer,
        address _milestoneManager,
        uint _maxAmount,
        address _acceptedToken,        
        uint _reviewTimeoutSeconds
    ) public
    {
        (LiquidPledging liquidPledging, LPPCappedMilestone milestone, uint64 idProject) = _deployMilestone(_name, _url, _parentProject);
        milestone.initialize(
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

        emit DeployMilestone(address(milestone));
    }

    function getRecoveryVault() public view returns (address) {
        return kernel.getRecoveryVault();
    }

    function _deployMilestone(
        string _name, 
        string _url, 
        uint64 _parentProject
    ) internal returns(LiquidPledging liquidPledging, LPPCappedMilestone milestone, uint64 idProject) 
    {
        address milestoneBase = kernel.getApp(kernel.APP_BASES_NAMESPACE(), MILESTONE_APP_ID);
        require(milestoneBase != address(0));
        liquidPledging = LiquidPledging(kernel.getApp(kernel.APP_ADDR_NAMESPACE(), LP_APP_ID));
        require(address(liquidPledging) != address(0));

        milestone = LPPCappedMilestone(kernel.newAppInstance(MILESTONE_APP_ID, milestoneBase));
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
}
