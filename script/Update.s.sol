// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import {ERC6551Proxy} from "solady/accounts/ERC6551Proxy.sol";
import {SimpleErc6551} from "../src/account/SimpleErc6551.sol";

import {C3Deploy} from "../src/deploy/C3Deploy.sol";
import {Salts} from "../src/deploy/Salts.sol";

import {LibRLP} from "solady/utils/LibRLP.sol";

import {UpgradeableBeacon} from "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IDiamond} from "diamond-1-hardhat/interfaces/IDiamond.sol";

import {DiamondBeaconUpgradeable} from "diamond-beacon/DiamondBeaconUpgradeable.sol";

import {FacetHelper} from "diamond-beacon/util/FacetHelper.sol";

import {FacetConfig} from "../src/subscription/FacetConfig.sol";

import {InitFacet} from "../src/subscription/facet/InitFacet.sol";
import {PropertiesFacet} from "../src/subscription/facet/PropertiesFacet.sol";
import {ERC721Facet} from "../src/subscription/facet/ERC721Facet.sol";
import {BurnableFacet} from "../src/subscription/facet/BurnableFacet.sol";
import {ClaimableFacet} from "../src/subscription/facet/ClaimableFacet.sol";
import {DepositableFacet} from "../src/subscription/facet/DepositableFacet.sol";
import {MetadataFacet} from "../src/subscription/facet/MetadataFacet.sol";
import {WithdrawableFacet} from "../src/subscription/facet/WithdrawableFacet.sol";

import "../src/profile/Profile.sol";
import "../src/subscription/ISubscription.sol";
import "../src/subscription/Subscription.sol";
import "../src/subscription/handle/SubscriptionHandle.sol";
import {BadgeHandle, UpgradeableBadgeHandle} from "../src/badge/handle/BadgeHandle.sol";
import {Badge} from "../src/badge/Badge.sol";

