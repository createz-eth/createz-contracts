// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/subscription/handle/Factory.sol";
import "../../../src/subscription/Subscription.sol";
import "../../../src/subscription/ISubscription.sol";

import {Strings} from "openzeppelin-contracts/utils/Strings.sol";

import {DiamondBeacon} from "diamond-beacon/DiamondBeacon.sol";

import {IDiamond} from "diamond-1-hardhat/interfaces/IDiamond.sol";
import {FacetHelper} from "diamond-beacon/util/FacetHelper.sol";

contract TestFactory is DiamondFactory {
    constructor(address beacon) DiamondFactory(beacon) initializer {
        __DiamondFactory_init();
    }

    function deploySubscription(
        string calldata _name,
        string calldata _symbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings
    ) public returns (address) {
        return super._deploySubscription(_name, _symbol, _metadata, _settings);
    }
}

contract TestSubscriptionInitialize is SubscriptionInitialize {
    using Strings for string;

    function initialize(string calldata tokenName, string calldata, MetadataStruct calldata, SubSettings calldata)
        external
        pure
    {
        require(!tokenName.equal("fail"), "failing");
    }

    function hello() public pure returns (string memory) {
        return "world";
    }
}

contract FactoryTest is Test {
    using FacetHelper for IDiamond.FacetCut[];
    using FacetHelper for bytes4;
    using FacetHelper for bytes4[];

    TestFactory private factory;

    DiamondBeacon private beacon;
    TestSubscriptionInitialize private subscription;

    MetadataStruct private metadata;
    SubSettings private settings;

    function setUp() public {
        subscription = new TestSubscriptionInitialize();
        IDiamond.FacetCut[] memory cuts = subscription.initialize.selector.asArray().asAddCut(address(subscription))
            .concat(subscription.hello.selector.asArray().asAddCut(address(subscription)));

        beacon = new DiamondBeacon(address(this), cuts);
        factory = new TestFactory(address(beacon));

        metadata = MetadataStruct("test", "test", "test");
        settings.token = address(1234);
        settings.rate = 1;
        settings.lock = 10;
        settings.epochSize = 100;
    }

    function testCreateSubscription() public {
        address result = factory.deploySubscription("test", "test", metadata, settings);

        assertTrue(result != address(0), "new contract deployed");
        assertFalse(address(subscription) == result, "subscription at new address");
        assertEq(subscription.hello(), TestSubscriptionInitialize(result).hello(), "subscription deployed");
    }

    function testCreateSubscription_initFail() public {
        vm.expectRevert();
        factory.deploySubscription("fail", "test", metadata, settings);
    }
}
