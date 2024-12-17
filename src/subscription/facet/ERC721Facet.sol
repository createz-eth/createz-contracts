// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OzERC721Enumerable, OzERC721EnumerableBind} from "../../dependency/OzERC721Enumerable.sol";

abstract contract AbstractERC721Facet {}

/**
 * @dev exports OZ ERC721 vanilla
 *
 */
contract ERC721Facet is OzERC721EnumerableBind, AbstractERC721Facet {}
