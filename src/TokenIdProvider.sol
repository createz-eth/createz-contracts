// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OzInitializable} from "./dependency/OzInitializable.sol";

library TokenIdProviderLib {
    struct TokenIdProviderStorage {
        uint256 _tokenId;
    }

    // keccak256(abi.encode(uint256(keccak256("subsub.storage.subscription.TokenIdProvider")) - 1)) & ~bytes32(uint256(0xff))
    // solhint-disable-next-line const-name-snakecase
    bytes32 private constant TokenIdProviderStorageLocation =
        0x40c8f2ce84303d686a9ccadcec2b4734ae4bd9191beee7cbddf307002bcc2700;

    function _getTokenIdProviderStorage() private pure returns (TokenIdProviderStorage storage $) {
        // solhint-disable no-inline-assembly
        assembly {
            $.slot := TokenIdProviderStorageLocation
        }
        // solhint-enable no-inline-assembly
    }

    function init(uint256 tokenId) internal {
        TokenIdProviderStorage storage $ = _getTokenIdProviderStorage();
        $._tokenId = tokenId;
    }

    function nextTokenId() internal returns (uint256) {
        TokenIdProviderStorage storage $ = _getTokenIdProviderStorage();
        $._tokenId++;
        return $._tokenId;
    }
}

abstract contract HasTokenIdProvider {
    /**
     * @notice creates and returns the next token id
     * @return a new token id to use
     */
    function _nextTokenId() internal virtual returns (uint256);
}

abstract contract TokenIdProvider is OzInitializable, HasTokenIdProvider {
    function __TokenIdProvider_init(uint256 tokenId) internal {
        __TokenIdProvider_init_unchained(tokenId);
    }

    function __TokenIdProvider_init_unchained(uint256 tokenId) internal {
        __checkInitializing();
        TokenIdProviderLib.init(tokenId);
    }

    function _nextTokenId() internal override returns (uint256) {
        return TokenIdProviderLib.nextTokenId();
    }
}