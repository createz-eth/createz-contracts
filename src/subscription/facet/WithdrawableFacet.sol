// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SubLib} from "../SubLib.sol";

import {OzContext, OzContextBind} from "../../dependency/OzContext.sol";
import {OzERC721Enumerable, OzERC721EnumerableBind} from "../../dependency/OzERC721Enumerable.sol";
import {OzInitializable, OzInitializableBind} from "../../dependency/OzInitializable.sol";

import {HasFlagSettings, FlagSettings} from "../../FlagSettings.sol";
import {Withdrawable, SubscriptionFlags} from "../ISubscription.sol";

import {HasPaymentToken, PaymentToken} from "../PaymentToken.sol";
import {Tips, HasTips} from "../Tips.sol";
import {HasRate, Rate} from "../Rate.sol";
import {HasUserData, UserData, MultiplierChange} from "../UserData.sol";
import {HasEpochs, Epochs} from "../Epochs.sol";
import {HasValidation, Validation} from "../Validation.sol";
import {HasBaseSubscription, BaseSubscription} from "../BaseSubscription.sol";
import {TimeAware, TimestampTimeAware} from "../TimeAware.sol";

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

import {ContextUpgradeable} from "openzeppelin-contracts-upgradeable/utils/ContextUpgradeable.sol";

import {ERC721Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721EnumerableUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

abstract contract AbstractWithdrawableFacet is
    OzContext,
    OzERC721Enumerable,
    HasValidation,
    HasBaseSubscription,
    HasPaymentToken,
    HasRate,
    HasUserData,
    HasEpochs,
    HasFlagSettings,
    SubscriptionFlags,
    Withdrawable
{
    using SubLib for uint256;

    function withdraw(uint256 tokenId, uint256 amount) external requireExists(tokenId) {
        _withdraw(tokenId, _asInternal(amount));
    }

    function cancel(uint256 tokenId) external requireExists(tokenId) {
        _withdraw(tokenId, _withdrawableFromSubscription(tokenId));
    }

    /**
     * @param amount internal representation (18 decimals) of amount to withdraw
     *
     */
    function _withdraw(uint256 tokenId, uint256 amount) private requireIsAuthorized(tokenId) {
        // amount is checked in _withdrawFromSubscription
        (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit) = _withdrawFromSubscription(tokenId, amount);

        _reduceInEpochs(depositedAt, oldDeposit, newDeposit, _multiplier(tokenId), _rate());

        uint256 externalAmount = _asExternal(amount);
        _paymentTokenSend(payable(__msgSender()), externalAmount);

        emit SubscriptionWithdrawn(tokenId, externalAmount, __msgSender(), _totalDeposited(tokenId));
        emit MetadataUpdate(tokenId);
    }

    function withdrawable(uint256 tokenId) external view requireExists(tokenId) returns (uint256) {
        return _asExternal(_withdrawableFromSubscription(tokenId));
    }
}

contract WithdrawableFacet is
    TimestampTimeAware,
    Rate,
    PaymentToken,
    Epochs,
    UserData,
    FlagSettings,
    Validation,
    BaseSubscription,
    OzInitializableBind,
    OzContextBind,
    OzERC721EnumerableBind,
    AbstractWithdrawableFacet
{}