contract UpdateScript is Script {
    using FacetHelper for IDiamond.FacetCut[];
    using FacetHelper for bytes4[];

    C3Deploy private c3;

    string private anvilSeed = "test test test test test test test test test test test junk";

    address private c3Deployer;
    address private deployer;

    Profile private profile;
    UpgradeableSubscriptionHandle private subHandle;
    DiamondBeaconUpgradeable private subscriptionBeacon;
    UpgradeableBadgeHandle private badgeHandle;
    UpgradeableBeacon private badgeBeacon;

    address private erc6551AccountImplementation;
    address private erc6551AccountBeacon;

    function run() public {
        {
            uint256 c3DeployerKey = vm.envOr("C3_PRIVATE_KEY", uint256(0));
            uint256 deployerKey = vm.envOr("PRIVATE_KEY", uint256(0));

            if (deployerKey == 0 && c3DeployerKey == 0) {
                // if no private key is set, we will get a test key
                deployerKey = vm.deriveKey(anvilSeed, 0);
                c3DeployerKey = deployerKey;
            }

            require(deployerKey != 0 && c3DeployerKey != 0, "Deployer keys not set properly");

            c3Deployer = vm.rememberKey(c3DeployerKey);
            deployer = vm.rememberKey(deployerKey);
        }

        {
            //////////////////////////////////////////////////////////////////////
            // DEPLOY C3
            //////////////////////////////////////////////////////////////////////

            c3 = C3Deploy(LibRLP.computeAddress(c3Deployer, 0));
            console.log("C3Deploy", address(c3));

            erc6551AccountBeacon = c3.predictAddress("ERC6551AccountBeacon");
            profile = Profile(c3.predictAddress(Salts.PROFILE_KEY));
            subHandle = UpgradeableSubscriptionHandle(c3.predictAddress(Salts.SUBSCRIPTION_HANDLE_KEY));
            subscriptionBeacon = DiamondBeaconUpgradeable(c3.predictAddress(Salts.SUBSCRIPTION_BEACON_KEY));
            badgeHandle = UpgradeableBadgeHandle(c3.predictAddress(Salts.BADGE_HANDLE_KEY));
            badgeBeacon = UpgradeableBeacon(c3.predictAddress(Salts.BADGE_BEACON_KEY));

            // simple Test Deployment

            vm.startBroadcast(deployer);

            //////////////////////////////////////////////////////////////////////
            // DEPLOY ERC6551 Account
            //////////////////////////////////////////////////////////////////////

            erc6551AccountImplementation = address(new SimpleErc6551());
            console.log("ERC6551 Account Implementation", erc6551AccountImplementation);

            UpgradeableBeacon(erc6551AccountBeacon).upgradeTo(erc6551AccountImplementation);
            console.log("ERC6551 Account Beacon", erc6551AccountBeacon);

            //////////////////////////////////////////////////////////////////////
            // DEPLOY PROFILE
            //////////////////////////////////////////////////////////////////////

            address profileImplementation = address(new Profile());

            profile.upgradeToAndCall(profileImplementation, "");

            console.log("Profile Contract Implementation", profileImplementation);
            console.log("Profile Contract Proxy", address(profile));

            //////////////////////////////////////////////////////////////////////
            // DEPLOY SUBSCRIPTION + SUBSCRIPTION_HANDLE
            //////////////////////////////////////////////////////////////////////

            {
                {
                    address impl = address(new UpgradeableSubscriptionHandle(address(subscriptionBeacon)));
                    subHandle.upgradeToAndCall(impl, "");
                }

                IDiamond.FacetCut[] memory cuts;
                // create Subscription Facets with a reference to the CORRECT handle proxy
                {
                    FacetConfig config = new FacetConfig();
                    {
                        InitFacet init = new InitFacet();
                        console.log("Subscription InitFacet", address(init));
                        cuts = config.initFacet(init).asReplaceCut(address(init));
                    }
                    {
                        PropertiesFacet props = new PropertiesFacet(address(subHandle));
                        console.log("Subscription PropertiesFacet", address(props));
                        cuts = cuts.concat(config.propertiesFacet(props).asReplaceCut(address(props)));
                    }
                    {
                        ERC721Facet erc721 = new ERC721Facet();
                        console.log("Subscription ERC721Facet", address(erc721));
                        cuts = cuts.concat(config.erc721Facet(erc721).asReplaceCut(address(erc721)));
                    }
                    {
                        BurnableFacet burn = new BurnableFacet();
                        console.log("Subscription BurnableFacet", address(burn));
                        cuts = cuts.concat(config.burnableFacet(burn).asReplaceCut(address(burn)));
                    }
                    {
                        ClaimableFacet claim = new ClaimableFacet(address(subHandle));
                        console.log("Subscription ClaimableFacet", address(claim));
                        cuts = cuts.concat(config.claimableFacet(claim).asReplaceCut(address(claim)));
                    }
                    {
                        DepositableFacet deposit = new DepositableFacet();
                        console.log("Subscription DepositableFacet", address(deposit));
                        cuts = cuts.concat(config.depositableFacet(deposit).asReplaceCut(address(deposit)));
                    }
                    {
                        MetadataFacet meta = new MetadataFacet();
                        console.log("Subscription MetadataFacet", address(meta));
                        cuts = cuts.concat(config.metadataFacet(meta).asReplaceCut(address(meta)));
                    }
                    {
                        WithdrawableFacet withdraw = new WithdrawableFacet();
                        console.log("Subscription WithdrawableFacet", address(withdraw));
                        cuts = cuts.concat(config.withdrawableFacet(withdraw).asReplaceCut(address(withdraw)));
                    }
                }

                address subBeaconImpl = address(new DiamondBeaconUpgradeable());

                subscriptionBeacon.upgradeToAndCall(subBeaconImpl, "");
                subscriptionBeacon.diamondCut(cuts, address(0), "");

                console.log("Subscription Beacon Implementation", subBeaconImpl);
                console.log("Subscription Beacon Proxy", address(subscriptionBeacon));

                console.log("SubHandle Proxy Contract", address(subHandle));
            }

            //////////////////////////////////////////////////////////////////////
            // DEPLOY BADGE + BADGE HANDLE
            //////////////////////////////////////////////////////////////////////

            {
                {
                    address impl = address(new UpgradeableBadgeHandle(address(badgeBeacon)));
                    badgeHandle.upgradeToAndCall(impl, "");
                }

                address badgeImplementation = address(new Badge(address(badgeHandle)));
                badgeBeacon.upgradeTo(badgeImplementation);

                console.log("BadgeHandle Proxy Contract", address(badgeHandle));

                console.log("Badge Implementation", address(badgeImplementation));
                console.log("Badge Beacon", address(badgeBeacon));
            }

            // end test deployment
            vm.stopBroadcast();
        }
    }
}
