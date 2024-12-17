// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {Math} from "openzeppelin-contracts/utils/math/Math.sol";
import "../../src/subscription/UserData.sol";
import {MathFunctions} from "../../src/MathFunctions.sol";

import {OzInitializableBind} from "../../src/dependency/OzInitializable.sol";

contract TestUserData is OzInitializableBind, UserData {
    uint256 private rate;

    constructor(uint24 lock_, uint256 rate_) initializer {
        __UserData_init(lock_);
        rate = rate_;
    }

    function _now() internal view override returns (uint256) {
        return block.number;
    }

    function getSubData(uint256 tokenId) public view returns (SubData memory) {
        return _getSubData(tokenId);
    }

    function setSubData(uint256 tokenId, SubData memory data) public {
        _setSubData(tokenId, data);
    }

    function _rate() internal view override returns (uint256) {
        return rate;
    }

    function multiplier(uint256 tokenId) public view virtual returns (uint24) {
        return _multiplier(tokenId);
    }

    function lock() public view virtual returns (uint24) {
        return _lock();
    }

    function isActive(uint256 tokenId) public view virtual returns (bool) {
        return _isActive(tokenId);
    }

    function expiresAt(uint256 tokenId) public view virtual returns (uint256) {
        return _expiresAt(tokenId);
    }

    function lastDepositedAt(uint256 tokenId) public view virtual returns (uint256) {
        return _lastDepositedAt(tokenId);
    }

    function deleteSubscription(uint256 tokenId) public virtual {
        _deleteSubscription(tokenId);
    }

    function createSubscription(uint256 tokenId, uint256 amount, uint24 multiplier_) public virtual {
        _createSubscription(tokenId, amount, multiplier_);
    }

    function extendSubscription(uint256 tokenId, uint256 amount)
        public
        virtual
        returns (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated)
    {
        return _extendSubscription(tokenId, amount);
    }

    function withdrawableFromSubscription(uint256 tokenId) public view virtual returns (uint256) {
        return _withdrawableFromSubscription(tokenId);
    }

    function withdrawFromSubscription(uint256 tokenId, uint256 amount)
        public
        virtual
        returns (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit)
    {
        return _withdrawFromSubscription(tokenId, amount);
    }

    function changeMultiplier(uint256 tokenId, uint24 newMultiplier) public returns (bool, MultiplierChange memory) {
        return _changeMultiplier(tokenId, newMultiplier);
    }

    function spent(uint256 tokenId) public view virtual returns (uint256 spent_, uint256 unspent) {
        return _spent(tokenId);
    }

    function totalDeposited(uint256 tokenId) public view virtual returns (uint256) {
        return _totalDeposited(tokenId);
    }
}

