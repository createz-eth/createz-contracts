// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721EnumerableUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

/**
 * @dev internal interface exposing OZ {ERC721Enumerable} methods without
 * binding to the implementation. The actually implementation needs to be
 * overriden later.
 */
abstract contract OzERC721Enumerable {
    // IERC721Enumerable just defines an external method but we need public
    function __totalSupply() internal view virtual returns (uint256);

    function __safeMint(address to, uint256 tokenId) internal virtual;

    function __ownerOf(uint256 tokenId) internal view virtual returns (address);

    function __isAuthorized(address owner, address spender, uint256 tokenId) internal view virtual returns (bool);

    function __burn(uint256 tokenId) internal virtual;
}

abstract contract OzERC721EnumerableBind is OzERC721Enumerable, ERC721EnumerableUpgradeable {
    function __totalSupply() internal view virtual override returns (uint256) {
        return totalSupply();
    }

    function __safeMint(address to, uint256 tokenId) internal virtual override {
        _safeMint(to, tokenId);
    }

    function __ownerOf(uint256 tokenId) internal view virtual override returns (address) {
        return _ownerOf(tokenId);
    }

    function __isAuthorized(address owner, address spender, uint256 tokenId)
        internal
        view
        virtual
        override
        returns (bool)
    {
        return _isAuthorized(owner, spender, tokenId);
    }

    function __burn(uint256 tokenId) internal virtual override {
        _burn(tokenId);
    }
}
