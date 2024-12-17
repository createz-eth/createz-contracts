// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC6551} from "solady/accounts/ERC6551.sol";

contract SimpleErc6551 is ERC6551 {
    string constant NAME = "SUBSUB_TOKEN_ACC";
    string constant VERSION = "1.0.0";

    function _domainNameAndVersion()
        internal
        view
        virtual
        override
        returns (string memory name, string memory version)
    {
        name = NAME;
        version = VERSION;
    }

    function _domainNameAndVersionMayChange() internal pure virtual override returns (bool result) {
        result = true;
    }
}
