// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {ManagingHandle} from "../../src/handle/ManagingHandle.sol";

import "../mocks/TestSubscription.sol";

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

interface MintingEvent {

  event Minted(
    address indexed to, uint256 indexed tokenId
  );
}

contract TestManagingHandle is ManagingHandle, MintingEvent {
    struct Details {
        bool set;
        bool managed;
    }

    mapping(address => Details) public registry;

    using Strings for string;


    function _addToRegistry(address addr, bool isManaged) internal override returns (bool set) {
        set = !registry[addr].set;
        registry[addr].set = true;
        registry[addr].managed = isManaged;
    }

    function _isManaged(address addr) internal view override returns (bool) {
        return registry[addr].managed;
    }

    function _safeMint(address to, uint256 tokenId, bytes memory) internal override {
      emit Minted(to, tokenId);
    }

    function setManaged(address addr, bool isManaged) public {
      registry[addr].set = true;
      registry[addr].managed = isManaged;
    }
}

contract ManagingHandleTest is Test, MintingEvent {
    TestManagingHandle private handle;

    address private user;

    function setUp() public {
        handle = new TestManagingHandle();
        user = address(10001);
    }


    function testRegister(address addr) public {
        vm.startPrank(user); // not a contract!

        uint256 tokenId = uint256(uint160(addr));

        vm.expectEmit();
        emit Minted(user, tokenId);

        handle.register(addr);
        assertFalse(handle.isManaged(tokenId), "registered contract marked as unmanaged");
    }

    function testRegister_twice(address addr) public {
        vm.startPrank(user); // not a contract!

        vm.expectEmit();
        emit Minted(user, uint256(uint160(addr)));

        handle.register(addr);

        vm.expectRevert();
        handle.register(addr);
    }

    function testManaged(address addr, bool managed) public {
        handle.setManaged(addr, managed);

        assertEq(handle.isManaged(uint256(uint160(addr))), managed, "managed value set");
    }

    function testManaged_largeValue(uint256 tokenId) public {
        tokenId = bound(tokenId, uint256(type(uint160).max) + 1, type(uint256).max);

        assertFalse(handle.isManaged(tokenId), "out of bounds tokenId is always false");
    }
}
