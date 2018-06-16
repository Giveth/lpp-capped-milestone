pragma solidity ^0.4.18;

import "./LPPCappedMilestone.sol";
import "@aragon/os/contracts/factory/AppProxyFactory.sol";
import "@aragon/os/contracts/kernel/Kernel.sol";
import "@aragon/os/contracts/common/VaultRecoverable.sol";
import "giveth-liquidpledging/contracts/LiquidPledging.sol";
import "giveth-liquidpledging/contracts/LPConstants.sol";


contract LPPCappedMilestoneFactory is LPConstants, VaultRecoverable, AppProxyFactory {
    Kernel public kernel;

    bytes32 constant public MILESTONE_APP_ID = keccak256("lpp-capped-milestone");
    bytes32 constant public MILESTONE_APP = keccak256(APP_BASES_NAMESPACE, MILESTONE_APP_ID);
    bytes32 constant public LP_APP_INSTANCE = keccak256(APP_ADDR_NAMESPACE, LP_APP_ID);

    event DeployMilestone(address milestone);

    function LPPCappedMilestoneFactory(address _kernel) public {
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

        DeployMilestone(address(milestone));
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
}
