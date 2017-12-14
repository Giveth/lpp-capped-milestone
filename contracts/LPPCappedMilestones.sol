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

import "liquidpledging/contracts/LiquidPledging.sol";
import "giveth-common-contracts/contracts/Escapable.sol";


contract LPPCappedMilestones is Escapable {
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

    mapping (uint64 => Milestone) milestones;


    event MilestoneAccepted(uint64 indexed idProject);
    event PaymentCollected(uint64 indexed idProject);

    //== constructor

    function LPPCappedMilestones(
        LiquidPledging _liquidPledging,
        address _escapeHatchCaller,
        address _escapeHatchDestination
    ) Escapable(_escapeHatchCaller, _escapeHatchDestination) public
    {
        liquidPledging = _liquidPledging;
    }

    //== fallback

    function() payable {}

    //== external

    /// @dev this is called by liquidPledging before every transfer to and from
    ///      a pledgeAdmin that has this contract as its plugin
    /// @dev see ILiquidPledgingPlugin interface for details about context param
    function beforeTransfer(
        uint64 pledgeManager,
        uint64 pledgeFrom,
        uint64 pledgeTo,
        uint64 context,
        uint amount
    ) external returns (uint maxAllowed)
    {
        require(msg.sender == address(liquidPledging));
        var (, , , fromIntendedProject, , ,) = liquidPledging.getPledge(pledgeFrom);
        var (, toOwner, , toIntendedProject, , , toPledgeState) = liquidPledging.getPledge(pledgeTo);
        Milestone storage m;

        // if m is the intendedProject, make sure m is still accepting funds (not accepted or canceled)
        if (context == TO_INTENDEDPROJECT) {
            m = milestones[toIntendedProject];
            // don't need to check if canceled b/c lp does this
            if (m.accepted) {
                return 0;
            }
        // if the pledge is being transferred to m and is in the Pledged state, make
        // sure m is still accepting funds (not accepted or canceled)
        } else if (context == TO_OWNER &&
            (fromIntendedProject != toOwner &&
                toPledgeState == LiquidPledgingBase.PledgeState.Pledged)) {
            //TODO what if milestone isn't initialized? should we throw?
            // this can happen if someone adds a project through lp with this contracts address as the plugin
            // we can require(maxAmount > 0);
            // don't need to check if canceled b/c lp does this
            m = milestones[toOwner];
            if (m.accepted) {
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
        uint amount
    ) external
    {
        require(msg.sender == address(liquidPledging));

        var (, fromOwner, , , , ,) = liquidPledging.getPledge(pledgeFrom);
        var (, toOwner, , , , , toPledgeState) = liquidPledging.getPledge(pledgeTo);

        if (context == TO_OWNER) {
            Milestone storage m;

            // If fromOwner != toOwner, the means that a pledge is being committed to
            // milestone m. We will accept any amount up to m.maxAmount, and return
            // the rest
            if (fromOwner != toOwner) {
                m = milestones[toOwner];
                uint returnFunds = 0;

                m.received += amount;
                // milestone is no longer accepting new funds
                if (m.accepted) {
                    returnFunds = amount;
                } else if (m.received > m.maxAmount) {
                    returnFunds = m.received - m.maxAmount;
                }

                // send any exceeding funds back
                if (returnFunds > 0) {
                    m.received -= returnFunds;
                    liquidPledging.cancelPledge(pledgeTo, returnFunds);
                }
            // if the pledge has been paid, then the vault should have transferred the
            // the funds to this contract. update the milestone with the amount the recipient
            // can collect. this is the amount of the paid pledge
            } else if (toPledgeState == LiquidPledgingBase.PledgeState.Paid) {
                m = milestones[toOwner];
                m.canCollect += amount;
            }
        }
    }

    //== public

    function addMilestone(
        string name,
        string url,
        uint _maxAmount,
        uint64 parentProject,
        address _recipient,
        address _reviewer,
        address _campaignReviewer
    ) public
    {
        uint64 idProject = liquidPledging.addProject(
            name,
            url,
            address(this),
            parentProject,
            uint64(0),
            ILiquidPledgingPlugin(this)
        );

        milestones[idProject] = Milestone(
            _maxAmount,
            0,
            0,
            _reviewer,
            _campaignReviewer,
            _recipient,
            false
        );
    }

    function acceptMilestone(uint64 idProject) public {
        bool isCanceled = liquidPledging.isProjectCanceled(idProject);
        require(!isCanceled);

        Milestone storage m = milestones[idProject];
        require(msg.sender == m.reviewer || msg.sender == m.campaignReviewer);
        require(!m.accepted);

        m.accepted = true;
        MilestoneAccepted(idProject);
    }

    function cancelMilestone(uint64 idProject) public {
        Milestone storage m = milestones[idProject];
        require(msg.sender == m.reviewer || msg.sender == m.campaignReviewer);
        require(!m.accepted);

        liquidPledging.cancelProject(idProject);
    }

    function withdraw(uint64 idProject, uint64 idPledge, uint amount) public {
        // we don't check if canceled here.
        // lp.withdraw will normalize the pledge & check if canceled
        Milestone storage m = milestones[idProject];
        require(msg.sender == m.recipient);
        require(m.accepted);

        liquidPledging.withdraw(idPledge, amount);
        collect(idProject);
    }

    /// Bit mask used for dividing pledge amounts in mWithdraw
    uint constant D64 = 0x10000000000000000;

    function mWithdraw(uint[] pledgesAmounts) public {
        uint64[] memory mIds = new uint64[](pledgesAmounts.length);

        for (uint i = 0; i < pledgesAmounts.length; i++ ) {
            uint64 idPledge = uint64(pledgesAmounts[i] & (D64-1));
            var (, idProject, , , , ,) = liquidPledging.getPledge(idPledge);

            mIds[i] = idProject;
            Milestone storage m = milestones[idProject];
            require(msg.sender == m.recipient);
            require(m.accepted);
        }

        liquidPledging.mWithdraw(pledgesAmounts);

        for (i = 0; i < mIds.length; i++ ) {
            collect(mIds[i]);
        }
    }

    function collect(uint64 idProject) public {
        Milestone storage m = milestones[idProject];
        require(msg.sender == m.recipient);

        if (m.canCollect > 0) {
            // TODO should this assert be removed?
            uint amount = m.canCollect;
            assert(this.balance >= amount);
            m.canCollect = 0;
            m.recipient.transfer(amount);
            PaymentCollected(idProject);
        }
    }

    function getMilestone(uint64 idProject) public view returns (
        uint maxAmount,
        uint received,
        uint canCollect,
        address reviewer,
        address campaignReviewer,
        address recipient,
        bool accepted
    ) {
        Milestone storage m = milestones[idProject];
        maxAmount = m.maxAmount;
        received = m.received;
        canCollect = m.canCollect;
        reviewer = m.reviewer;
        campaignReviewer = m.campaignReviewer;
        recipient = m.recipient;
        accepted = m.accepted;
    }
}
