// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/subscription/Epochs.sol";

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import {OzInitializableBind} from "../../src/dependency/OzInitializable.sol";

contract TestEpochs is OzInitializableBind, Epochs {
    constructor(uint256 epochSize_) initializer {
        __Epochs_init(epochSize_);
    }

    function getEpoch(uint256 epoch) external view virtual returns (Epoch memory) {
        return _getEpoch(epoch);
    }

    function setEpoch(uint256 epoch, Epoch memory data) external virtual {
        _setEpoch(epoch, data);
    }

    function setLastProcessedEpoch(uint256 epoch) external virtual {
        _setLastProcessedEpoch(epoch);
    }

    function setActiveSubShares(uint256 shares) external virtual {
        _setActiveSubShares(shares);
    }

    function getActiveSubShares() external virtual returns (uint256) {
        return _getActiveSubShares();
    }

    function setClaimed(uint256 claimed) external virtual {
        _setClaimed(claimed);
    }

    function _now() internal view override returns (uint256) {
        return block.number;
    }

    function epochSize() external view virtual returns (uint256) {
        return _epochSize();
    }

    function currentEpoch() external view virtual returns (uint256) {
        return _currentEpoch();
    }

    function lastProcessedEpoch() external view virtual returns (uint256) {
        return _lastProcessedEpoch();
    }

    function activeSubShares() external view virtual returns (uint256) {
        return _activeSubShares();
    }

    function claimed() external view virtual returns (uint256) {
        return _claimed();
    }

    function scanEpochs(uint256 rate, uint256 upToEpoch)
        external
        view
        virtual
        returns (uint256 amount, uint256 starting, uint256 expiring)
    {
        return _scanEpochs(rate, upToEpoch);
    }

    function addNewSub(uint256 depositedAt, uint256 amount, uint256 shares, uint256 rate) external {
        _addToEpochs(depositedAt, amount, shares, rate);
    }

    function extendInEpochs(uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, uint256 shares, uint256 rate)
        external
    {
        _extendInEpochs(depositedAt, oldDeposit, newDeposit, shares, rate);
    }

    function reduceInEpochs(uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, uint256 shares, uint256 rate)
        external
    {
        _reduceInEpochs(depositedAt, oldDeposit, newDeposit, shares, rate);
    }

    function claim(uint256 rate, uint256 upToEpoch) external returns (uint256) {
        return _claimEpochs(rate, upToEpoch);
    }
}

