// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import {ERC6551Registry} from "erc6551/ERC6551Registry.sol";
import {IERC6551Executable} from "erc6551/interfaces/IERC6551Executable.sol";
import {ERC6551Proxy} from "solady/accounts/ERC6551Proxy.sol";
import {SimpleErc6551} from "../src/account/SimpleErc6551.sol";

import {C3Deploy} from "../src/deploy/C3Deploy.sol";
import {Salts} from "../src/deploy/Salts.sol";

import {LibRLP} from "solady/utils/LibRLP.sol";

import {ERC20DecimalsMock} from "../test/mocks/ERC20DecimalsMock.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {DummyPriceFeed} from "../test/mocks/DummyPriceFeed.sol";

import {BadBeaconNotContract} from "openzeppelin-contracts/mocks/proxy/BadBeacon.sol";
import {BeaconProxy} from "openzeppelin-contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IDiamond} from "diamond-1-hardhat/interfaces/IDiamond.sol";

import {DiamondBeaconProxy} from "diamond-beacon/DiamondBeaconProxy.sol";
import {DiamondBeaconUpgradeable} from "diamond-beacon/DiamondBeaconUpgradeable.sol";

import "../src/profile/Profile.sol";
import "../src/subscription/ISubscription.sol";
import "../src/subscription/Subscription.sol";
import "../src/subscription/handle/SubscriptionHandle.sol";
import {BadgeHandle, UpgradeableBadgeHandle} from "../src/badge/handle/BadgeHandle.sol";
import {Badge} from "../src/badge/Badge.sol";

