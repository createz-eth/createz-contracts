// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {CREATE3} from "solady/utils/CREATE3.sol";

/**
 * @dev simple CREATE3 wrapper to have a constant deployer address independent from the caller
 *
 */
contract C3Deploy {
    mapping(address => bool) public deployers;

    constructor(address initDeployer) {
        deployers[initDeployer] = true;
    }

    modifier onlyDeployer() {
        require(deployers[msg.sender], "Not a deployer");
        _;
    }

    function setDeployer(address newDeployer, bool state) public onlyDeployer {
        deployers[newDeployer] = state;
    }

    function predictAddress(string memory salt) public view returns (address) {
        return CREATE3.predictDeterministicAddress(keccak256(bytes(salt)));
    }

    function deploy(bytes memory initCode, string memory salt) public onlyDeployer returns (address) {
        return CREATE3.deployDeterministic(initCode, keccak256(bytes(salt)));
    }
}
