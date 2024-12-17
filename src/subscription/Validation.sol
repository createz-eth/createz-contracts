// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

import {ERC721EnumerableUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

import {SubLib} from "./SubLib.sol";

import {OzContext} from "../dependency/OzContext.sol";
import {OzERC721Enumerable} from "../dependency/OzERC721Enumerable.sol";

import {SubscriptionFlags} from "./ISubscription.sol";

library BaseSubscriptionLib {}

/**
 * @notice Provides validation functions needed throughout other subscription modules
 */
abstract contract HasValidation {
    modifier requireExists(uint256 tokenId) virtual;
    modifier requireValidFlags(uint256 flags) virtual;
    modifier requireValidMultiplier(uint24 multi) virtual;
    modifier requireIsAuthorized(uint256 tokenId) virtual;
}

abstract contract Validation is OzContext, OzERC721Enumerable, HasValidation, SubscriptionFlags {
    modifier requireExists(uint256 tokenId) virtual override {
        require(__ownerOf(tokenId) != address(0), "SUB: subscription does not exist");
        _;
    }

    modifier requireValidFlags(uint256 flags) virtual override {
        require(flags <= ALL_FLAGS, "SUB: invalid settings");
        _;
    }

    modifier requireValidMultiplier(uint24 multi) virtual override {
        require(multi >= SubLib.MULTIPLIER_BASE && multi <= SubLib.MULTIPLIER_MAX, "SUB: multiplier invalid");
        _;
    }

    modifier requireIsAuthorized(uint256 tokenId) virtual override {
        require(
            __isAuthorized(__ownerOf(tokenId), __msgSender(), tokenId), "ERC721: caller is not token owner or approved"
        );
        _;
    }
}
