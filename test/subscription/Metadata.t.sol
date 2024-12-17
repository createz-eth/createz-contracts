// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {OzInitializableBind} from "../../src/dependency/OzInitializable.sol";

import {ERC20DecimalsMock} from "../mocks/ERC20DecimalsMock.sol";
import "../../src/subscription/Metadata.sol";

contract TestMetadata is OzInitializableBind, Metadata {
    constructor(string memory description, string memory image, string memory externalUrl) initializer {
        __Metadata_init(description, image, externalUrl);
    }

    function setDescription(string calldata _description) public {
        _setDescription(_description);
    }

    function setImage(string calldata _image) public {
        _setImage(_image);
    }

    function setExternalUrl(string calldata _externalUrl) public {
        _setExternalUrl(_externalUrl);
    }
}

contract MetadataTest is Test {
    TestMetadata private md;
    string private desc;
    string private img;
    string private extUrl;

    function setUp() public {
        desc = "some thing";
        img = "foo";
        extUrl = "bar";

        md = new TestMetadata(desc, img, extUrl);
    }

    function testSetMetadata() public view {
        (string memory _desc, string memory _img, string memory _extUrl) = md.metadata();

        assertEq(_desc, desc, "description");
        assertEq(_img, img, "image");
        assertEq(_extUrl, extUrl, "externalUrl");
    }

    function testSetDescription(string memory d) public {
        md.setDescription(d);

        (string memory _desc, string memory _img, string memory _extUrl) = md.metadata();

        assertEq(_desc, d, "description");

        assertEq(_img, img, "image");
        assertEq(_extUrl, extUrl, "externalUrl");
    }

    function testSetImage(string memory i) public {
        md.setImage(i);

        (string memory _desc, string memory _img, string memory _extUrl) = md.metadata();

        assertEq(_desc, desc, "description");

        assertEq(_img, i, "image");

        assertEq(_extUrl, extUrl, "externalUrl");
    }

    function testSetExternalUrl(string memory e) public {
        md.setExternalUrl(e);

        (string memory _desc, string memory _img, string memory _extUrl) = md.metadata();

        assertEq(_desc, desc, "description");
        assertEq(_img, img, "image");
        assertEq(_extUrl, e, "externalUrl");
    }
}
