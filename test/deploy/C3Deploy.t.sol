// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/deploy/C3Deploy.sol";

contract TestC3 {}

contract C3DeployTest is Test {
    function setUp() public {}

    function testDeploy(address deployer, string memory salt) public {
        assumePayable(deployer);
        assumeNotPrecompile(deployer);

        C3Deploy c3 = new C3Deploy(deployer);

        vm.startPrank(deployer);
        assertEq(
            c3.predictAddress(salt),
            c3.deploy(abi.encodePacked(type(C3Deploy).creationCode, abi.encode(deployer)), salt),
            "Inconsistent deployment address"
        );
    }

    function testDeploy_notDeployer(address deployer, string memory salt, address other) public {
        assumePayable(deployer);
        assumeNotPrecompile(deployer);
        vm.assume(deployer != other);

        C3Deploy c3 = new C3Deploy(deployer);

        vm.startPrank(other);
        vm.expectRevert("Not a deployer");
        c3.deploy(abi.encodePacked(type(C3Deploy).creationCode, abi.encode(deployer)), salt);
    }

    function testDeploy_notDeployer_unset(address deployer, string memory salt) public {
        assumePayable(deployer);
        assumeNotPrecompile(deployer);

        C3Deploy c3 = new C3Deploy(deployer);

        vm.startPrank(deployer);
        c3.setDeployer(deployer, false);

        vm.expectRevert("Not a deployer");
        c3.deploy(abi.encodePacked(type(C3Deploy).creationCode, abi.encode(deployer)), salt);
    }

    function testDeploy_newDeployer(address deployer, string memory salt, address other) public {
        assumePayable(deployer);
        assumeNotPrecompile(deployer);
        vm.assume(deployer != other);

        C3Deploy c3 = new C3Deploy(deployer);

        vm.prank(deployer);
        c3.setDeployer(other, true);

        vm.startPrank(other);
        assertEq(
            c3.predictAddress(salt),
            c3.deploy(abi.encodePacked(type(C3Deploy).creationCode, abi.encode(deployer)), salt),
            "Inconsistent deployment address"
        );
    }
}
