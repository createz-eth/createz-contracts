// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IMintAllowedUpgradeable.sol";

import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/utils/ContextUpgradeable.sol";

abstract contract MintAllowedUpgradeable is Initializable, ContextUpgradeable, IMintAllowedUpgradeable {
    struct MintAllowedStorage {
        // tokenId => minterAddress => is allowed to mint
        mapping(uint256 => mapping(address => bool)) _mintAllowed;
        // tokenId => isFrozen
        mapping(uint256 => bool) _mintAllowedFrozen;
    }

    // keccak256(abi.encode(uint256(keccak256("subsub.storage.MintAllowed")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MintAllowedStorageLocation =
        0x4f61531dcaa0d27e01e5a004ecb9227e5bd475d65ba122d6d2b0e240c58f4c00;

    function _getMintAllowedStorage() private pure returns (MintAllowedStorage storage $) {
        assembly {
            $.slot := MintAllowedStorageLocation
        }
    }

    function __MintAllowedUpgradeable_init() internal onlyInitializing {
        __MintAllowedUpgradeable_init_unchained();
    }

    function __MintAllowedUpgradeable_init_unchained() internal onlyInitializing {}

    function setMintAllowed(address minter, uint256 id, bool allow) public virtual {
        require(_idExists(id), "MintAllowed: token does not exist");
        require(!isMintAllowedFrozen(id), "MintAllowed: Minter list is frozen");
        MintAllowedStorage storage $ = _getMintAllowedStorage();
        $._mintAllowed[id][minter] = allow;

        emit MintAllowed(_msgSender(), minter, id, allow);
    }

    function isMintAllowed(address minter, uint256 id) public view virtual returns (bool) {
        MintAllowedStorage storage $ = _getMintAllowedStorage();
        return $._mintAllowed[id][minter];
    }

    function getMinters(uint256 id) external view returns (address[] memory) {
        revert("Not Implemented");
    }

    function freezeMintAllowed(uint256 id) external {
        require(_idExists(id), "MintAllowed: token does not exist");
        MintAllowedStorage storage $ = _getMintAllowedStorage();
        $._mintAllowedFrozen[id] = true;

        emit MintAllowedFrozen(_msgSender(), id);
    }

    function isMintAllowedFrozen(uint256 id) public view returns (bool) {
        MintAllowedStorage storage $ = _getMintAllowedStorage();
        return $._mintAllowedFrozen[id];
    }

    function _idExists(uint256 id) internal view virtual returns (bool);

    function _requireMintAllowed(uint256 id) internal view virtual {
        require(isMintAllowed(_msgSender(), id), "MintAllowed: sender not allowed to mint");
    }
}
