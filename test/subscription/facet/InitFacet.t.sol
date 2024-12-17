// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../../src/subscription/facet/InitFacet.sol";

import {FacetConfig} from "../../../src/subscription/FacetConfig.sol";

import {PropertiesFacet} from "../../../src/subscription/facet/PropertiesFacet.sol";
import {ERC721Facet} from "../../../src/subscription/facet/ERC721Facet.sol";

import {MetadataStruct, SubSettings, ISubscriptionInternal} from "../../../src/subscription/ISubscription.sol";

import {IDiamond} from "diamond-1-hardhat/interfaces/IDiamond.sol";

import {DiamondBeaconProxy} from "diamond-beacon/DiamondBeaconProxy.sol";
import {DiamondBeacon} from "diamond-beacon/DiamondBeacon.sol";
import {FacetHelper} from "diamond-beacon/util/FacetHelper.sol";

import {ERC20DecimalsMock} from "../../mocks/ERC20DecimalsMock.sol";
import {ERC721Mock} from "../../mocks/ERC721Mock.sol";

contract InitFacetTest is Test {
    using FacetHelper for IDiamond.FacetCut[];
    using FacetHelper for bytes4[];

    FacetConfig public config;

    ISubscriptionInternal public sub;
    InitFacet public impl;
    PropertiesFacet public propFacet;
    ERC721Facet public erc721Facet;
    ERC721Mock public handleContract;

    address public owner;

    ERC20DecimalsMock public testToken;

    string public name;
    string public symbol;
    MetadataStruct public metadata;
    SubSettings public settings;
    uint256 public rate;
    uint24 public lock;
    uint64 public epochSize;
    uint256 public maxSupply;

    uint8 public decimals;

    function setUp() public {
        config = new FacetConfig();

        owner = address(10);
        metadata = MetadataStruct("description", "image", "externalUrl");
        rate = 5;
        lock = 100;
        epochSize = 10;
        maxSupply = 10_000;
        decimals = 12;

        testToken = new ERC20DecimalsMock(decimals);
        handleContract = new ERC721Mock("handle", "HANDLE");

        settings = SubSettings(address(testToken), rate, lock, epochSize, maxSupply);

        createSub();
        sub.initialize(name, symbol, metadata, settings);
    }

    function createSub() public {
        impl = new InitFacet();
        propFacet = new PropertiesFacet(address(handleContract));
        erc721Facet = new ERC721Facet();

        IDiamond.FacetCut[] memory cuts = config.initFacet(impl).asAddCut(address(impl)).concat(
            config.propertiesFacet(propFacet).asAddCut(address(propFacet))
        ).concat(config.erc721Facet(erc721Facet).asAddCut(address(erc721Facet)));

        DiamondBeacon beacon = new DiamondBeacon(owner, cuts);
        DiamondBeaconProxy proxy = new DiamondBeaconProxy(address(beacon), "");
        sub = ISubscriptionInternal(address(proxy));

        handleContract.mint(owner, uint256(uint160(address(sub))));
    }

    function testConstruct_initializerDisabledOnImpl() public {
        vm.expectRevert();
        impl.initialize("name", "symbol", metadata, settings);
    }

    function testInit() public view {
        assertEq(sub.name(), name, "name");
        assertEq(sub.symbol(), symbol, "symbol");
        assertEq(sub.symbol(), symbol, "symbol");

        {
            (address _token, uint256 _rate, uint24 _lock, uint256 _epochSize, uint256 _maxSupply) = sub.settings();

            assertEq(_token, address(testToken), "token");
            assertEq(_rate, rate, "rate");
            assertEq(_lock, lock, "lock");
            assertEq(_epochSize, epochSize, "epochSize");
            assertEq(_maxSupply, maxSupply, "maxSupply");
        }
        {
            (string memory _description, string memory _image, string memory _externalUrl) = sub.metadata();

            assertEq(_description, metadata.description, "description");
            assertEq(_image, metadata.image, "image");
            assertEq(_externalUrl, metadata.externalUrl, "externalUrl");
        }
        {
            (address _token, uint256 _rate, uint24 _lock, uint256 _epochSize, uint256 _maxSupply) = sub.settings();

            assertEq(_token, address(testToken), "token");
            assertEq(_rate, rate, "rate");
            assertEq(_lock, lock, "lock");
            assertEq(_epochSize, epochSize, "epochSize");
            assertEq(_maxSupply, maxSupply, "maxSupply");
        }
    }

    function testConstruct_not0rate() public {
        settings.rate = 0;

        createSub();

        vm.expectRevert("SUB: rate cannot be 0");
        sub.initialize(name, symbol, metadata, settings);
    }

    function testConstruct_not0epochSize() public {
        settings.epochSize = 0;

        createSub();

        vm.expectRevert("SUB: invalid epochSize");
        sub.initialize(name, symbol, metadata, settings);
    }

    function testConstruct_lockTooLarge(uint24 lock_) public {
        lock_ = uint24(bound(lock_, SubLib.LOCK_BASE + 1, type(uint24).max));
        settings.lock = lock_;

        createSub();

        vm.expectRevert("SUB: lock percentage out of range");
        sub.initialize(name, symbol, metadata, settings);
    }
}
