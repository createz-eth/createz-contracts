// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import {IERC6551Account} from "erc6551/interfaces/IERC6551Account.sol";

import {OzContext} from "../dependency/OzContext.sol";

import {IOwnable} from "../IOwnable.sol";

interface HandleOwnedErrors {
    error UnauthorizedAccount(address account);
}

abstract contract HasHandleOwned is IOwnable, HandleOwnedErrors {
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function _checkOwner() internal view virtual;

    function _isValidSigner(address acc) internal view virtual returns (bool);
}

abstract contract HandleOwned is OzContext, HasHandleOwned {
    address private immutable _handleContract;

    constructor(address handleContract) {
        _handleContract = handleContract;
    }

    function _checkOwner() internal view virtual override {
        address owner_ = owner();
        if (owner_ != __msgSender() && !_isValidSigner(owner_)) {
            revert UnauthorizedAccount(__msgSender());
        }
    }

    function _isValidSigner(address acc) internal view virtual override returns (bool) {
        // is the owner a contract?
        address payable acc_ = payable(acc);
        if (acc_.code.length > 0) {
            // does the owner contract implement the interface
            try IERC6551Account(acc_).isValidSigner(__msgSender(), "") returns (bytes4 magicValue) {
                return magicValue == 0x523e3260;
            } catch {
                return false;
            }
        }
        return false;
    }

    function owner() public view virtual override returns (address) {
        return IERC721(_handleContract).ownerOf(uint256(uint160(address(this))));
    }
}
