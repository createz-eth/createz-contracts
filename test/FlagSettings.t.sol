// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FlagSettings.sol";

contract TestFlagSettings is FlagSettings {
    function init() public initializer {}

    uint256 private requiredFlags;

    function setRequiredFlags(uint256 rf) public {
        requiredFlags = rf;
    }

    function setFlags(uint256 flags) public {
        _setFlags(flags);
    }

    function withFlag() public whenEnabled(requiredFlags) {}

    function withoutFlag() public whenDisabled(requiredFlags) {}
}

contract FlagSettingsTest is Test {
    TestFlagSettings private fs;

    function setUp() public {
        fs = new TestFlagSettings();

        fs.init();
    }

    function testFuzz_SetGet(uint256 flags) public {
        assertEq(fs.getFlags(), 0, "no flags set");

        fs.setFlags(flags);

        assertEq(fs.getFlags(), flags, "flags set");
    }

    function testFuzz_FlagsEnabled(uint256 flags) public {
        flags = bound(flags, 1, type(uint256).max);
        assertFalse(fs.flagsEnabled(flags), "no flags set");

        fs.setFlags(flags);
        assertTrue(fs.flagsEnabled(flags), "flags enabled");

        fs.setFlags(0xff | fs.getFlags());
        assertTrue(fs.flagsEnabled(flags), "some flags added, flags still enabled");

        fs.setFlags(type(uint256).max);
        assertTrue(fs.flagsEnabled(flags), "all flags, flags still enabled");
    }

    function testFuzz_ModifiedSet(uint256 flags) public {
        flags = bound(flags, 1, type(uint256).max);
        fs.setRequiredFlags(flags);

        fs.setFlags(type(uint256).max);
        fs.withFlag();

        fs.setFlags(flags);
        fs.withFlag();

        vm.expectRevert();
        fs.withoutFlag();
    }

    function testFuzz_ModifiedNotSet(uint256 flags) public {
        flags = bound(flags, 1, type(uint256).max);
        fs.setRequiredFlags(flags);

        fs.withoutFlag();

        fs.setFlags(flags);
        fs.withFlag();

        vm.expectRevert();
        fs.withoutFlag();
    }
}
