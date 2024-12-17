// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SubLib} from "../SubLib.sol";

import {HasFlagSettings, FlagSettings} from "../../FlagSettings.sol";
import {Depositable, SubscriptionFlags} from "../ISubscription.sol";

import {HasMaxSupply, MaxSupply} from "../MaxSupply.sol";
import {HasTokenIdProvider, TokenIdProvider} from "../../TokenIdProvider.sol";
import {HasPaymentToken, PaymentToken} from "../PaymentToken.sol";
import {Tips, HasTips} from "../Tips.sol";
import {HasRate, Rate} from "../Rate.sol";
import {HasUserData, UserData, MultiplierChange} from "../UserData.sol";
import {HasEpochs, Epochs} from "../Epochs.sol";
import {HasValidation, Validation} from "../Validation.sol";
import {HasBaseSubscription, BaseSubscription} from "../BaseSubscription.sol";
import {TimeAware, TimestampTimeAware} from "../TimeAware.sol";

import {OzContext, OzContextBind} from "../../dependency/OzContext.sol";
import {OzERC721Enumerable, OzERC721EnumerableBind} from "../../dependency/OzERC721Enumerable.sol";
import {OzInitializable, OzInitializableBind} from "../../dependency/OzInitializable.sol";

import {ContextUpgradeable} from "openzeppelin-contracts-upgradeable/utils/ContextUpgradeable.sol";

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC721Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721EnumerableUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

abstract contract AbstractDepositableFacet is
    OzContext,
    OzERC721Enumerable,
    HasValidation,
    HasBaseSubscription,
    HasMaxSupply,
    HasTokenIdProvider,
    HasPaymentToken,
    HasTips,
    TimeAware,
    HasRate,
    HasUserData,
    HasEpochs,
    HasFlagSettings,
    SubscriptionFlags,
    Depositable
{
    using SubLib for uint256;

    function mint(uint256 amount, uint24 _multiplier, string calldata message)
        external
        payable
        whenDisabled(MINTING_PAUSED)
        requireValidMultiplier(_multiplier)
        returns (uint256)
    {
        // check max supply
        require(__totalSupply() < _maxSupply(), "SUB: max supply reached");
        // uint subscriptionEnd = amount / rate;
        uint256 tokenId = _nextTokenId();

        uint256 internalAmount = _asInternal(amount);

        // TODO do we need return values?
        _createSubscription(tokenId, internalAmount, _multiplier);

        // addToEpochs is not allowed to add a new sub to the past
        _addToEpochs(_now(), internalAmount, _multiplier, _rate());

        // we transfer the ORIGINAL amount into the contract, claiming any overflows / dust
        _paymentTokenReceive(msg.sender, amount);

        __safeMint(msg.sender, tokenId);

        emit SubscriptionRenewed(tokenId, amount, __msgSender(), _totalDeposited(tokenId), message);

        return tokenId;
    }

    function renew(uint256 tokenId, uint256 amount, string calldata message)
        external
        payable
        whenDisabled(RENEWAL_PAUSED)
        requireExists(tokenId)
    {
        uint256 multiplier_ = _multiplier(tokenId);
        uint256 rate = _rate();
        uint256 internalAmount = _asInternal(amount);

        {
            (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactived) =
                _extendSubscription(tokenId, internalAmount);

            if (reactived) {
                // subscription was inactive, new streak was created, add "new" sub to epochs
                _addToEpochs(_now(), newDeposit, multiplier_, rate);
            } else {
                // subscription is not expired
                _extendInEpochs(depositedAt, oldDeposit, newDeposit, multiplier_, rate);
            }
        }

        // finally transfer tokens into this contract
        // we use the ORIGINAL amount here
        _paymentTokenReceive(msg.sender, amount);

        emit SubscriptionRenewed(tokenId, amount, __msgSender(), _totalDeposited(tokenId), message);
        emit MetadataUpdate(tokenId);
    }

    function changeMultiplier(uint256 tokenId, uint24 newMultiplier)
        external
        requireExists(tokenId)
        requireValidMultiplier(newMultiplier)
        requireIsAuthorized(tokenId)
    {
        (bool isActive_, MultiplierChange memory change) = _changeMultiplier(tokenId, newMultiplier);

        if (isActive_) {
            uint256 rate = _rate();
            _reduceInEpochs(change.oldDepositAt, change.oldAmount, change.reducedAmount, change.oldMultiplier, rate);

            // newDepositAt is not allowed to be in the past
            _addToEpochs(change.newDepositAt, change.newAmount, newMultiplier, rate);
        }
        // else => inactive subs are effectively not tracked in Epochs, thus no further changes as necessary

        emit MultiplierChanged(tokenId, __msgSender(), change.oldMultiplier, newMultiplier);
    }

    function tip(uint256 tokenId, uint256 amount, string calldata message)
        external
        payable
        requireExists(tokenId)
        whenDisabled(TIPPING_PAUSED)
    {
        require(amount > 0, "SUB: amount too small");

        _addTip(tokenId, amount);

        _paymentTokenReceive(__msgSender(), amount);

        emit Tipped(tokenId, amount, __msgSender(), _tips(tokenId), message);
        emit MetadataUpdate(tokenId);
    }

    function isActive(uint256 tokenId) external view requireExists(tokenId) returns (bool) {
        return _isActive(tokenId);
    }

    function multiplier(uint256 tokenId) external view returns (uint24) {
        return _multiplier(tokenId);
    }

    function deposited(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return _asExternal(_totalDeposited(tokenId));
    }

    function expiresAt(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return _expiresAt(tokenId);
    }

    function spent(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        (uint256 spentAmount,) = _spent(tokenId);
        return _asExternal(spentAmount);
    }

    function unspent(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        (, uint256 unspentAmount) = _spent(tokenId);
        return _asExternal(unspentAmount);
    }

    function tips(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return _tips(tokenId);
    }

    function activeSubShares() external view returns (uint256) {
        return _activeSubShares();
    }
}

contract DepositableFacet is
    TimestampTimeAware,
    OzContextBind,
    OzInitializableBind,
    OzERC721EnumerableBind,
    TokenIdProvider,
    MaxSupply,
    Rate,
    PaymentToken,
    Tips,
    Epochs,
    UserData,
    FlagSettings,
    Validation,
    BaseSubscription,
    AbstractDepositableFacet
{}