contract UserDataTest is Test {
    using Math for uint256;
    using MathFunctions for uint256;

    uint24 constant BASE_MULTI = 100;
    uint24 constant MAX_MULTI = 10_000;
    uint24 constant BASE_LOCK = 10_000;
    uint24 constant MAX_LOCK = 10_000;

    TestUserData private sd;

    uint256 private tokenId;
    uint24 private lock;
    uint256 private rate;
    uint256 private _block;

    function setUp() public {
        tokenId = 1;
        lock = 100;
        rate = 10;
        _block = 1234;

        sd = new TestUserData(lock, rate);
    }

    function testCreateSub_duplicate(uint256 _tokenId) public {
        _tokenId = bound(_tokenId, 1, type(uint256).max);

        sd.createSubscription(_tokenId, 0, BASE_MULTI);

        vm.expectRevert();
        sd.createSubscription(_tokenId, 0, BASE_MULTI);
    }

    function testCreateSub_empty() public {
        uint256 amount = 0;
        uint24 multi = BASE_MULTI;

        vm.roll(_block);

        sd.createSubscription(tokenId, amount, multi);

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertFalse(sd.isActive(tokenId), "token inactive");
        assertEq(sd.expiresAt(tokenId), _block, "token expires now");
        assertEq(sd.withdrawableFromSubscription(tokenId), 0, "nothing to withdraw");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, 0, "nothing spent");
            assertEq(unspent, 0, "nothing unspent");
        }
        assertEq(sd.totalDeposited(tokenId), 0, "nothing deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "last deposit now");
    }

    function testCreateSub() public {
        uint256 amount = 100_000;
        uint24 multi = BASE_MULTI;

        uint256 expiresAt = _block + ((amount * SubLib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertTrue(sd.isActive(tokenId), "token active");
        assertEq(sd.expiresAt(tokenId), expiresAt, "token expires now");
        assertEq(
            sd.withdrawableFromSubscription(tokenId),
            amount - ((amount * lock) / 10_000),
            "withdrawable only unlocked amount"
        );
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, rate, "init: 1st block spent");
            assertEq(unspent, amount - rate, "init: rest unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount, "init: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "last deposit now");

        // check half way

        vm.roll(_block + ((expiresAt - _block) / 2));
        assertEq(sd.multiplier(tokenId), multi, "half: multiplier set");
        assertEq(
            sd.withdrawableFromSubscription(tokenId),
            (amount / 2) - rate,
            "half: half withdrawable, minus current block"
        );
        assertTrue(sd.isActive(tokenId), "half: token active");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, (amount / 2) + rate, "half: half spent");
            assertEq(unspent, (amount / 2) - rate, "half: half unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount, "half: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "half: last deposit still set");

        // expire
        vm.roll(expiresAt);

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertEq(sd.withdrawableFromSubscription(tokenId), 0, "expired: nothing withdrawable");
        assertFalse(sd.isActive(tokenId), "expired: token inactive");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, amount, "expired: all spent");
            assertEq(unspent, 0, "expired: nothing unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount, "expired: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "last deposit still set");
    }

    function testFuzz_CreateSub(uint256 amount, uint128 _rate, uint24 multi) public {
        multi = uint24(bound(multi, BASE_MULTI, MAX_MULTI));

        lock = uint24(bound(multi + multi, 1, MAX_LOCK));
        rate = bound(_rate, 1, type(uint64).max);
        // more than 1 time unit amount must be deposited
        amount = bound(amount, ((rate * multi) / SubLib.MULTIPLIER_BASE) + 1, type(uint128).max);

        sd = new TestUserData(lock, rate);
        uint256 blockRate = (rate * multi) / BASE_MULTI;

        uint256 expiresAt = _block + ((amount * SubLib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertTrue(sd.isActive(tokenId), "token active, in mint block");
        assertEq(sd.expiresAt(tokenId), expiresAt, "token expires");
        assertEq(
            sd.withdrawableFromSubscription(tokenId),
            (amount - ((amount * lock) / BASE_LOCK)).min(
                ((amount * SubLib.MULTIPLIER_BASE) - (rate * multi)) / SubLib.MULTIPLIER_BASE
            ),
            "withdrawable only unlocked or unspent amount"
        );
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, blockRate, "init: 1st block spent");
            assertEq(unspent, amount - blockRate, "init: rest unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount, "init: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "last deposit now");

        // check half way

        vm.roll(_block + ((expiresAt - _block) / 2));
        assertEq(sd.multiplier(tokenId), multi, "half: multiplier set");
        assertEq(
            sd.withdrawableFromSubscription(tokenId),
            (
                ((amount * SubLib.MULTIPLIER_BASE) - ((1 + ((expiresAt - _block) / 2)) * rate * multi))
                    / SubLib.MULTIPLIER_BASE
            ).min(amount - ((amount * lock) / BASE_LOCK)),
            "half: half withdrawable, minus current block"
        );
        assertTrue(sd.isActive(tokenId), "half: token active");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(
                spent, (((1 + ((expiresAt - _block) / 2)) * rate * multi) / SubLib.MULTIPLIER_BASE), "half: half spent"
            );
            assertEq(
                unspent,
                amount - (((1 + ((expiresAt - _block) / 2)) * rate * multi) / SubLib.MULTIPLIER_BASE),
                "half: half unspent"
            );
        }
        assertEq(sd.totalDeposited(tokenId), amount, "half: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "half: last deposit still set");

        // expire
        vm.roll(expiresAt);

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertEq(sd.withdrawableFromSubscription(tokenId), 0, "expired: nothing withdrawable");
        assertFalse(sd.isActive(tokenId), "expired: token inactive");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, amount, "expired: all spent");
            assertEq(unspent, 0, "expired: nothing unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount, "expired: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "last deposit still set");
    }

    function testCreateSub_noLock() public {
        uint256 amount = 100_000;
        uint24 multi = BASE_MULTI;
        lock = 0;
        sd = new TestUserData(lock, rate);

        uint256 expiresAt = _block + ((amount * SubLib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertTrue(sd.isActive(tokenId), "token active");
        assertEq(sd.expiresAt(tokenId), expiresAt, "token expires now");
        assertEq(sd.withdrawableFromSubscription(tokenId), amount - rate, "the current block has to be paid");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, rate, "init: first block spent");
            assertEq(unspent, amount - rate, "init: rest unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount, "init: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "last deposit now");
    }

    function testExtendSub() public {
        uint256 amount = 100_000;
        uint24 multi = BASE_MULTI;

        uint256 expiresAt = _block + ((amount * SubLib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertTrue(sd.isActive(tokenId), "token active");
        assertEq(sd.expiresAt(tokenId), expiresAt, "token expires now");
        assertEq(
            sd.withdrawableFromSubscription(tokenId),
            amount - ((amount * lock) / 10_000),
            "withdrawable only unlocked amount"
        );
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, rate, "init: first block spent");
            assertEq(unspent, amount - rate, "init: rest unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount, "init: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "last deposit now");

        // extend sub
        uint256 extendedAt = _block + 10;
        assertGt(expiresAt, extendedAt, "not yet expired");
        vm.roll(extendedAt);

        uint256 addedAmount = 50_000;
        {
            (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated) =
                sd.extendSubscription(tokenId, addedAmount);

            assertFalse(reactivated, "extendedAt: subscription not reactivated");
            assertEq(oldDeposit, amount, "extendedAt: old deposit");
            assertEq(newDeposit, amount + addedAmount, "extendedAt: new deposit, amount updated");
            assertEq(depositedAt, _block, "extendedAt: init deposit unchanged");
        }

        assertEq(sd.multiplier(tokenId), multi, "extendedAt: multiplier set");
        assertTrue(sd.isActive(tokenId), "extendedAt: token active");
        assertEq(
            sd.expiresAt(tokenId),
            _block + (((amount + addedAmount) * SubLib.MULTIPLIER_BASE) / (rate * multi)),
            "extendedAt: token expires at new date"
        );

        // because the time passed is relatively small, we know that we are still within the locked amount
        {
            // remember: until extension
            uint256 spentFunds = ((extendedAt - _block) * (rate * multi)) / SubLib.MULTIPLIER_BASE;
            uint256 unspentFunds = (amount + addedAmount) - spentFunds;

            assertEq(
                sd.withdrawableFromSubscription(tokenId),
                ((amount + addedAmount) - spentFunds) - ((unspentFunds * lock) / 10_000),
                "extendedAt: withdrawable only unlocked amount"
            );

            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, spentFunds + rate, "extendedAt: mind current block");
            assertEq(unspent, unspentFunds - rate, "extendedAt: mind current block");
        }
        assertEq(sd.totalDeposited(tokenId), amount + addedAmount, "extendedAt: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), extendedAt, "extendedAt: last deposit unchanged");

        // old expire
        vm.roll(expiresAt);
        assertTrue(sd.isActive(tokenId), "old expiredAt: token active");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, amount + rate, "old expiredAt: inital deposit spent, plus current block");
            assertEq(unspent, addedAmount - rate, "old expiresAt: added deposit unspent, minux current");
        }

        // new expire
        vm.roll(expiresAt + ((addedAmount * SubLib.MULTIPLIER_BASE) / (rate * multi)));

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertEq(sd.withdrawableFromSubscription(tokenId), 0, "expired: nothing withdrawable");
        assertFalse(sd.isActive(tokenId), "expired: token inactive");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, amount + addedAmount, "expired: all spent");
            assertEq(unspent, 0, "expired: nothing unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount + addedAmount, "expired: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), extendedAt, "last deposit still unchanged");
    }

    function testFuzz_ExtendSub(uint256 amount, uint128 _rate, uint24 multi) public {
        multi = uint24(bound(multi, BASE_MULTI, MAX_MULTI));

        lock = uint24(bound(uint256(multi) + _rate, 0, MAX_LOCK));
        rate = bound(_rate, 1, type(uint64).max);

        // more than 1 time unit amount must be deposited
        amount = bound(amount, ((rate * multi) / SubLib.MULTIPLIER_BASE) + 1, type(uint256).max / 1_000_000);

        sd = new TestUserData(lock, rate);

        uint256 expiresAt = _block + ((amount * SubLib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        assertTrue(sd.isActive(tokenId), "token active");
        assertEq(sd.expiresAt(tokenId), expiresAt, "token expires now");
        assertEq(
            sd.withdrawableFromSubscription(tokenId),
            (amount - ((amount * lock) / BASE_LOCK)).min(
                ((amount * SubLib.MULTIPLIER_BASE) - (rate * multi)) / SubLib.MULTIPLIER_BASE
            ),
            "withdrawable only unlocked or unspent amount"
        );

        // extend sub
        uint256 extendedAt = (bound(amount, _block, expiresAt - 1));
        assertGe(expiresAt, extendedAt, "not yet expired");
        vm.roll(extendedAt);

        uint256 addedAmount = bound(amount, 0, type(uint128).max - 1);
        {
            (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated) =
                sd.extendSubscription(tokenId, addedAmount);

            assertFalse(reactivated, "extendedAt: subscription not reactivated");
            assertEq(oldDeposit, amount, "extendedAt: old deposit");
            assertEq(newDeposit, amount + addedAmount, "extendedAt: new deposit, amount updated");
            assertEq(depositedAt, _block, "extendedAt: init deposit unchanged");
        }

        assertEq(sd.multiplier(tokenId), multi, "extendedAt: multiplier unchanged");
        assertEq(
            sd.expiresAt(tokenId),
            _block + ((amount + addedAmount) * SubLib.MULTIPLIER_BASE) / (rate * multi),
            "extendedAt: token expires at new date"
        );
        assertTrue(sd.isActive(tokenId), "extendedAt: token active");

        {
            uint256 total = (amount + addedAmount) * SubLib.MULTIPLIER_BASE;
            uint256 spentFunds = (1 + extendedAt - _block) * (rate * multi);
            uint256 usedFunds = ((extendedAt - _block) * (rate * multi));
            // this is fucked, because the locked amount is actually precomputed and based
            uint256 lockedFunds = ((((total - usedFunds) / SubLib.MULTIPLIER_BASE) * lock) / BASE_LOCK)
                * SubLib.MULTIPLIER_BASE + usedFunds;

            console.log("spent", (total - spentFunds) / SubLib.MULTIPLIER_BASE);
            console.log("unlocked", (total - lockedFunds) / SubLib.MULTIPLIER_BASE);
            assertEq(
                sd.withdrawableFromSubscription(tokenId),
                (total - spentFunds).min(total - lockedFunds) / SubLib.MULTIPLIER_BASE,
                "extendedAt: withdrawable only unlocked or unspent amount"
            );

            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(
                spent,
                ((1 + extendedAt - _block) * (rate * multi)) / SubLib.MULTIPLIER_BASE,
                "extendedAt: spent, mind current block, higher precision"
            );
            assertEq(
                unspent,
                (amount + addedAmount) - ((1 + extendedAt - _block) * (rate * multi)) / SubLib.MULTIPLIER_BASE,
                "extendedAt: unspent, mind current block, higher precision"
            );
        }
        assertEq(sd.totalDeposited(tokenId), amount + addedAmount, "extendedAt: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), extendedAt, "extendedAt: last deposit updated");

        // new expire
        vm.roll(_block + (((amount + addedAmount) * SubLib.MULTIPLIER_BASE) / (rate * multi)));

        assertEq(sd.withdrawableFromSubscription(tokenId), 0, "expired: nothing withdrawable");
        assertFalse(sd.isActive(tokenId), "expired: token inactive");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, amount + addedAmount, "expired: all spent");
            assertEq(unspent, 0, "expired: nothing unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount + addedAmount, "expired: all in total deposited");
    }

    function testExtendSub_unlocked() public {
        uint256 amount = 100_000;
        uint24 multi = BASE_MULTI;

        uint256 expiresAt = _block + ((amount * SubLib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        // extend sub
        uint256 extendedAt = _block + 2_000;
        assertGt(expiresAt, extendedAt, "not yet expired");
        vm.roll(extendedAt);

        uint256 addedAmount = 50_000;
        {
            (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated) =
                sd.extendSubscription(tokenId, addedAmount);

            assertFalse(reactivated, "extendedAt: subscription not reactivated");
            assertEq(oldDeposit, amount, "extendedAt: old deposit");
            assertEq(newDeposit, amount + addedAmount, "extendedAt: new deposit, amount updated");
            assertEq(depositedAt, _block, "extendedAt: init deposit unchanged");
        }

        assertTrue(sd.isActive(tokenId), "extendedAt: token active");
        assertEq(
            sd.expiresAt(tokenId),
            expiresAt + ((addedAmount * SubLib.MULTIPLIER_BASE) / (rate * multi)),
            "extendedAt: token expires now"
        );

        // because the time passed exceeds the original locked amount of funds, the locked amount is updated
        {
            // we do not mind that the block of the extension is spent
            uint256 spentFunds = ((extendedAt - _block) * (rate * multi)) / SubLib.MULTIPLIER_BASE;
            uint256 unspentFunds = (amount + addedAmount) - spentFunds;

            assertEq(
                sd.withdrawableFromSubscription(tokenId),
                ((amount + addedAmount) - spentFunds) - ((unspentFunds * lock) / 10_000),
                "extendedAt: withdrawable, updated locked amount, only unspent amount"
            );

            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, spentFunds + rate, "extendedAt: until current block amount spent");
            assertEq(unspent, unspentFunds - rate, "extendedAt: until current block unspent");
        }
        assertEq(sd.lastDepositedAt(tokenId), extendedAt, "extendedAt: last deposit unchanged");

        // new expire
        // old expire + new amount
        vm.roll(expiresAt + ((addedAmount * SubLib.MULTIPLIER_BASE) / (rate * multi)));

        assertFalse(sd.isActive(tokenId), "expired: token inactive");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, amount + addedAmount, "expired: all funds spent");
            assertEq(unspent, 0, "expired: nothing unspent");
        }
    }

    function testExtendSub_reactivate() public {
        uint256 amount = 100_000;
        uint24 multi = BASE_MULTI;

        uint256 expiresAt = _block + ((amount * SubLib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        // extend sub, far in the future
        uint256 extendedAt = _block + 1_000_000;
        assertLt(expiresAt, extendedAt, "subscription expired");
        vm.roll(extendedAt);
        assertFalse(sd.isActive(tokenId), "token expired before extending");

        uint256 addedAmount = 50_000;
        {
            (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated) =
                sd.extendSubscription(tokenId, addedAmount);

            assertTrue(reactivated, "extendedAt: subscription reactivated");
            assertEq(oldDeposit, amount, "extendedAt: old deposit is the amount from the previous sub streak");
            assertEq(newDeposit, addedAmount, "extendedAt: new deposit, restarted");
            assertEq(depositedAt, extendedAt, "extendedAt: init deposit updated");
        }

        assertEq(sd.multiplier(tokenId), multi, "extendedAt: multiplier unchanged");
        assertTrue(sd.isActive(tokenId), "extendedAt: token active");
        assertEq(
            sd.expiresAt(tokenId),
            extendedAt + ((addedAmount * SubLib.MULTIPLIER_BASE) / (rate * multi)),
            "extendedAt: token expires at new date"
        );

        {
            assertEq(
                sd.withdrawableFromSubscription(tokenId),
                addedAmount - ((addedAmount * lock) / 10_000),
                "extendedAt: withdrawable only part of added amount"
            );

            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, amount + rate, "extendedAt: old amount spent, plus current block");
            assertEq(unspent, addedAmount - rate, "extendedAt: new amount unspent, minus current block");
        }
        assertEq(sd.totalDeposited(tokenId), amount + addedAmount, "extendedAt: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), extendedAt, "extendedAt: last deposit unchanged");

        // new expire
        vm.roll(extendedAt + ((addedAmount * SubLib.MULTIPLIER_BASE) / (rate * multi)));

        assertEq(sd.multiplier(tokenId), multi, "expired: multiplier unchanged");
        assertEq(sd.withdrawableFromSubscription(tokenId), 0, "expired: nothing withdrawable");
        assertFalse(sd.isActive(tokenId), "expired: token inactive");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, amount + addedAmount, "expired: all spent");
            assertEq(unspent, 0, "expired: nothing unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount + addedAmount, "expired: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), extendedAt, "last deposit unchanged");
    }

    function testReduceSub() public {
        uint256 amount = 100_000;
        uint24 multi = BASE_MULTI;

        uint256 expiresAt = _block + ((amount * SubLib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertTrue(sd.isActive(tokenId), "token active");
        assertEq(sd.expiresAt(tokenId), expiresAt, "token expires now");
        assertEq(
            sd.withdrawableFromSubscription(tokenId),
            amount - ((amount * lock) / 10_000),
            "withdrawable only unlocked amount"
        );
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, rate, "init: first block");
            assertEq(unspent, amount - rate, "init: except first block unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount, "init: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "last deposit now");

        // reduce sub
        uint256 reducedAt = _block + 1;
        assertGt(expiresAt, reducedAt, "not yet expired");
        vm.roll(reducedAt);

        uint256 reducedAmount = 50_000;
        uint256 newExpiresAt = _block + (((amount - reducedAmount) * SubLib.MULTIPLIER_BASE) / (rate * multi));
        {
            (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit) =
                sd.withdrawFromSubscription(tokenId, reducedAmount);

            assertEq(oldDeposit, amount, "reducedAt: old deposit");
            assertEq(newDeposit, amount - reducedAmount, "reducedAt: new deposit, amount updated");
            assertEq(depositedAt, _block, "reducedAt: init deposit unchanged");
        }

        assertEq(sd.multiplier(tokenId), multi, "reducedAt: multiplier set");
        assertTrue(sd.isActive(tokenId), "reducedAt: token active");
        assertEq(sd.expiresAt(tokenId), newExpiresAt, "reducedAt: token expires earlier");
        assertEq(
            sd.withdrawableFromSubscription(tokenId),
            amount - ((amount * lock) / 10_000) - reducedAmount,
            "reducedAt: locked amount unchanged"
        );

        vm.roll(newExpiresAt);
        assertFalse(sd.isActive(tokenId), "expired: token inactive");
    }

    function testReduceSub_cancel() public {
        uint256 amount = 100_000;
        uint24 multi = BASE_MULTI;

        uint256 expiresAt = _block + ((amount * SubLib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertTrue(sd.isActive(tokenId), "token active");
        assertEq(sd.expiresAt(tokenId), expiresAt, "token expires now");
        assertEq(
            sd.withdrawableFromSubscription(tokenId),
            amount - ((amount * lock) / 10_000),
            "withdrawable only unlocked amount"
        );
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, rate, "init: first block");
            assertEq(unspent, amount - rate, "init: except first block unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount, "init: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "last deposit now");

        // reduce sub
        uint256 reducedAt = _block + 1;
        assertGt(expiresAt, reducedAt, "not yet expired");
        vm.roll(reducedAt);

        uint256 reducedAmount = sd.withdrawableFromSubscription(tokenId);
        uint256 newExpiresAt = _block + (((amount - reducedAmount) * SubLib.MULTIPLIER_BASE) / (rate * multi));
        {
            (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit) =
                sd.withdrawFromSubscription(tokenId, reducedAmount);

            assertEq(oldDeposit, amount, "reducedAt: old deposit");
            assertEq(newDeposit, amount - reducedAmount, "reducedAt: new deposit, amount updated");
            assertEq(depositedAt, _block, "reducedAt: init deposit unchanged");
        }

        assertEq(sd.multiplier(tokenId), multi, "reducedAt: multiplier set");
        assertTrue(sd.isActive(tokenId), "reducedAt: token active");
        assertEq(sd.expiresAt(tokenId), newExpiresAt, "reducedAt: token expires earlier");
        assertEq(
            sd.withdrawableFromSubscription(tokenId),
            amount - ((amount * lock) / 10_000) - reducedAmount,
            "reducedAt: locked amount unchanged"
        );

        vm.roll(newExpiresAt);
        assertFalse(sd.isActive(tokenId), "expired: token inactive");
    }

    function testReduceSub_cancel_noLock() public {
        uint256 amount = 100_000;
        uint24 multi = BASE_MULTI;
        lock = 0;
        sd = new TestUserData(lock, rate);

        uint256 expiresAt = _block + ((amount * SubLib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        assertEq(sd.multiplier(tokenId), multi, "multiplier set");
        assertTrue(sd.isActive(tokenId), "token active");
        assertEq(sd.expiresAt(tokenId), expiresAt, "token expires now");
        assertEq(sd.withdrawableFromSubscription(tokenId), amount - rate, "all funds except current block withdrawable");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, rate, "init: first block");
            assertEq(unspent, amount - rate, "init: except first block unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount, "init: all in total deposited");
        assertEq(sd.lastDepositedAt(tokenId), _block, "last deposit now");

        // reduce sub, token becomes inactive in the following block
        uint256 reducedAt = _block + 1;
        assertGt(expiresAt, reducedAt, "not yet expired");
        vm.roll(reducedAt);

        assertEq(sd.withdrawableFromSubscription(tokenId), amount - (rate * 2), "only 2 blocks are paid");
        uint256 reducedAmount = sd.withdrawableFromSubscription(tokenId);
        uint256 newExpiresAt = _block + (((amount - reducedAmount) * SubLib.MULTIPLIER_BASE) / (rate * multi));
        {
            (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit) =
                sd.withdrawFromSubscription(tokenId, reducedAmount);

            assertEq(oldDeposit, amount, "reducedAt: old deposit");
            assertEq(newDeposit, amount - reducedAmount, "reducedAt: new deposit, amount updated");
            assertEq(depositedAt, _block, "reducedAt: init deposit unchanged");
        }

        assertEq(sd.multiplier(tokenId), multi, "reducedAt: multiplier set");
        assertTrue(sd.isActive(tokenId), "reducedAt: token is still active in the cancelation block");
        assertEq(sd.expiresAt(tokenId), newExpiresAt, "reducedAt: token expires earlier");
        assertEq(sd.withdrawableFromSubscription(tokenId), 0, "reducedAt: nothing to withdraw");

        // token becomes inactive in the following block
        vm.roll(reducedAt + 1);
        assertFalse(sd.isActive(tokenId), "expired: token inactive");
    }

    function testFuzz_ReduceSub(uint256 amount, uint128 _rate, uint24 multi) public {
        multi = uint24(bound(multi, BASE_MULTI, MAX_MULTI));

        lock = uint24(bound(multi + multi, 0, MAX_LOCK));

        rate = bound(_rate, 1, type(uint128).max);

        // more than 1 time unit amount must be deposited
        amount = bound(amount, ((rate * multi) / SubLib.MULTIPLIER_BASE) + 1, type(uint256).max / 100_000);

        sd = new TestUserData(lock, rate);

        uint256 expiresAt = _block + ((amount * SubLib.MULTIPLIER_BASE) / (rate * multi));
        vm.roll(_block);

        // create
        sd.createSubscription(tokenId, amount, multi);

        // reduce sub
        uint256 reducedAt = (bound(amount, _block, expiresAt - 1));
        assertGe(expiresAt, reducedAt, "not yet expired");
        vm.roll(reducedAt);

        uint256 reducedAmount = bound(amount, 0, sd.withdrawableFromSubscription(tokenId));
        {
            uint256 newExpiresAt = _block + (((amount - reducedAmount) * SubLib.MULTIPLIER_BASE) / (rate * multi));
            uint256 withdrawable = sd.withdrawableFromSubscription(tokenId);

            (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit) =
                sd.withdrawFromSubscription(tokenId, reducedAmount);

            assertEq(oldDeposit, amount, "reducedAt: old deposit");
            assertEq(newDeposit, amount - reducedAmount, "reducedAt: new deposit, amount updated");
            assertEq(depositedAt, _block, "reducedAt: init deposit unchanged");

            assertEq(sd.multiplier(tokenId), multi, "reducedAt: multiplier unchanged");
            assertEq(sd.expiresAt(tokenId), newExpiresAt, "reducedAt: token expires earlier");
            assertTrue(sd.isActive(tokenId), "reducedAt: token active");

            assertEq(
                sd.withdrawableFromSubscription(tokenId),
                withdrawable - reducedAmount,
                "reducedAt: withdrawable only unlocked or unspent amount"
            );
        }

        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(
                spent,
                ((1 + reducedAt - _block) * (rate * multi)) / SubLib.MULTIPLIER_BASE,
                "reducedAt: spent, mind current block, higher precision"
            );
            assertEq(
                unspent,
                (amount - reducedAmount) - ((1 + reducedAt - _block) * (rate * multi)) / SubLib.MULTIPLIER_BASE,
                "reducedAt: unspent, mind current block, higher precision"
            );
        }
        assertEq(sd.totalDeposited(tokenId), amount - reducedAmount, "reducedAt: total deposited reduced");
        assertEq(sd.lastDepositedAt(tokenId), _block, "reducedAt: last deposit unchanged");

        // new expire
        vm.roll(_block + (((amount - reducedAmount) * SubLib.MULTIPLIER_BASE) / (rate * multi)));

        assertEq(sd.withdrawableFromSubscription(tokenId), 0, "expired: nothing withdrawable");
        assertFalse(sd.isActive(tokenId), "expired: token inactive");
        {
            (uint256 spent, uint256 unspent) = sd.spent(tokenId);
            assertEq(spent, amount - reducedAmount, "expired: all spent");
            assertEq(unspent, 0, "expired: nothing unspent");
        }
        assertEq(sd.totalDeposited(tokenId), amount - reducedAmount, "expired: all in total deposited");
    }

    function testChangeMultiplier(uint256 t) public {
        SubData memory od = SubData({
            mintedAt: 10,
            streakStartedAt: 100,
            lastDepositAt: 100,
            totalDeposited: 2501,
            currentDeposit: 2003,
            lockedAmount: 1002,
            multiplier: 100
        });
        sd.setSubData(tokenId, od);

        t = bound(t, od.streakStartedAt, od.streakStartedAt + (od.currentDeposit / rate) - 1);
        uint256 t1 = t + 1;
        uint256 tt = t1 - od.streakStartedAt;
        vm.roll(t);

        uint24 newMulti = 200;

        (bool isActive, MultiplierChange memory changed) = sd.changeMultiplier(tokenId, newMulti);
        assertTrue(isActive, "sub not active");
        assertEq(changed.oldDepositAt, od.streakStartedAt, "changed: old deposit at");
        assertEq(changed.oldAmount, od.currentDeposit, "changed: old amount");
        assertEq(changed.oldMultiplier, od.multiplier, "changed: old multiplier");
        assertEq(changed.reducedAmount, tt * rate, "changed: reducedAmount");
        assertEq(changed.newDepositAt, t1, "changed: new deposit at");
        assertEq(changed.newAmount, od.currentDeposit - (tt * rate), "changed: new amount");

        SubData memory subData = sd.getSubData(tokenId);

        assertEq(subData.multiplier, newMulti, "multiplier changed");
        assertEq(subData.mintedAt, od.mintedAt, "mintedAd unchanged");
        assertEq(subData.totalDeposited, od.totalDeposited, "totalDeposited unchanged");
        assertEq(subData.streakStartedAt, t1, "streakStartedAt updated");
        assertEq(subData.lastDepositAt, t1, "lastDepositAt updated");
        assertEq(subData.currentDeposit, od.currentDeposit - (tt * rate), "currentDeposit reduced");
        assertEq(subData.lockedAmount, od.lockedAmount.subTo0(tt * rate), "lockedAmount reduced");
    }

    function testChangeMultiplier_expiringBlock() public {
        SubData memory od = SubData({
            mintedAt: 10,
            streakStartedAt: 100,
            lastDepositAt: 100,
            totalDeposited: 2501, // add dust
            currentDeposit: 2003,
            lockedAmount: 2002,
            multiplier: 100
        });
        sd.setSubData(tokenId, od);

        uint256 t = 299;
        uint256 t1 = t + 1;
        vm.roll(t);

        uint24 newMulti = 200;

        (bool isActive, MultiplierChange memory changed) = sd.changeMultiplier(tokenId, newMulti);
        assertTrue(isActive, "sub not active");
        assertEq(changed.oldDepositAt, od.streakStartedAt, "changed: old deposit at");
        assertEq(changed.oldAmount, od.currentDeposit, "changed: old amount");
        assertEq(changed.oldMultiplier, od.multiplier, "changed: old multiplier");
        assertEq(changed.reducedAmount, 2000, "changed: reducedAmount");
        assertEq(changed.newDepositAt, t1, "changed: new deposit at");
        assertEq(changed.newAmount, 3, "changed: new amount");

        SubData memory subData = sd.getSubData(tokenId);

        assertEq(subData.multiplier, newMulti, "multiplier changed");
        assertEq(subData.mintedAt, od.mintedAt, "mintedAd unchanged");
        assertEq(subData.totalDeposited, od.totalDeposited, "totalDeposited unchanged");
        assertEq(subData.streakStartedAt, t1, "streakStartedAt updated");
        assertEq(subData.lastDepositAt, t1, "lastDepositAt updated");
        assertEq(subData.currentDeposit, 3, "currentDeposit reduced");
        assertEq(subData.lockedAmount, 2, "lockedAmount reduced");
    }

    function testChangeMultiplier_inactive() public {
        SubData memory od = SubData({
            mintedAt: 10,
            streakStartedAt: 100,
            lastDepositAt: 100,
            totalDeposited: 2501,
            currentDeposit: 2003,
            lockedAmount: 1002,
            multiplier: 100
        });
        sd.setSubData(tokenId, od);

        uint256 t = 1000;
        vm.roll(t);

        uint24 newMulti = 200;

        (bool isActive, MultiplierChange memory changed) = sd.changeMultiplier(tokenId, newMulti);
        assertFalse(isActive, "sub not active");
        assertEq(changed.oldDepositAt, 0, "changed: old deposit at");
        assertEq(changed.oldAmount, 0, "changed: old amount");
        assertEq(changed.oldMultiplier, od.multiplier, "changed: old multiplier");
        assertEq(changed.reducedAmount, 0, "changed: reducedAmount");
        assertEq(changed.newDepositAt, 0, "changed: new deposit at");
        assertEq(changed.newAmount, 0, "changed: new amount");

        SubData memory subData = sd.getSubData(tokenId);

        assertEq(subData.multiplier, newMulti, "multiplier changed");
        assertEq(subData.mintedAt, od.mintedAt, "mintedAd unchanged");
        assertEq(subData.totalDeposited, od.totalDeposited, "totalDeposited unchanged");
        assertEq(subData.streakStartedAt, t, "streakStartedAt reset");
        assertEq(subData.lastDepositAt, t, "lastDepositAt reset");
        assertEq(subData.currentDeposit, 0, "currentDeposit reset");
        assertEq(subData.lockedAmount, 0, "lockedAmount reset");
    }
}
