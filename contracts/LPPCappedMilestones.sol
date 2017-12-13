pragma solidity ^0.4.17;

import "liquidpledging/contracts/LiquidPledging.sol";
import "giveth-common-contracts/contracts/Escapable.sol";

contract LPPCappedMilestones is Escapable {
    uint constant FROM_OWNER = 0;
    uint constant FROM_INTENDEDPROJECT = 255;
    uint constant TO_OWNER = 256;
    uint constant TO_INTENDEDPROJECT = 511;

    LiquidPledging public liquidPledging;

    struct Milestone {
        uint maxAmount;
        uint received;
        uint canCollect;
        address reviewer;
        address campaignReviewer;
        address recipient;
        bool accepted;
    }

    mapping(uint64 => Milestone) milestones;

    //TODO add code to change addresses for a milestone
//    address public newreviewer;
//    address public newCampaignReviewer;
//    address public newRecipient;


    event MilestoneAccepted(uint64 indexed idProject);
    event PaymentCollected(uint64 indexed idProject, uint amount);

    function LPPCappedMilestones(
        LiquidPledging _liquidPledging,
        address _escapeHatchCaller,
        address _escapeHatchDestination
    ) Escapable(_escapeHatchCaller, _escapeHatchDestination) public
    {
        liquidPledging = _liquidPledging;
    }

    function addMilestone(
        string name,
        string url,
        uint _maxAmount,
        uint64 parentProject,
        address _recipient,
        address _reviewer,
        address _campaignReviewer
    ) public {
        uint64 idProject = liquidPledging.addProject(name, url, address(this), parentProject, uint64(0), ILiquidPledgingPlugin(this));
        milestones[idProject] = Milestone(_maxAmount, 0, 0, _reviewer, _campaignReviewer, _recipient, false);
    }

    /// @dev Plugins are used (much like web hooks) to initiate an action
    ///  upon any donation, delegation, or transfer; this is an optional feature
    ///  and allows for extreme customization of the contract
    /// @dev Context The situation that is triggering the plugin:
    ///  0 -> Plugin for the owner transferring pledge to another party
    ///  1 -> Plugin for the first delegate transferring pledge to another party
    ///  2 -> Plugin for the second delegate transferring pledge to another party
    ///  ...
    ///  255 -> Plugin for the intendedProject transferring pledge to another party
    ///
    ///  256 -> Plugin for the owner receiving pledge from another party
    ///  257 -> Plugin for the first delegate receiving pledge from another party
    ///  258 -> Plugin for the second delegate receiving pledge from another party
    ///  ...
    ///  511 -> Plugin for the intendedProject receiving pledge from another party
    function beforeTransfer(
        uint64 pledgeManager,
        uint64 pledgeFrom,
        uint64 pledgeTo,
        uint64 context,
        uint amount
    ) external returns (uint maxAllowed){
        require(msg.sender == address(liquidPledging));
        var (, , , fromIntendedProject , , , ) = liquidPledging.getPledge(pledgeFrom);
        var (, toOwner , , toIntendedProject , , , toPledgeState ) = liquidPledging.getPledge(pledgeTo);
        Milestone storage m;

        // If it is proposed or comes from somewhere else of a proposed project, do not allow.
        // only allow from the proposed project to the project in order normalize it.
        // don't need to check if canceled b/c lp does this
        if (context == TO_INTENDEDPROJECT) {
            m = milestones[ toIntendedProject ];
            if (m.accepted) {
                return 0;
            }
        } else if (context == TO_OWNER) {
            if (fromIntendedProject != toOwner &&
                    toPledgeState == LiquidPledgingBase.PledgeState.Pledged) {
                //TODO what if milestone isn't initialized? should we throw?
                // this can happen if someone adds a project through lp with this contracts address as the plugin
                // we can require(maxAmount > 0);
                // don't need to check if canceled b/c lp does this
                m = milestones[ toOwner ];
                if (m.accepted) {
                    return 0;
                }
            } else if (toPledgeState == LiquidPledgingBase.PledgeState.Paying) {
//                 only accepted milestones can be moved to paying status
                m = milestones[ toOwner ];
                require(m.accepted);
            }
        }
        return amount;
    }

    /// @dev Plugins are used (much like web hooks) to initiate an action
    ///  upon any donation, delegation, or transfer; this is an optional feature
    ///  and allows for extreme customization of the contract
    /// @dev Context The situation that is triggering the plugin, see note for
    ///  `beforeTransfer()`
    function afterTransfer(
        uint64 pledgeManager,
        uint64 pledgeFrom,
        uint64 pledgeTo,
        uint64 context,
        uint amount
    ) external {
        uint returnFunds;
        require(msg.sender == address(liquidPledging));

        var (, oldOwner, , , , , ) = liquidPledging.getPledge(pledgeFrom);
        var (, toOwner , , , , , toPledgeState) = liquidPledging.getPledge(pledgeTo);

        if (context == TO_OWNER ) {
            Milestone storage m;

            // Recipient of the funds from a different owner
            if (oldOwner != toOwner) {
                m = milestones[ toOwner ];

                m.received += amount;
                if (m.accepted) {
                    returnFunds = amount;
                } else if (m.received > m.maxAmount) {
                    returnFunds = m.received - m.maxAmount;
                } else {
                    returnFunds = 0;
                }

                if (returnFunds > 0) {  // Sends exceeding money back
                    m.received -= returnFunds;
                    liquidPledging.cancelPledge(pledgeTo, returnFunds);
                }
            } else if (toPledgeState == LiquidPledgingBase.PledgeState.Paid) {
                m = milestones[ toOwner ];
                m.canCollect += amount;
            }
        }
    }

    function acceptMilestone(uint64 idProject) {
        bool isCanceled = liquidPledging.isProjectCanceled(idProject);
        require(!isCanceled);

        Milestone storage m = milestones[ idProject ];
        require(msg.sender == m.reviewer || msg.sender == m.campaignReviewer);
        require(!m.accepted);

        m.accepted = true;
        MilestoneAccepted(idProject);
    }

    function cancelMilestone(uint64 idProject) {
        Milestone storage m = milestones[ idProject ];
        require(msg.sender == m.reviewer || msg.sender == m.campaignReviewer);
        require(!m.accepted);

        liquidPledging.cancelProject(idProject);
    }

    function withdraw(uint64 idProject, uint64 idPledge, uint amount) public {
        // we don't check if canceled here.
        // lp.withdraw will normalize the pledge & check if canceled
        // beforeTransfer will check if milestone is accepted
//        Milestone storage m = milestones[ idProject ];
//        require(msg.sender == m.recipient);
//        require(m.accepted);
        //TODO update this and before/after transfer depending on mTransfer methods

        liquidPledging.withdraw(idPledge, amount);
        collect(idProject);
    }

    uint constant D64 = 0x10000000000000000;

    function mWithdraw(uint[] pledgesAmounts) public {
        // to save gas, we will perform any necessary checks in the beforeTransfer
        // method. This saves us from having to iterate & make additional calls to
        // fetch the pledge for each pledgeAmount, since we are already fetching
        // in beforeTransfer
        //TODO this removes the require(msg.sender == m.recipient) check
        liquidPledging.mWithdraw(pledgesAmounts);
        // TODO pick the above or below method
        // withdraw -> 295154
        // mWithdraw:
        // 1 pledge -> 296898
        // 2 pledge -> 568657
        // 3 pledge -> 840482

        // before/after transfer -- this however removes the require(msg.sender == m.recipient) check from withdraw & collect
        // withdraw -> 290479
        // mWithdraw:
        // 1 pledge -> 290552
        // 2 pledge -> 556230
        // 3 pledge -> 821974

        // might be better to use the before/after transfer functionality
//        uint64[] memory mIds = new uint64[](pledgesAmounts.length);
//
//        for (uint i = 0; i < pledgesAmounts.length; i++ ) {
//            uint64 idPledge = uint64( pledgesAmounts[i] & (D64-1) );
//            var (, idProject , , , , , ) = liquidPledging.getPledge(idPledge);
//
//            mIds[ i ] = idProject;
//            Milestone storage m = milestones[ idProject ];
//            require(msg.sender == m.recipient);
//            require(m.accepted);
//        }
//
//        liquidPledging.mWithdraw(pledgesAmounts);
//
//        for (i = 0; i < mIds.length; i++ ) {
//            collect(mIds[i]);
//        }
    }

    function collect(uint64 idProject) public {
        Milestone storage m = milestones[ idProject ];
        require(msg.sender == m.recipient);

        if (m.canCollect > 0) {
            // TODO should this be removes?
            assert(this.balance >= m.canCollect);
            uint amount = m.canCollect;
            m.canCollect = 0;
            m.recipient.transfer(amount);
            PaymentCollected(idProject, amount);
        }
    }

    function getMilestone(uint64 idProject) public view returns(
        uint maxAmount,
        uint received,
        uint canCollect,
        address reviewer,
        address campaignReviewer,
        address recipient,
        bool accepted
    ) {
        Milestone storage m = milestones[ idProject ];
        maxAmount = m.maxAmount;
        received = m.received;
        canCollect = m.canCollect;
        reviewer = m.reviewer;
        campaignReviewer = m.campaignReviewer;
        recipient = m.recipient;
        accepted = m.accepted;
    }

    function () payable {}
}
