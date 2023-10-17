// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ISubscriptionManager.sol";
import "../src/SubscriptionManager.sol";
import "../src/subscription/Subscription.sol";
import "../src/subscription/ISubscription.sol";

import "./mocks/TestSubscription.sol";
import "./mocks/ERC20DecimalsMock.sol";

import {ERC721Mock} from "./mocks/ERC721Mock.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";

import {UpgradeableBeacon} from "openzeppelin-contracts/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SubscriptionManagerTest is Test, SubscriptionManagerEvents {
    using Address for address;

    SubscriptionManager private manager;

    ERC20DecimalsMock private token;

    ERC721Mock private profile;
    uint256 private profileTokenId;

    IBeacon private beacon;
    Subscription private subscription;

    MetadataStruct private metadata;
    SubSettings private settings;

    address[] private createdContracts; // side effect?

    function setUp() public {
        subscription = new TestSubscription();
        beacon = new UpgradeableBeacon(address(subscription), address(this));
        profile = new ERC721Mock("test", "test");
        profileTokenId = 10;
        token = new ERC20DecimalsMock(18);

        metadata = MetadataStruct("test", "test", "test");
        settings.token = token;
        settings.rate = 1;
        settings.lock = 10;
        settings.epochSize = 100;

        profile.mint(address(this), profileTokenId);

        SubscriptionManager impl = new SubscriptionManager();

        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        manager = SubscriptionManager(address(proxy));
        manager.initialize(address(beacon), address(profile));
    }

    function testProfileContract() public {
        assertEq(address(profile), manager.profileContract(), "Profile contract set");
    }

    function testCreateSubscription() public {
        vm.expectEmit(true, false, false, false);
        emit SubscriptionContractCreated(profileTokenId, address(0));

        settings.token = token;

        address result = manager.createSubscription("My Subscription", "SUB", metadata, settings, profileTokenId);
        assertFalse(result == address(0), "contract not created");

        (IERC20Metadata resToken,,,,) = Subscription(result).settings();
        assertEq(address(token), address(resToken), "new contract initialized, token is set");

        address[] memory contracts = manager.getSubscriptionContracts(profileTokenId);
        address[] memory res = new address[](1);
        res[0] = result;
        assertEq(contracts, res, "contracts stored");
    }

    function testCreateSubscription_notTokenOwner() public {
        vm.expectRevert("Manager: Not owner of token");
        vm.startPrank(address(1234));

        manager.createSubscription("My Subscription", "SUB", metadata, settings, profileTokenId);
    }

    function testCreateSubscription_multipleContracts() public {
        settings.token = IERC20Metadata(token);

        for (uint256 i = 0; i < 100; i++) {
            address result = manager.createSubscription("My Subscription", "SUB", metadata, settings, profileTokenId);
            assertFalse(result == address(0), "contract not created");

            (IERC20Metadata resToken,,,,) = Subscription(result).settings();
            assertEq(address(token), address(resToken), "new contract initialized, token is set");
            createdContracts.push(result);
        }

        address[] memory contracts = manager.getSubscriptionContracts(profileTokenId);
        address[] memory _createdContracts = createdContracts;
        assertEq(contracts, _createdContracts, "contracts stored");
    }
}
