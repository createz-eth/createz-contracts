// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IDiamond} from "diamond-1-hardhat/interfaces/IDiamond.sol";

import {BurnableFacet} from "./facet/BurnableFacet.sol";
import {ClaimableFacet} from "./facet/ClaimableFacet.sol";
import {DepositableFacet} from "./facet/DepositableFacet.sol";
import {ERC721Facet} from "./facet/ERC721Facet.sol";
import {InitFacet} from "./facet/InitFacet.sol";
import {MetadataFacet} from "./facet/MetadataFacet.sol";
import {PropertiesFacet} from "./facet/PropertiesFacet.sol";
import {WithdrawableFacet} from "./facet/WithdrawableFacet.sol";

import {ISubscriptionInternal, SubscriptionProperties} from "./ISubscription.sol";

import {IMetadata} from "./Metadata.sol";

contract FacetConfig {
    bytes4[] private s;

    // TODO test overloaded functions

    function clear() private {
        delete(s);
    }

    function initFacet(InitFacet f) public returns (bytes4[] memory) {
        clear();

        s.push(f.initialize.selector);

        return s;
    }

    function propertiesFacet(PropertiesFacet f) public returns (bytes4[] memory) {
        clear();

        s.push(f.metadata.selector);
        s.push(f.settings.selector);
        s.push(f.epochState.selector);

        s.push(f.setDescription.selector);
        s.push(f.setImage.selector);
        s.push(f.setExternalUrl.selector);

        s.push(f.setFlags.selector);
        s.push(f.getFlags.selector);
        s.push(f.flagsEnabled.selector);

        s.push(f.owner.selector);

        return s;
    }

    function erc721Facet(ERC721Facet f) public returns (bytes4[] memory) {
        clear();

        s.push(f.tokenOfOwnerByIndex.selector);
        s.push(f.totalSupply.selector);
        s.push(f.tokenByIndex.selector);
        s.push(f.balanceOf.selector);
        s.push(f.ownerOf.selector);
        s.push(f.name.selector);
        s.push(f.symbol.selector);
        s.push(f.approve.selector);
        s.push(f.getApproved.selector);
        s.push(f.setApprovalForAll.selector);
        s.push(f.isApprovedForAll.selector);
        s.push(f.transferFrom.selector);

        // overloaded
        s.push(bytes4(keccak256("safeTransferFrom(address,address,uint256)")));
        s.push(bytes4(keccak256("safeTransferFrom(address,address,uint256,bytes)")));

        s.push(f.supportsInterface.selector);

        return s;
    }

    function burnableFacet(BurnableFacet f) public returns (bytes4[] memory) {
        clear();

        s.push(f.burn.selector);

        return s;
    }

    function claimableFacet(ClaimableFacet f) public returns (bytes4[] memory) {
        clear();

        s.push(f.claimTips.selector);
        s.push(f.claimed.selector);
        s.push(f.claimedTips.selector);
        s.push(f.claimableTips.selector);

        // overloaded
        s.push(bytes4(keccak256("claim(address)")));
        s.push(bytes4(keccak256("claim(address,uint256)")));
        s.push(bytes4(keccak256("claimable()")));
        s.push(bytes4(keccak256("claimable(uint256,uint256)")));

        return s;
    }

    function depositableFacet(DepositableFacet f) public returns (bytes4[] memory) {
        clear();

        s.push(f.mint.selector);
        s.push(f.renew.selector);
        s.push(f.changeMultiplier.selector);
        s.push(f.tip.selector);
        s.push(f.isActive.selector);
        s.push(f.multiplier.selector);
        s.push(f.deposited.selector);
        s.push(f.expiresAt.selector);
        s.push(f.spent.selector);
        s.push(f.unspent.selector);
        s.push(f.tips.selector);
        s.push(f.activeSubShares.selector);

        return s;
    }

    function metadataFacet(MetadataFacet f) public returns (bytes4[] memory) {
        clear();

        s.push(f.contractURI.selector);
        s.push(f.tokenURI.selector);

        return s;
    }

    function withdrawableFacet(WithdrawableFacet f) public returns (bytes4[] memory) {
        clear();

        s.push(f.withdraw.selector);
        s.push(f.cancel.selector);
        s.push(f.withdrawable.selector);

        return s;
    }
}
