// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SubLib} from "./SubLib.sol";

import {Math} from "openzeppelin-contracts/utils/math/Math.sol";

library TipsLib {
    using SubLib for uint256;

    struct UserTips {
        uint256 tips; // amount of tips sent to this subscription
    }

    struct TipsStorage {
        mapping(uint256 => UserTips) _userTips;
        // amount of tips EVER sent to the contract, the value only increments
        uint256 _allTips;
        // amount of tips EVER claimed from the contract, the value only increments
        uint256 _claimedTips;
    }

    // keccak256(abi.encode(uint256(keccak256("subsub.storage.subscription.TipStorage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant TipsStorageLocation = 0x6593c8e4864b6bbd915fc15cbe50a3f84670836b50d945261e8b1599f6e37400;

    function _getTipsStorage() private pure returns (TipsStorage storage $) {
        assembly {
            $.slot := TipsStorageLocation
        }
    }

    function addTip(uint256 tokenId, uint256 amount) internal {
        TipsStorage storage $ = _getTipsStorage();
        // TODO change me
        $._userTips[tokenId].tips += amount;
        $._allTips += amount;
    }

    function tips(uint256 tokenId) internal view returns (uint256) {
        TipsStorage storage $ = _getTipsStorage();
        return $._userTips[tokenId].tips;
    }

    function allTips() internal view returns (uint256) {
        TipsStorage storage $ = _getTipsStorage();
        return $._allTips;
    }

    function claimedTips() internal view returns (uint256) {
        TipsStorage storage $ = _getTipsStorage();
        return $._claimedTips;
    }

    function claimableTips() internal view returns (uint256) {
        TipsStorage storage $ = _getTipsStorage();
        return $._allTips - $._claimedTips;
    }

    function claimTips() internal returns (uint256 claimable) {
        TipsStorage storage $ = _getTipsStorage();
        claimable = $._allTips - $._claimedTips;
        $._claimedTips = $._allTips;
    }
}

abstract contract HasTips {
    /**
     * @notice adds the given amount of funds to the tips of a subscription
     * @param tokenId subscription identifier
     * @param amount tip amount
     */
    function _addTip(uint256 tokenId, uint256 amount) internal virtual;

    /**
     * @notice returns the amount of tips placed in the given subscription
     * @param tokenId subscription identifier
     * @return the total amount of tips
     */
    function _tips(uint256 tokenId) internal view virtual returns (uint256);

    /**
     * @notice returns the amount of all tips placed in this contract
     * @return the total amount of tips in this contract
     */
    function _allTips() internal view virtual returns (uint256);

    /**
     * @notice returns the amount of tips that were claimed from this contract
     * @return the total amount of tips claimed from this contract
     */
    function _claimedTips() internal view virtual returns (uint256);

    /**
     * @notice returns the amount of tips that can be claimed from this contract
     * @dev returns the amount of not yet claimed tips
     * @return the amount of tips claimable from this contract
     */
    function _claimableTips() internal view virtual returns (uint256);

    /**
     * @notice claims the available tips from this contract
     * @return the amount of tips that were claimed by this call
     */
    function _claimTips() internal virtual returns (uint256);
}

abstract contract Tips is HasTips {
    function _addTip(uint256 tokenId, uint256 amount) internal virtual override {
        TipsLib.addTip(tokenId, amount);
    }

    function _tips(uint256 tokenId) internal view virtual override returns (uint256) {
        return TipsLib.tips(tokenId);
    }

    function _allTips() internal view virtual override returns (uint256) {
        return TipsLib.allTips();
    }

    function _claimedTips() internal view virtual override returns (uint256) {
        return TipsLib.claimedTips();
    }

    function _claimableTips() internal view virtual override returns (uint256) {
        return TipsLib.claimableTips();
    }

    function _claimTips() internal virtual override returns (uint256 claimable) {
        return TipsLib.claimTips();
    }
}
