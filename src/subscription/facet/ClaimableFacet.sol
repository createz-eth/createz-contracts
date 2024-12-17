// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ContextUpgradeable} from "openzeppelin-contracts-upgradeable/utils/ContextUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

import {SubLib} from "../SubLib.sol";

import {OzContext, OzContextBind} from "../../dependency/OzContext.sol";
import {OzInitializable, OzInitializableBind} from "../../dependency/OzInitializable.sol";

import {Claimable, SubscriptionFlags} from "../ISubscription.sol";

import {HasPaymentToken, PaymentToken} from "../PaymentToken.sol";
import {Tips, HasTips} from "../Tips.sol";
import {HasRate, Rate} from "../Rate.sol";
import {HasHandleOwned, HandleOwned} from "../../handle/HandleOwned.sol";
import {HasEpochs, Epochs} from "../Epochs.sol";
import {HasTips, Tips} from "../Tips.sol";
import {HasBaseSubscription, BaseSubscription} from "../BaseSubscription.sol";
import {TimeAware, TimestampTimeAware} from "../TimeAware.sol";

abstract contract AbstractClaimableFacet is
    Claimable,
    HasBaseSubscription,
    HasPaymentToken,
    HasRate,
    HasEpochs,
    HasTips,
    HasHandleOwned
{
    using SubLib for uint256;

    function claim(address payable to) external {
        claim(to, _currentEpoch());
    }

    function claim(address payable to, uint256 upToEpoch) public onlyOwner {
        // epochs validity is checked in _claimEpochs
        uint256 amount = _claimEpochs(_rate(), upToEpoch);

        // convert to external amount
        amount = _asExternal(amount);

        _paymentTokenSend(to, amount);

        emit FundsClaimed(amount, _asExternal(_claimed()));
    }

    function claimable(uint256 startEpoch, uint256 endEpoch) public view returns (uint256) {
        (uint256 amount,,) = _scanEpochs(_rate(), _currentEpoch());

        return _asExternal(amount);
    }

    function claimable() external view returns (uint256) {
        return claimable(_lastProcessedEpoch(), _currentEpoch());
    }

    function claimTips(address payable to) external onlyOwner {
        uint256 amount = _claimTips();

        _paymentTokenSend(to, amount);

        emit TipsClaimed(amount, _claimedTips());
    }

    function claimed() external view returns (uint256) {
        return _asExternal(_claimed());
    }

    function claimedTips() external view returns (uint256) {
        return _asExternal(_claimedTips());
    }

    function claimableTips() external view returns (uint256) {
        return _claimableTips();
    }
}

contract ClaimableFacet is
    OzInitializableBind,
    OzContextBind,
    TimestampTimeAware,
    Rate,
    PaymentToken,
    Epochs,
    Tips,
    HandleOwned,
    BaseSubscription,
    AbstractClaimableFacet
{
    constructor(address handleContract) HandleOwned(handleContract) {
        _disableInitializers();
    }
}
