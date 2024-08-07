// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Lib} from "./Lib.sol";
import {HasRate} from "./Rate.sol";
import {TimeAware} from "./TimeAware.sol";

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";

import "forge-std/console.sol";

abstract contract HasUserData {
    struct SubData {
        uint256 mintedAt; // mint date
        uint256 streakStartedAt; // start of a new subscription streak (on mint / on renewal after expired)
        uint256 lastDepositAt; // date of last deposit, counting only renewals of subscriptions
        // it remains untouched on withdrawals and tips
        uint256 totalDeposited; // amount of tokens ever deposited
        uint256 currentDeposit; // deposit since streakStartedAt, resets with streakStartedAt
        uint256 lockedAmount; // amount of locked funds as of lastDepositAt
        uint24 multiplier;
    }

    /**
     * @notice the percentage of unspent funds that are locked on a subscriber deposit
     * @return the percentage of unspent funds being locked on subscriber deposit
     */
    function _lock() internal view virtual returns (uint24);

    /**
     * @notice checks the status of a subscription
     * @dev a subscription is active if it has not expired yet, now < expiration date, excluding the expiration date
     * @param tokenId subscription identifier
     * @return active status
     */
    function _isActive(uint256 tokenId) internal view virtual returns (bool);

    /**
     * @notice returns the time unit at which a given subscription expires
     * @param tokenId subscription identifier
     * @return expiration date
     */
    function _expiresAt(uint256 tokenId) internal view virtual returns (uint256);

    /**
     * @notice deletes a subscription and all its data
     * @param tokenId subscription identifier
     */
    function _deleteSubscription(uint256 tokenId) internal virtual;

    /**
     * @notice creates a new subscription using the given token id during mint
     * @dev the subscription cannot exist in UserData storage before. The multiplier cannot be changed after this call.
     * @param tokenId new identifier of the subscription
     * @param amount amount to deposit into the new subscription
     * @param multiplier multiplier that is applied to the rate in this subscription
     */
    function _createSubscription(uint256 tokenId, uint256 amount, uint24 multiplier) internal virtual;

    /**
     * @notice adds the given amount to an existing subscription
     * @dev the subscription is identified by the tokenId. It may be expired.
     * The return values describe the state of the subscription and the coordinates and changes of the current subscription streak.
     * If a subscription was expired before extending, a new subscription streak is started with a new depositedAt date.
     * @param tokenId subscription identifier
     * @param amount amount to add to the given subscription
     * @return depositedAt start date of the current subscription streak
     * @return oldDeposit deposited amount counting from the depositedAt date before extension
     * @return newDeposit deposited amount counting from the depositedAt data after extension
     * @return reactivated flag if the subscription was expired and thus a new subscription streak is started
     */
    function _extendSubscription(uint256 tokenId, uint256 amount)
        internal
        virtual
        returns (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated);

    /**
     * @notice returns the amount that can be withdrawn from a given subscription
     * @dev the subscription has to be active and contain unspent and unlocked funds
     * @param tokenId subscription identifier
     * @return the withdrawable amount
     */
    function _withdrawableFromSubscription(uint256 tokenId) internal view virtual returns (uint256);

    /**
     * @notice reduces the deposit amount of the existing subscription without changing the deposit time / start time of the current subscription streak
     * @dev the subscription may not be expired and the funds that can be withdrawn have to be unspent and unlocked
     * @param tokenId subscription identifier
     * @param amount amount to withdraw from the subscription
     * @return depositedAt start date of the current subscription streak
     * @return oldDeposit deposited amount counting from the depositedAt date before extension
     * @return newDeposit deposited amount counting from the depositedAt data after extension
     */
    function _withdrawFromSubscription(uint256 tokenId, uint256 amount)
        internal
        virtual
        returns (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit);

    /**
     * @notice Change data
     *
     */
    struct MultiplierChange {
        uint256 oldDepositAt;
        uint256 oldAmount;
        uint24 oldMultiplier;
        uint256 reducedAmount;
        uint256 newDepositAt;
        uint256 newAmount;
    }

    /**
     * @notice changes the multiplier of a subscription by ending the current streak, if any, and starting a new one with the new multiplier
     * @dev the subscription may be expired
     * @param tokenId subscription identifier
     * @param newMultiplier the new multiplier value
     * @return isActive the active state of the subscription
     * @return change data reflecting the change of an active subscription, all values, except oldMultiplier, are 0 if the sub is inactive
     */
    function _changeMultiplier(uint256 tokenId, uint24 newMultiplier)
        internal
        virtual
        returns (bool isActive, MultiplierChange memory change);

    /**
     * @notice returns the amount of total spent and yet unspent funds in the subscription, excluding tips
     * @dev in an active subscription, the current time unit is considered spent in order to prevent
     * subscribing and withdrawing within the same transaction and having an active sub without paying for
     * at least one time unit
     * @param tokenId subscription identifier
     * @return spent the spent amount
     * @return unspent the unspent amount left in the subscription
     */
    function _spent(uint256 tokenId) internal view virtual returns (uint256 spent, uint256 unspent);

    /**
     * @notice returns the amount of total deposited funds in a given subscription.
     * @dev this includes unspent and/or withdrawable funds.
     * @param tokenId subscription identifier
     * @return the total deposited amount
     */
    function _totalDeposited(uint256 tokenId) internal view virtual returns (uint256);

    /**
     * @notice returns the applied multiplier of a given subscription
     * @param tokenId subscription identifier
     * @return the multiplier base 100 == 1x
     */
    function _multiplier(uint256 tokenId) internal view virtual returns (uint24);

    /**
     * @notice returns the date at which the last deposit for a given subscription took place
     * @dev this value lies within the current or last subscription streak range and does not change on withdrawals
     * @param tokenId subscription identifier
     * @return the time unit date of the last deposit
     */
    function _lastDepositedAt(uint256 tokenId) internal view virtual returns (uint256);

    /**
     * @notice returns the internal storage struct of a given subscription
     * @param tokenId subscription identifier
     * @return the internal subscription data representation
     */
    function _getSubData(uint256 tokenId) internal view virtual returns (SubData memory);
}

