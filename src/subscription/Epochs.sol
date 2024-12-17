// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SubLib} from "./SubLib.sol";
import {TimeAware} from "./TimeAware.sol";

import {OzInitializable} from "../dependency/OzInitializable.sol";

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

/**
 * @title Subscription Epochs
 * @notice Epochs account for starting and expiring subscriptions
 * @dev Epochs always start from genesis
 */
struct Epoch {
    /**
     * @notice Number of expiring subscription shares
     */
    uint256 expiring;
    /**
     * @notice Number of starting subscription shares
     */
    uint256 starting; // number of starting subscription shares
    /**
     * @notice The amount of funds belonging to starting and ending subs in the epoch
     * @dev The amount is represented in internal decimals and multiplied by the amount of shares, thus based to MULTIPLIER_BASE when returned externally
     */
    uint256 partialFunds;
}

library EpochsLib {
    using Math for uint256;
    using SubLib for uint256;

    struct EpochsStorage {
        uint256 _epochSize;
        // the last claimed epoch
        uint256 _lastProcessedEpoch;
        // this value is set, after the initial claim.
        // It allows us to identify the meaning of epoch 0,
        // if this value is false, there was no claim at epoch 0,
        // otherwise epoch 0 is actually a valid last processed epoch
        bool _initialClaim;
        mapping(uint256 => Epoch) _epochs;
        // number of active subscriptions with a multiplier represented as shares
        // base 100:
        // 1 Sub * 1x == 100 shares
        // 1 Sub * 2.5x == 250 shares
        uint256 _activeSubShares;
        // internal counter for claimed subscription funds
        // based on internal representation
        uint256 _claimed;
    }

    // keccak256(abi.encode(uint256(keccak256("subsub.storage.subscription.Epochs")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant EpochsStorageLocation = 0x5506e84e9939bd9349ed9f3ee02b85a4ad709d31a62ad2a713a4a6a54ced2600;

    function _getEpochsStorage() private pure returns (EpochsStorage storage $) {
        assembly {
            $.slot := EpochsStorageLocation
        }
    }

    function init(uint256 epochSize_, uint256 time) internal {
        EpochsStorage storage $ = _getEpochsStorage();
        $._epochSize = epochSize_;
        $._lastProcessedEpoch = uint256(epochAt(time)).max(1) - 1; // current epoch -1 or 0
    }

    /**
     * @notice returns the raw data of an epoch
     * @dev the raw epoch data access is meant for debugging/testing
     * @param epoch the epoch id to get
     * @return raw epoch data
     */
    function getEpoch(uint256 epoch) internal view returns (Epoch memory) {
        EpochsStorage storage $ = _getEpochsStorage();
        return $._epochs[epoch];
    }

    /**
     * @notice set raw epoch data
     * @dev setting raw epoch data is meant for testing and debugging
     * @param epoch the epoch id
     * @param data the epoch data to set
     */
    function setEpoch(uint256 epoch, Epoch memory data) internal {
        EpochsStorage storage $ = _getEpochsStorage();
        $._epochs[epoch] = data;
    }

    /**
     * @notice set last processed epoch
     * @dev for testing and debugging
     * @param epoch the epoch id
     */
    function setLastProcessedEpoch(uint256 epoch) internal {
        EpochsStorage storage $ = _getEpochsStorage();
        $._lastProcessedEpoch = epoch;
    }

    /**
     * @notice set active sub shares
     * @dev for testing and debugging
     * @param shares number of shares
     */
    function setActiveSubShares(uint256 shares) internal {
        EpochsStorage storage $ = _getEpochsStorage();
        $._activeSubShares = shares;
    }

    /**
     * @notice get active sub shares
     * @dev for testing and debugging
     * @return number of active shares (internal state)
     */
    function getActiveSubShares() internal view returns (uint256) {
        EpochsStorage storage $ = _getEpochsStorage();
        return $._activeSubShares;
    }

    /**
     * @notice set claimed amount
     * @dev for testing and debugging
     * @param claimed_ amount of claimed funds
     */
    function setClaimed(uint256 claimed_) internal {
        EpochsStorage storage $ = _getEpochsStorage();
        $._claimed = claimed_;
    }

    function epochSize() internal view returns (uint256) {
        EpochsStorage storage $ = _getEpochsStorage();
        return $._epochSize;
    }

    function epochAt(uint256 time) internal view returns (uint256) {
        EpochsStorage storage $ = _getEpochsStorage();
        return time.epochOf($._epochSize);
    }

    function claimed() internal view returns (uint256) {
        EpochsStorage storage $ = _getEpochsStorage();
        return $._claimed;
    }

    function lastProcessedEpoch() internal view returns (uint256) {
        EpochsStorage storage $ = _getEpochsStorage();
        return $._lastProcessedEpoch;
    }

    function activeSubShares(uint256 time) internal view returns (uint256) {
        EpochsStorage storage $ = _getEpochsStorage();
        uint256 currentEpoch_ = epochAt(time);
        uint256 _activeSubs = $._activeSubShares;

        for (uint256 i = $._lastProcessedEpoch; i < currentEpoch_; i++) {
            // remove subs expiring in this epoch
            _activeSubs += $._epochs[i].starting;
            _activeSubs -= $._epochs[i].expiring;
        }

        // add most recent starting subs, being optimistic
        _activeSubs += $._epochs[currentEpoch_].starting;
        return _activeSubs;
    }

    /**
     * @notice handle from which epoch to start processing
     * @param suggestedLastEpoch the epoch that was last processed (exclusive)
     * @param initialClaim was there an initial claim, thus was epoch 0 processed?
     * @return the epoch start from processing (inclusive)
     */
    function startProcessingEpoch(uint256 suggestedLastEpoch, bool initialClaim) internal pure returns (uint256) {
        if (suggestedLastEpoch > 0) {
            return suggestedLastEpoch + 1;
        }
        // the given epoch is 0
        if (initialClaim) {
            // 0 + 1
            return 1;
        }
        return 0;
    }

    /**
     * @notice scan epochs starting from last processed to given epoch
     * @param rate the rate to apply
     * @param upToEpoch the epoch to scan to, excluding
     * @return amount the total amount of funds processed
     * @return starting the number of starting shares
     * @return expiring the number of expiring shares
     * @return lastEpoch the last epoch being processed, 0 if there was no scanning
     */
    function scanEpochs(uint256 rate, uint256 upToEpoch)
        internal
        view
        returns (uint256 amount, uint256 starting, uint256 expiring, uint256 lastEpoch)
    {
        EpochsStorage storage $ = _getEpochsStorage();
        uint256 _activeSubs = $._activeSubShares;

        for (uint256 i = startProcessingEpoch($._lastProcessedEpoch, $._initialClaim); i < upToEpoch; i++) {
            // remove subs expiring in this epoch
            uint256 epochExpiring = $._epochs[i].expiring;
            uint256 epochStarting = $._epochs[i].starting;

            if (epochExpiring > _activeSubs) {
                // more subs expire than there are active ones
                // thus subs start and expire within this epoch (sub is shorter than an epoch)
                _activeSubs = 0;
                epochStarting -= epochExpiring;
            } else {
                _activeSubs -= epochExpiring;
            }

            // we do not apply the individual multiplier to `rate` as it is
            // included in _activeSubs, expiring, and starting subs
            amount += $._epochs[i].partialFunds + (_activeSubs * $._epochSize * rate);

            // use original values here to account for all subs
            starting += $._epochs[i].starting;
            expiring += $._epochs[i].expiring;

            // add new subs starting in this epoch, sanitized
            _activeSubs += epochStarting;

            lastEpoch = i;
        }
        // the amount is mutliplied by the shares and has to be returned to its base
        amount = amount / SubLib.MULTIPLIER_BASE;
    }

    function claimEpochs(uint256 rate, uint256 upToEpoch, uint256 time) internal returns (uint256) {
        require(upToEpoch > 0, "SUB: cannot handle epoch 0");
        require(upToEpoch <= epochAt(time), "SUB: cannot claim current epoch");

        EpochsStorage storage $ = _getEpochsStorage();

        require(upToEpoch > $._lastProcessedEpoch, "SUB: cannot claim claimed epoch");

        (uint256 amount, uint256 starting, uint256 expiring, uint256 lastEpoch) = scanEpochs(rate, upToEpoch);

        // delete epochs
        for (uint256 i = startProcessingEpoch($._lastProcessedEpoch, $._initialClaim); i <= lastEpoch; i++) {
            delete $._epochs[i];
        }

        if (starting > expiring) {
            $._activeSubShares += starting - expiring;
        } else {
            $._activeSubShares -= expiring - starting;
        }

        // lastEpoch might be 0, if there was nothing to process
        if ($._lastProcessedEpoch < lastEpoch) {
            $._lastProcessedEpoch = lastEpoch;
        }
        $._claimed += amount;
        $._initialClaim = true;

        return amount;
    }

    function addToEpochs(uint256 depositedAt, uint256 amount, uint256 shares, uint256 rate) internal {
        // adjust internal rate to number of shares
        rate = rate * shares;
        // inflate by multiplier base to reduce rounding errors
        amount = amount * SubLib.MULTIPLIER_BASE;
        uint256 expiresAt_ = amount.expiresAt(depositedAt, rate);

        EpochsStorage storage $ = _getEpochsStorage();

        {
            // starting
            uint256 startingEpoch = depositedAt.epochOf($._epochSize);
            $._epochs[startingEpoch].starting += shares;

            uint256 remainingTimeUnits = uint256($._epochSize - (depositedAt % $._epochSize)).min(
                expiresAt_ - depositedAt // subscription ends within the current time slot
            );
            uint256 partialFunds = remainingTimeUnits * rate;
            $._epochs[startingEpoch].partialFunds += partialFunds;

            // reduce amount by partial funds
            amount -= partialFunds;
        }

        // expiring
        uint256 expiringEpoch = expiresAt_ / $._epochSize;
        $._epochs[expiringEpoch].expiring += shares;

        // add the rest as partial Funds, might just be some dust
        $._epochs[expiringEpoch].partialFunds += amount % ($._epochSize * rate);
    }

    function extendInEpochs(uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, uint256 shares, uint256 rate)
        internal
    {
        require(oldDeposit <= newDeposit, "new deposit too small");
        rate = rate * shares;

        //inflate
        oldDeposit = oldDeposit * SubLib.MULTIPLIER_BASE;
        newDeposit = newDeposit * SubLib.MULTIPLIER_BASE;

        EpochsStorage storage $ = _getEpochsStorage();
        uint256 startEpoch = depositedAt / $._epochSize;

        uint256 oldExpireEpoch = oldDeposit.expiresAt(depositedAt, rate).epochOf($._epochSize);

        uint256 newExpiresAt = newDeposit.expiresAt(depositedAt, rate);

        if (startEpoch == oldExpireEpoch) {
            // old sub starts and expires in same epoch => unwind all

            // remove the entire sub funds from partialfunds
            $._epochs[oldExpireEpoch].partialFunds -= oldDeposit;
            $._epochs[oldExpireEpoch].expiring -= shares;

            // add "new" sub (add method) without touching starting shares

            // TODO refactor with "add" method
            {
                // handle head

                uint256 partialTimeUnits = uint256($._epochSize - (depositedAt % $._epochSize)).min(
                    newExpiresAt - depositedAt // subscription ends within the current time slot
                );
                uint256 partialFunds = partialTimeUnits * rate;
                $._epochs[startEpoch].partialFunds += partialFunds;

                // reduce amount by partial funds
                newDeposit -= partialFunds;
            }

            // handle tail
            uint256 expiringEpoch = newExpiresAt / $._epochSize;
            $._epochs[expiringEpoch].expiring += shares;

            // add the rest as partial Funds, might just be some dust
            $._epochs[expiringEpoch].partialFunds += newDeposit % ($._epochSize * rate);
            // TODO end refactor
        } else {
            // sub spans across epochs
            // the head state is not being touched, only the tail is moved

            // deduct head from deposit
            {
                uint256 headFunds = ($._epochSize - (depositedAt % $._epochSize)) * rate;
                newDeposit -= headFunds;
                oldDeposit -= headFunds;
            }

            uint256 epochRate = $._epochSize * rate;
            // unwind tail
            $._epochs[oldExpireEpoch].partialFunds -= oldDeposit % epochRate;
            $._epochs[oldExpireEpoch].expiring -= shares;

            // set new tail
            uint256 newExpiringEpoch = newExpiresAt / $._epochSize;
            $._epochs[newExpiringEpoch].partialFunds += newDeposit % epochRate;
            $._epochs[newExpiringEpoch].expiring += shares;
        }
    }

    function reduceInEpochs(
        uint256 depositedAt,
        uint256 oldDeposit,
        uint256 newDeposit,
        uint256 shares,
        uint256 time,
        uint256 rate
    ) internal {
        require(oldDeposit >= newDeposit, "Not reduce"); // sanity check
        rate = rate * shares;
        //inflate
        oldDeposit = oldDeposit * SubLib.MULTIPLIER_BASE;
        newDeposit = newDeposit * SubLib.MULTIPLIER_BASE;

        // require(newExpiresAt >= now, "Deposit too small");
        // sub cannot be expired

        EpochsStorage storage $ = _getEpochsStorage();
        uint256 startEpoch = depositedAt / $._epochSize;

        uint256 oldExpiresAt = oldDeposit.expiresAt(depositedAt, rate);
        // require(oldExpiresAt >= _now()); // cannot be claimed or expired yet

        uint256 oldExpireEpoch = oldExpiresAt / $._epochSize;

        uint256 newExpiresAt = newDeposit.expiresAt(depositedAt, rate);

        // the new sub cannot expire in the past
        require(newExpiresAt > time, "Deposit too small"); // sanity check

        if (startEpoch == oldExpireEpoch) {
            // old sub starts and expires in same epoch => just change deposit in partialFunds

            // remove the entire sub funds from partialFunds
            $._epochs[oldExpireEpoch].partialFunds -= oldDeposit;
            // keep shares as is, as new tail is also in this epoch

            // just add the entire new deposit, as the sub expires in this epoch
            $._epochs[oldExpireEpoch].partialFunds += newDeposit;
        } else {
            // the original sub spans across multiple epochs, we might only have to change the tail
            uint256 newExpiringEpoch = newExpiresAt / $._epochSize;

            if (startEpoch == newExpiringEpoch) {
                // the new sub starts and expires in the same epoch
                // unwind all from multiple epochs
                // remove tail and head funds from partialfunds
                {
                    // handle head
                    uint256 partialTimeUnits = $._epochSize - (depositedAt % $._epochSize); // sub spanned multiple epochs
                    uint256 partialFunds = partialTimeUnits * rate;
                    $._epochs[startEpoch].partialFunds -= partialFunds;
                    // keep start shares as is
                    oldDeposit -= partialFunds;
                }

                // handle tail
                $._epochs[oldExpireEpoch].expiring -= shares;

                // remove the rest as partial Funds, might just be some dust
                $._epochs[oldExpireEpoch].partialFunds -= oldDeposit % ($._epochSize * rate);

                ///////////////////////////////////////////////////////////////
                // add new head/tail

                // as the new sub starts and ends within a single epoch, we just dump it in partialFunds
                $._epochs[newExpiringEpoch].partialFunds += newDeposit;
                $._epochs[newExpiringEpoch].expiring += shares;
            } else {
                // the new sub still spans across multiple epochs, thus we only change the tail
                // deduct head from deposit
                {
                    uint256 partialTimeUnits = $._epochSize - (depositedAt % $._epochSize); // sub spanned multiple epochs
                    uint256 partialFunds = partialTimeUnits * rate;
                    // keep start shares as is
                    oldDeposit -= partialFunds;
                    newDeposit -= partialFunds;
                }
                // unwind tail
                $._epochs[oldExpireEpoch].expiring -= shares;

                // remove the rest as partial Funds, might just be some dust
                $._epochs[oldExpireEpoch].partialFunds -= oldDeposit % ($._epochSize * rate);

                // set new tail
                $._epochs[newExpiringEpoch].expiring += shares;

                // add the rest as partial Funds, might just be some dust
                $._epochs[newExpiringEpoch].partialFunds += newDeposit % ($._epochSize * rate);
            }
        }
    }
}

