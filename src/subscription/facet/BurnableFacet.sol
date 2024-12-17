// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OzContext, OzContextBind} from "../../dependency/OzContext.sol";
import {OzERC721Enumerable, OzERC721EnumerableBind} from "../../dependency/OzERC721Enumerable.sol";
import {OzInitializable, OzInitializableBind} from "../../dependency/OzInitializable.sol";

import {Burnable, SubscriptionFlags} from "../ISubscription.sol";

import {HasPaymentToken, PaymentToken} from "../PaymentToken.sol";
import {HasRate, Rate} from "../Rate.sol";
import {HasUserData, UserData} from "../UserData.sol";
import {TimeAware, TimestampTimeAware} from "../TimeAware.sol";

import {ERC721EnumerableUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

abstract contract AbstractBurnableFacet is OzContext, OzERC721Enumerable, HasUserData, Burnable {
    function burn(uint256 tokenId) external {
        // only owner of tokenId can burn
        require(__msgSender() == __ownerOf(tokenId), "SUB: not the owner");

        _deleteSubscription(tokenId);

        __burn(tokenId);
    }
}

contract BurnableFacet is
    TimestampTimeAware,
    Rate,
    PaymentToken,
    UserData,
    OzInitializableBind,
    OzContextBind,
    OzERC721EnumerableBind,
    AbstractBurnableFacet
{}
