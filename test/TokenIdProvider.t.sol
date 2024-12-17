// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TokenIdProvider.sol";

import {OzInitializableBind} from "../src/dependency/OzInitializable.sol";

contract TestTokenIdProvider is OzInitializableBind, TokenIdProvider {
    constructor(uint256 _tokenId) initializer {
        __TokenIdProvider_init(_tokenId);
    }

    function nextTokenId() public returns (uint256) {
        return _nextTokenId();
    }
}

contract TokenIdProviderTest is Test {
    TestTokenIdProvider private provider;
    uint256 initId;

    function setUp() public {
        initId = 1;
        provider = new TestTokenIdProvider(initId);
    }

    function testNextTokenId_init(uint256 _id) public {
        _id = bound(_id, 0, type(uint256).max - 1);
        provider = new TestTokenIdProvider(_id);
        assertEq(_id + 1, provider.nextTokenId(), "Token id updated");
    }

    function testNextTokenId_increment() public {
        for (uint256 i = 1; i <= 20; i++) {
            assertEq(initId + i, provider.nextTokenId(), "Token id updated");
        }
    }
}
