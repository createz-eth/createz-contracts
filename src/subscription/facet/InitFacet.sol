// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SubscriptionInitialize, MetadataStruct, SubSettings} from "../ISubscription.sol";

import {SubLib} from "../SubLib.sol";

import {FlagSettings} from "../../FlagSettings.sol";

import {Rate} from "../Rate.sol";
import {Epochs} from "../Epochs.sol";
import {UserData} from "../UserData.sol";
import {PaymentToken} from "../PaymentToken.sol";
import {MaxSupply} from "../MaxSupply.sol";
import {TokenIdProvider} from "../../TokenIdProvider.sol";
import {Metadata} from "../Metadata.sol";
import {TimestampTimeAware} from "../TimeAware.sol";

import {OzERC721EnumerableBind} from "../../dependency/OzERC721Enumerable.sol";
import {OzContextBind} from "../../dependency/OzContext.sol";
import {OzInitializableBind} from "../../dependency/OzInitializable.sol";

contract InitFacet is
    OzInitializableBind,
    OzContextBind,
    OzERC721EnumerableBind,
    MaxSupply,
    TokenIdProvider,
    Metadata,
    Rate,
    PaymentToken,
    Epochs,
    UserData,
    FlagSettings,
    TimestampTimeAware
{
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string calldata tokenName,
        string calldata tokenSymbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings
    ) external initializer {
        require(_settings.epochSize > 0, "SUB: invalid epochSize");
        require(_settings.lock <= SubLib.LOCK_BASE, "SUB: lock percentage out of range");
        require(_settings.rate > 0, "SUB: rate cannot be 0");
        // TODO FIXME
        // require(_settings.epochSize >= 1 days, "SUB: epoch size has to be at least 1 day");

        // call initializers of inherited contracts
        __ERC721_init_unchained(tokenName, tokenSymbol);
        __FlagSettings_init_unchained();
        __Rate_init_unchained(_settings.rate);
        __Epochs_init_unchained(_settings.epochSize);
        __UserData_init_unchained(_settings.lock);
        __PaymentToken_init_unchained(_settings.token);
        __MaxSupply_init_unchained(_settings.maxSupply);
        __TokenIdProvider_init_unchained(0);
        __Metadata_init_unchained(_metadata.description, _metadata.image, _metadata.externalUrl);
    }
}
