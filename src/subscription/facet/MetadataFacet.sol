// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721Metadata} from "openzeppelin-contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {ERC721Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";

import {ISubscriptionInternal, SubscriptionMetadata} from "../ISubscription.sol";
import {ViewLib} from "../ViewLib.sol";

import {HasValidation, Validation} from "../Validation.sol";

import {OzERC721EnumerableBind} from "../../dependency/OzERC721Enumerable.sol";
import {OzContextBind} from "../../dependency/OzContext.sol";

abstract contract AbstractMetadataFacet is SubscriptionMetadata, IERC721Metadata, HasValidation {
    function contractURI() external view returns (string memory) {
        return ViewLib.contractData(ISubscriptionInternal(address(this)));
    }

    function tokenURI(uint256 tokenId) public view virtual requireExists(tokenId) returns (string memory) {
        return ViewLib.tokenData(ISubscriptionInternal(address(this)), tokenId);
    }
}

contract MetadataFacet is OzContextBind, OzERC721EnumerableBind, Validation, AbstractMetadataFacet {
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override(ERC721Upgradeable, AbstractMetadataFacet)
        returns (string memory)
    {
        return AbstractMetadataFacet.tokenURI(tokenId);
    }
}
