// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @dev internal interface exposing OZ {Initializable} methods without binding
 * to the implementation. The actually implementation needs to be overriden
 * later.
 */
abstract contract OzInitializable {
    function __checkInitializing() internal view virtual;
}

abstract contract OzInitializableBind is OzInitializable, Initializable {
    function __checkInitializing() internal view virtual override {
        _checkInitializing();
    }
}
