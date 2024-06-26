// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

interface FlagEvents {
    event FlagSet(address account, uint256 flag, uint256 newFlags);
}

abstract contract HasFlagSettings {
    function _setFlags(uint256 flags) internal virtual;

    function flagsEnabled(uint256 flags) public view virtual returns (bool);

    function getFlags() public view virtual returns (uint256);

    function _requireDisabled(uint256 flag) internal view virtual {
        require(!flagsEnabled(flag), "Flag: setting enabled");
    }

    function _requireEnabled(uint256 flag) internal view virtual {
        require(flagsEnabled(flag), "Flag: setting disabled");
    }

    modifier whenDisabled(uint256 flags) virtual {
        _requireDisabled(flags);
        _;
    }

    modifier whenEnabled(uint256 flags) virtual {
        _requireEnabled(flags);
        _;
    }
}

abstract contract FlagSettings is Initializable, ContextUpgradeable, FlagEvents, HasFlagSettings {
    struct FlagStorage {
        uint256 _flags;
    }

    // keccak256(abi.encode(uint256(keccak256("createz.storage.FlagSettings")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FlagStorageLocation = 0xef76360c7e011776eb025551396387367250d165806b070a47601953eabbc300;

    function _getFlagStorage() private pure returns (FlagStorage storage $) {
        assembly {
            $.slot := FlagStorageLocation
        }
    }

    function __FlagSettings_init() internal onlyInitializing {
        __FlagSettings_init_unchained();
    }

    function __FlagSettings_init_unchained() internal onlyInitializing {
        FlagStorage storage $ = _getFlagStorage();
        $._flags = 0;
    }

    function _setFlags(uint256 flags) internal override {
        FlagStorage storage $ = _getFlagStorage();
        uint256 oldFlags = $._flags;
        $._flags = flags;
        emit FlagSet(_msgSender(), flags, oldFlags);
    }

    function flagsEnabled(uint256 flags) public view override returns (bool) {
        FlagStorage storage $ = _getFlagStorage();
        return ($._flags & flags) == flags;
    }

    function getFlags() public view override returns (uint256) {
        FlagStorage storage $ = _getFlagStorage();
        return $._flags;
    }
}