/**
 * @title Has Epochs Mixin interface
 * @notice Provides internal 'interface' functions of the mixin
 */
abstract contract HasEpochs {
    /**
     * @notice Provides the size of an epoch as defined in the subscription plan settings
     * @return Size of an epoch in time units
     */
    function _epochSize() internal view virtual returns (uint256);

    /**
     * @notice Provides the sequential number of the current epoch
     * @return the sequential number of the current epoch
     */
    function _currentEpoch() internal view virtual returns (uint256);

    /**
     * @notice Provides the last epoch that was processed by a claim
     * @return the sequential number of the last claimed epoch
     */
    function _lastProcessedEpoch() internal view virtual returns (uint256);

    /**
     * @notice Provides the number of active shares
     * @dev The active shares hint towards the number of active subscriptions.
     *      100 shares equal 1 non-multiplied subscription
     * @return the sequential number of the current epoch
     */
    function _activeSubShares() internal view virtual returns (uint256);

    /**
     * @notice Amount of (ever) claimed funds
     * @dev The amount is represented in internal decimals
     * @return Amount of (ever) claimed funds
     */
    function _claimed() internal view virtual returns (uint256);

    /**
     * @notice scans the internal state up until the given epoch (excluded) and return the state change diff
     * @dev the internal state change between the epochs lastProcessedEpoch + 1 (included) and the currentEpoch - 1 is aggregated and returned without actually changing the state
     * The internal state has to be updated separately
     * @param rate the rate that is applied to calculate the returned amount of processed funds, the contracts rate
     * @param upToEpoch the epoch up until to process to (excluded)
     * @return amount the amount of funds processed in the processed epochs
     * @return starting the number of subscription shares that started in the epochs processed
     * @return expiring the number of subscription shares that expired in the epochs processed
     */
    function _scanEpochs(uint256 rate, uint256 upToEpoch)
        internal
        view
        virtual
        returns (uint256 amount, uint256 starting, uint256 expiring);

    /**
     * @notice updates the internal state of the subscription contract by processing completed epochs and returning the amount of newly claimable funds
     * @dev this function uses _scanEpochs to get an aggregated state change and subsequently apply it to storage
     * @param rate the rate that is applied to calculate the returned amount of processed funds, the contracts rate
     * @param upToEpoch the epoch to advance the state to (excluded). Has to be less or equal to current epoch
     * @return The amount of claimable funds
     */
    function _claimEpochs(uint256 rate, uint256 upToEpoch) internal virtual returns (uint256);

    /**
     * @notice Adds a new subscription based on amount of funds and number of shares to the epochs
     * @dev the given rate and amount are used to calculate the duration of the subscription, the number of shares does not affect the rate or amount.
     * @param depositedAt The time the new subscription is started, it is not allowed to be in the past, specifically before the last processed epoch
     * @param amount The amount of funds for this new subscription
     * @param shares The number of shares this new subscription contains
     * @param rate The rate that is applied to the amount, the contracts original rate
     */
    function _addToEpochs(uint256 depositedAt, uint256 amount, uint256 shares, uint256 rate) internal virtual;

    /**
     * @notice extends an active subscription in the epochs based on its coordinates
     * @dev the subscription is extended using the new deposit data and removed from the old deposit data location
     * @param depositedAt The time the subscription was originally deposited/started at
     * @param oldDeposit The amount of funds the original subscription contained
     * @param newDeposit The amount of funds the subscription now contains
     * @param shares The number of shares this subscription contains
     * @param rate The rate that is applied to the amount, the contracts rate
     */
    function _extendInEpochs(uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, uint256 shares, uint256 rate)
        internal
        virtual;

    /**
     * @notice reduces an active subscription in the epochs based on its coordinates
     * @dev the subscription is reduced using the new deposit data and removed from the old deposit data location
     * @param depositedAt The time the subscription was originally deposited/started at
     * @param oldDeposit The amount of funds the original subscription contained
     * @param newDeposit The amount of funds the subscription now contains
     * @param shares The number of shares this subscription contains
     * @param rate The rate that is applied to the amount, the contracts rate
     */
    function _reduceInEpochs(uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, uint256 shares, uint256 rate)
        internal
        virtual;
}

