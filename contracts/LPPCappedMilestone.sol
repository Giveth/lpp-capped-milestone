pragma solidity 0.4.18;

/*
    Copyright 2017
    RJ Ewing <perissology@protonmail.com>
    S van Heummen <satya.vh@gmail.com>

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
import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/os/contracts/kernel/IKernel.sol";
import "giveth-bridge/contracts/IForeignGivethBridge.sol";


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

contract LPPCappedMilestone is AragonApp {
    uint constant TO_OWNER = 256;
    uint constant TO_INTENDEDPROJECT = 511;
    // keccack256(Kernel.APP_ADDR_NAMESPACE(), keccack256("ForeignGivethBridge"))
    bytes32 constant public FOREIGN_BRIDGE_INSTANCE = 0xa46b3f7f301ac0173ef5564df485fccae3b60583ddb12c767fea607ff6971d0b;

    LiquidPledging public liquidPledging;
    uint64 public idProject;

    address public reviewer;
    address public newReviewer;    
    address public recipient;
    address public newRecipient;
    address public campaignReviewer;
    address public newCampaignReviewer;
    address public milestoneManager;
    address public acceptedToken;
    uint public maxAmount;
    uint public received = 0;
    bool public requestComplete;
    bool public completed;

    // @notice After marking complete, and after this timeout, the recipient can withdraw the money
    // even if the milestone was not marked as complete.
    // Must be set in seconds.
    uint public reviewTimeoutSeconds;
    uint public reviewTimeout = 0;

    event MilestoneCompleteRequested(address indexed liquidPledging, uint64 indexed idProject);
    event MilestoneCompleteRequestRejected(address indexed liquidPledging, uint64 indexed idProject);
    event MilestoneCompleteRequestApproved(address indexed liquidPledging, uint64 indexed idProject);

    event MilestoneChangeReviewerRequested(address indexed liquidPledging, uint64 indexed idProject, address reviewer);
    event MilestoneReviewerChanged(address indexed liquidPledging, uint64 indexed idProject, address reviewer);

    event MilestoneChangeCampaignReviewerRequested(address indexed liquidPledging, uint64 indexed idProject, address reviewer);
    event MilestoneCampaignReviewerChanged(address indexed liquidPledging, uint64 indexed idProject, address reviewer);

    event MilestoneChangeRecipientRequested(address indexed liquidPledging, uint64 indexed idProject, address recipient);
    event MilestoneRecipientChanged(address indexed liquidPledging, uint64 indexed idProject, address recipient);

    event PaymentCollected(address indexed liquidPledging, uint64 indexed idProject);


    modifier onlyReviewer() {
        require(msg.sender == reviewer);
        _;
    }

    modifier onlyCampaignReviewer() {
        require(msg.sender == campaignReviewer);
        _;
    }

    modifier onlyManagerOrRecipient() {
        require(msg.sender == milestoneManager || msg.sender == recipient);
        _;
    }   

    modifier checkReviewTimeout() { 
        if (!completed && reviewTimeout > 0 && now > reviewTimeout) {
            completed = true;
        }
        require(completed);
        _; 
    }
    
    //== constructor

    // @notice we pass in the idProject here because it was throwing stack too deep error
    function initialize(
        address _reviewer,
        address _campaignReviewer,
        address _recipient,
        address _milestoneManager,
        uint _reviewTimeoutSeconds,
        uint _maxAmount,
        address _acceptedToken,
        // if these params are at the beginning, we get a stack too deep error
        address _liquidPledging,
        uint64 _idProject
    ) onlyInit external
    {
        require(_reviewer != 0);        
        require(_campaignReviewer != 0);
        require(_recipient != 0);
        require(_milestoneManager != 0);
        require(_liquidPledging != 0);
        require(_acceptedToken != 0);
        initialized();

        idProject = _idProject;
        liquidPledging = LiquidPledging(_liquidPledging);

        var ( , addr, , , , , , plugin) = liquidPledging.getPledgeAdmin(idProject);
        require(addr == address(this) && plugin == address(this));

        maxAmount = _maxAmount;
        acceptedToken = _acceptedToken;
        reviewer = _reviewer;        
        recipient = _recipient;
        reviewTimeoutSeconds = _reviewTimeoutSeconds;
        campaignReviewer = _campaignReviewer;
        milestoneManager = _milestoneManager;        
    }

    //== external

    // don't allow cancel if the milestone is completed
    function isCanceled() public constant returns (bool) {
        return liquidPledging.isProjectCanceled(idProject);
    }

    // @notice Milestone manager can request to mark a milestone as completed
    // When he does, the timeout is initiated. So if the reviewer doesn't
    // handle the request in time, the recipient can withdraw the funds
    function requestMarkAsComplete() onlyManagerOrRecipient external {
        require(!isCanceled());
        require(!requestComplete);

        requestComplete = true;
        MilestoneCompleteRequested(liquidPledging, idProject);        
        
        // start the review timeout
        reviewTimeout = now + reviewTimeoutSeconds;    
    }

    // @notice The reviewer can reject a completion request from the milestone manager
    // When he does, the timeout is reset.
    function rejectCompleteRequest() onlyReviewer external {
        require(!isCanceled());

        // reset 
        completed = false;
        requestComplete = false;
        reviewTimeout = 0;
        MilestoneCompleteRequestRejected(liquidPledging, idProject);
    }   

    // @notice The reviewer can approve a completion request from the milestone manager
    // When he does, the milestone's state is set to completed and the funds can be
    // withdrawn by the recipient.
    function approveMilestoneCompleted() onlyReviewer external {
        require(!isCanceled());

        completed = true;
        MilestoneCompleteRequestApproved(liquidPledging, idProject);         
    }

    // @notice The reviewer and the milestone manager can cancel a milestone.
    function cancelMilestone() external {
        require(msg.sender == milestoneManager || msg.sender == reviewer);
        require(!isCanceled());

        liquidPledging.cancelProject(idProject);
    }    

    // @notice The reviewer can request changing a reviewer.
    function requestChangeReviewer(address _newReviewer) onlyReviewer external {
        newReviewer = _newReviewer;

        MilestoneChangeReviewerRequested(liquidPledging, idProject, newReviewer);                 
    }    

    // @notice The new reviewer needs to accept the request from the old
    // reviewer to become the new reviewer.
    // @dev There's no point in adding a rejectNewReviewer because as long as
    // the new reviewer doesn't accept, the old reviewer remains the reviewer.    
    function acceptNewReviewerRequest() external {
        require(newReviewer == msg.sender);

        reviewer = newReviewer;
        newReviewer = 0;

        MilestoneReviewerChanged(liquidPledging, idProject, reviewer);         
    }  

    // @notice The campaign reviewer can request changing a campaign reviewer.
    function requestChangeCampaignReviewer(address _newCampaignReviewer) onlyCampaignReviewer external {
        newCampaignReviewer = _newCampaignReviewer;

        MilestoneChangeCampaignReviewerRequested(liquidPledging, idProject, newReviewer);                 
    }    

    // @notice The new campaign reviewer needs to accept the request from the old
    // campaign reviewer to become the new campaign reviewer.
    // @dev There's no point in adding a rejectNewCampaignReviewer because as long as
    // the new reviewer doesn't accept, the old reviewer remains the reviewer.    
    function acceptNewCampaignReviewerRequest() external {
        require(newCampaignReviewer == msg.sender);

        campaignReviewer = newCampaignReviewer;
        newCampaignReviewer = 0;

        MilestoneCampaignReviewerChanged(liquidPledging, idProject, reviewer);         
    }  

    // @notice The recipient can request changing recipient.
    // @dev There's no point in adding a rejectNewRecipient because as long as
    // the new recipient doesn't accept, the old recipient remains the recipient.
    function requestChangeRecipient(address _newRecipient) onlyReviewer external {
        newRecipient = _newRecipient;

        MilestoneChangeRecipientRequested(liquidPledging, idProject, newRecipient);                 
    }

    // @notice The new recipient needs to accept the request from the old
    // recipient to become the new recipient.
    function acceptNewRecipient() external {
        require(newRecipient == msg.sender);

        recipient = newRecipient;
        newRecipient = 0;

        MilestoneRecipientChanged(liquidPledging, idProject, recipient);         

    }     

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
        
        // only accept that token
        if (token != acceptedToken) {
            return 0;
        }

        var (, , , fromIntendedProject, , , ,) = liquidPledging.getPledge(pledgeFrom);
        var (, toOwner, , , , , ,toPledgeState) = liquidPledging.getPledge(pledgeTo);

        // if m is the intendedProject, make sure m is still accepting funds (not completed or canceled)
        if (context == TO_INTENDEDPROJECT) {
            // don't need to check if canceled b/c lp does this
            if (completed) {
                return 0;
            }
        // if the pledge is being transferred to m and is in the Pledged state, make
        // sure m is still accepting funds (not completed or canceled)
        } else if (context == TO_OWNER &&
            (fromIntendedProject != toOwner &&
                toPledgeState == LiquidPledgingStorage.PledgeState.Pledged)) {
            //TODO what if milestone isn't initialized? should we throw?
            // this can happen if someone adds a project through lp with this contracts address as the plugin
            // we can require(maxAmount > 0);
            // don't need to check if canceled b/c lp does this
            if (completed) {
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

        var (, fromOwner, , , , , ,) = liquidPledging.getPledge(pledgeFrom);
        var (, toOwner, , , , , , ) = liquidPledging.getPledge(pledgeTo);

        if (context == TO_OWNER) {
            // If fromOwner != toOwner, the means that a pledge is being committed to
            // milestone. We will accept any amount up to m.maxAmount, and return
            // the rest
            if (fromOwner != toOwner) {
                uint returnFunds = 0;
                uint newBalance = received + amount;

                // milestone is no longer accepting new funds
                if (completed) {
                    returnFunds = amount;
                } else if (newBalance > maxAmount) {
                    returnFunds = newBalance - maxAmount;
                    received = maxAmount;
                } else {
                    received = received + amount;
                }

                // send any exceeding funds back
                if (returnFunds > 0) {
                    liquidPledging.cancelPledge(pledgeTo, returnFunds);
                }
            }
        }
    }

    // @notice Allows the recipient or milestoneManager to initiate withdraw from
    // the vault to this milestone. If the vault is autoPay, this will disburse the
    // payment to the recipient
    // Checks if reviewTimeout has passed, if so, sets completed to yes
    function mWithdraw(uint[] pledgesAmounts) onlyManagerOrRecipient checkReviewTimeout external {
        liquidPledging.mWithdraw(pledgesAmounts);
        _disburse();
    }

    // @notice Allows the recipient or milestoneManager to initiate withdraw of a single pledge, from
    // the vault to this milestone. If the vault is autoPay, this will disburse the payment to the
    // recipient
    // Checks if reviewTimeout has passed, if so, sets completed to yes
    function withdraw(uint64 idPledge, uint amount) onlyManagerOrRecipient checkReviewTimeout external {
        liquidPledging.withdraw(idPledge, amount);
        _disburse();
    }

    // @notice Allows the recipient or milestoneManager to disburse funds to the recipient
    function disburse() onlyManagerOrRecipient checkReviewTimeout external {
        _disburse();
    }

    /**
    * @dev By default, AragonApp will allow anyone to call transferToVault
    *      We need to blacklist the `acceptedToken`
    * @param token Token address that would be recovered
    * @return bool whether the app allows the recovery
    */
    function allowRecoverability(address token) public view returns (bool) {
        return token != acceptedToken;
    }

    function _disburse() internal {
        IKernel kernel = liquidPledging.kernel();
        IForeignGivethBridge bridge = IForeignGivethBridge(kernel.getApp(FOREIGN_BRIDGE_INSTANCE));

        ERC20 milestoneToken = ERC20(acceptedToken);
        uint amount = milestoneToken.balanceOf(this);

        if (amount > 0) {
            bridge.withdraw(recipient, acceptedToken, amount);
            PaymentCollected(liquidPledging, idProject);            
        }
    }
}
