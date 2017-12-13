pragma solidity ^0.4.13;

import "liquidpledging/contracts/LiquidPledging.sol";
import "giveth-common-contracts/contracts/Escapable.sol";

contract MaxAmountMilestones is Escapable {
    uint constant FROM_OWNER = 0;
    uint constant FROM_INTENDEDPROJECT = 255;
    uint constant TO_OWNER = 256;
    uint constant TO_INTENDEDPROJECT = 511;

    LiquidPledging public liquidPledging;

    struct Milestone {
        uint maxAmount;
        uint cumulatedReceived;
        uint canCollect;
        address milestoneReviewer;
        address campaignReviewer;
        address recipient;
        bool accepted;
    }

    mapping(uint64 => Milestone) milestones;

//    address public newMilestoneReviewer;
//    address public newCampaignReviewer;
//    address public newRecipient;
//    bool public initPending;


    event MilestoneAccepted(uint64 indexed idProject);
    event PaymentCollected(uint64 indexed idProject, uint amount);

    function MaxAmountMilestones(
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
        uint64 parentProject,
        address _recipient,
        uint _maxAmount,
        address _milestoneReviewer,
        address _campaignReviewer
    ) public {
        idProject = liquidPledging.addProject(name, url, address(this), parentProject, uint64(0), ILiquidPledgingPlugin(this));
        milestones[idProject] = Milestone(_maxAmount, _milestoneReviewer, _campaignReviewer, _recipient);
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
        // If it is proposed or comes from somewhere else of a proposed project, do not allow.
        // only allow from the proposed project to the project in order normalize it.
        if (context == TO_INTENDEDPROJECT) {
            Milestone storage milestone = milestones[ toIntendedProject ];
            if (milestone.accepted || isCanceled(toIntendedProject)) {
                return 0;
            }
        } else if (context == TO_OWNER) {
            if (fromIntendedProject != toOwner &&
                    toPledgeState == LiquidPledgingBase.PledgeState.Pledged) {
                //TODO what if milestone isn't initialized? should we throw?
                // this can happen if someone adds a project through lp with this contracts address as the plugin
                // we can require(maxAmount > 0);
                Milestone storage milestone = milestones[ toOwner ];
                if (milestone.accepted || isCanceled(toIntendedProject)) {
                    return 0;
                }
//            } else if (toPledgeState == LiquidPledgingBase.PledgeState.Paying) {
                // only accepted milestones can be moved to paying status
//                Milestone storage m = milestones[ toOwner ];
//                require(m.accepted);
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
            // Recipient of the funds from a different owner
            if (oldOwner != toOwner) {
                Milestone storage milestone = milestones[ toOwner ];

                milestone.cumulatedReceived += amount;
                if (milestone.accepted || isCanceled(toOwner)) {
                    returnFunds = amount;
                } else if (milestone.cumulatedReceived > milestone.maxAmount) {
                    returnFunds = milestone.cumulatedReceived - milestone.maxAmount;
                } else {
                    returnFunds = 0;
                }

                if (returnFunds > 0) {  // Sends exceeding money back
                    milestone.cumulatedReceived -= returnFunds;
                    liquidPledging.cancelPledge(pledgeTo, returnFunds);
                }
            } else if (toPledgeState == LiquidPledgingBase.PledgeState.Paid) {
                Milestone storage m = milestones[ toOwner ];
                m.canCollect += amount;
            }
        }
    }

    function isCanceled(uint64 idProject) constant returns (bool) {
        return liquidPledging.isProjectCanceled(idProject);
    }

    function acceptMilestone(uint64 idProject) onlyReviewer {
        require(!isCanceled(idProject));

        Milestone storage milestone = milestones[ idProject ];
        require(!milestone.accepted);

        milestone.accepted = true;
        MilestoneAccepted(idProject);
    }

    function cancelMilestone(uint64 idProject) onlyReviewer {
        require(!isCanceled(idProject));

        Milestone storage milestone = milestones[ idProject ];
        require(!milestone.accepted);

        liquidPledging.cancelProject(idProject);
    }

    function withdraw(uint64 idProject, uint64 idPledge, uint amount) onlyRecipient {
        require(!isCanceled(idProject));

        Milestone storage milestone = milestones[ idProject ];
        require(milestone.accepted);

        liquidPledging.withdraw(idPledge, amount);
        collect(idProject);
    }

    function mWithdraw(uint[] pledgesAmounts) onlyRecipient {
        // to save gas, we will perform any necessary checks in the beforeTransfer
        // method. This saves us from having to iterate & make additional calls to
        // fetch the pledge for each pledgeAmount, since we are already fetching
        // in beforeTransfer
//        liquidPledging.mWithdraw(pledgesAmounts);
        //TODO check gas cost of if the same idProject is in multiple times
        uint64[] memory projects = new unit64[](pledgesAmounts.length);

        for (uint i = 0; i < pledgesAmounts.length; i++ ) {
            uint64 idPledge = uint64( pledgesAmounts[i] & (LiquidPledging.D64-1) );
            var (, idProject , , , , , ) = liquidPledging.getPledge(idPledge);

            projects.push(idProject);
            Milestone storage m = milestones[ idProject ];
            require(m.accepted);
        }

        liquidPledging.mWithdraw(pledgesAmounts);

        // TODO if idProject is in array multiple times, this will transfer all the milestone canCollect value the first time
        for (uint i = 0; i < projects.length; i++ ) {
            collect(projects[i]);
        }
    }

    function collect(uint64 idProject) onlyRecipient {
        Milestone storage m = milestones[ idProject ];

        if (m.canCollect > 0) {
            assert(this.balance >= m.canCollect);
            uint memory amount = m.canCollect;
            m.canCollect = 0;
            m.recipient.transfer(amount);
            PaymentCollected(idProject, amount);
        }
    }

    function () payable {}
}
