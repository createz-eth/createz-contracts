// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISubscriptionHandle} from "./ISubscriptionHandle.sol";
import {HasFactory, DiamondFactory} from "./Factory.sol";
import {HasContractRegistry, ContractRegistry} from "../../handle/ContractRegistry.sol";
import {ManagingHandle} from "../../handle/ManagingHandle.sol";

import {MetadataStruct, SubSettings} from "../ISubscription.sol";

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "openzeppelin-contracts-upgradeable/utils/ContextUpgradeable.sol";
import {IERC165} from "openzeppelin-contracts/utils/introspection/IERC165.sol";
import {ERC721Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721BurnableUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import {ERC721EnumerableUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

import {UUPSUpgradeable} from "openzeppelin-contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";

// TODO get rid of Burnable inheritance
abstract contract SubscriptionHandle is
    Initializable,
    ContextUpgradeable,
    ISubscriptionHandle,
    HasFactory,
    HasContractRegistry,
    ERC721BurnableUpgradeable,
    ERC721EnumerableUpgradeable
{
    // TODO? store subscription contract in manager for validity check -> isManaged()?

    function mint(
        string calldata _name,
        string calldata _symbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings
    ) external returns (address) {
        address addr = _deploySubscription(_name, _symbol, _metadata, _settings);

        require(_addToRegistry(addr, true), "Handle: Contract already added");

        uint256 tokenId = uint256(uint160(addr));
        _safeMint(_msgSender(), tokenId);

        emit SubscriptionContractCreated(tokenId, addr);
        return addr;
    }

    // useless overrides

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721EnumerableUpgradeable, ERC721Upgradeable)
    {
        super._increaseBalance(account, value);
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721EnumerableUpgradeable, ERC721Upgradeable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721EnumerableUpgradeable, ERC721Upgradeable, IERC165)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}

contract UpgradeableSubscriptionHandle is
    SubscriptionHandle,
    DiamondFactory,
    ContractRegistry,
    ManagingHandle,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    constructor(address beacon) DiamondFactory(beacon) {
        _disableInitializers();
    }

    function initialize(address owner) external initializer {
        __DiamondFactory_init_unchained();
        __Context_init_unchained();
        __ERC721Enumerable_init_unchained();
        __Ownable_init_unchained(owner);
    }

    function _authorizeUpgrade(address) internal virtual override {
        _checkOwner();
    }

    function _safeMint(address to, uint256 tokenId, bytes memory data)
        internal
        override(ERC721Upgradeable, ManagingHandle)
    {
        super._safeMint(to, tokenId, data);
    }
}

// is not upgradeable
contract SimpleSubscriptionHandle is SubscriptionHandle, DiamondFactory, ContractRegistry, ManagingHandle {
    constructor(address beacon) DiamondFactory(beacon) initializer {
        __DiamondFactory_init_unchained();
        __Context_init_unchained();
        __ERC721Enumerable_init_unchained();
    }

    function _safeMint(address to, uint256 tokenId, bytes memory data)
        internal
        override(ERC721Upgradeable, ManagingHandle)
    {
        super._safeMint(to, tokenId, data);
    }
}