contract EpochsTest is Test {
    using Math for uint256;

    TestEpochs private e;

    uint256 private epochSize;
    uint256 rate;

    function setUp() public {
        epochSize = 100;
        rate = 10;

        e = new TestEpochs(epochSize);
    }

    function oneTimeUnit(uint256 _rate, uint256 _shares) private pure returns (uint256) {
        return ((_rate * _shares) / 100) + 1;
    }

    function test_claimSingleSub(uint16 jump) public {
        uint256 shares = 100;
        uint256 deposit = 100_000_000;
        e.addNewSub(block.number, deposit, shares, rate);

        vm.roll(block.number + 2 * epochSize);

        (uint256 claimable,,) = e.scanEpochs(rate, e.currentEpoch());
        uint256 claimed = e.claim(rate, e.currentEpoch());
        assertEq(claimable, claimed, "1st claim: claimed amount equal to claimable");
        assertEq(claimed, e.claimed(), "1st claim: claimed amount stored in contract");

        vm.roll(block.number + jump);

        (claimable,,) = e.scanEpochs(rate, e.currentEpoch());
        uint256 claimed2 = e.claim(rate, e.currentEpoch());
        assertEq(claimable, claimed2, "2nd claim: claimed amount equal to claimable");
        assertEq(claimed + claimed2, e.claimed(), "2nd claim: claimed amount is updated");
    }

    function testClaimed_init() public view {
        assertEq(0, e.claimed(), "initialized at 0");
    }

    function testLastProcessedEpoch_init0() public view {
        assertEq(0, e.lastProcessedEpoch(), "initialized at 0");
    }

    function testLastProcessedEpoch_init(uint256 time) public {
        time = bound(time, epochSize + 1, type(uint64).max);
        vm.roll(time);

        e = new TestEpochs(epochSize);
        assertEq(
            (block.number / epochSize) - 1, e.lastProcessedEpoch(), "last processed epoch initialized to last epoch"
        );
    }

    function testActiveSubShares() public {
        e.setEpoch(0, Epoch(100, 200, 0));
        e.setEpoch(2, Epoch(100, 200, 0));
        e.setEpoch(4, Epoch(100, 200, 0));

        vm.roll(1);
        assertEq(200, e.activeSubShares());

        vm.roll(1 * epochSize);
        assertEq(100, e.activeSubShares());

        vm.roll(2 * epochSize);
        assertEq(300, e.activeSubShares());

        vm.roll(3 * epochSize);
        assertEq(200, e.activeSubShares());

        vm.roll(4 * epochSize);
        assertEq(400, e.activeSubShares());
    }

    function testActiveSubShares_persisted() public {
        e.setLastProcessedEpoch(1);
        e.setActiveSubShares(150);
        e.setEpoch(2, Epoch(100, 200, 0));
        e.setEpoch(4, Epoch(100, 200, 0));

        vm.roll(2 * epochSize);
        assertEq(350, e.activeSubShares());

        vm.roll(3 * epochSize);
        assertEq(250, e.activeSubShares());

        vm.roll(4 * epochSize);
        assertEq(450, e.activeSubShares());
    }

    function testActiveSubShares_sameEpochExpired() public {
        e.setLastProcessedEpoch(1);
        e.setEpoch(2, Epoch(200, 200, 0));

        vm.roll(3 * epochSize);
        assertEq(0, e.activeSubShares());
    }

    function testActiveSubShares_moreExpiring() public {
        e.setLastProcessedEpoch(1);
        e.setActiveSubShares(150);
        e.setEpoch(2, Epoch(350, 200, 0));

        vm.roll(2 * epochSize);
        assertEq(350, e.activeSubShares());

        vm.roll(3 * epochSize);
        assertEq(0, e.activeSubShares());
    }

    function testScanEpochs() public {
        uint256 upToEpoch = 10;
        uint256 activeShares = 3_000;

        e.setActiveSubShares(activeShares);
        e.setLastProcessedEpoch(1);

        e.setEpoch(2, Epoch({expiring: 100, starting: 200, partialFunds: 1_000}));
        e.setEpoch(4, Epoch({expiring: 500, starting: 0, partialFunds: 60_000}));
        e.setEpoch(8, Epoch({expiring: 0, starting: 888, partialFunds: 2_000}));

        e.setEpoch(upToEpoch, Epoch({expiring: 9999, starting: 9999, partialFunds: 99999}));

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, upToEpoch);

        // 2: 3k - 100 * epochRate + 1k => 2901k
        // 3: 3.1k * epochRate => 3100k
        // 4: 2.6k * epochRate + 60k => 2660k
        // 5-7: 2.6k * epochRate => 3 * 2600k => 7800k
        // 8: 2600 * epochRate + 2k => 2602k
        // 9: 3488 * epochRate => 3488k
        // div MULTI_BASE => 22_551_000 / 100 => 225_510
        assertEq(amount, 225_510, "amount");
        assertEq(expiring, 600, "expiring");
        assertEq(starting, 1088, "expiring");
    }

    function testClaimEpochs() public {
        uint256 upToEpoch = 10;
        uint256 claimed = 10_000_000;
        uint256 activeShares = 3_000;

        e.setActiveSubShares(activeShares);
        e.setClaimed(claimed);
        e.setLastProcessedEpoch(1);

        e.setEpoch(2, Epoch({expiring: 100, starting: 200, partialFunds: 1_000}));
        e.setEpoch(4, Epoch({expiring: 500, starting: 0, partialFunds: 60_000}));
        e.setEpoch(8, Epoch({expiring: 0, starting: 888, partialFunds: 2_000}));

        e.setEpoch(upToEpoch, Epoch({expiring: 9999, starting: 9999, partialFunds: 99999}));
        e.setEpoch(upToEpoch + 1, Epoch({expiring: 7777, starting: 7777, partialFunds: 77777}));

        vm.roll(upToEpoch * epochSize);

        // do not re-test scanEpoch
        (uint256 claimableAmount,,) = e.scanEpochs(rate, upToEpoch);

        // do test
        uint256 claimedAmount = e.claim(rate, upToEpoch);

        assertEq(claimedAmount, claimableAmount, "claimable amount claimed");
        assertEq(e.claimed(), claimed + claimedAmount, "Claimed incremented");
        assertEq(e.lastProcessedEpoch(), upToEpoch - 1, "lastProcessedEpoch updated to previous value");
        assertEq(e.getActiveSubShares(), activeShares - 100 + 200 - 500 + 888, "active shares processes");
        assertEq(e.getEpoch(2).partialFunds, 0, "epoch 2 deleted");
        assertEq(e.getEpoch(4).partialFunds, 0, "epoch 4 deleted");
        assertEq(e.getEpoch(8).partialFunds, 0, "epoch 8 deleted");

        assertEq(e.getEpoch(upToEpoch).partialFunds, 99999, "epoch current epoch not deleted");
    }

    function testClaimEpochs_deleteClaimed(uint256 upToEpoch, uint256 lastProcessedEpoch, uint256 currentEpoch)
        public
    {
        lastProcessedEpoch = (bound(lastProcessedEpoch, 1, 100));
        upToEpoch = (bound(upToEpoch, lastProcessedEpoch + 1, 200));
        currentEpoch = (bound(currentEpoch, upToEpoch, 300));

        uint256 claimed = 10_000_000;
        uint256 activeShares = 3_000;

        e.setActiveSubShares(activeShares);
        e.setClaimed(claimed);
        e.setLastProcessedEpoch(1);

        for (uint256 i = lastProcessedEpoch + 1; i < upToEpoch; i++) {
            e.setEpoch(i, Epoch({expiring: 100, starting: 200, partialFunds: 1_000}));
        }

        vm.roll(upToEpoch * epochSize);

        // do not re-test scanEpoch
        (uint256 claimableAmount,,) = e.scanEpochs(rate, upToEpoch);

        // do test
        uint256 claimedAmount = e.claim(rate, upToEpoch);

        assertEq(claimedAmount, claimableAmount, "claimable amount claimed");
        assertEq(e.claimed(), claimed + claimedAmount, "Claimed incremented");
        assertEq(e.lastProcessedEpoch(), upToEpoch - 1, "lastProcessedEpoch updated to previous value");
        assertEq(
            e.getActiveSubShares(),
            activeShares + (100 * (upToEpoch - (lastProcessedEpoch + 1))),
            "active shares processed"
        );

        for (uint256 i = lastProcessedEpoch + 1; i < upToEpoch; i++) {
            assertEq(e.getEpoch(i).partialFunds, 0, "epoch i deleted");
        }
    }

    function testClaimEpochs_futureEpochsUnchanged(
        uint256 upToEpoch,
        uint256 futureEpoch,
        uint256 lastProcessedEpoch,
        uint256 currentEpoch
    ) public {
        // lastProcessedEpoch -> upToEpoch -> currentEpoch -> futureEpoch

        lastProcessedEpoch = (bound(lastProcessedEpoch, 0, 100));
        upToEpoch = (bound(upToEpoch, lastProcessedEpoch + 1, 200));
        currentEpoch = (bound(currentEpoch, upToEpoch, 300));
        futureEpoch = (bound(futureEpoch, currentEpoch, 400));

        e.setLastProcessedEpoch(lastProcessedEpoch);

        e.setEpoch(futureEpoch, Epoch({expiring: 9999, starting: 9999, partialFunds: 99999}));
        e.setEpoch(futureEpoch + 1, Epoch({expiring: 7777, starting: 7777, partialFunds: 77777}));

        vm.roll(uint256(currentEpoch) * uint256(epochSize));

        // do test
        uint256 claimedAmount = e.claim(rate, upToEpoch);

        assertEq(claimedAmount, 0, "claimable amount claimed");
        assertEq(e.claimed(), 0, "Claimed unchanged");
        assertEq(e.lastProcessedEpoch(), upToEpoch - 1, "lastProcessedEpoch updated to previous value");
        assertEq(e.getActiveSubShares(), 0, "active shares unchanged");

        assertEq(e.getEpoch(futureEpoch).partialFunds, 99999, "unclaimed epoch not deleted");
        assertEq(e.getEpoch(futureEpoch + 1).partialFunds, 77777, "unclaimed epoch not deleted (2)");
    }

    function testClaimEpochs_alreadyClaimed(uint256 upToEpoch, uint256 currentEpoch) public {
        currentEpoch = bound(currentEpoch, 2, type(uint64).max - 2);
        upToEpoch = bound(upToEpoch, 1, currentEpoch - 1);

        e.setLastProcessedEpoch(currentEpoch - 1);

        vm.roll(uint256(currentEpoch) * uint256(epochSize));

        vm.expectRevert("SUB: cannot claim claimed epoch");
        e.claim(rate, upToEpoch);
    }

    function testClaimEpochs_twice() public {
        e.setLastProcessedEpoch(10);

        vm.roll(20 * epochSize);

        e.claim(rate, 19);
        e.claim(rate, 19);
    }

    function testClaimEpochs_epoch0(uint256 _rate) public {
        vm.expectRevert("SUB: cannot handle epoch 0");
        e.claim(_rate, 0);
    }

    function testClaimEpochs_futureEpoch(uint256 time, uint256 future) public {
        // some realistic time
        time = bound(time, 0, type(uint64).max - 1_000);
        // some time in the next epoch
        future = bound(future, time + epochSize, type(uint64).max);

        vm.roll(time);
        // initialize sub

        vm.expectRevert("SUB: cannot claim current epoch");
        e.claim(rate, future / epochSize);
    }

    function testAddToEpochs(uint24 shares, uint256 amount, uint256 depositedAt, uint256 _epochSize) public {
        // sub spans multiple epochs
        shares = uint24(bound(shares, SubLib.MULTIPLIER_BASE, SubLib.MULTIPLIER_MAX));
        epochSize = (bound(_epochSize, 1, type(uint32).max));
        amount = bound(amount, ((epochSize * shares * rate) / SubLib.MULTIPLIER_BASE) + 1, type(uint192).max);
        depositedAt = bound(depositedAt, 0, type(uint32).max);
        e = new TestEpochs(epochSize);

        // addToEpochs
        e.addNewSub(depositedAt, amount, shares, rate);

        Epoch memory startingEpoch = e.getEpoch(SubLib.epochOf(depositedAt, epochSize));
        uint256 expiresAt = SubLib.expiresAt(amount, depositedAt, rate, shares);
        Epoch memory expiringEpoch = e.getEpoch(SubLib.epochOf(expiresAt, epochSize));

        assertLt(SubLib.epochOf(depositedAt, epochSize), SubLib.epochOf(expiresAt, epochSize), "multiple epochs");

        assertEq(startingEpoch.starting, shares, "shares started");
        assertEq(
            startingEpoch.partialFunds,
            (epochSize - (depositedAt % epochSize)) * rate * shares,
            "starting partial funds"
        );

        assertEq(expiringEpoch.expiring, shares, "shares expiring");
        assertEq(
            expiringEpoch.partialFunds,
            ((expiresAt % epochSize) * rate * shares) + ((amount * SubLib.MULTIPLIER_BASE) % (rate * shares)),
            "expiring partial funds, including dust"
        );

        // sanity
        assertGe(
            amount * SubLib.MULTIPLIER_BASE,
            startingEpoch.partialFunds + expiringEpoch.partialFunds,
            "amount less than partial amounts"
        );
    }

    function testAddToEpochs_singleEpoch(
        uint24 shares,
        uint256 amount,
        uint256 epoch,
        uint256 depositedAt,
        uint256 _epochSize
    ) public {
        // sub spans multiple epochs
        shares = uint24(bound(shares, SubLib.MULTIPLIER_BASE, SubLib.MULTIPLIER_MAX));
        epoch = (bound(epoch, 0, type(uint64).max));
        epochSize = (bound(_epochSize, 1, type(uint32).max));
        depositedAt = bound(depositedAt, 0, epochSize - 1) + (epoch * epochSize);
        amount =
            bound(amount, 1, (((epochSize - (depositedAt % epochSize)) * shares * rate) / SubLib.MULTIPLIER_BASE) - 1);
        e = new TestEpochs(epochSize);

        // addToEpochs
        e.addNewSub(depositedAt, amount, shares, rate);
        uint256 expiresAt = SubLib.expiresAt(amount, depositedAt, rate, shares);

        console.log("start and end", depositedAt, expiresAt);
        assertEq(
            SubLib.epochOf(depositedAt, epochSize),
            SubLib.epochOf(expiresAt, epochSize),
            "starting and expiring in same epoch"
        );

        Epoch memory ep = e.getEpoch(SubLib.epochOf(depositedAt, epochSize));
        assertEq(ep.starting, shares, "shares started");
        assertEq(ep.expiring, shares, "shares expiring");
        assertEq(ep.partialFunds, amount * SubLib.MULTIPLIER_BASE, "partial funds contains all funds");
    }

    ////////////////////////////
    // integration test like
    ////////////////////////////

    function testActiveSubShares_new() public {
        uint256 shares = 100;
        e.addNewSub(block.number, 100_000, shares, rate);
        assertEq(e.activeSubShares(), shares, "new sub is active");
    }

    function testActiveSubShares_expiredImmediately() public {
        uint256 shares = 100;
        // only valid for 1 block
        e.addNewSub(block.number, rate, shares, rate);
        assertEq(e.activeSubShares(), shares, "new sub is active even after expiration in current epoch");

        vm.roll(epochSize + 1);
        assertEq(e.activeSubShares(), 0, "subs expired");
    }

    function testActiveSubShares_multiplier(uint16 shares) public {
        uint256 amount = 100_000;
        shares = uint16(bound(shares, 100, 10_000));
        e.addNewSub(block.number, amount, shares, rate);
        vm.roll(epochSize + 1);
        assertEq(e.activeSubShares(), shares, "first epoch: sub is active");

        vm.roll(((amount * 100) / (rate * shares)) + 1);
        assertEq(e.activeSubShares(), shares, "last epoch: sub is active");

        vm.roll(((amount * 100) / (rate * shares)) + epochSize + 1);
        assertEq(e.activeSubShares(), 0, "subs expired");
    }

    function testActiveSubShares_2subSequential() public {
        uint256 shares = 100;
        uint256 amount = 100_000;
        e.addNewSub(block.number, amount, shares, rate);
        assertEq(e.activeSubShares(), shares, "new sub is active even after expiration in current epoch");

        vm.roll(epochSize + 1);
        assertEq(e.activeSubShares(), shares, "first epoch: sub is active");

        uint256 firstExpire = (amount / (rate * epochSize)) * epochSize;
        vm.roll(firstExpire + 1);
        assertEq(e.activeSubShares(), shares, "last epoch: sub is active");

        // add second sub
        shares = 125;
        amount = 50_000;
        e.addNewSub(block.number, amount, shares, rate);
        assertEq(e.activeSubShares(), shares + 100, "both subs are active");

        vm.roll(firstExpire + epochSize + 1);
        assertEq(e.activeSubShares(), shares, "only second sub active");

        vm.roll(firstExpire + (((amount * 100) / (rate * shares))) + 1);
        assertEq(e.activeSubShares(), shares, "second sub about to expire");

        vm.roll(firstExpire + (((amount * 100) / (rate * shares)) + epochSize) + 1);
        assertEq(e.activeSubShares(), 0, "2nd sub expired");
    }

    function testActiveSubShares_2subParallel() public {
        uint256 shares = 100;
        uint256 amount = 100_000;
        uint256 shares2 = 222;
        uint256 amount2 = 2_200_000;

        e.addNewSub(block.number, amount, shares, rate);
        e.addNewSub(block.number, amount2, shares2, rate);
        assertEq(e.activeSubShares(), shares + shares2, "both new subs active");

        vm.roll(epochSize + 1);
        assertEq(e.activeSubShares(), shares + shares2, "first epoch: both subs active");

        uint256 firstExpire = ((amount * 100) / (rate * shares));
        vm.roll(firstExpire + 1);
        assertEq(e.activeSubShares(), shares + shares2, "first sub about to expire");

        vm.roll(firstExpire + epochSize + 1);
        assertEq(e.activeSubShares(), shares2, "first sub expired");

        uint256 secondExpire = ((amount2 * 100) / (rate * shares2));
        vm.roll(secondExpire + 1);
        assertEq(e.activeSubShares(), shares2, "second sub about to expire");

        vm.roll(secondExpire + epochSize + 1);
        assertEq(e.activeSubShares(), 0, "second sub expired");
    }

    function testActiveSubShares_extendSubscription_initNotOneEpoch(
        uint16 shares,
        uint256 initDeposit,
        uint256 newDeposit
    ) public {
        shares = uint16(bound(shares, 100, 10_000));

        initDeposit = bound(initDeposit, epochSize * oneTimeUnit(rate, shares), 1_000_000);
        newDeposit = bound(newDeposit, initDeposit + oneTimeUnit(rate, shares), initDeposit * 10);

        uint256 initDepositAt = epochSize / 10;
        uint256 initExpiresAt = initDepositAt + (initDeposit * 100) / (rate * shares);

        assertNotEq(initDepositAt / epochSize, initExpiresAt / epochSize, "init sub not in 1 epoch");
        vm.roll(initDepositAt);

        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);

        vm.roll(initDepositAt + epochSize + 1);
        assertEq(e.activeSubShares(), shares, "first epoch: sub is active");

        vm.roll(initExpiresAt - 1);
        assertEq(e.activeSubShares(), shares, "last epoch: sub is active");

        //////////
        //////////
        //////////
        uint256 newExpiresAt = initDepositAt + (newDeposit * 100) / (rate * shares);
        assertGt(newExpiresAt, initExpiresAt, "sanity: longer expiration");

        e.extendInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        if (initExpiresAt / epochSize != newExpiresAt / epochSize) {
            vm.roll(initExpiresAt + epochSize);
            assertEq(e.activeSubShares(), shares, "init sub extended");
        }

        vm.roll(newExpiresAt);
        assertEq(e.activeSubShares(), shares, "end of extended sub");

        vm.roll(newExpiresAt + epochSize);
        assertEq(e.activeSubShares(), 0, "extended sub expired");
    }

    // initial sub starts and expires within a single epoch
    function testActiveSubShares_extendSubscription_initOneEpoch(uint16 shares, uint256 newDeposit) public {
        shares = uint16(bound(shares, 100, 10_000));

        uint256 initDeposit = (epochSize / 6) * oneTimeUnit(rate, shares);
        newDeposit = bound(newDeposit, initDeposit + (rate * shares), initDeposit * 10);

        uint256 initDepositAt = epochSize / 10;
        uint256 initExpiresAt = initDepositAt + (initDeposit * 100) / (rate * shares);

        assertEq(initDepositAt / epochSize, initExpiresAt / epochSize, "init sub not in 1 epoch");
        vm.roll(initDepositAt);

        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);

        vm.roll(initDepositAt);
        assertEq(e.activeSubShares(), shares, "first epoch: sub is active");

        vm.roll(initExpiresAt - 1);
        assertEq(e.activeSubShares(), shares, "last epoch: sub is active");

        //////////
        //////////
        //////////
        uint256 newExpiresAt = initDepositAt + (newDeposit * 100) / (rate * shares);
        assertGt(newExpiresAt, initExpiresAt, "sanity: longer expiration");

        e.extendInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        vm.roll(initExpiresAt + epochSize);
        assertEq(e.activeSubShares(), shares, "init sub extended");

        vm.roll(newExpiresAt);
        assertEq(e.activeSubShares(), shares, "end of extended sub");

        vm.roll(newExpiresAt + epochSize);
        assertEq(e.activeSubShares(), 0, "extended sub expired");
    }

    function testExtendSubscription_extendExpiredSubscription(uint16 shares, uint256 nextDepositAt) public {
        uint256 initDeposit = 100_000;
        uint256 initDepositAt = epochSize / 10;

        shares = uint16(bound(shares, 100, 10_000));
        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));
        nextDepositAt = bound(nextDepositAt, initExpiresAt + 1, initExpiresAt * 100);
        //
        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        vm.roll(nextDepositAt + epochSize); // next epoch after expiry
        assertEq(e.activeSubShares(), 0, "initial sub expired");

        vm.expectRevert();
        // cannot extend an expired sub
        e.extendInEpochs(initDepositAt, initDeposit, 1, shares, rate);
    }

    function testProcessEpochs_noSubs() public view {
        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 25);
        assertEq(amount, 0, "no funds claimable");
        assertEq(starting, 0, "sub is starting");
        assertEq(expiring, 0, "sub not expiring");
    }

    function testAdd0AmountSub(uint16 shares) public {
        vm.roll(10);
        shares = uint16(bound(shares, 100, 10_000));

        e.addNewSub(block.number, 0, shares, rate);

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 1);
        assertEq(amount, 0, "no funds claimable");
        assertEq(starting, shares, "sub is starting");
        assertEq(expiring, shares, "sub all expiring");
    }

    function testAdd1AmountSub(uint16 shares) public {
        vm.roll(10);
        shares = uint16(bound(shares, 100, 10_000));

        e.addNewSub(block.number, 1, shares, rate);

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 1);
        assertEq(amount, 1, "all funds claimable");
        assertEq(starting, shares, "sub is starting");
        assertEq(expiring, shares, "sub expiring");
    }

    function testAdd1TimeUnitAmountSub(uint16 shares) public {
        vm.roll(10);
        shares = uint16(bound(shares, 100, 10_000));

        uint256 deposit = (rate * shares) / 100; // 1 time unit
        e.addNewSub(block.number, deposit, shares, rate);

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 1);
        assertEq(amount, deposit, "all funds claimable");
        assertEq(starting, shares, "sub is starting");
        assertEq(expiring, shares, "sub expiring");
    }

    function testAdd1EpochAmountSub(uint16 shares) public {
        vm.roll(10);
        shares = uint16(bound(shares, 100, 10_000));

        uint256 deposit = (rate * epochSize * shares) / 100; // 1 epoch size
        e.addNewSub(block.number, deposit, shares, rate);

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 1);
        assertEq(amount, (rate * (epochSize - 10) * shares) / 100, "e0: partial funds claimable");
        assertEq(starting, shares, "e0: sub is starting");
        assertEq(expiring, 0, "e0: sub expiring");

        (amount, starting, expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, deposit, "e1: all funds claimable");
        assertEq(starting, shares, "e1: sub is starting");
        assertEq(expiring, shares, "e1: sub expiring");
    }

    function testAddSub(uint16 shares, uint256 deposit) public {
        vm.roll(10);
        shares = uint16(bound(shares, 100, 10_000));
        deposit = bound(deposit, 0, 1_000_000);

        e.addNewSub(block.number, deposit, shares, rate);

        uint256 maxEpoch = (1_000_000 / 10) / epochSize;

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, maxEpoch + 1);
        assertEq(amount, deposit, "all funds claimable");
        assertEq(starting, shares, "sub is starting");
        assertEq(expiring, shares, "sub expiring");
    }

    function testProcessEpochs(uint16 shares) public {
        uint256 initDeposit = 100_000;
        uint256 initDepositAt = epochSize / 10;

        shares = uint16(bound(shares, 100, 10_000));

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);
        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 0);
        assertEq(amount, 0, "init: no funds claimable");
        assertEq(starting, 0, "init: sub is starting");
        assertEq(expiring, 0, "init: sub not expiring");

        // check each subsequent epoch
        for (uint256 i = 1; i <= (initExpiresAt / epochSize); i++) {
            (amount, starting, expiring) = e.scanEpochs(rate, i);
            assertEq(
                amount, ((rate * shares) * ((epochSize * i) - initDepositAt)) / 100, "epoch i: partial funds claimable"
            );
            assertEq(starting, shares, "epoch i: sub is starting");
            assertEq(expiring, 0, "epoch i: sub not expiring");
        }

        (amount, starting, expiring) = e.scanEpochs(rate, (initExpiresAt / epochSize) + 1);
        assertEq(amount, initDeposit, "last epoch: all funds claimable");
        assertEq(starting, shares, "last epoch: sub is starting");
        assertEq(expiring, shares, "last epoch: sub is expiring");
    }

    function testProcessEpochs_multiple_totalAmount(uint16 shares1, uint16 shares2) public {
        uint256 deposit1 = 100_000;
        uint256 deposit1At = 10;

        uint256 deposit2 = 200_000;
        uint256 deposit2At = deposit1At + (epochSize * bound(shares2, 1, 10));

        shares1 = uint16(bound(shares1, 100, 10_000));
        shares2 = uint16(bound(shares2, 100, 10_000));

        uint256 deposit1ExpiresAt = deposit1At + ((deposit1 * 100) / (rate * shares1));
        uint256 deposit2ExpiresAt = deposit2At + ((deposit2 * 100) / (rate * shares2));

        vm.roll(deposit1At);
        // initialize sub
        e.addNewSub(block.number, deposit1, shares1, rate);

        vm.roll(deposit2At);
        // add 2nd sub
        e.addNewSub(block.number, deposit2, shares2, rate);

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 0);
        assertEq(amount, 0, "init: no funds claimable");
        assertEq(starting, 0, "init: sub is starting");
        assertEq(expiring, 0, "init: sub not expiring");

        (amount, starting, expiring) = e.scanEpochs(rate, (deposit1ExpiresAt.max(deposit2ExpiresAt) / epochSize) + 1);
        assertEq(amount, deposit1 + deposit2, "last epoch: all funds claimable");
        assertEq(starting, shares1 + shares2, "last epoch: sub is starting");
        assertEq(expiring, shares1 + shares2, "last epoch: sub is expiring");
    }

    function testProcessEpochs_extendOneEpochSubByOneEpoch(uint16 shares, uint256 initDeposit, uint256 newDeposit)
        public
    {
        shares = uint16(bound(shares, 100, 10_000));

        initDeposit = bound(initDeposit, epochSize * oneTimeUnit(rate, shares), 1_000_000); // at least 1 epoch
        newDeposit = bound(
            newDeposit,
            initDeposit + (epochSize * oneTimeUnit(rate, shares)),
            initDeposit + (epochSize * oneTimeUnit(rate, shares) * 10)
        ); // add at least another epoch
        uint256 initDepositAt = epochSize / 10;

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));
        uint256 newDepositAt = bound(newDeposit, initDepositAt, initExpiresAt - 1);

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, initExpiresAt / epochSize + 1);
        assertEq(amount, initDeposit, "sub exp: all funds claimable");
        assertEq(starting, shares, "sub exp: sub started");
        assertEq(expiring, shares, "sub exp: sub expired");

        vm.roll(newDepositAt);
        e.extendInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        // sub expiration was moved
        (amount, starting, expiring) = e.scanEpochs(rate, (initExpiresAt / epochSize) + 1);
        assertGt(amount, initDeposit, "sub ext: initial funds and new partial deposit claimable");
        assertEq(starting, shares, "sub exp: sub started");
        assertEq(expiring, 0, "sub exp: sub still active");

        // extended sub expired
        (amount, starting, expiring) =
            e.scanEpochs(rate, ((initDepositAt + (newDeposit * 100) / (rate * shares)) / epochSize) + 1);
        assertEq(amount, newDeposit, "sub ext exp: all funds claimable");
        assertEq(starting, shares, "sub ext exp: sub started");
        assertEq(expiring, shares, "sub ext exp: sub expired");
    }

    // generic extension
    function testProcessEpochs_extendEpoch(uint16 shares, uint256 initDeposit, uint256 newDeposit) public {
        shares = uint16(bound(shares, 100, 10_000));

        initDeposit = bound(initDeposit, oneTimeUnit(rate, shares), 1_000_000); // at least 1 time unit
        newDeposit = bound(newDeposit, initDeposit + 1, initDeposit + (((epochSize * rate * shares) * 10) / 100)); // at least 1 gwei
        uint256 initDepositAt = epochSize / 10;

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));
        uint256 newExpiresAt = initDepositAt + ((newDeposit * 100) / (rate * shares));
        uint256 newDepositAt = bound(newDeposit, initDepositAt, initExpiresAt - 1);

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, (initExpiresAt / epochSize) + 1);
        assertEq(amount, initDeposit, "sub exp: all funds claimable");
        assertEq(starting, shares, "sub exp: sub started");
        assertEq(expiring, shares, "sub exp: sub expired");

        vm.roll(newDepositAt);
        e.extendInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        if ((initExpiresAt / epochSize) != (newExpiresAt / epochSize)) {
            // sub expiration was moved to a new epoch
            (amount, starting, expiring) = e.scanEpochs(rate, (initExpiresAt / epochSize) + 1);
            assertGt(amount, initDeposit, "sub ext: initial funds and new partial deposit claimable");
            assertEq(starting, shares, "sub exp: sub started");
            assertEq(expiring, 0, "sub exp: sub still active");
        }

        // extended sub expired
        (amount, starting, expiring) = e.scanEpochs(rate, (newExpiresAt / epochSize) + 1);
        assertEq(amount, newDeposit, "sub ext exp: all funds claimable");
        assertEq(starting, shares, "sub ext exp: sub started");
        assertEq(expiring, shares, "sub ext exp: sub expired");
    }

    function testExtendEpoch_extendMultiEpoch_byOneTimeUnit() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * epochSize; // 1 epoch
        uint256 newDeposit = initDeposit + rate;
        uint256 initDepositAt = epochSize / 10;

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));
        // uint256 newExpiresAt = initDepositAt + ((newDeposit * 100) / (rate * shares));
        uint256 newDepositAt = initExpiresAt - 1;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, initDeposit, "sub exp: all funds claimable");
        assertEq(starting, shares, "sub exp: sub started");
        assertEq(expiring, shares, "sub exp: sub expired");

        vm.roll(newDepositAt);
        e.extendInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        // extended sub expired
        (amount, starting, expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, newDeposit, "sub ext exp: all funds claimable");
        assertEq(starting, shares, "sub ext exp: sub started");
        assertEq(expiring, shares, "sub ext exp: sub expired");
    }

    function testExtendEpoch_extendMultiEpoch_byOneEpoch() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * epochSize; // 1 epoch
        uint256 newDeposit = initDeposit * 2;
        uint256 initDepositAt = epochSize / 10;

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));
        // uint256 newExpiresAt = initDepositAt + ((newDeposit * 100) / (rate * shares));
        uint256 newDepositAt = initExpiresAt - 1;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, initDeposit, "sub exp: all funds claimable");
        assertEq(starting, shares, "sub exp: sub started");
        assertEq(expiring, shares, "sub exp: sub expired");

        vm.roll(newDepositAt);
        e.extendInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        // extended sub active
        (amount, starting, expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, (epochSize + epochSize - initDepositAt) * rate, "sub ext: more funds claimable");
        assertEq(starting, shares, "sub ext: sub started");
        assertEq(expiring, 0, "sub ext: sub not yet expired");

        // extended sub expired
        (amount, starting, expiring) = e.scanEpochs(rate, 3);
        assertEq(amount, newDeposit, "sub ext exp: all funds claimable");
        assertEq(starting, shares, "sub ext exp: sub started");
        assertEq(expiring, shares, "sub ext exp: sub expired");
    }

    function testExtendEpoch_extendSingleEpoch_byOneTimeUnit() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * (epochSize / 2); // 1 epoch
        uint256 newDeposit = initDeposit + rate;
        uint256 initDepositAt = epochSize + (epochSize / 10);

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));
        // uint256 newExpiresAt = initDepositAt + ((newDeposit * 100) / (rate * shares));
        uint256 newDepositAt = initExpiresAt - 1;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, initDeposit, "epoch 1 : all init funds claimable");
        assertEq(starting, shares, "epoch 1: sub started");
        assertEq(expiring, shares, "epoch 1: sub expired");

        vm.roll(newDepositAt);
        e.extendInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        // extended sub expired
        (amount, starting, expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, newDeposit, "sub ext exp: all funds claimable");
        assertEq(starting, shares, "sub ext exp: sub started");
        assertEq(expiring, shares, "sub ext exp: sub expired");
    }

    function testExtendEpoch_extendSingleEpoch_byOneEpoch() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * (epochSize / 2); // 1 epoch
        uint256 newDeposit = initDeposit + (epochSize * rate);
        uint256 initDepositAt = epochSize + (epochSize / 10);

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));
        // uint256 newExpiresAt = initDepositAt + ((newDeposit * 100) / (rate * shares));
        uint256 newDepositAt = initExpiresAt - 1;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, initDeposit, "epoch 1 : no funds claimable");
        assertEq(starting, shares, "epoch 1: sub started");
        assertEq(expiring, shares, "epoch 1: sub expired");

        vm.roll(newDepositAt);
        e.extendInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        // extended sub
        (amount, starting, expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, (epochSize + epochSize - initDepositAt) * rate, "sub ext: partial funds claimable");
        assertEq(starting, shares, "sub ext: sub started");
        assertEq(expiring, 0, "sub ext: sub not yet expired");

        // extended sub expired
        (amount, starting, expiring) = e.scanEpochs(rate, 3);
        assertEq(amount, newDeposit, "sub ext exp: all funds claimable");
        assertEq(starting, shares, "sub ext exp: sub started");
        assertEq(expiring, shares, "sub ext exp: sub expired");
    }

    function testReduceEpoch_ReduceMultiEpoch_byOneEpoch() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * epochSize * 2; // 2 epochs
        uint256 newDeposit = initDeposit / 2; // 1 epoch
        uint256 initDepositAt = epochSize / 10;

        uint256 newDepositAt = initDepositAt + 1;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, (epochSize + epochSize - initDepositAt) * rate, "sub init e2: partial funds claimable");
        assertEq(starting, shares, "sub init e2: sub started");
        assertEq(expiring, 0, "sub init e2: sub not expired");
        assertEq(e.activeSubShares(), shares, "sub init e2: sub active");

        (amount, starting, expiring) = e.scanEpochs(rate, 3);
        assertEq(amount, initDeposit, "sub init e3: all funds claimable");
        assertEq(starting, shares, "sub init e3: sub started");
        assertEq(expiring, shares, "sub init e3: sub expired");

        vm.roll(newDepositAt);
        e.reduceInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        // reduced sub inactive
        (amount, starting, expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, newDeposit, "sub red e2: reduced funds claimable");
        assertEq(starting, shares, "sub red e2: sub started");
        assertEq(expiring, shares, "sub red e2: sub expired");

        vm.roll(initDepositAt + (1 * epochSize));
        assertEq(e.activeSubShares(), shares, "sub not expired");

        vm.roll(initDepositAt + (2 * epochSize));
        assertEq(e.activeSubShares(), 0, "sub expired");
    }

    function testReduceEpoch_ReduceMultiEpoch_byOneTimeUnit() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * epochSize * 2; // 2 epochs
        uint256 newDeposit = initDeposit - rate; // 1 time unit reduced
        uint256 initDepositAt = epochSize / 10;

        uint256 newDepositAt = initDepositAt + 1;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, (epochSize + epochSize - initDepositAt) * rate, "sub init e2: partial funds claimable");
        assertEq(starting, shares, "sub init e2: sub started");
        assertEq(expiring, 0, "sub init e2: sub not expired");

        (amount, starting, expiring) = e.scanEpochs(rate, 3);
        assertEq(amount, initDeposit, "sub init e3: all funds claimable");
        assertEq(starting, shares, "sub init e3: sub started");
        assertEq(expiring, shares, "sub init e3: sub expired");

        vm.roll(newDepositAt);
        e.reduceInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        // reduced sub active
        (amount, starting, expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, (epochSize + epochSize - initDepositAt) * rate, "sub red e2: partial funds claimable");
        assertEq(starting, shares, "sub red e2: sub started");
        assertEq(expiring, 0, "sub red e2: sub not expired");

        // reduced sub inactive
        (amount, starting, expiring) = e.scanEpochs(rate, 3);
        assertEq(amount, newDeposit, "sub red e3: reduced funds claimable");
        assertEq(starting, shares, "sub red e3: sub started");
        assertEq(expiring, shares, "sub red e3: sub expired");

        vm.roll(initDepositAt + (1 * epochSize));
        assertEq(e.activeSubShares(), shares, "e1: sub not expired");

        vm.roll(initDepositAt + (2 * epochSize));
        assertEq(e.activeSubShares(), shares, "e2: sub not expired");

        vm.roll(initDepositAt + (3 * epochSize));
        assertEq(e.activeSubShares(), 0, "e3: sub expired");
    }

    function testReduceEpoch_reduceMultiEpoch_cancelToOneTimeUnit() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * epochSize * 2; // 2 epochs
        uint256 newDeposit = rate; // to 1 time unit reduced
        uint256 initDepositAt = epochSize / 10;

        uint256 newDepositAt = initDepositAt;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, (epochSize + epochSize - initDepositAt) * rate, "sub init e2: partial funds claimable");
        assertEq(starting, shares, "sub init e2: sub started");
        assertEq(expiring, 0, "sub init e2: sub not expired");

        (amount, starting, expiring) = e.scanEpochs(rate, 3);
        assertEq(amount, initDeposit, "sub init e3: all funds claimable");
        assertEq(starting, shares, "sub init e3: sub started");
        assertEq(expiring, shares, "sub init e3: sub expired");

        vm.roll(newDepositAt);
        e.reduceInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "canceled sub still seen as active");

        // reduced sub inactive
        (amount, starting, expiring) = e.scanEpochs(rate, 1);
        assertEq(amount, newDeposit, "sub red e1: all funds claimable");
        assertEq(starting, shares, "sub red e1: sub started");
        assertEq(expiring, shares, "sub red e1: sub expired");

        vm.roll(initDepositAt + epochSize);
        assertEq(e.activeSubShares(), 0, "e1: sub expired");
    }

    function testReduceEpoch_reduceMultiEpoch_cancelToOneTimeUnit_past() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * epochSize * 2; // 2 epochs
        uint256 newDeposit = rate; // to 1 time unit reduced
        uint256 initDepositAt = epochSize / 10;

        uint256 newDepositAt = initDepositAt + 1;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);

        vm.roll(newDepositAt);
        vm.expectRevert();
        e.reduceInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);
    }

    function testReduceEpoch_reduceMultiEpoch_cancelToZeroTimeUnit() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * epochSize * 2; // 2 epochs
        uint256 newDeposit = 0; // to 1 time unit reduced
        uint256 initDepositAt = epochSize / 10;

        uint256 newDepositAt = initDepositAt;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        vm.roll(newDepositAt);
        vm.expectRevert();
        e.reduceInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);
    }

    function testReduceEpoch_reduceSingleEpoch_byOneTimeUnit() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * (epochSize / 2); // just some time units
        uint256 newDeposit = initDeposit - rate; // 1 time unit reduced
        uint256 initDepositAt = epochSize + (epochSize / 10); // not epoch 0

        uint256 newDepositAt = initDepositAt + 1;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, initDeposit, "sub init e2: all funds claimable");
        assertEq(starting, shares, "sub init e2: sub started");
        assertEq(expiring, shares, "sub init e2: sub expired");

        vm.roll(newDepositAt);
        e.reduceInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        // reduced sub inactive
        (amount, starting, expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, newDeposit, "sub red e2: all funds claimable");
        assertEq(starting, shares, "sub red e2: sub started");
        assertEq(expiring, shares, "sub red e2: sub not expired");

        vm.roll(initDepositAt + epochSize);
        assertEq(e.activeSubShares(), 0, "e1: sub expired");
    }

    function testReduceEpoch_reduceSingleEpoch_cancelToOneTimeUnit() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * (epochSize / 2); // just some time units
        uint256 newDeposit = rate; // to 1 time unit reduced
        uint256 initDepositAt = epochSize + (epochSize / 10); // not epoch 0

        uint256 newDepositAt = initDepositAt;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, initDeposit, "sub init e2: all funds claimable");
        assertEq(starting, shares, "sub init e2: sub started");
        assertEq(expiring, shares, "sub init e2: sub expired");

        vm.roll(newDepositAt);
        e.reduceInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        // reduced sub inactive
        (amount, starting, expiring) = e.scanEpochs(rate, 2);
        assertEq(amount, newDeposit, "sub red e2: all funds claimable");
        assertEq(starting, shares, "sub red e2: sub started");
        assertEq(expiring, shares, "sub red e2: sub not expired");

        vm.roll(initDepositAt + epochSize);
        assertEq(e.activeSubShares(), 0, "e1: sub expired");
    }

    function testReduceEpoch_reduceSingleEpoch_cancelToOneTimeUnit_past() public {
        uint256 shares = 100; // neutral

        uint256 initDeposit = rate * (epochSize / 2); // just some time units
        uint256 newDeposit = rate; // to 1 time unit reduced
        uint256 initDepositAt = epochSize + (epochSize / 10); // not epoch 0

        uint256 newDepositAt = initDepositAt + 1;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);

        vm.roll(newDepositAt);
        vm.expectRevert();
        e.reduceInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);
    }

    function testProcessEpochs_reduceEpoch(uint16 shares, uint256 initDeposit, uint256 newDeposit) public {
        shares = uint16(bound(shares, 100, 10_000));

        initDeposit = bound(initDeposit, oneTimeUnit(rate, shares), 5_000_000); // at least 2 time unit
        newDeposit = bound(newDeposit, oneTimeUnit(rate, shares), initDeposit); // at least 1 time unit
        uint256 initDepositAt = epochSize / 10;

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));
        uint256 newExpiresAt = initDepositAt + ((newDeposit * 100) / (rate * shares));
        uint256 newDepositAt = bound(newDeposit, initDepositAt, newExpiresAt - 1);

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);
        assertEq(e.activeSubShares(), shares, "at initial deposit, sub is active");

        (uint256 amount, uint256 starting, uint256 expiring) = e.scanEpochs(rate, (initExpiresAt / epochSize) + 1);
        assertEq(amount, initDeposit, "sub reduce: all funds claimable");
        assertEq(starting, shares, "sub reduce: sub started");
        assertEq(expiring, shares, "sub reduce: sub expired");

        vm.roll(newDepositAt);
        e.reduceInEpochs(initDepositAt, initDeposit, newDeposit, shares, rate);

        // sub expiration was moved to a new epoch, sub needs to still be expired in old epoch
        (amount, starting, expiring) = e.scanEpochs(rate, (initExpiresAt / epochSize) + 1);
        assertEq(amount, newDeposit, "sub reduce: new deposit is expired");
        assertEq(starting, shares, "sub reduce: sub started");
        assertEq(expiring, shares, "sub reduce: sub expired");

        // extended sub expired
        (amount, starting, expiring) = e.scanEpochs(rate, (newExpiresAt / epochSize) + 1);
        assertEq(amount, newDeposit, "sub reduce exp: all funds claimable");
        assertEq(starting, shares, "sub reduce exp: sub started");
        assertEq(expiring, shares, "sub reduce exp: sub expired");
    }

    function testClaim(uint16 shares, uint256 initDeposit) public {
        shares = uint16(bound(shares, 100, 10_000));

        initDeposit =
            bound(initDeposit, oneTimeUnit(rate, shares) * epochSize, oneTimeUnit(rate, shares) * epochSize * 25);
        uint256 initDepositAt = epochSize / 10;

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));

        uint256 totalClaimed = 0;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);

        {
            // claim epoch 0
            vm.roll(initDepositAt + epochSize);

            uint256 amount = e.claim(rate, e.currentEpoch());
            totalClaimed += amount;

            assertEq(amount, (rate * shares * (epochSize - initDepositAt)) / 100, "epoch 0: partial funds claimable");

            assertEq(totalClaimed, e.claimed(), "epoch 0: total claimed");
            assertEq(0, e.lastProcessedEpoch(), "epoch 0: last processed epoch");
            assertEq(shares, e.activeSubShares(), "epoch 0: shares active");

            // try second claim -> no change
            amount = e.claim(rate, e.currentEpoch());
            assertEq(amount, 0, "epoch 0, 2: second claim ineffective");
            assertEq(totalClaimed, e.claimed(), "epoch 0, 2: total claimed");
            assertEq(0, e.lastProcessedEpoch(), "epoch 0, 2: last processed epoch");
            assertEq(shares, e.activeSubShares(), "epoch 0, 2: shares active");
        }

        // if sub is too small to contain full epochs, we skip this check
        if (initExpiresAt / epochSize != 1) {
            // check each subsequent epoch
            for (uint256 i = 2; i <= ((initExpiresAt) / epochSize); i++) {
                vm.roll(initDepositAt + (i * epochSize));

                uint256 amount = e.claim(rate, e.currentEpoch());
                totalClaimed += amount;
                assertEq(amount, (rate * shares * epochSize) / 100, "epoch i: partial funds claimable");

                assertEq(totalClaimed, e.claimed(), "epoch i: total claimed");
                assertEq(i - 1, e.lastProcessedEpoch(), "epoch i: last processed epoch");
                assertEq(shares, e.activeSubShares(), "epoch i: shares active");

                // try second claim -> no change
                amount = e.claim(rate, e.currentEpoch());
                assertEq(amount, 0, "epoch i, 2: second claim ineffective");
                assertEq(totalClaimed, e.claimed(), "epoch i, 2: total claimed");
                assertEq(i - 1, e.lastProcessedEpoch(), "epoch i, 2: last processed epoch");
                assertEq(shares, e.activeSubShares(), "epoch i, 2: shares active");
            }
        }

        {
            vm.roll(initExpiresAt + epochSize);

            uint256 amount = e.claim(rate, e.currentEpoch());
            totalClaimed += amount;

            assertEq(totalClaimed, e.claimed(), "last epoch: total claimed");
            assertEq(totalClaimed, initDeposit, "last epoch: total claimable funds");
            assertEq(initExpiresAt / epochSize, e.lastProcessedEpoch(), "last epoch: last processed epoch");
            assertEq(0, e.activeSubShares(), "last epoch: shares not active");

            // try second claim -> no change
            amount = e.claim(rate, e.currentEpoch());
            assertEq(amount, 0, "last epoch, 2: second claim ineffective");
            assertEq(totalClaimed, e.claimed(), "last epoch, 2: total claimed");
            assertEq(totalClaimed, initDeposit, "last epoch, 2: total claimable funds");
            assertEq(initExpiresAt / epochSize, e.lastProcessedEpoch(), "last epoch, 2: last processed epoch");
            assertEq(0, e.activeSubShares(), "last epoch, 2: shares not active");
        }
    }

    function testClaim_singleEpoch(uint16 shares, uint256 initDeposit) public {
        shares = uint16(bound(shares, 100, 10_000));

        initDeposit = bound(initDeposit, oneTimeUnit(rate, shares), oneTimeUnit(rate, shares) * (epochSize / 2));
        uint256 initDepositAt = epochSize / 10;

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);

        // claim epoch 0
        vm.roll(initDepositAt + epochSize);

        uint256 amount = e.claim(rate, e.currentEpoch());

        assertEq(amount, initDeposit, "epoch 0: partial funds claimable");

        assertEq(e.claimed(), initDeposit, "epoch 0: total amount claimed");
        assertEq(0, e.lastProcessedEpoch(), "epoch 0: last processed epoch");
        assertEq(0, e.activeSubShares(), "epoch 0: shares not active after expire");
    }

    function testClaim_single_total(uint16 shares) public {
        uint256 initDeposit = 100_000;
        uint256 initDepositAt = 10;

        shares = uint16(bound(shares, 100, 10_000));

        uint256 initExpiresAt = initDepositAt + ((initDeposit * 100) / (rate * shares));

        vm.roll(initDepositAt);
        // initialize sub
        e.addNewSub(block.number, initDeposit, shares, rate);

        {
            vm.roll(initExpiresAt + epochSize);

            e.claim(rate, e.currentEpoch());

            assertEq(initDeposit, e.claimed(), "last epoch: total funds claimed");
            assertEq(initExpiresAt / epochSize, e.lastProcessedEpoch(), "last epoch: last processed epoch");
            assertEq(0, e.activeSubShares(), "last epoch: shares not active after expire");
        }
    }

    function testClaim_mutliple_total(uint16 shares1, uint16 shares2) public {
        uint256 deposit1 = 100_000;
        uint256 deposit1At = 10;

        uint256 deposit2 = 200_000;
        uint256 deposit2At = deposit1At + (epochSize * bound(shares2, 1, 10));

        shares1 = uint16(bound(shares1, 100, 10_000));
        shares2 = uint16(bound(shares2, 100, 10_000));

        uint256 deposit1ExpiresAt = deposit1At + ((deposit1 * 100) / (rate * shares1));
        uint256 deposit2ExpiresAt = deposit2At + ((deposit2 * 100) / (rate * shares2));

        vm.roll(deposit1At);
        // initialize sub
        e.addNewSub(block.number, deposit1, shares1, rate);

        vm.roll(deposit2At);
        // add 2nd sub
        e.addNewSub(block.number, deposit2, shares2, rate);

        if (deposit1ExpiresAt > deposit2At) {
            // subs intersect
            assertEq(shares1 + shares2, e.activeSubShares(), "shares from both subs active");
        }

        vm.roll(deposit1ExpiresAt.max(deposit2ExpiresAt) + epochSize);

        e.claim(rate, e.currentEpoch());

        assertEq(deposit1 + deposit2, e.claimed(), "last epoch: total funds claimed");
        assertEq(
            deposit1ExpiresAt.max(deposit2ExpiresAt) / epochSize,
            e.lastProcessedEpoch(),
            "last epoch: last processed epoch"
        );
        assertEq(0, e.activeSubShares(), "last epoch: all shares not active after expire");
    }

    function testClaim_epoch0(uint256 time) public {
        time = bound(time, 0, epochSize - 1);

        vm.roll(time);

        uint256 currentEpoch = e.currentEpoch();
        assertEq(currentEpoch, 0, "current epoch is 0");

        vm.expectRevert("SUB: cannot handle epoch 0"); // cannot handle claim of epoch 0
        e.claim(rate, currentEpoch);
    }

    function testClaim_noSubs(uint256 epoch) public {
        epoch = bound(epoch, 1, 50);

        vm.roll(epochSize * epoch);

        uint256 amount = e.claim(rate, e.currentEpoch());
        assertEq(0, amount, "no funds claimed");

        assertEq(0, e.claimed(), "total funds 0");
        assertEq(epoch - 1, e.lastProcessedEpoch(), "last processed epoch advanced to previous epoch");
        assertEq(0, e.activeSubShares(), "no subs exist");
    }
}
