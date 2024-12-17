// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OzInitializable} from "../dependency/OzInitializable.sol";

library MaxSupplyLib {
    struct MaxSupplyStorage {
        uint256 _maxSupply;
    }

    // keccak256(abi.encode(uint256(keccak256("subsub.storage.subscription.MaxSupply")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MaxSupplyStorageLocation =
        0xd5a193fb325eb4e2a20c62d7d7a9d4af372aaa9384d3e03b4a2a820ccc9af600;

    function _getMaxSupplyStorage() private pure returns (MaxSupplyStorage storage $) {
        assembly {
            $.slot := MaxSupplyStorageLocation
        }
    }

    function init(uint256 maxSupply_) internal {
        MaxSupplyStorage storage $ = _getMaxSupplyStorage();
        $._maxSupply = maxSupply_;
    }

    function maxSupply() internal view returns (uint256) {
        MaxSupplyStorage storage $ = _getMaxSupplyStorage();
        return $._maxSupply;
    }
}

abstract contract HasMaxSupply {
    function _maxSupply() internal view virtual returns (uint256);
}

abstract contract MaxSupply is OzInitializable, HasMaxSupply {
    function __MaxSupply_init(uint256 maxSupply) internal {
        __MaxSupply_init_unchained(maxSupply);
    }

    function __MaxSupply_init_unchained(uint256 maxSupply) internal {
        __checkInitializing();
        MaxSupplyLib.init(maxSupply);
    }

    function _maxSupply() internal view override returns (uint256) {
        return MaxSupplyLib.maxSupply();
    }
}