abstract contract Epochs is OzInitializable, TimeAware, HasEpochs {
    function __Epochs_init(uint256 epochSize) internal {
        __Epochs_init_unchained(epochSize);
    }

    function __Epochs_init_unchained(uint256 epochSize) internal {
        __checkInitializing();
        EpochsLib.init(epochSize, _now());
    }

    /**
     * @notice returns the raw data of an epoch
     * @dev the raw epoch data access is meant for debugging/testing
     * @param epoch the epoch id to get
     * @return raw epoch data
     */
    function _getEpoch(uint256 epoch) internal view virtual returns (Epoch memory) {
        return EpochsLib.getEpoch(epoch);
    }

    /**
     * @notice set raw epoch data
     * @dev setting raw epoch data is meant for testing and debugging
     * @param epoch the epoch id
     * @param data the epoch data to set
     */
    function _setEpoch(uint256 epoch, Epoch memory data) internal virtual {
        EpochsLib.setEpoch(epoch, data);
    }

    /**
     * @notice set last processed epoch
     * @dev for testing and debugging
     * @param epoch the epoch id
     */
    function _setLastProcessedEpoch(uint256 epoch) internal virtual {
        EpochsLib.setLastProcessedEpoch(epoch);
    }

    /**
     * @notice set active sub shares
     * @dev for testing and debugging
     * @param shares number of shares
     */
    function _setActiveSubShares(uint256 shares) internal virtual {
        EpochsLib.setActiveSubShares(shares);
    }

    /**
     * @notice get active sub shares
     * @dev for testing and debugging
     * @return number of active shares (internal state)
     */
    function _getActiveSubShares() internal virtual returns (uint256) {
        return EpochsLib.getActiveSubShares();
    }

    /**
     * @notice set claimed amount
     * @dev for testing and debugging
     * @param claimed amount of claimed funds
     */
    function _setClaimed(uint256 claimed) internal virtual {
        EpochsLib.setClaimed(claimed);
    }

    function _epochSize() internal view virtual override returns (uint256) {
        return EpochsLib.epochSize();
    }

    function _currentEpoch() internal view virtual override returns (uint256) {
        return EpochsLib.epochAt(_now());
    }

    function _claimed() internal view virtual override returns (uint256) {
        return EpochsLib.claimed();
    }

    function _lastProcessedEpoch() internal view virtual override returns (uint256) {
        return EpochsLib.lastProcessedEpoch();
    }

    function _activeSubShares() internal view virtual override returns (uint256) {
        return EpochsLib.activeSubShares(_now());
    }

    // TODO remove me
    function _startProcessingEpoch(uint256 suggestedLastEpoch, bool initialClaim)
        internal
        pure
        virtual
        returns (uint256)
    {
        return EpochsLib.startProcessingEpoch(suggestedLastEpoch, initialClaim);
    }

    function _scanEpochs(uint256 rate, uint256 upToEpoch)
        internal
        view
        virtual
        override
        returns (uint256 amount, uint256 starting, uint256 expiring)
    {
        (amount, starting, expiring,) = EpochsLib.scanEpochs(rate, upToEpoch);
    }

    function _claimEpochs(uint256 rate, uint256 upToEpoch) internal virtual override returns (uint256) {
        return EpochsLib.claimEpochs(rate, upToEpoch, _now());
    }

    function _addToEpochs(uint256 depositedAt, uint256 amount, uint256 shares, uint256 rate)
        internal
        virtual
        override
    {
        EpochsLib.addToEpochs(depositedAt, amount, shares, rate);
    }

    function _extendInEpochs(uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, uint256 shares, uint256 rate)
        internal
        virtual
        override
    {
        EpochsLib.extendInEpochs(depositedAt, oldDeposit, newDeposit, shares, rate);
    }

    function _reduceInEpochs(uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, uint256 shares, uint256 rate)
        internal
        virtual
        override
    {
        EpochsLib.reduceInEpochs(depositedAt, oldDeposit, newDeposit, shares, _now(), rate);
    }
}
