// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SubscriptionProperties} from "../ISubscription.sol";
import {HasHandleOwned, HandleOwned} from "../../handle/HandleOwned.sol";
import {HasValidation, Validation} from "../Validation.sol";
import {Epochs, HasEpochs} from "../Epochs.sol";
import {Rate, HasRate} from "../Rate.sol";
import {UserData, HasUserData} from "../UserData.sol";
import {PaymentToken, HasPaymentToken} from "../PaymentToken.sol";
import {Metadata, HasMetadata} from "../Metadata.sol";
import {MaxSupply, HasMaxSupply} from "../MaxSupply.sol";
import {TimestampTimeAware} from "../TimeAware.sol";
import {HasFlagSettings, FlagSettings} from "../../FlagSettings.sol";

import {OzContext, OzContextBind} from "../../dependency/OzContext.sol";
import {OzERC721Enumerable, OzERC721EnumerableBind} from "../../dependency/OzERC721Enumerable.sol";
import {OzInitializable, OzInitializableBind} from "../../dependency/OzInitializable.sol";

/**
 * @dev Properties are not exposed on {ISubscription} but only used to modify subscription properties
 */
abstract contract AbstractPropertiesFacet is
    HasMaxSupply,
    HasMetadata,
    HasRate,
    HasHandleOwned,
    HasPaymentToken,
    HasUserData,
    HasEpochs,
    HasFlagSettings,
    HasValidation,
    SubscriptionProperties
{
    function settings()
        external
        view
        returns (address token, uint256 rate, uint24 lock, uint256 epochSize, uint256 maxSupply_)
    {
        token = _paymentToken();
        rate = _rate();
        lock = _lock();
        epochSize = _epochSize();
        maxSupply_ = _maxSupply();
    }

    function epochState() external view returns (uint256 currentEpoch, uint256 lastProcessedEpoch) {
        currentEpoch = _currentEpoch();
        lastProcessedEpoch = _lastProcessedEpoch();
    }

    function setFlags(uint256 flags) external onlyOwner requireValidFlags(flags) {
        _setFlags(flags);
    }

    function setDescription(string calldata _description) external onlyOwner {
        _setDescription(_description);
    }

    function setImage(string calldata _image) external onlyOwner {
        _setImage(_image);
    }

    function setExternalUrl(string calldata _externalUrl) external onlyOwner {
        _setExternalUrl(_externalUrl);
    }
}

contract PropertiesFacet is
    TimestampTimeAware,
    HandleOwned,
    MaxSupply,
    Metadata,
    Rate,
    PaymentToken,
    Epochs,
    UserData,
    FlagSettings,
    Validation,
    OzInitializableBind,
    OzContextBind,
    OzERC721EnumerableBind,
    AbstractPropertiesFacet
{
    constructor(address handleContract) HandleOwned(handleContract) {
        _disableInitializers();
    }
}
