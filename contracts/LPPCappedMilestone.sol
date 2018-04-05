pragma solidity ^0.4.17;

/*
    Copyright 2017, RJ Ewing <perissology@protonmail.com>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

import "giveth-liquidpledging/contracts/LiquidPledging.sol";
import "giveth-liquidpledging/contracts/EscapableApp.sol";
import "giveth-common-contracts/contracts/ERC20.sol";
import "minimetoken/contracts/MiniMeToken.sol";
import "@aragon/os/contracts/acl/ACL.sol";
import "@aragon/os/contracts/kernel/KernelProxy.sol";
import "@aragon/os/contracts/kernel/Kernel.sol";


/// @title LPPCappedMilestone
/// @author RJ Ewing<perissology@protonmail.com>
/// @notice The LPPCappedMilestone contract is a plugin contract for liquidPledging,
///  extending the functionality of a liquidPledging project. This contract
///  prevents withdrawals from any pledges this contract is the owner of.
///  This contract has 4 roles. The admin, a reviewer, and a recipient role. 
///
///  1. The admin can cancel the milestone, update the conditions the milestone accepts transfers
///  and send a tx as the milestone. 
///  2. The reviewer can cancel the milestone. 
///  3. The recipient role will receive the pledge's owned by this milestone. 

contract LPPCappedMilestone is EscapableApp, TokenController {
    uint constant TO_OWNER = 256;
    uint constant TO_INTENDEDPROJECT = 511;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant REVIEWER_ROLE = keccak256("REVIEWER_ROLE");
    bytes32 public constant RECIPIENT_ROLE = keccak256("RECIPIENT_ROLE");

    MiniMeToken public campaignToken;
    LiquidPledging public liquidPledging;
    uint64 public idProject;

    address public reviewer;
    address public newReviewer;    
    address public recipient;
    address public newRecipient;
    address public campaignReviewer;
    uint public maxAmount;
    uint public received;
    uint public canCollect;
    bool public accepted;

    // first param should be liquidpledging address
    event MilestoneAccepted(uint64 indexed idProject);
    event PaymentCollected(uint64 indexed idProject);

    //== constructor

   function initialize(address _escapeHatchDestination) onlyInit public {
        require(false); // overload the EscapableApp
        _escapeHatchDestination;
    }

    function initialize(
        address _token,        
        address _escapeHatchDestination,
        address _reviewer,
        address _campaignReviewer,
        address _recipient,
        uint _maxAmount
    ) onlyInit external
    {
        // try moving return to see if the stack fails
        // initialize 1
        // initialize 2, then call super.initalize
        super.initialize(_escapeHatchDestination);

        require(_recipient != 0);
        require(_reviewer != 0);
        require(_campaignReviewer != 0);

        reviewer = _reviewer;
        campaignReviewer = _campaignReviewer;
        recipient = _recipient;
        maxAmount = _maxAmount;
        accepted = false;
        canCollect = 0;

        campaignToken = MiniMeToken(_token);
    }

    function initializeLP(
        string _name,
        string _url,        
        address _liquidPledging,
        uint64 _parentProject
    ) onlyInit external
    {
        require(_liquidPledging != 0);        
        liquidPledging = LiquidPledging(_liquidPledging);

        idProject = liquidPledging.addProject(
            _name,
            _url,
            address(this),
            _parentProject,
            0,
            ILiquidPledgingPlugin(this)
        );        
    }

    function acceptMilestone(uint64 idProject) public {
        require(_hasRole(ADMIN_ROLE) || _hasRole(REVIEWER_ROLE));
        require(!isCanceled());

        accepted = true;
        MilestoneAccepted(idProject);
    }

    function cancelMilestone(uint64 idProject) public {
        require(_hasRole(ADMIN_ROLE) || _hasRole(REVIEWER_ROLE));
        require(!isCanceled());

        liquidPledging.cancelProject(idProject);
    }    

    function isCanceled() public constant returns (bool) {
        return liquidPledging.isProjectCanceled(idProject);
    }

    function _hasRole(bytes32 role) internal returns(bool) {
      return canPerform(msg.sender, role, new uint[](0));
    }    


    function changeReviewer(address _newReviewer) external auth(REVIEWER_ROLE) {
        newReviewer = _newReviewer;
    }    

    function acceptNewReviewer() external {
        require(newReviewer == msg.sender);

        ACL acl = ACL(kernel.acl());
        acl.revokePermission(reviewer, address(this), REVIEWER_ROLE);
        acl.grantPermission(newReviewer, address(this), REVIEWER_ROLE);

        reviewer = newReviewer;
        newReviewer = 0;
    }  
    
    function changeRecipient(address _newRecipient) external auth(REVIEWER_ROLE) {
        newRecipient = _newRecipient;
    }

    function acceptNewRecipient() external {
        require(newRecipient == msg.sender);

        ACL acl = ACL(kernel.acl());
        acl.revokePermission(recipient, address(this), RECIPIENT_ROLE);
        acl.grantPermission(newRecipient, address(this), RECIPIENT_ROLE);

        recipient = newRecipient;
        newRecipient = 0;
    }     



    // function LPPCappedMilestones(
    //     LiquidPledging _liquidPledging,
    //     address _escapeHatchCaller,
    //     address _escapeHatchDestination
    // ) Escapable(_escapeHatchCaller, _escapeHatchDestination) public
    // {
    //     liquidPledging = _liquidPledging;
    // }

    // //== fallback

    // function() payable {}

    //== external

    /// @dev this is called by liquidPledging before every transfer to and from
    ///      a pledgeAdmin that has this contract as its plugin
    /// @dev see ILiquidPledgingPlugin interface for details about context param
    function beforeTransfer(
        uint64 pledgeManager,
        uint64 pledgeFrom,
        uint64 pledgeTo,
        uint64 context,
        address token,
        uint amount
    ) external returns (uint maxAllowed)
    {
        require(msg.sender == address(liquidPledging));
        var (, , , fromIntendedProject, , , ,) = liquidPledging.getPledge(pledgeFrom);
        var (, toOwner, , toIntendedProject, , , ,toPledgeState) = liquidPledging.getPledge(pledgeTo);

        // if m is the intendedProject, make sure m is still accepting funds (not accepted or canceled)
        if (context == TO_INTENDEDPROJECT) {
            // don't need to check if canceled b/c lp does this
            if (accepted) {
                return 0;
            }
        // if the pledge is being transferred to m and is in the Pledged state, make
        // sure m is still accepting funds (not accepted or canceled)
        } else if (context == TO_OWNER &&
            (fromIntendedProject != toOwner &&
                toPledgeState == LiquidPledgingStorage.PledgeState.Pledged)) {
            //TODO what if milestone isn't initialized? should we throw?
            // this can happen if someone adds a project through lp with this contracts address as the plugin
            // we can require(maxAmount > 0);
            // don't need to check if canceled b/c lp does this
            if (accepted) {
                return 0;
            }
        }
        return amount;
    }

    /// @dev this is called by liquidPledging after every transfer to and from
    ///      a pledgeAdmin that has this contract as its plugin
    /// @dev see ILiquidPledgingPlugin interface for details about context param
    function afterTransfer(
        uint64 pledgeManager,
        uint64 pledgeFrom,
        uint64 pledgeTo,
        uint64 context,
        address token,
        uint amount
    ) external
    {
        require(msg.sender == address(liquidPledging));

        // 
        // this.balance just shows what's in the contract
        // 

        var (, fromOwner, , , , , ,) = liquidPledging.getPledge(pledgeFrom);
        var (, toOwner, , , , , , toPledgeState) = liquidPledging.getPledge(pledgeTo);

        if (context == TO_OWNER) {
            // If fromOwner != toOwner, the means that a pledge is being committed to
            // milestone m. We will accept any amount up to m.maxAmount, and return
            // the rest
            if (fromOwner != toOwner) {
                uint returnFunds = 0;

                received += amount;
                // milestone is no longer accepting new funds
                if (accepted) {
                    returnFunds = amount;
                } else if (received > maxAmount) {
                    returnFunds = received - maxAmount;
                }

                // send any exceeding funds back
                if (returnFunds > 0) {
                    received -= returnFunds;
                    liquidPledging.cancelPledge(pledgeTo, returnFunds);
                }
            }
        }
    }

    function cancelMilestone() external {
        require(_hasRole(ADMIN_ROLE) || _hasRole(REVIEWER_ROLE));
        require(!isCanceled());

        liquidPledging.cancelProject(idProject);
    }


    //== public

    // function addMilestone(
    //     string name,
    //     string url,
    //     uint _maxAmount,
    //     uint64 parentProject,
    //     address _recipient,
    //     address _reviewer,
    //     address _campaignReviewer
    // ) public
    // {
    //     uint64 idProject = liquidPledging.addProject(
    //         name,
    //         url,
    //         address(this),
    //         parentProject,
    //         uint64(0),
    //         ILiquidPledgingPlugin(this)
    //     );

    //     milestones[idProject] = Milestone(
    //         _maxAmount,
    //         0,
    //         0,
    //         _reviewer,
    //         _campaignReviewer,
    //         _recipient,
    //         false
    //     );
    // }

    // function acceptMilestone(uint64 idProject) public {
    //     bool isCanceled = liquidPledging.isProjectCanceled(idProject);
    //     require(!isCanceled);

    //     Milestone storage m = milestones[idProject];
    //     require(msg.sender == m.reviewer || msg.sender == m.campaignReviewer);
    //     require(!m.accepted);

    //     m.accepted = true;
    //     MilestoneAccepted(idProject);
    // }

    // function cancelMilestone(uint64 idProject) public {
    //     Milestone storage m = milestones[idProject];
    //     require(msg.sender == m.reviewer || msg.sender == m.campaignReviewer);
    //     require(!m.accepted);

    //     liquidPledging.cancelProject(idProject);
    // }

    // function withdraw(uint64 idProject, uint64 idPledge, uint amount) public {
    //     require(_hasRole(RECIPIENT_ROLE));
    //     require(accepted);

    //     // we don't check if canceled here.
    //     // lp.withdraw will normalize the pledge & check if canceled
    //     Milestone storage m = milestones[idProject];

    //     liquidPledging.withdraw(idPledge, amount);
    //     collect(idProject);
    // }

    /// Bit mask used for dividing pledge amounts in mWithdraw
    /// This is the multiple withdraw contract


    // token should be param
    function collect(uint64 idProject, address _token) public auth(RECIPIENT_ROLE){
        uint amount = canCollect;

        ERC20 milestoneToken = ERC20(_token);
        assert(milestoneToken.balanceOf(this) >= amount);

        require(milestoneToken.transfer(recipient, amount));

        PaymentCollected(idProject);
    }
}
