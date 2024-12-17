// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/profile/Profile.sol";

import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

// TODO test mint/renew with amount==0
contract ProfileTest is Test {
    event Minted(address indexed to, uint256 indexed tokenId);

    Profile public profile;
    Profile public implementation;

    address public alice;
    address public bob;
    address public owner;

    function setUp() public {
        alice = address(10);
        bob = address(20);
        owner = address(1234);

        implementation = new Profile();
        profile =
            Profile(address(new ERC1967Proxy(address(implementation), abi.encodeCall(Profile.initialize, (owner)))));
    }

    function testMetadata() public view {
        assertEq(implementation.name(), "", "name is not set on implementation");
        assertEq(implementation.symbol(), "", "symbol is not set on implementation");

        assertEq(profile.name(), "SubSub Profile", "name is set");
        assertEq(profile.symbol(), "subP", "symbol is set");
    }

    function testMint() public {
        vm.startPrank(alice);

        vm.expectEmit();
        emit Minted(alice, 1);
        uint256 aliceTokenId = profile.mint("test", "test", "test", "test");

        assertEq(profile.ownerOf(aliceTokenId), alice, "alice minted a token");
        assertEq(profile.totalSupply(), 1, "1 token minted");

        vm.startPrank(bob);

        vm.expectEmit();
        emit Minted(bob, 2);
        uint256 bobTokenId = profile.mint("test", "test", "test", "test");
        assertEq(profile.ownerOf(bobTokenId), bob, "bob minted a token");

        assertLt(aliceTokenId, bobTokenId, "token ids are unique");

        assertEq(profile.totalSupply(), 2, "2 tokens minted");
    }

    function testUpgrade() public {
        // initialized
        assertEq(owner, profile.owner(), "Owner set in initializer");

        address newImpl = address(new Profile());
        vm.prank(owner);
        profile.upgradeToAndCall(newImpl, "");
    }

    function testUpgrade_notAuthorized(address user) public {
        vm.assume(owner != user);
        assumePayable(user);
        assumeNotPrecompile(user);

        address newImpl = address(new Profile());
        vm.prank(user);
        vm.expectRevert();
        profile.upgradeToAndCall(newImpl, "");
    }

    function testInitilizer_disabled() public {
        vm.expectRevert();
        implementation.initialize(address(0));
    }
}
