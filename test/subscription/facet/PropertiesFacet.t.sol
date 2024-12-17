// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {PropertiesFacet} from "../../../src/subscription/facet/PropertiesFacet.sol";

import {
    SubscriptionEvents,
    ClaimEvents,
    MetadataStruct,
    SubSettings,
    SubscriptionFlags
} from "../../../src/subscription/ISubscription.sol";

import {HasUserData, UserData} from "../../../src/subscription/UserData.sol";
import {HasEpochs, Epochs} from "../../../src/subscription/Epochs.sol";
import {HasBaseSubscription, BaseSubscription} from "../../../src/subscription/BaseSubscription.sol";

import {HasHandleOwned, HandleOwned} from "../../../src/handle/HandleOwned.sol";
import {IOwnable} from "../../../src/IOwnable.sol";

import {ERC20DecimalsMock} from "../../mocks/ERC20DecimalsMock.sol";

contract PropertiesFacetTest is Test, SubscriptionEvents, ClaimEvents, SubscriptionFlags {
    event MetadataUpdate(uint256 _tokenId);

    PropertiesSub public sub;

    address public owner;
    address public alice;
    address public bob;

    ERC20DecimalsMock public testToken;

    MetadataStruct public metadata;
    SubSettings public settings;
    uint256 public rate;
    uint24 public lock;
    uint256 public epochSize;
    uint256 public maxSupply;

    uint8 public decimals;

    function setUp() public {
        owner = address(10);
        alice = address(11);
        bob = address(12);
        metadata = MetadataStruct("description", "image", "externalUrl");
        rate = 5;
        lock = 100;
        epochSize = 10;
        maxSupply = 10_000;
        decimals = 12;

        testToken = new ERC20DecimalsMock(decimals);
        testToken.mint(alice, 10_000_000_000 ether);
        // bob does not receive tokens

        settings = SubSettings(address(testToken), rate, lock, epochSize, maxSupply);
        sub = new PropertiesSub(owner, "name", "symbol", metadata);
    }

    function testSetExternalUrl() public {
        string memory url = "something else";
        vm.prank(owner);
        sub.setExternalUrl(url);

        (,, string memory externalUrl) = sub.metadata();

        assertEq(url, externalUrl);
    }

    function testSetExternalUrl_notOwner() public {
        vm.startPrank(alice);

        vm.expectRevert();
        sub.setExternalUrl("meh");
    }

    function testSetImage() public {
        string memory newImage = "something else";
        vm.prank(owner);
        sub.setImage(newImage);

        (, string memory image,) = sub.metadata();

        assertEq(newImage, image);
    }

    function testSetImage_notOwner() public {
        vm.startPrank(alice);

        vm.expectRevert();
        sub.setImage("meh");
    }

    function testSetDescription() public {
        string memory desc = "something else";
        vm.prank(owner);
        sub.setDescription(desc);

        (string memory description,,) = sub.metadata();

        assertEq(desc, description);
    }

    function testSetDescription_notOwner() public {
        string memory desc = "something else";
        vm.startPrank(alice);

        vm.expectRevert();
        sub.setDescription(desc);
    }

    function testSetFlags(uint256 flags) public {
        flags = bound(flags, 0, ALL_FLAGS);
        vm.prank(owner);
        sub.setFlags(flags);
    }

    function testSetFlags_invalid(uint256 flags) public {
        flags = bound(flags, ALL_FLAGS + 1, type(uint256).max);
        vm.startPrank(alice);

        vm.expectRevert();
        sub.setFlags(flags);
    }

    function testSetFlags_notOwner() public {
        uint256 flags = 1;
        vm.startPrank(alice);

        vm.expectRevert();
        sub.setFlags(flags);
    }
}

contract PropertiesSub is PropertiesFacet {
    address private _owner;

    constructor(address owner_, string memory tokenName, string memory tokenSymbol, MetadataStruct memory _metadata)
        PropertiesFacet(address(0))
        initializer
    {
        _owner = owner_;
        __ERC721_init_unchained(tokenName, tokenSymbol);
        __Metadata_init_unchained(_metadata.description, _metadata.image, _metadata.externalUrl);
    }

    // override HandleOwned
    function _checkOwner() internal view override(HasHandleOwned, HandleOwned) {
        require(_msgSender() == _owner, "Not Owner");
    }

    function _isValidSigner(address acc) internal view override(HasHandleOwned, HandleOwned) returns (bool) {
        return acc == _owner;
    }

    function owner() public view override(IOwnable, HandleOwned) returns (address) {
        return _owner;
    }

    function _disableInitializers() internal override {}
}