contract TestDataScript is Script {
    C3Deploy private c3;

    MetadataStruct private metadata;
    SubSettings private settings;

    string private anvilSeed = "test test test test test test test test test test test junk";

    address private c3Deployer;
    address private deployer;
    address private alice;
    address private bob;
    address private charlie;
    address private dora;
    address private eve;

    ERC20DecimalsMock private testUsd;

    bytes32 private salt = 0;

    Profile private profile;
    SubscriptionHandle private subHandle;
    BadgeHandle private badgeHandle;

    // ERC6551
    address constant erc6551RegistryAddress = 0x000000006551c19487814612e58FE06813775758;
    ERC6551Registry private erc6551Registry = ERC6551Registry(erc6551RegistryAddress);

    address private erc6551AccountImplementation;
    address private erc6551AccountProxy;

    function setUp() public {
        metadata = MetadataStruct("You gain access to my heart", "https://picsum.photos/800/600", "https://example.com");

        settings.token = address(1);

        uint256 rate = 5 ether;
        settings.rate = rate / 2592000; // $5 per month
        settings.lock = 100;
        settings.epochSize = 60 * 60;
        settings.maxSupply = 10_000;
    }

    function run() public {
        {
            // if no private key is set, we will get a test key
            uint256 deployerKey = vm.deriveKey(anvilSeed, 0);
            uint256 c3DeployerKey = deployerKey;

            c3Deployer = vm.rememberKey(c3DeployerKey);
            deployer = vm.rememberKey(deployerKey);
        }

        {
            //////////////////////////////////////////////////////////////////////
            // DEPLOY C3
            //////////////////////////////////////////////////////////////////////

            c3 = C3Deploy(LibRLP.computeAddress(c3Deployer, 0));
            console.log("C3Deploy", address(c3));

            erc6551AccountProxy = c3.predictAddress("ERC6551Proxy");
            profile = Profile(c3.predictAddress(Salts.PROFILE_KEY));
            subHandle = UpgradeableSubscriptionHandle(c3.predictAddress(Salts.SUBSCRIPTION_HANDLE_KEY));
            badgeHandle = UpgradeableBadgeHandle(c3.predictAddress(Salts.BADGE_HANDLE_KEY));

            //////////////////////////////////////////////////////////////////////
            // DEPLOY TEST DATA
            //////////////////////////////////////////////////////////////////////

            alice = vm.rememberKey(vm.deriveKey(anvilSeed, 1));
            bob = vm.rememberKey(vm.deriveKey(anvilSeed, 2));
            charlie = vm.rememberKey(vm.deriveKey(anvilSeed, 3));
            dora = vm.rememberKey(vm.deriveKey(anvilSeed, 4));
            eve = vm.rememberKey(vm.deriveKey(anvilSeed, 5));

            //////////////////////////////////////////////////////////////////////
            // DEPLOY ERC6551 REGISTRY
            //////////////////////////////////////////////////////////////////////
            vm.startBroadcast(deployer);

            erc6551Registry =
                ERC6551Registry(c3.deploy(abi.encodePacked(type(ERC6551Registry).creationCode), "ERC6551Registry"));

            console.log("ERC6551 Registry", address(erc6551Registry));

            vm.stopBroadcast();
            //////////////////////////////////////////////////////////////////////
            // DEPLOY TEST ERC20 TOKEN
            //////////////////////////////////////////////////////////////////////

            vm.startBroadcast(deployer);

            testUsd = ERC20DecimalsMock(
                c3.deploy(abi.encodePacked(type(ERC20DecimalsMock).creationCode, abi.encode(18)), "TestUSD ERC20")
            );
            console.log("TestUSD ERC20 Token Contract", address(testUsd));
            settings.token = address(testUsd);

            testUsd.mint(deployer, 100_000 ether);
            testUsd.mint(alice, 100_000 ether);
            testUsd.mint(bob, 100_000 ether);
            testUsd.mint(charlie, 100_000 ether);
            testUsd.mint(dora, 100_000 ether);

            vm.stopBroadcast();

            //////////////////////////////////////////////////////////////////////
            // DEPLOY TEST CHAINLINK FEED REGISTRY
            //////////////////////////////////////////////////////////////////////

            vm.startBroadcast(deployer);

            {
                uint8 decimals = 8;
                DummyPriceFeed priceFeed = DummyPriceFeed(
                    c3.deploy(
                        abi.encodePacked(type(DummyPriceFeed).creationCode, abi.encode(decimals)), "TestUSD PriceFeed"
                    )
                );
                console.log("TestUSD Price Feed", address(priceFeed));

                priceFeed.setAnswer(99860888);
            }
            vm.stopBroadcast();

            //////////////////////////////////////////////////////////////////////
            // ALICE's TEST DATA
            //////////////////////////////////////////////////////////////////////

            {
                vm.startBroadcast(alice);
                uint256 pAlice = profile.mint(
                    "Alice",
                    "Hi, I am Alice, a super cool influencer",
                    "https://picsum.photos/id/64/600.jpg",
                    "https://example.com"
                );

                address pAliceAccount =
                    erc6551Registry.createAccount(erc6551AccountProxy, salt, block.chainid, address(profile), pAlice);

                address aliceSubscription1 =
                    createSubscriptionPlanWithErc6551(pAliceAccount, "Tier 1 Sub", "SUBt1", metadata, settings);

                Subscription sub2 = Subscription(
                    createSubscriptionPlanWithErc6551(pAliceAccount, "Tier 2 Sub", "SUBt2", metadata, settings)
                );
                sub2.setFlags(3);

                require(
                    subHandle.ownerOf(uint256(uint160(aliceSubscription1))) == pAliceAccount,
                    "ERC6551 account not the owner"
                );
                vm.stopBroadcast();
                address[3] memory subs = [alice, bob, charlie];
                subscribeTo(subs, aliceSubscription1, 10 ether);
            }

            //////////////////////////////////////////////////////////////////////
            // BOB's TEST DATA
            //////////////////////////////////////////////////////////////////////

            {
                vm.startBroadcast(bob);
                uint256 pBob = profile.mint(
                    "Bob",
                    "Hi, I am Bob, a super cool influencer",
                    "https://picsum.photos/id/91/600.jpg",
                    "https://example.com"
                );

                address pBobAccount =
                    erc6551Registry.createAccount(erc6551AccountProxy, salt, block.chainid, address(profile), pBob);

                address plan = createSubscriptionPlanWithErc6551(pBobAccount, "Tier 1 Sub", "SUBt1", metadata, settings);
                vm.stopBroadcast();
                address[3] memory subs = [alice, charlie, dora];
                subscribeTo(subs, plan, 10 ether);
            }

            //////////////////////////////////////////////////////////////////////
            // CHARLIE's TEST DATA
            //////////////////////////////////////////////////////////////////////

            {
                vm.startBroadcast(charlie);
                uint256 pCharlie = profile.mint(
                    "Charlie",
                    "Hi, I am Charlie, a super cool influencer",
                    "https://picsum.photos/id/399/600.jpg",
                    "https://example.com"
                );

                address pCharlieAccount =
                    erc6551Registry.createAccount(erc6551AccountProxy, salt, block.chainid, address(profile), pCharlie);

                address plan =
                    createSubscriptionPlanWithErc6551(pCharlieAccount, "Tier 1 Sub", "SUBt1", metadata, settings);
                vm.stopBroadcast();
                address[3] memory subs = [alice, bob, dora];
                subscribeTo(subs, plan, 10 ether);
            }

            //////////////////////////////////////////////////////////////////////
            // DORA's TEST DATA
            //////////////////////////////////////////////////////////////////////

            {
                vm.startBroadcast(dora);

                address plan = subHandle.mint("Dora's Tier 1 Sub", "SUBt1", metadata, settings);

                vm.stopBroadcast();

                address[3] memory subs = [alice, bob, charlie];
                subscribeTo(subs, plan, 10 ether);
            }

            //////////////////////////////////////////////////////////////////////
            // EVE's TEST DATA
            //////////////////////////////////////////////////////////////////////

            {
                vm.startBroadcast(eve);
                profile.mint(
                    "Eve",
                    "Hi, I am Eve, a super cool influencer",
                    "https://picsum.photos/id/1062/600.jpg",
                    "https://example.com"
                );

                vm.stopBroadcast();
            }
        }
    }

    function createSubscriptionPlanWithErc6551(
        address acc,
        string memory _name,
        string memory _symbol,
        MetadataStruct memory _metadata,
        SubSettings memory _settings
    ) private returns (address) {
        IERC6551Executable executableAccount = IERC6551Executable(acc);

        bytes memory result = executableAccount.execute(
            address(subHandle),
            0,
            abi.encodeWithSelector(SubscriptionHandle.mint.selector, _name, _symbol, _metadata, _settings),
            0
        );
        return abi.decode(result, (address));
    }

    function subscribeTo(address[3] memory subscribers, address subPlan, uint256 amount) private {
        for (uint256 i = 0; i < subscribers.length && subscribers[i] != address(0); i++) {
            address subscriber = subscribers[i];
            ISubscription plan = ISubscription(subPlan);
            vm.startBroadcast(subscriber);

            testUsd.approve(subPlan, amount);
            plan.mint(amount, 100, "Hello World!");

            vm.stopBroadcast();
        }
    }
}
