// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ContextUpgradeable} from "openzeppelin-contracts-upgradeable/utils/ContextUpgradeable.sol";

/**
 * @dev internal interface exposing OZ {Context} methods without binding to
 * the implementation. The actually implementation needs to be overriden later.
 */
abstract contract OzContext {
    function __msgSender() internal view virtual returns (address);
}

abstract contract OzContextBind is OzContext, ContextUpgradeable {
    function __msgSender() internal view virtual override returns (address) {
        return _msgSender();
    }
}
