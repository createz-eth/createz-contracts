// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SubLib} from "./SubLib.sol";
import {HasRate} from "./Rate.sol";
import {TimeAware} from "./TimeAware.sol";

import {OzInitializable} from "../dependency/OzInitializable.sol";

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

/**
 * @notice Change data
 */
struct MultiplierChange {
    uint256 oldDepositAt;
    uint256 oldAmount;
    uint24 oldMultiplier;
    uint256 reducedAmount;
    uint256 newDepositAt;
    uint256 newAmount;
}

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

library UserDataLib {
    using SubLib for uint256;
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

    // keccak256(abi.encode(uint256(keccak256("subsub.storage.subscription.UserData")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant UserDataStorageLocation =
        0xc461b00ee048bb772d4796a2912d26b5bb4f59e0aaef62e3b44e0e55e7a76900;

    function _getUserDataStorage() private pure returns (UserDataStorage storage $) {
        assembly {
            $.slot := UserDataStorageLocation
        }
    }

    function init(uint24 lock_) internal {
        UserDataStorage storage $ = _getUserDataStorage();
        $._lock = lock_;
    }

    function lock() internal view returns (uint24) {
        UserDataStorage storage $ = _getUserDataStorage();
        return $._lock;
    }

    function isActive(uint256 tokenId, uint256 time, uint256 rate) internal view returns (bool) {
        return time < expiresAt(tokenId, rate);
    }

    function expiresAt(uint256 tokenId, uint256 rate) internal view returns (uint256) {
        // a subscription is active form the starting time slot (including)
        // to the calculated ending time slot (excluding)
        // active = [start, + deposit / (rate * multiplier))
        UserDataStorage storage $ = _getUserDataStorage();
        uint256 depositAt = $._subData[tokenId].streakStartedAt;
        uint256 currentDeposit_ = $._subData[tokenId].currentDeposit;

        return depositAt + currentDeposit_.validFor(rate, $._subData[tokenId].multiplier);
    }

    function deleteSubscription(uint256 tokenId) internal {
        UserDataStorage storage $ = _getUserDataStorage();
        delete $._subData[tokenId];
    }

    function createSubscription(uint256 tokenId, uint256 amount, uint24 multiplier_, uint256 time) internal {
        UserDataStorage storage $ = _getUserDataStorage();
        require($._subData[tokenId].mintedAt == 0, "Subscription already exists");

        // set initially and never change
        $._subData[tokenId].multiplier = multiplier_;
        $._subData[tokenId].mintedAt = time;

        // init new subscription streak
        $._subData[tokenId].streakStartedAt = time;
        $._subData[tokenId].lastDepositAt = time;
        $._subData[tokenId].totalDeposited = amount;
        $._subData[tokenId].currentDeposit = amount;

        // set lockedAmount
        // the locked amount is rounded down, it is in favor of the subscriber
        $._subData[tokenId].lockedAmount = amount.asLocked($._lock);
    }

    function extendSubscription(uint256 tokenId, uint256 amount, uint256 time, uint256 rate)
        internal
        returns (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated)
    {
        UserDataStorage storage $ = _getUserDataStorage();

        oldDeposit = $._subData[tokenId].currentDeposit;

        // TODO direct access
        reactivated = time > expiresAt(tokenId, rate);
        if (reactivated) {
            // subscrption was expired and is being reactivated
            newDeposit = amount;
            // start new subscription streak
            $._subData[tokenId].streakStartedAt = time;
            $._subData[tokenId].lockedAmount = newDeposit.asLocked($._lock);
        } else {
            // extending active subscription
            uint256 remainingDeposit = (
                (oldDeposit * SubLib.MULTIPLIER_BASE)
                // spent amount
                - (((time - $._subData[tokenId].streakStartedAt) * (rate * $._subData[tokenId].multiplier)))
            ) / SubLib.MULTIPLIER_BASE;

            // deposit is counted from streakStartedAt
            newDeposit = oldDeposit + amount;

            // locked amount is counted from lastDepositAt
            $._subData[tokenId].lockedAmount = (remainingDeposit + amount).asLocked($._lock);
        }

        $._subData[tokenId].currentDeposit = newDeposit;
        $._subData[tokenId].lastDepositAt = time;
        $._subData[tokenId].totalDeposited += amount;

        depositedAt = $._subData[tokenId].streakStartedAt;
    }

    function withdrawableFromSubscription(uint256 tokenId, uint256 time, uint256 rate)
        internal
        view
        returns (uint256)
    {
        if (!isActive(tokenId, time, rate)) {
            return 0;
        }

        UserDataStorage storage $ = _getUserDataStorage();

        uint256 lastDepositAt = $._subData[tokenId].lastDepositAt;
        uint256 currentDeposit_ = $._subData[tokenId].currentDeposit * SubLib.MULTIPLIER_BASE;

        // locked + spent up until last deposit
        uint256 lockedAmount = ($._subData[tokenId].lockedAmount * SubLib.MULTIPLIER_BASE)
            + ((lastDepositAt - $._subData[tokenId].streakStartedAt) * (rate * $._subData[tokenId].multiplier));

        // the current block is spent, thus +1
        uint256 spentFunds = (1 + time - $._subData[tokenId].streakStartedAt) * (rate * $._subData[tokenId].multiplier);

        // postpone rebasing to the last moment
        return (currentDeposit_ - lockedAmount).min(currentDeposit_ - (spentFunds).min(currentDeposit_))
            / SubLib.MULTIPLIER_BASE;
    }

    /// @notice reduces the deposit amount of the existing subscription without changing the deposit time
    function withdrawFromSubscription(uint256 tokenId, uint256 amount, uint256 time, uint256 rate)
        internal
        returns (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit)
    {
        require(amount <= withdrawableFromSubscription(tokenId, time, rate), "Withdraw amount too large");

        UserDataStorage storage $ = _getUserDataStorage();
        oldDeposit = $._subData[tokenId].currentDeposit;
        newDeposit = oldDeposit - amount;
        $._subData[tokenId].currentDeposit = newDeposit;
        $._subData[tokenId].totalDeposited -= amount;

        // locked amount and last depositedAt remain unchanged

        depositedAt = $._subData[tokenId].streakStartedAt;
    }

    function changeMultiplier(uint256 tokenId, uint24 newMultiplier, uint256 time, uint256 rate)
        internal
        returns (bool isActive_, MultiplierChange memory change)
    {
        isActive_ = isActive(tokenId, time, rate);

        SubData storage subData = _getUserDataStorage()._subData[tokenId];
        if (isActive_) {
            // +1 as the current timeunit is already paid for using the current multiplier, thus the streak has to start at the next time unit
            change = resetStreak(subData, time + 1, rate);
        } else {
            // export only old multiplier value
            change.oldMultiplier = subData.multiplier;
            // create a new streak with 0 funds
            subData.streakStartedAt = time;
            subData.lastDepositAt = time;
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
    function resetStreak(SubData storage subData, uint256 time, uint256 rate)
        private
        returns (MultiplierChange memory change)
    {
        // reset streakStartedAt
        // reset lastDepositAt
        // reduce currentDeposit according to spent
        // reduce locked amount according to spent
        uint256 spent_ = currentStreakSpent(subData, time, rate);

        change.oldDepositAt = subData.streakStartedAt;
        change.oldAmount = subData.currentDeposit;
        change.oldMultiplier = subData.multiplier;

        subData.streakStartedAt = time;
        subData.lastDepositAt = time;
        subData.currentDeposit -= spent_;
        if (subData.lockedAmount < spent_) {
            subData.lockedAmount = 0;
        } else {
            subData.lockedAmount -= spent_;
        }

        change.reducedAmount = spent_;
        change.newDepositAt = time;
        change.newAmount = subData.currentDeposit;
    }

    function spent(uint256 tokenId, uint256 time, uint256 rate) internal view returns (uint256, uint256) {
        UserDataStorage storage $ = _getUserDataStorage();
        uint256 totalDeposited_ = $._subData[tokenId].totalDeposited;

        uint256 spentAmount;

        if (!isActive(tokenId, time, rate)) {
            spentAmount = totalDeposited_;
        } else {
            // +1 as we want to include the current timeunit
            spentAmount = totalSpent($._subData[tokenId], time + 1, rate);
        }

        uint256 unspentAmount = totalDeposited_ - spentAmount;

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
        return multipliedCurrentStreakSpent(subData, time, rate) / SubLib.MULTIPLIER_BASE;
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
        uint256 currentDeposit = subData.currentDeposit * SubLib.MULTIPLIER_BASE;
        uint256 spentAmount = ((subData.totalDeposited * SubLib.MULTIPLIER_BASE) - currentDeposit)
            + multipliedCurrentStreakSpent(subData, time, rate);

        // postponed rebasing
        return spentAmount / SubLib.MULTIPLIER_BASE;
    }

    function totalDeposited(uint256 tokenId) internal view returns (uint256) {
        UserDataStorage storage $ = _getUserDataStorage();
        return $._subData[tokenId].totalDeposited;
    }

    function multiplier(uint256 tokenId) internal view returns (uint24) {
        UserDataStorage storage $ = _getUserDataStorage();
        return $._subData[tokenId].multiplier;
    }

    function lastDepositedAt(uint256 tokenId) internal view returns (uint256) {
        UserDataStorage storage $ = _getUserDataStorage();
        return $._subData[tokenId].lastDepositAt;
    }

    function getSubData(uint256 tokenId) internal view returns (SubData memory) {
        UserDataStorage storage $ = _getUserDataStorage();
        return $._subData[tokenId];
    }

    function setSubData(uint256 tokenId, SubData memory data) internal {
        UserDataStorage storage $ = _getUserDataStorage();
        $._subData[tokenId] = data;
    }
}

abstract contract HasUserData {
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

abstract contract UserData is OzInitializable, TimeAware, HasRate, HasUserData {
    function __UserData_init(uint24 lock) internal {
        __UserData_init_unchained(lock);
    }

    function __UserData_init_unchained(uint24 lock) internal {
        __checkInitializing();
        UserDataLib.init(lock);
    }

    function _lock() internal view virtual override returns (uint24) {
        return UserDataLib.lock();
    }

    function _isActive(uint256 tokenId) internal view virtual override returns (bool) {
        return UserDataLib.isActive(tokenId, _now(), _rate());
    }

    function _expiresAt(uint256 tokenId) internal view virtual override returns (uint256) {
        return UserDataLib.expiresAt(tokenId, _rate());
    }

    function _deleteSubscription(uint256 tokenId) internal virtual override {
        return UserDataLib.deleteSubscription(tokenId);
    }

    function _createSubscription(uint256 tokenId, uint256 amount, uint24 multiplier) internal virtual override {
        UserDataLib.createSubscription(tokenId, amount, multiplier, _now());
    }

    function _extendSubscription(uint256 tokenId, uint256 amount)
        internal
        virtual
        override
        returns (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated)
    {
        (depositedAt, oldDeposit, newDeposit, reactivated) =
            UserDataLib.extendSubscription(tokenId, amount, _now(), _rate());
    }

    function _withdrawableFromSubscription(uint256 tokenId) internal view virtual override returns (uint256) {
        return UserDataLib.withdrawableFromSubscription(tokenId, _now(), _rate());
    }

    function _withdrawFromSubscription(uint256 tokenId, uint256 amount)
        internal
        virtual
        override
        returns (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit)
    {
        (depositedAt, oldDeposit, newDeposit) = UserDataLib.withdrawFromSubscription(tokenId, amount, _now(), _rate());
    }

    function _changeMultiplier(uint256 tokenId, uint24 newMultiplier)
        internal
        virtual
        override
        returns (bool isActive, MultiplierChange memory change)
    {
        (isActive, change) = UserDataLib.changeMultiplier(tokenId, newMultiplier, _now(), _rate());
    }

    function _spent(uint256 tokenId)
        internal
        view
        virtual
        override
        returns (uint256 spentAmount, uint256 unspentAmount)
    {
        (spentAmount, unspentAmount) = UserDataLib.spent(tokenId, _now(), _rate());
    }

    function _totalDeposited(uint256 tokenId) internal view virtual override returns (uint256) {
        return UserDataLib.totalDeposited(tokenId);
    }

    function _multiplier(uint256 tokenId) internal view virtual override returns (uint24) {
        return UserDataLib.multiplier(tokenId);
    }

    function _lastDepositedAt(uint256 tokenId) internal view virtual override returns (uint256) {
        return UserDataLib.lastDepositedAt(tokenId);
    }

    function _getSubData(uint256 tokenId) internal view virtual override returns (SubData memory) {
        return UserDataLib.getSubData(tokenId);
    }

    function _setSubData(uint256 tokenId, SubData memory data) internal virtual {
        UserDataLib.setSubData(tokenId, data);
    }
}
