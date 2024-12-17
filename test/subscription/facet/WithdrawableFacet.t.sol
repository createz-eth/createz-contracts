// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {WithdrawableFacet} from "../../../src/subscription/facet/WithdrawableFacet.sol";

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

contract WithdrawableFacetTest is Test, SubscriptionEvents, ClaimEvents, SubscriptionFlags {
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

    function testWithdraw(uint256 tokenId, uint256 amount, uint256 withdrawable) public {
        withdrawable = bound(withdrawable, 0, type(uint192).max);
        WithdrawSub _sub = new WithdrawSub(settings, withdrawable);

        uint256 exWithdrawable = withdrawable / _sub.CONV();
        amount = bound(amount, 0, exWithdrawable);
        testToken.mint(address(_sub), exWithdrawable);
        _sub.simpleMint(bob, tokenId);

        assertEq(testToken.balanceOf(address(_sub)), exWithdrawable, "withdrawable amount of funds in contract");

        vm.startPrank(bob);
        vm.expectEmit();
        emit SubWithdrawn(tokenId, amount * _sub.CONV());
        vm.expectEmit();
        emit EpochsReduced(_sub.DEPOSITED_AT(), _sub.OLD_DEPOSIT(), _sub.NEW_DEPOSIT(), _sub.MULTI(), settings.rate);
        vm.expectEmit();
        emit SubscriptionWithdrawn(tokenId, amount, bob, _sub.TOTAL_DEPOSITED());
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.withdraw(tokenId, amount);

        assertEq(testToken.balanceOf(address(bob)), amount, "amount transferred");
    }

    function testWithdraw_native(uint256 tokenId, uint256 amount, uint256 withdrawable) public {
        withdrawable = bound(withdrawable, 0, type(uint192).max);
        settings.token = address(0);
        WithdrawSub _sub = new WithdrawSub(settings, withdrawable);

        uint256 exWithdrawable = withdrawable / _sub.CONV();
        amount = bound(amount, 0, exWithdrawable);
        deal(address(_sub), type(uint192).max);
        _sub.simpleMint(bob, tokenId);

        vm.startPrank(bob);
        vm.expectEmit();
        emit SubWithdrawn(tokenId, amount * _sub.CONV());
        vm.expectEmit();
        emit EpochsReduced(_sub.DEPOSITED_AT(), _sub.OLD_DEPOSIT(), _sub.NEW_DEPOSIT(), _sub.MULTI(), settings.rate);
        vm.expectEmit();
        emit SubscriptionWithdrawn(tokenId, amount, bob, _sub.TOTAL_DEPOSITED());
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.withdraw(tokenId, amount);

        assertEq(address(bob).balance, amount, "amount transferred");
        assertEq(address(_sub).balance, type(uint192).max - amount, "amount transferred from contract");
    }

    function testWithdraw_tokenNotExist(uint256 tokenId, uint256 amount, uint256 withdrawable) public {
        withdrawable = bound(withdrawable, 0, type(uint192).max);
        WithdrawSub _sub = new WithdrawSub(settings, withdrawable);

        vm.startPrank(bob);

        vm.expectRevert("SUB: subscription does not exist");
        _sub.withdraw(tokenId, amount);
    }

    function testWithdraw_notOwner(address user, uint256 tokenId, uint256 amount, uint256 withdrawable) public {
        vm.assume(user != address(this) && user != bob);
        withdrawable = bound(withdrawable, 0, type(uint192).max);
        WithdrawSub _sub = new WithdrawSub(settings, withdrawable);

        uint256 exWithdrawable = withdrawable / _sub.CONV();
        amount = bound(amount, 0, exWithdrawable);
        testToken.mint(address(_sub), exWithdrawable);
        _sub.simpleMint(bob, tokenId);

        vm.startPrank(user);

        vm.expectRevert("ERC721: caller is not token owner or approved");
        _sub.withdraw(tokenId, amount);
    }

    function testCancel(uint256 tokenId, uint256 withdrawable) public {
        withdrawable = bound(withdrawable, 0, type(uint192).max);
        WithdrawSub _sub = new WithdrawSub(settings, withdrawable);

        uint256 exWithdrawable = withdrawable / _sub.CONV();
        testToken.mint(address(_sub), exWithdrawable);
        _sub.simpleMint(bob, tokenId);

        assertEq(testToken.balanceOf(address(_sub)), exWithdrawable, "withdrawable amount of funds in contract");

        vm.startPrank(bob);
        vm.expectEmit();
        emit SubWithdrawn(tokenId, withdrawable);
        vm.expectEmit();
        emit EpochsReduced(_sub.DEPOSITED_AT(), _sub.OLD_DEPOSIT(), _sub.NEW_DEPOSIT(), _sub.MULTI(), settings.rate);
        vm.expectEmit();
        emit SubscriptionWithdrawn(tokenId, exWithdrawable, bob, _sub.TOTAL_DEPOSITED());
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.cancel(tokenId);

        assertEq(testToken.balanceOf(address(bob)), exWithdrawable, "amount transferred");
    }

    function testCancel_native(uint256 tokenId, uint256 withdrawable) public {
        withdrawable = bound(withdrawable, 0, type(uint192).max);
        settings.token = address(0);
        WithdrawSub _sub = new WithdrawSub(settings, withdrawable);

        uint256 exWithdrawable = withdrawable / _sub.CONV();
        deal(address(_sub), type(uint192).max);
        _sub.simpleMint(bob, tokenId);

        vm.startPrank(bob);
        vm.expectEmit();
        emit SubWithdrawn(tokenId, withdrawable);
        vm.expectEmit();
        emit EpochsReduced(_sub.DEPOSITED_AT(), _sub.OLD_DEPOSIT(), _sub.NEW_DEPOSIT(), _sub.MULTI(), settings.rate);
        vm.expectEmit();
        emit SubscriptionWithdrawn(tokenId, exWithdrawable, bob, _sub.TOTAL_DEPOSITED());
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.cancel(tokenId);

        assertEq(address(bob).balance, exWithdrawable, "amount transferred");
        assertEq(address(_sub).balance, type(uint192).max - exWithdrawable, "amount transferred from contract");
    }

    function testCancel_notOwner(address user, uint256 tokenId, uint256 withdrawable) public {
        vm.assume(user != address(this) && user != bob);
        withdrawable = bound(withdrawable, 0, type(uint192).max);
        WithdrawSub _sub = new WithdrawSub(settings, withdrawable);

        uint256 exWithdrawable = withdrawable / _sub.CONV();
        testToken.mint(address(_sub), exWithdrawable);
        _sub.simpleMint(bob, tokenId);

        assertEq(testToken.balanceOf(address(_sub)), exWithdrawable, "withdrawable amount of funds in contract");

        vm.startPrank(user);

        vm.expectRevert("ERC721: caller is not token owner or approved");
        _sub.cancel(tokenId);
    }

    function testCancel_tokenNotExist(uint256 tokenId, uint256 withdrawable) public {
        withdrawable = bound(withdrawable, 0, type(uint192).max);
        WithdrawSub _sub = new WithdrawSub(settings, withdrawable);

        vm.startPrank(bob);

        vm.expectRevert("SUB: subscription does not exist");
        _sub.cancel(tokenId);
    }
}