abstract contract UserData is Initializable, TimeAware, HasRate, HasUserData {
    using Lib for uint256;
    using Math for uint256;

    struct UserDataStorage {
        // locked % of deposited amount
        // 0 - 10000
        uint24 _lock;
        mapping(uint256 => SubData) _subData;
        // amount of tips EVER sent to the contract, the value only increments
        uint256 _allTips;
        // amount of tips EVER claimed from the contract, the value only increments
        uint256 _claimedTips;
    }

    // keccak256(abi.encode(uint256(keccak256("createz.storage.subscription.UserData")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant UserDataStorageLocation =
        0x759c70339345f5b3443b65fe6ae2d943782a2a023089a4692e3f21ca7befef00;

    function _getUserDataStorage() private pure returns (UserDataStorage storage $) {
        assembly {
            $.slot := UserDataStorageLocation
        }
    }

    function __UserData_init(uint24 lock) internal onlyInitializing {
        __UserData_init_unchained(lock);
    }

    function __UserData_init_unchained(uint24 lock) internal onlyInitializing {
        UserDataStorage storage $ = _getUserDataStorage();
        $._lock = lock;
    }

    function _lock() internal view override returns (uint24) {
        UserDataStorage storage $ = _getUserDataStorage();
        return $._lock;
    }

    function _isActive(uint256 tokenId) internal view override returns (bool) {
        return _now() < _expiresAt(tokenId);
    }

    function _expiresAt(uint256 tokenId) internal view override returns (uint256) {
        // a subscription is active form the starting time slot (including)
        // to the calculated ending time slot (excluding)
        // active = [start, + deposit / (rate * multiplier))
        UserDataStorage storage $ = _getUserDataStorage();
        uint256 depositAt = $._subData[tokenId].streakStartedAt;
        uint256 currentDeposit_ = $._subData[tokenId].currentDeposit;

        return depositAt + currentDeposit_.validFor(_rate(), $._subData[tokenId].multiplier);
    }

    function _deleteSubscription(uint256 tokenId) internal override {
        UserDataStorage storage $ = _getUserDataStorage();
        delete $._subData[tokenId];
    }

    function _createSubscription(uint256 tokenId, uint256 amount, uint24 multiplier) internal override {
        uint256 now_ = _now();

        UserDataStorage storage $ = _getUserDataStorage();
        require($._subData[tokenId].mintedAt == 0, "Subscription already exists");

        // set initially and never change
        $._subData[tokenId].multiplier = multiplier;
        $._subData[tokenId].mintedAt = now_;

        // init new subscription streak
        $._subData[tokenId].streakStartedAt = now_;
        $._subData[tokenId].lastDepositAt = now_;
        $._subData[tokenId].totalDeposited = amount;
        $._subData[tokenId].currentDeposit = amount;

        // set lockedAmount
        // the locked amount is rounded down, it is in favor of the subscriber
        $._subData[tokenId].lockedAmount = amount.asLocked($._lock);
    }

    function _extendSubscription(uint256 tokenId, uint256 amount)
        internal
        override
        returns (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated)
    {
        uint256 now_ = _now();
        UserDataStorage storage $ = _getUserDataStorage();

        oldDeposit = $._subData[tokenId].currentDeposit;

        // TODO direct access
        reactivated = now_ > _expiresAt(tokenId);
        if (reactivated) {
            // subscrption was expired and is being reactivated
            newDeposit = amount;
            // start new subscription streak
            $._subData[tokenId].streakStartedAt = now_;
            $._subData[tokenId].lockedAmount = newDeposit.asLocked($._lock);
        } else {
            // extending active subscription
            uint256 remainingDeposit = (
                (oldDeposit * Lib.MULTIPLIER_BASE)
                // spent amount
                - (((now_ - $._subData[tokenId].streakStartedAt) * (_rate() * $._subData[tokenId].multiplier)))
            ) / Lib.MULTIPLIER_BASE;

            // deposit is counted from streakStartedAt
            newDeposit = oldDeposit + amount;

            // locked amount is counted from lastDepositAt
            $._subData[tokenId].lockedAmount = (remainingDeposit + amount).asLocked($._lock);
        }

        $._subData[tokenId].currentDeposit = newDeposit;
        $._subData[tokenId].lastDepositAt = now_;
        $._subData[tokenId].totalDeposited += amount;

        depositedAt = $._subData[tokenId].streakStartedAt;
    }

    function _withdrawableFromSubscription(uint256 tokenId) internal view override returns (uint256) {
        if (!_isActive(tokenId)) {
            return 0;
        }

        UserDataStorage storage $ = _getUserDataStorage();

        uint256 lastDepositAt = $._subData[tokenId].lastDepositAt;
        uint256 currentDeposit_ = $._subData[tokenId].currentDeposit * Lib.MULTIPLIER_BASE;

        // locked + spent up until last deposit
        uint256 lockedAmount = ($._subData[tokenId].lockedAmount * Lib.MULTIPLIER_BASE)
            + ((lastDepositAt - $._subData[tokenId].streakStartedAt) * (_rate() * $._subData[tokenId].multiplier));

        // the current block is spent, thus +1
        uint256 spentFunds =
            (1 + _now() - $._subData[tokenId].streakStartedAt) * (_rate() * $._subData[tokenId].multiplier);

        // postpone rebasing to the last moment
        return (currentDeposit_ - lockedAmount).min(currentDeposit_ - (spentFunds).min(currentDeposit_))
            / Lib.MULTIPLIER_BASE;
    }

    /// @notice reduces the deposit amount of the existing subscription without changing the deposit time
    function _withdrawFromSubscription(uint256 tokenId, uint256 amount)
        internal
        override
        returns (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit)
    {
        require(amount <= _withdrawableFromSubscription(tokenId), "Withdraw amount too large");

        UserDataStorage storage $ = _getUserDataStorage();
        oldDeposit = $._subData[tokenId].currentDeposit;
        newDeposit = oldDeposit - amount;
        $._subData[tokenId].currentDeposit = newDeposit;
        $._subData[tokenId].totalDeposited -= amount;

        // locked amount and last depositedAt remain unchanged

        depositedAt = $._subData[tokenId].streakStartedAt;
    }

    function _changeMultiplier(uint256 tokenId, uint24 newMultiplier)
        internal
        virtual
        override
        returns (bool isActive, MultiplierChange memory change)
    {
        isActive = _isActive(tokenId);

        SubData storage subData = _getUserDataStorage()._subData[tokenId];
        uint256 now_ = _now();
        if (isActive) {
            // +1 as the current timeunit is already paid for using the current multiplier, thus the streak has to start at the next time unit
            change = resetStreak(subData, now_ + 1);
        } else {
            // export only old multiplier value
            change.oldMultiplier = subData.multiplier;
            // create a new streak with 0 funds
            subData.streakStartedAt = now_;
            subData.lastDepositAt = now_;
            subData.currentDeposit = 0;
            subData.lockedAmount = 0;
        }

        subData.multiplier = newMultiplier;
    }

    /**
     * @notice ends the current streak of a given active subscription at the given time and starts a new streak. Unspent funds are moved to the new streak and the locked amount is reduced accordingly
     * @dev the new streak starts at the following time unit after the given time. The amount of funds to transfer to the new streak is calculated based on the rate and the multiplier in the given sub data.
     * @param subData sub to reset
     * @param time time to reset to
     * @return change info about the applied changes
     */
    function resetStreak(SubData storage subData, uint256 time) private returns (MultiplierChange memory change) {
        // reset streakStartedAt
        // reset lastDepositAt
        // reduce currentDeposit according to spent
        // reduce locked amount according to spent
        uint256 spent = currentStreakSpent(subData, time, _rate());

        change.oldDepositAt = subData.streakStartedAt;
        change.oldAmount = subData.currentDeposit;
        change.oldMultiplier = subData.multiplier;

        subData.streakStartedAt = time;
        subData.lastDepositAt = time;
        subData.currentDeposit -= spent;
        if (subData.lockedAmount < spent) {
            subData.lockedAmount = 0;
        } else {
            subData.lockedAmount -= spent;
        }

        change.reducedAmount = spent;
        change.newDepositAt = time;
        change.newAmount = subData.currentDeposit;
    }

    function _spent(uint256 tokenId) internal view override returns (uint256, uint256) {
        UserDataStorage storage $ = _getUserDataStorage();
        uint256 totalDeposited = $._subData[tokenId].totalDeposited;

        uint256 spentAmount;

        if (!_isActive(tokenId)) {
            spentAmount = totalDeposited;
        } else {
            // +1 as we want to include the current timeunit
            spentAmount = totalSpent($._subData[tokenId], _now() + 1, _rate());
        }

        uint256 unspentAmount = totalDeposited - spentAmount;

        return (spentAmount, unspentAmount);
    }

    /**
     * @notice calculates the amount of funds spent in a currently active streak until the given time (excluding)
     * @dev the active state of the sub is not tested
     * @param subData active subscription
     * @param time up until to calculate the spent amount
     * @param rate the rate to apply
     * @return amount of funds spent
     */
    function currentStreakSpent(SubData storage subData, uint256 time, uint256 rate) private view returns (uint256) {
        // postponed rebasing
        return multipliedCurrentStreakSpent(subData, time, rate) / Lib.MULTIPLIER_BASE;
    }

    /**
     * @notice calculates the multiplied amount of funds spent in a currently active streak until the given time (excluding)
     * @param subData active subscription
     * @param time up until to calculate the spent amount
     * @param rate the rate to apply
     * @return amount of funds spent in an inflated, multiplied state
     */
    function multipliedCurrentStreakSpent(SubData storage subData, uint256 time, uint256 rate)
        private
        view
        returns (uint256)
    {
        return ((time - subData.streakStartedAt) * rate * subData.multiplier);
    }

    /**
     * @notice calculates the amount of funds spent in total in the given subscription
     * @param subData subscription
     * @param time up until to calculate the spent amount
     * @param rate the rate to apply
     * @return amount of funds spent in the subscription
     */
    function totalSpent(SubData storage subData, uint256 time, uint256 rate) private view returns (uint256) {
        uint256 currentDeposit = subData.currentDeposit * Lib.MULTIPLIER_BASE;
        uint256 spentAmount = ((subData.totalDeposited * Lib.MULTIPLIER_BASE) - currentDeposit)
        + multipliedCurrentStreakSpent(subData, time, rate);

        // postponed rebasing
        return spentAmount / Lib.MULTIPLIER_BASE;
    }

    function _totalDeposited(uint256 tokenId) internal view override returns (uint256) {
        UserDataStorage storage $ = _getUserDataStorage();
        return $._subData[tokenId].totalDeposited;
    }

    function _multiplier(uint256 tokenId) internal view override returns (uint24) {
        UserDataStorage storage $ = _getUserDataStorage();
        return $._subData[tokenId].multiplier;
    }

    function _lastDepositedAt(uint256 tokenId) internal view override returns (uint256) {
        UserDataStorage storage $ = _getUserDataStorage();
        return $._subData[tokenId].lastDepositAt;
    }

    function _getSubData(uint256 tokenId) internal view override returns (SubData memory) {
        UserDataStorage storage $ = _getUserDataStorage();
        return $._subData[tokenId];
    }

    function _setSubData(uint256 tokenId, SubData memory data) internal {
        UserDataStorage storage $ = _getUserDataStorage();
        $._subData[tokenId] = data;
    }
}