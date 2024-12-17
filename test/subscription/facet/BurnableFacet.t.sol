// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {BurnableFacet} from "../../../src/subscription/facet/BurnableFacet.sol";
import {ERC721Facet} from "../../../src/subscription/facet/ERC721Facet.sol";

import {DiamondBeaconProxy} from "diamond-beacon/DiamondBeaconProxy.sol";
import {DiamondBeacon} from "diamond-beacon/DiamondBeacon.sol";
import {FacetHelper} from "diamond-beacon/util/FacetHelper.sol";

import {FacetConfig} from "../../../src/subscription/FacetConfig.sol";
import {IDiamond} from "diamond-1-hardhat/interfaces/IDiamond.sol";

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

import {ERC20DecimalsMock} from "../../mocks/ERC20DecimalsMock.sol";

contract BurnableFacetTest is Test, SubscriptionEvents, ClaimEvents, SubscriptionFlags {
    using FacetHelper for IDiamond.FacetCut[];
    using FacetHelper for bytes4;
    using FacetHelper for bytes4[];

    FacetConfig public config;

    event MetadataUpdate(uint256 _tokenId);

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
        config = new FacetConfig();

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
    }

    function createSub() private returns (BurnSub) {
        BurnSub impl = new BurnSub();
        ERC721Facet erc721Facet = new ERC721Facet();

        bytes4[] memory simpleMint = impl.simpleMint.selector.asArray();

        IDiamond.FacetCut[] memory cuts = config.burnableFacet(impl).asAddCut(address(impl)).concat(
            config.erc721Facet(erc721Facet).asAddCut(address(erc721Facet)).concat(simpleMint.asAddCut(address(impl)))
        );

        DiamondBeacon beacon = new DiamondBeacon(owner, cuts);
        DiamondBeaconProxy proxy = new DiamondBeaconProxy(address(beacon), "");

        return BurnSub(address(proxy));
    }

    function testBurn(uint256 tokenId) public {
        BurnSub _sub = createSub();

        _sub.simpleMint(alice, tokenId);

        assertEq(_sub.totalSupply(), 1, "Token created");
        assertEq(_sub.balanceOf(alice), 1, "Token created to user");

        vm.prank(alice);
        vm.expectEmit();
        emit Burned(tokenId);

        _sub.burn(tokenId);

        assertEq(_sub.totalSupply(), 0, "Token burned");
        assertEq(_sub.balanceOf(alice), 0, "Token burned from user");
    }

    function testBurn_notOwner(uint256 tokenId, address user) public {
        vm.assume(alice != user && user != address(this));
        BurnSub _sub = createSub();

        _sub.simpleMint(alice, tokenId);

        assertEq(_sub.balanceOf(alice), 1, "Token created to user");

        vm.startPrank(user);
        vm.expectRevert();
        _sub.burn(tokenId);
    }

    function testBurn_twice(uint256 tokenId) public {
        BurnSub _sub = createSub();

        _sub.simpleMint(alice, tokenId);

        vm.prank(alice);

        _sub.burn(tokenId);

        vm.expectRevert();
        _sub.burn(tokenId);
    }
}

event Burned(uint256 indexed tokenId);

contract BurnSub is BurnableFacet {
    constructor() {}

    function _deleteSubscription(uint256 tokenId) internal override(HasUserData, UserData) {
        emit Burned(tokenId);
    }

    // helpers
    function simpleMint(address to, uint256 tokenId) external {
        _safeMint(to, tokenId);
    }
}