event SubWithdrawn(uint256 indexed tokenId, uint256 indexed amount);

event EpochsReduced(
    uint256 indexed depositedAt, uint256 indexed oldDeposit, uint256 indexed newDeposit, uint256 shares, uint256 rate
);

// Override dependent methods
contract WithdrawSub is WithdrawableFacet {
    uint256 public constant CONV = 10;
    uint24 public constant MULTI = 9999;

    uint256 public constant DEPOSITED_AT = 1234;
    uint256 public constant OLD_DEPOSIT = 2345;
    uint256 public constant NEW_DEPOSIT = 6789;

    uint256 public constant TOTAL_DEPOSITED = 9876;

    uint256 public withdrawable;

    constructor(SubSettings memory settings, uint256 _withdrawable) initializer {
        __Rate_init_unchained(settings.rate);
        __PaymentToken_init_unchained(settings.token);
        withdrawable = _withdrawable;
    }

    function _withdrawableFromSubscription(uint256) internal view override(HasUserData, UserData) returns (uint256) {
        return withdrawable;
    }

    function _withdrawFromSubscription(uint256 tokenId, uint256 amount)
        internal
        override(HasUserData, UserData)
        returns (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit)
    {
        emit SubWithdrawn(tokenId, amount);
        depositedAt = DEPOSITED_AT;
        oldDeposit = OLD_DEPOSIT;
        newDeposit = NEW_DEPOSIT;
    }

    function _reduceInEpochs(uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, uint256 shares, uint256 rate)
        internal
        override(HasEpochs, Epochs)
    {
        emit EpochsReduced(depositedAt, oldDeposit, newDeposit, shares, rate);
    }

    function _totalDeposited(uint256) internal pure override(HasUserData, UserData) returns (uint256) {
        return TOTAL_DEPOSITED;
    }

    function _multiplier(uint256) internal pure override(HasUserData, UserData) returns (uint24) {
        return MULTI;
    }

    function _asInternal(uint256 v)
        internal
        view
        virtual
        override(HasBaseSubscription, BaseSubscription)
        returns (uint256)
    {
        return v * CONV;
    }

    function _asExternal(uint256 v)
        internal
        view
        virtual
        override(HasBaseSubscription, BaseSubscription)
        returns (uint256)
    {
        return v / CONV;
    }

    // helpers
    function simpleMint(address to, uint256 tokenId) external {
        _safeMint(to, tokenId);
    }
}
