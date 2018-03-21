/* eslint-env mocha */
/* eslint-disable no-await-in-loop */
const TestRPC = require('ganache-cli');
const chai = require('chai');
const contracts = require('../build/contracts');
const { LPVault, LiquidPledging, LPFactory, test, LiquidPledgingState } = require('giveth-liquidpledging');
const { MiniMeToken, MiniMeTokenFactory, MiniMeTokenState } = require('minimetoken');
const Web3 = require('web3');
const { StandardTokenTest, assertFail } = test;

const assert = chai.assert;


const printLPState = async(liquidPledgingState) => {
    const st = await liquidPledgingState.getState();
    console.log(JSON.stringify(st, null, 2));
};

const printBalances = async(liquidPledging) => {
    const st = await liquidPledging.getState();
    assert.equal(st.pledges.length, 13);
    for (let i = 1; i <= 12; i += 1) {
        console.log(i, ethConnector.web3.fromWei(st.pledges[i].amount).toNumber());
    }
};


describe('LPPCappedMilestones test', function() {
    this.timeout(0);

    let testrpc;
    let web3;
    let accounts;
    let liquidPledging;
    let liquidPledgingState;
    let vault;
    let milestones;
    let donor1;
    let donor2;
    let delegate1;
    let adminMilestone1;
    let recipient1;
    let recipient2;
    let reviewer1;
    let reviewer2;
    let campaignReviewer1;
    let campaignReviewer2;

    before(async() => {
        testrpc = TestRPC.server({
            ws: true,
            gasLimit: 9700000,
            total_accounts: 10,
        });

        testrpc.listen(8545, '127.0.0.1', (err) => { });

        web3 = new Web3('ws://localhost:8545');
        accounts = await web3.eth.getAccounts();

        donor1 = accounts[1];
        donor2 = accounts[2];
        delegate1 = accounts[2];
        adminMilestone1 = accounts[3];
        recipient1 = accounts[4];
        reviewer1 = accounts[5];
        campaignReviewer1 = accounts[6];
        recipient2 = accounts[7];
        reviewer2 = accounts[8];
        campaignReviewer2 = accounts[9];
    });

    after((done) => {
        testrpc.close();
        done();
    });

    it('Should deploy LiquidPledging contract', async() => {
        const baseVault = await LPVault.new(web3);
        const baseLP = await LiquidPledging.new(web3);
        const lpFactory = await LPFactory.new(web3, baseVault.$address, baseLP.$address);

        const r = await lpFactory.newLP(accounts[0], accounts[1], { $extraGas: 200000 });

        const vaultAddress = r.events.DeployVault.returnValues.vault;
        vault = new LPVault(web3, vaultAddress);

        const lpAddress = r.events.DeployLiquidPledging.returnValues.liquidPledging;
        liquidPledging = new LiquidPledging(web3, lpAddress);

        liquidPledgingState = new LiquidPledgingState(liquidPledging);

        // set permissions
        const kernel = new contracts.Kernel(web3, await liquidPledging.kernel());
        // acl = new contracts.ACL(web3, await kernel.acl());
        // await acl.createPermission(accounts[0], vault.$address, await vault.CANCEL_PAYMENT_ROLE(), accounts[0], { $extraGas: 200000 });
        // await acl.createPermission(accounts[0], vault.$address, await vault.CONFIRM_PAYMENT_ROLE(), accounts[0], { $extraGas: 200000 });        

        // giver1Token = await StandardTokenTest.new(web3);
        // await giver1Token.mint(giver1, web3.utils.toWei('1000'));
        // await giver1Token.approve(liquidPledging.$address, "0xFFFFFFFFFFFFFFFF", { from: giver1 });

        // const codeHash = web3.utils.keccak256(LPPCappedMilestonesRuntimeByteCode);
        // await liquidPledging.addValidPlugin(codeHash);

        // milestones = await LPPCappedMilestones.new(web3, liquidPledging.$address, accounts[0], accounts[1]);
    });

    // it('Should create new milestone', async() => {
    //     await milestones.addMilestone('Milestone1', '', 1000, 0, recipient1, reviewer1, campaignReviewer1); // pledgeAdmin 1

    //     const nManagers = await liquidPledging.numberOfPledgeAdmins();
    //     assert.equal(nManagers, 1);

    //     const res = await liquidPledging.getPledgeAdmin(1);
    //     assert.equal(res.adminType, 2); // Project
    //     assert.equal(res.addr, milestones.$address);
    //     assert.equal(res.name, 'Milestone1');
    //     assert.equal(res.url, '');
    //     assert.equal(res.commitTime, 0);
    //     assert.equal(res.plugin, milestones.$address);

    //     const m = await milestones.getMilestone(1);
    //     assert.equal(m.maxAmount, 1000);
    //     assert.equal(m.received, 0);
    //     assert.equal(m.canCollect, 0);
    //     assert.equal(m.reviewer, reviewer1);
    //     assert.equal(m.campaignReviewer, campaignReviewer1);
    //     assert.equal(m.recipient, recipient1);
    //     assert.equal(m.accepted, false);
    // });

    // it('Should make a donation', async() => {
    //     await liquidPledging.donate(0, 1, { from: donor1, value: 100 });

    //     const m = await milestones.getMilestone(1);
    //     assert.equal(m.maxAmount, 1000);
    //     assert.equal(m.received, 100);
    //     assert.equal(m.canCollect, 0);
    //     assert.equal(m.reviewer, reviewer1);
    //     assert.equal(m.campaignReviewer, campaignReviewer1);
    //     assert.equal(m.recipient, recipient1);
    //     assert.equal(m.accepted, false);
    // });

    // it('Should create another milestone', async() => {
    //     await milestones.addMilestone('Milestone2', '', 1000, 0, recipient2, reviewer2, campaignReviewer2); // pledgeAdmin 3

    //     const nManagers = await liquidPledging.numberOfPledgeAdmins();
    //     assert.equal(nManagers, 3);

    //     const m = await milestones.getMilestone(3);
    //     assert.equal(m.maxAmount, 1000);
    //     assert.equal(m.received, 0);
    //     assert.equal(m.canCollect, 0);
    //     assert.equal(m.reviewer, reviewer2);
    //     assert.equal(m.campaignReviewer, campaignReviewer2);
    //     assert.equal(m.recipient, recipient2);
    //     assert.equal(m.accepted, false);
    // });

    // it('Should refund any excess donations', async() => {
    //     await liquidPledging.donate(0, 3, { from: donor2, value: 1100 });

    //     const m = await milestones.getMilestone(3);
    //     assert.equal(m.maxAmount, 1000);
    //     assert.equal(m.received, 1000);
    //     assert.equal(m.canCollect, 0);
    //     assert.equal(m.reviewer, reviewer2);
    //     assert.equal(m.campaignReviewer, campaignReviewer2);
    //     assert.equal(m.recipient, recipient2);
    //     assert.equal(m.accepted, false);

    //     // await printLPState(liquidPledgingState);
    //     // check that the 100 excess was returned to the giver's pledge
    //     const p = await liquidPledging.getPledge(3);
    //     assert.equal(p.amount, 100);
    // });

    // it('Should not be able to withdraw non-accepted milestone', async() => {
    //     await assertFail(async() => {
    //         await milestones.withdraw(3, 3, 1000);
    //     });
    // });

    // it('Only reviewer should be able to accept milestone', async() => {
    //     await assertFail(async() => {
    //         await milestones.acceptMilestone(3, { from: donor1 });
    //     });
    // });

    // it('Should mark milestone Completed', async() => {
    //     await milestones.acceptMilestone(3, { from: reviewer2 });
    //     const m = await milestones.getMilestone(3);
    //     assert.equal(m.accepted, true);
    // });

    // it('Should not accept funds if accepted', async() => {
    //     await liquidPledging.donate(4, 3, { from: donor2, value: 100 });

    //     const m = await milestones.getMilestone(3);
    //     assert.equal(m.received, 1000);

    //     // check that the 100 excess was returned to the giver's pledge
    //     const p = await liquidPledging.getPledge(3);
    //     assert.equal(p.amount, 200);
    // });

    // it('Should not accept delegate funds if accepted', async() => {
    //     await liquidPledging.addDelegate('Delegate1', 'URLDelegate1', 0, 0, { from: delegate1 }); // admin 5
    //     await liquidPledging.donate(4, 5, { from: donor2, value: 100 }); // pledge 5

    //     await liquidPledging.transfer(5, 5, 100, 3, { from: delegate1 }); // pledge 6

    //     // check that the 100 excess was returned to the giver's pledge
    //     const delegatePledge = await liquidPledging.getPledge(5);
    //     assert.equal(delegatePledge.amount, 100);
    //     // check that pledge 6 w/ intendedProject is 0
    //     const intendedProjectPledge = await liquidPledging.getPledge(6);
    //     assert.equal(intendedProjectPledge.amount, 0);
    // });

    // it('only reviewer should be able to cancel', async() => {
    //     await milestones.addMilestone('Milestone3', '', 1000, 0, recipient1, reviewer1, campaignReviewer1); // pledgeAdmin 6

    //     await assertFail(async() => {
    //         await milestones.cancelMilestone(6, { from: donor1 });
    //     });

    //     await milestones.cancelMilestone(6, { from: campaignReviewer1 });

    //     const m = await liquidPledging.getPledgeAdmin(6);
    //     assert.equal(m.canceled, true);
    // });

    // it('Should throw on transfer if canceled', async() => {
    //     await assertFail(async() => {
    //         await liquidPledging.transfer(5, 5, 100, 6, { from: delegate1 });
    //     });
    // });

    // it('Should only update received on delegation commit', async() => {
    //     // delegate the funds
    //     await liquidPledging.transfer(5, 5, 100, 1, { from: delegate1 }); // pledge 7

    //     const mBefore = await milestones.getMilestone(1);
    //     assert.equal(mBefore.received, 100);

    //     // commit the delegation
    //     await liquidPledging.transfer(4, 7, 100, 1, { from: donor2 }); // pledge 7

    //     const mAfter = await milestones.getMilestone(1);
    //     assert.equal(mAfter.received, 200);
    // });

    // it('Only recipient can withdraw funds from accepted milestone', async() => {
    //     await assertFail(async() => {
    //         await milestones.withdraw(3, 4, 200, { from: recipient1 });
    //     });
    // });

    // it('Should be able to withdraw funds from accepted milestone', async() => {
    //     // paying
    //     await milestones.withdraw(3, 4, 200, { from: recipient2 });

    //     // confirm payment
    //     await vault.confirmPayment(0);

    //     const bal = await web3.eth.getBalance(milestones.$address);
    //     assert.equal(bal, 200);

    //     const m = await milestones.getMilestone(3);
    //     assert.equal(m.canCollect, 200);
    // });

    // it('only recipient can collect funds', async() => {
    //     await assertFail(async() => {
    //         await milestones.collect(3, { from: recipient1 });
    //     });
    // });

    // it('Should be able to collect funds', async() => {
    //     const startBal = await web3.eth.getBalance(recipient2);

    //     const { gasUsed } = await milestones.collect(3, { from: recipient2, gas: 50000, gasPrice: 1 });

    //     const endBal = await web3.eth.getBalance(recipient2);
    //     const expected = web3.utils.toBN(startBal).add(web3.utils.toBN('200')).sub(web3.utils.toBN(gasUsed)).toString();
    //     assert.equal(endBal, expected);

    //     const bal = await web3.eth.getBalance(milestones.$address);
    //     assert.equal(bal, 0);

    //     const m = await milestones.getMilestone(3);
    //     assert.equal(m.canCollect, 0);
    // });

    // it('should make another donation', async() => {
    //     await liquidPledging.donate(4, 1, { from: donor2, value: 500 });
    // });

    // it('should be accepted by campaignReviewer', async() => {
    //     await milestones.acceptMilestone(1, { from: campaignReviewer1 });
    // });

    // it('mWithdraw should withdraw multiple pledges', async() => {
    //     const pledges = [
    //         { amount: 100, id: 2 },
    //         { amount: 100, id: 8 },
    //         { amount: 500, id: 11 },
    //     ];

    //     // .substring is to remove the 0x prefix on the toHex result
    //     const encodedPledges = pledges.map(p => {
    //         return '0x' + utils.padLeft(utils.toHex(p.amount).substring(2), 48) + utils.padLeft(utils.toHex(p.id).substring(2), 16);
    //     });

    //     await milestones.mWithdraw(encodedPledges, { from: recipient1, $extraGas: 500000 });

    //     // confirm payment
    //     await vault.multiConfirm([1, 2, 3]);

    //     const bal = await web3.eth.getBalance(milestones.$address);
    //     assert.equal(bal, 700);

    //     const m = await milestones.getMilestone(1);
    //     assert.equal(m.canCollect, 700);
    // });

    // it('should not be able to collect if canCollect is 0', async() => {
    //     // await printLPState(liquidPledgingState);
    //     const m = await milestones.getMilestone(3);
    //     assert.equal(m.canCollect, 0);

    //     const startBal = await web3.eth.getBalance(milestones.$address);
    //     assert.isAbove(web3.utils.toDecimal(startBal), 0);

    //     await milestones.collect(3, { from: recipient2 });

    //     const endBal = await web3.eth.getBalance(milestones.$address);
    //     assert.equal(startBal, endBal)
    // });

    // it('reviewer should be able to cancel milestone', async() => {
    //     await milestones.addMilestone('Milestone3', '', 1000, 0, recipient1, reviewer1, campaignReviewer1); // pledgeAdmin 7
    //     await milestones.cancelMilestone(7, { from: reviewer1 });

    //     const m = await liquidPledging.getPledgeAdmin(7);
    //     assert.equal(m.canceled, true);
    // });
});