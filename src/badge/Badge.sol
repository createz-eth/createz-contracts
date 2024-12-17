// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IBadge.sol";

import {MintAllowedUpgradeable} from "../MintAllowedUpgradeable.sol";
import {HandleOwned, HasHandleOwned} from "../handle/HandleOwned.sol";

import {OzContext, OzContextBind} from "../dependency/OzContext.sol";

import {ERC1155Upgradeable} from "openzeppelin-contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import {ERC1155BurnableUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC1155/extensions/ERC1155BurnableUpgradeable.sol";
import {ERC1155SupplyUpgradeable} from
    "openzeppelin-contracts-upgradeable/token/ERC1155/extensions/ERC1155SupplyUpgradeable.sol";

contract Badge is
    OzContextBind,
    IBadge,
    ERC1155SupplyUpgradeable,
    ERC1155BurnableUpgradeable,
    HandleOwned,
    MintAllowedUpgradeable
{
    struct BadgeStorage {
        mapping(uint256 => TokenData) _tokenData;
        uint256 _nextId;
    }

    // keccak256(abi.encode(uint256(keccak256("subsub.storage.Badge")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BadgeStorageLocation = 0x95c6cf3869da6cb68433b41d6e6d03ced98ce0bbe5df3fce2aaefc3bdb762e00;

    constructor(address handleContract) HandleOwned(handleContract) {
        _disableInitializers();
    }

    function _getBadgeStorage() private pure returns (BadgeStorage storage $) {
        assembly {
            $.slot := BadgeStorageLocation
        }
    }

    function __BadgeUpgradeable_init() internal onlyInitializing {
        __BadgeUpgradeable_init_unchained();
    }

    function __BadgeUpgradeable_init_unchained() internal onlyInitializing {
        BadgeStorage storage $ = _getBadgeStorage();
        $._nextId = 1;
    }

    function initialize() external initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __ERC1155_init_unchained("");
        __ERC1155Supply_init_unchained();
        __ERC1155Burnable_init_unchained();
        __MintAllowedUpgradeable_init_unchained();
        __BadgeUpgradeable_init_unchained();
    }

    function mint(address to, uint256 id, uint256 amount, bytes memory data) external {
        _requireMintAllowed(id);

        BadgeStorage storage $ = _getBadgeStorage();
        require($._tokenData[id].maxSupply - totalSupply(id) >= amount, "Badge: exceeds token's max supply");
        require(type(uint256).max - totalSupply() >= amount, "Badge: exceeds contract's max supply");

        _mint(to, id, amount, data);
    }

    function mintBatch(address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) external {
        BadgeStorage storage $ = _getBadgeStorage();
        for (uint256 i = 0; i < ids.length; i++) {
            _requireMintAllowed(ids[i]);
            require(
                $._tokenData[ids[i]].maxSupply - totalSupply(ids[i]) >= amounts[i], "Badge: exceeds token's max supply"
            );
            require(type(uint256).max - totalSupply() >= amounts[i], "Badge: exceeds contract's max supply");
        }

        _mintBatch(to, ids, amounts, data);
    }

    function burn(address account, uint256 id, uint256 value)
        public
        override(IBadgeOperations, ERC1155BurnableUpgradeable)
    {
        super.burn(account, id, value);
    }

    function burnBatch(address account, uint256[] memory ids, uint256[] memory values)
        public
        override(IBadgeOperations, ERC1155BurnableUpgradeable)
    {
        super.burnBatch(account, ids, values);
    }

    function createToken(TokenData memory tokenData) external onlyOwner returns (uint256 id) {
        require(tokenData.maxSupply > 0, "Badge: new token maxSupply == 0");

        BadgeStorage storage $ = _getBadgeStorage();

        id = $._nextId++;

        $._tokenData[id] = tokenData;

        emit TokenCreated(__msgSender(), id);
    }

    function setMintAllowed(address minter, uint256 id, bool allow)
        public
        override(IMintAllowedUpgradeable, MintAllowedUpgradeable)
        onlyOwner
    {
        super.setMintAllowed(minter, id, allow);
    }

    function _idExists(uint256 id) internal view override returns (bool) {
        return exists(id);
    }

    function exists(uint256 id) public view override returns (bool) {
        BadgeStorage storage $ = _getBadgeStorage();
        return id < $._nextId && id > 0;
    }

    function latestId() external view returns (uint256) {
        BadgeStorage storage $ = _getBadgeStorage();
        return $._nextId - 1;
    }

    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        virtual
        override(ERC1155SupplyUpgradeable, ERC1155Upgradeable)
    {
        super._update(from, to, ids, values);
    }
}
