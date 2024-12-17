// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {DepositableFacet} from "../../../src/subscription/facet/DepositableFacet.sol";

import {SubLib} from "../../../src/subscription/SubLib.sol";

import {
    SubscriptionEvents,
    ClaimEvents,
    MetadataStruct,
    SubSettings,
    SubscriptionFlags
} from "../../../src/subscription/ISubscription.sol";

import {HasUserData, UserData, MultiplierChange} from "../../../src/subscription/UserData.sol";
import {HasEpochs, Epochs} from "../../../src/subscription/Epochs.sol";
import {HasTips, Tips} from "../../../src/subscription/Tips.sol";
import {HasBaseSubscription, BaseSubscription} from "../../../src/subscription/BaseSubscription.sol";

import {HasFlagSettings, FlagSettings} from "../../../src/FlagSettings.sol";

import {ERC20DecimalsMock} from "../../mocks/ERC20DecimalsMock.sol";

contract DepositableFacetTest is Test, SubscriptionEvents, ClaimEvents, SubscriptionFlags {
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

    function testMint(uint256 amount, uint24 multiplier, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));
        multiplier = uint24(bound(multiplier, SubLib.MULTIPLIER_BASE, SubLib.MULTIPLIER_MAX));

        MintSub _sub = new MintSub(settings);

        vm.startPrank(alice);
        testToken.approve(address(_sub), amount);

        vm.expectEmit();
        emit SubCreated(1, amount * _sub.CONV(), multiplier);
        vm.expectEmit();
        emit AddedToEpochs(block.number, amount * _sub.CONV(), multiplier, rate);
        vm.expectEmit();
        emit SubscriptionRenewed(1, amount, alice, _sub.TOTAL_DEPOSITED(), message);

        _sub.mint(amount, multiplier, message);

        assertEq(_sub.balanceOf(alice), 1, "Token created");
        assertEq(testToken.balanceOf(address(_sub)), amount, "amount transferred");
    }

    function testMint_native(uint256 amount, uint24 multiplier, string calldata message) public {
        deal(alice, 100 ether);
        amount = bound(amount, 0, alice.balance);
        multiplier = uint24(bound(multiplier, SubLib.MULTIPLIER_BASE, SubLib.MULTIPLIER_MAX));

        settings.token = address(0);
        MintSub _sub = new MintSub(settings);

        vm.startPrank(alice);

        vm.expectEmit();
        emit SubCreated(1, amount * _sub.CONV(), multiplier);
        vm.expectEmit();
        emit AddedToEpochs(block.number, amount * _sub.CONV(), multiplier, rate);
        vm.expectEmit();
        emit SubscriptionRenewed(1, amount, alice, _sub.TOTAL_DEPOSITED(), message);

        _sub.mint{value: amount}(amount, multiplier, message);

        assertEq(_sub.balanceOf(alice), 1, "Token created");
        assertEq(address(_sub).balance, amount, "amount transferred");
    }

    function testMint_maxSupply(uint256 amount, uint24 multiplier, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));
        multiplier = uint24(bound(multiplier, SubLib.MULTIPLIER_BASE, SubLib.MULTIPLIER_MAX));

        settings.maxSupply = 1;
        MintSub _sub = new MintSub(settings);

        vm.startPrank(alice);
        testToken.approve(address(_sub), amount);
        _sub.mint(amount, multiplier, message);

        vm.expectRevert("SUB: max supply reached");
        _sub.mint(amount, multiplier, message);
    }

    function testMint_maxSupply0(uint256 amount, uint24 multiplier, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));
        multiplier = uint24(bound(multiplier, SubLib.MULTIPLIER_BASE, SubLib.MULTIPLIER_MAX));

        settings.maxSupply = 0;
        MintSub _sub = new MintSub(settings);

        vm.startPrank(alice);
        vm.expectRevert("SUB: max supply reached");
        _sub.mint(amount, multiplier, message);
    }

    function testMint_invalidMultiplier(uint256 amount, uint24 multiplier, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));
        multiplier = uint24(bound(multiplier, 0, 99));

        MintSub _sub = new MintSub(settings);

        vm.startPrank(alice);

        vm.expectRevert("SUB: multiplier invalid");
        _sub.mint(amount, multiplier, message);
    }

    function testMint_invalidMultiplier_large(uint256 amount, uint24 multiplier, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));
        multiplier = uint24(bound(multiplier, 100_001, type(uint24).max));

        MintSub _sub = new MintSub(settings);

        vm.startPrank(alice);

        vm.expectRevert("SUB: multiplier invalid");
        _sub.mint(amount, multiplier, message);
    }

    function testMint_mintPaused(uint256 amount, uint24 multiplier, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));
        multiplier = uint24(bound(multiplier, 100_001, type(uint24).max));

        MintSub _sub = new MintSub(settings);
        vm.prank(owner);
        _sub.setFlags(MINTING_PAUSED);

        vm.expectRevert("Flag: setting enabled");
        _sub.mint(amount, multiplier, message);
    }

    function testChangeMultiplier_active(uint256 tokenId, uint24 newMulti) public {
        newMulti = uint24(bound(newMulti, SubLib.MULTIPLIER_BASE, SubLib.MULTIPLIER_MAX));

        ChangeMultiplierActiveSub _sub = new ChangeMultiplierActiveSub(settings);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(alice);

        vm.expectEmit();
        emit MultiChange(tokenId, newMulti);
        vm.expectEmit();
        emit EpochsReduced(_sub.OLD_DEPOSITED_AT(), _sub.OLD_AMOUNT(), _sub.REDUCED_AMOUNT(), _sub.OLD_MULTI(), rate);
        vm.expectEmit();
        emit AddedToEpochs(_sub.NEW_DEPOSITED_AT(), _sub.NEW_AMOUNT(), newMulti, rate);
        vm.expectEmit();
        emit MultiplierChanged(tokenId, alice, _sub.OLD_MULTI(), newMulti);

        _sub.changeMultiplier(tokenId, newMulti);
    }

    function testChangeMultiplier_inactive(uint256 tokenId, uint24 newMulti) public {
        newMulti = uint24(bound(newMulti, SubLib.MULTIPLIER_BASE, SubLib.MULTIPLIER_MAX));

        ChangeMultiplierInactiveSub _sub = new ChangeMultiplierInactiveSub(settings);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(alice);

        vm.expectEmit();
        emit MultiChange(tokenId, newMulti);
        vm.expectEmit();
        emit MultiplierChanged(tokenId, alice, _sub.OLD_MULTI(), newMulti);

        _sub.changeMultiplier(tokenId, newMulti);
    }

    function testChangeMultiplier_NoToken(uint256 tokenId, uint24 newMulti) public {
        newMulti = uint24(bound(newMulti, SubLib.MULTIPLIER_BASE, SubLib.MULTIPLIER_MAX));

        ChangeMultiplierInactiveSub _sub = new ChangeMultiplierInactiveSub(settings);

        vm.expectRevert("SUB: subscription does not exist");
        _sub.changeMultiplier(tokenId, newMulti);
    }

    function testChangeMultiplier_invalidMulti_lower(uint256 tokenId, uint24 newMulti) public {
        newMulti = uint24(bound(newMulti, 0, SubLib.MULTIPLIER_BASE - 1));

        ChangeMultiplierInactiveSub _sub = new ChangeMultiplierInactiveSub(settings);
        _sub.simpleMint(alice, tokenId);

        vm.expectRevert("SUB: multiplier invalid");
        _sub.changeMultiplier(tokenId, newMulti);
    }

    function testChangeMultiplier_invalidMulti_higher(uint256 tokenId, uint24 newMulti) public {
        newMulti = uint24(bound(newMulti, SubLib.MULTIPLIER_MAX + 1, type(uint24).max));

        ChangeMultiplierInactiveSub _sub = new ChangeMultiplierInactiveSub(settings);
        _sub.simpleMint(alice, tokenId);

        vm.expectRevert("SUB: multiplier invalid");
        _sub.changeMultiplier(tokenId, newMulti);
    }

    function testChangeMultiplier_unauthorized(uint256 tokenId, uint24 newMulti, address user) public {
        vm.assume(user != alice);
        newMulti = uint24(bound(newMulti, SubLib.MULTIPLIER_BASE, SubLib.MULTIPLIER_MAX));

        ChangeMultiplierInactiveSub _sub = new ChangeMultiplierInactiveSub(settings);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(user);

        vm.expectRevert("ERC721: caller is not token owner or approved");
        _sub.changeMultiplier(tokenId, newMulti);
    }

    function testRenew(uint256 tokenId, uint256 amount, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));

        RenewExtendSub _sub = new RenewExtendSub(settings);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(alice);
        testToken.approve(address(_sub), amount);
        assertEq(testToken.balanceOf(address(_sub)), 0, "no tokens in contract");

        vm.expectEmit();
        emit SubExtended(tokenId, amount * _sub.CONV());
        vm.expectEmit();
        emit EpochsExtended(_sub.DEPOSITED_AT(), _sub.OLD_DEPOSIT(), _sub.NEW_DEPOSIT(), _sub.MULTI(), settings.rate);
        vm.expectEmit();
        emit SubscriptionRenewed(tokenId, amount, alice, _sub.TOTAL_DEPOSITED(), message);
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.renew(tokenId, amount, message);

        assertEq(testToken.balanceOf(address(_sub)), amount, "amount transferred");
    }

    function testRenew_native(uint256 tokenId, uint256 amount, string calldata message) public {
        deal(alice, 100 ether);
        amount = bound(amount, 0, alice.balance);

        settings.token = address(0);
        RenewExtendSub _sub = new RenewExtendSub(settings);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(alice);
        assertEq(address(_sub).balance, 0, "no eth in contract");

        vm.expectEmit();
        emit SubExtended(tokenId, amount * _sub.CONV());
        vm.expectEmit();
        emit EpochsExtended(_sub.DEPOSITED_AT(), _sub.OLD_DEPOSIT(), _sub.NEW_DEPOSIT(), _sub.MULTI(), settings.rate);
        vm.expectEmit();
        emit SubscriptionRenewed(tokenId, amount, alice, _sub.TOTAL_DEPOSITED(), message);
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.renew{value: amount}(tokenId, amount, message);

        assertEq(address(_sub).balance, amount, "amount transferred");
    }

    function testRenew_reactivate(uint256 tokenId, uint256 amount, string calldata message) public {
        amount = bound(amount, 0, testToken.balanceOf(alice));

        RenewReactivateSub _sub = new RenewReactivateSub(settings);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(alice);
        testToken.approve(address(_sub), amount);
        assertEq(testToken.balanceOf(address(_sub)), 0, "no tokens in contract");

        vm.expectEmit();
        emit SubExtended(tokenId, amount * _sub.CONV());
        vm.expectEmit();
        emit AddedToEpochs(block.number, _sub.NEW_DEPOSIT(), _sub.MULTI(), settings.rate);
        vm.expectEmit();
        emit SubscriptionRenewed(tokenId, amount, alice, _sub.TOTAL_DEPOSITED(), message);
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.renew(tokenId, amount, message);

        assertEq(testToken.balanceOf(address(_sub)), amount, "amount transferred");
    }

    function testRenew_otherUser(address user, uint256 tokenId, uint256 amount, string calldata message) public {
        vm.assume(user != address(0) && user != alice && user != address(this));

        testToken.mint(user, 100_000_000_000 ether);
        amount = bound(amount, 0, testToken.balanceOf(user));

        RenewExtendSub _sub = new RenewExtendSub(settings);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(user);
        testToken.approve(address(_sub), amount);
        assertEq(testToken.balanceOf(address(_sub)), 0, "no tokens in contract");

        vm.expectEmit();
        emit SubExtended(tokenId, amount * _sub.CONV());
        vm.expectEmit();
        emit EpochsExtended(_sub.DEPOSITED_AT(), _sub.OLD_DEPOSIT(), _sub.NEW_DEPOSIT(), _sub.MULTI(), settings.rate);
        vm.expectEmit();
        emit SubscriptionRenewed(tokenId, amount, user, _sub.TOTAL_DEPOSITED(), message);
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.renew(tokenId, amount, message);

        assertEq(testToken.balanceOf(address(_sub)), amount, "amount transferred");
    }

    function testRenew_noToken(address user, uint256 tokenId, uint256 amount, string calldata message) public {
        RenewExtendSub _sub = new RenewExtendSub(settings);

        vm.startPrank(user);

        vm.expectRevert("SUB: subscription does not exist");
        _sub.renew(tokenId, amount, message);
    }

    function testRenew_paused(address user, uint256 tokenId, uint256 amount, string calldata message) public {
        RenewExtendSub _sub = new RenewExtendSub(settings);

        vm.prank(owner);
        _sub.setFlags(RENEWAL_PAUSED);

        vm.startPrank(user);

        vm.expectRevert("Flag: setting enabled");
        _sub.renew(tokenId, amount, message);
    }

    function testTip(uint256 tokenId, uint256 amount, string calldata message) public {
        amount = bound(amount, 1, testToken.balanceOf(alice));

        TipSub _sub = new TipSub(settings, 0);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(alice);
        testToken.approve(address(_sub), amount);
        assertEq(testToken.balanceOf(address(_sub)), 0, "no tokens in contract");

        vm.expectEmit();
        emit TipAdded(tokenId, amount);
        vm.expectEmit();
        emit Tipped(tokenId, amount, alice, _sub.TIPS(), message);
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.tip(tokenId, amount, message);

        assertEq(testToken.balanceOf(address(_sub)), amount, "amount transferred");
    }

    function testTip_native(uint256 tokenId, uint256 amount, string calldata message) public {
        deal(alice, 100 ether);
        amount = bound(amount, 1, alice.balance);

        settings.token = address(0);
        TipSub _sub = new TipSub(settings, 0);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(alice);
        assertEq(address(_sub).balance, 0, "no eth in contract");

        vm.expectEmit();
        emit TipAdded(tokenId, amount);
        vm.expectEmit();
        emit Tipped(tokenId, amount, alice, _sub.TIPS(), message);
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.tip{value: amount}(tokenId, amount, message);

        assertEq(address(_sub).balance, amount, "amount transferred");
    }

    function testTip_anyUser(address user, uint256 tokenId, uint256 amount, string calldata message) public {
        vm.assume(user != address(0));
        testToken.mint(user, 100_000_000_000 ether);
        amount = bound(amount, 1, testToken.balanceOf(user));

        TipSub _sub = new TipSub(settings, 0);
        _sub.simpleMint(alice, tokenId);

        vm.startPrank(user);
        testToken.approve(address(_sub), amount);
        assertEq(testToken.balanceOf(address(_sub)), 0, "no tokens in contract");

        vm.expectEmit();
        emit TipAdded(tokenId, amount);
        vm.expectEmit();
        emit Tipped(tokenId, amount, user, _sub.TIPS(), message);
        vm.expectEmit();
        emit MetadataUpdate(tokenId);

        _sub.tip(tokenId, amount, message);

        assertEq(testToken.balanceOf(address(_sub)), amount, "amount transferred");
    }

    function testTip0(uint256 tokenId, string calldata message) public {
        TipSub _sub = new TipSub(settings, 0);
        _sub.simpleMint(alice, tokenId);

        vm.expectRevert("SUB: amount too small");
        _sub.tip(tokenId, 0, message);
    }

    function testTip_notExist(uint256 tokenId, uint256 amount, string calldata message) public {
        TipSub _sub = new TipSub(settings, 0);

        vm.expectRevert("SUB: subscription does not exist");
        _sub.tip(tokenId, amount, message);
    }

    function testTip_disabled(uint256 tokenId, uint256 amount, string calldata message) public {
        TipSub _sub = new TipSub(settings, 0);
        _sub.simpleMint(alice, tokenId);

        vm.prank(owner);
        _sub.setFlags(TIPPING_PAUSED);

        vm.expectRevert("Flag: setting enabled");
        _sub.tip(tokenId, amount, message);
    }
}

//
// EVENTS
//
event SubCreated(uint256 indexed tokenId, uint256 indexed amount, uint24 indexed multiplier);

event AddedToEpochs(uint256 depositedAt, uint256 indexed amount, uint256 shares, uint256 rate);

event SubExtended(uint256 indexed tokenId, uint256 indexed amount);

event EpochsExtended(
    uint256 indexed depositedAt, uint256 indexed oldDeposit, uint256 indexed newDeposit, uint256 shares, uint256 rate
);

event TipAdded(uint256 indexed tokenId, uint256 indexed amount);

event EpochsReduced(
    uint256 indexed depositedAt, uint256 indexed oldDeposit, uint256 indexed newDeposit, uint256 shares, uint256 rate
);

event MultiChange(uint256 indexed tokenId, uint24 indexed multiplier);

//
// MOCKS
//
contract MintSub is FlagSettings, DepositableFacet {
    uint256 public constant CONV = 10;
    uint256 public constant TOTAL_DEPOSITED = 9876;

    constructor(SubSettings memory settings) initializer {
        __Rate_init_unchained(settings.rate);
        __Epochs_init_unchained(settings.epochSize);
        __UserData_init_unchained(settings.lock);
        __PaymentToken_init_unchained(settings.token);
        __MaxSupply_init_unchained(settings.maxSupply);
        __TokenIdProvider_init_unchained(0);
    }

    function _totalDeposited(uint256) internal pure override(HasUserData, UserData) returns (uint256) {
        return TOTAL_DEPOSITED;
    }

    function _createSubscription(uint256 tokenId, uint256 amount, uint24 multiplier)
        internal
        override(HasUserData, UserData)
    {
        emit SubCreated(tokenId, amount, multiplier);
    }

    function _addToEpochs(uint256 depositedAt, uint256 amount, uint256 shares, uint256 rate)
        internal
        override(HasEpochs, Epochs)
    {
        emit AddedToEpochs(depositedAt, amount, shares, rate);
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

    // helper
    function simpleMint(address to, uint256 tokenId) external {
        _safeMint(to, tokenId);
    }

    function setFlags(uint256 flags) external {
        _setFlags(flags);
    }
}

contract RenewExtendSub is DepositableFacet {
    uint256 public constant CONV = 10;
    uint24 public constant MULTI = 9999;

    uint256 public constant DEPOSITED_AT = 1234;
    uint256 public constant OLD_DEPOSIT = 2345;
    uint256 public constant NEW_DEPOSIT = 6789;

    uint256 public constant TOTAL_DEPOSITED = 9876;

    constructor(SubSettings memory settings) initializer {
        __Rate_init_unchained(settings.rate);
        __Epochs_init_unchained(settings.epochSize);
        __UserData_init_unchained(settings.lock);
        __PaymentToken_init_unchained(settings.token);
    }

    function _multiplier(uint256) internal pure override(HasUserData, UserData) returns (uint24) {
        return MULTI;
    }

    function _extendSubscription(uint256 tokenId, uint256 amount)
        internal
        override(HasUserData, UserData)
        returns (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated)
    {
        emit SubExtended(tokenId, amount);

        depositedAt = DEPOSITED_AT;
        oldDeposit = OLD_DEPOSIT;
        newDeposit = NEW_DEPOSIT;
        reactivated = false;
    }

    function _extendInEpochs(uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, uint256 shares, uint256 rate)
        internal
        override(HasEpochs, Epochs)
    {
        emit EpochsExtended(depositedAt, oldDeposit, newDeposit, shares, rate);
    }

    function _totalDeposited(uint256) internal pure override(HasUserData, UserData) returns (uint256) {
        return TOTAL_DEPOSITED;
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
    // helper

    function simpleMint(address to, uint256 tokenId) external {
        _safeMint(to, tokenId);
    }

    function setFlags(uint256 flags) external {
        _setFlags(flags);
    }
}

contract RenewReactivateSub is DepositableFacet {
    uint256 public constant CONV = 10;
    uint24 public constant MULTI = 9999;

    uint256 public constant DEPOSITED_AT = 1234;
    uint256 public constant OLD_DEPOSIT = 2345;
    uint256 public constant NEW_DEPOSIT = 6789;

    uint256 public constant TOTAL_DEPOSITED = 9876;

    constructor(SubSettings memory settings) initializer {
        __Rate_init_unchained(settings.rate);
        __Epochs_init_unchained(settings.epochSize);
        __UserData_init_unchained(settings.lock);
        __PaymentToken_init_unchained(settings.token);
    }

    function _multiplier(uint256) internal pure override(HasUserData, UserData) returns (uint24) {
        return MULTI;
    }

    function _extendSubscription(uint256 tokenId, uint256 amount)
        internal
        override(HasUserData, UserData)
        returns (uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, bool reactivated)
    {
        emit SubExtended(tokenId, amount);

        depositedAt = DEPOSITED_AT;
        oldDeposit = OLD_DEPOSIT;
        newDeposit = NEW_DEPOSIT;
        reactivated = true;
    }

    function _addToEpochs(uint256 depositedAt, uint256 amount, uint256 shares, uint256 rate)
        internal
        override(HasEpochs, Epochs)
    {
        emit AddedToEpochs(depositedAt, amount, shares, rate);
    }

    function _totalDeposited(uint256) internal pure override(HasUserData, UserData) returns (uint256) {
        return TOTAL_DEPOSITED;
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
    // helper

    function simpleMint(address to, uint256 tokenId) external {
        _safeMint(to, tokenId);
    }
}

contract ChangeMultiplierActiveSub is DepositableFacet {
    uint256 public constant CONV = 10;
    uint24 public constant OLD_MULTI = 999;
    uint24 public constant NEW_MULTI = 2222;

    uint256 public constant OLD_DEPOSITED_AT = 1234;
    uint256 public constant OLD_AMOUNT = 2345;
    uint256 public constant REDUCED_AMOUNT = 55433;
    uint256 public constant NEW_DEPOSITED_AT = 44444;
    uint256 public constant NEW_AMOUNT = 55555;

    uint256 public constant TOTAL_DEPOSITED = 9876;

    constructor(SubSettings memory settings) initializer {
        __Rate_init_unchained(settings.rate);
        __Epochs_init_unchained(settings.epochSize);
        __UserData_init_unchained(settings.lock);
        __PaymentToken_init_unchained(settings.token);
    }

    function _changeMultiplier(uint256 tokenId, uint24 multi)
        internal
        virtual
        override(HasUserData, UserData)
        returns (bool isActive_, MultiplierChange memory c)
    {
        emit MultiChange(tokenId, multi);

        isActive_ = true;
        c.oldDepositAt = OLD_DEPOSITED_AT;
        c.oldAmount = OLD_AMOUNT;
        c.oldMultiplier = OLD_MULTI;
        c.reducedAmount = REDUCED_AMOUNT;
        c.newDepositAt = NEW_DEPOSITED_AT;
        c.newAmount = NEW_AMOUNT;
    }

    function _addToEpochs(uint256 depositedAt, uint256 amount, uint256 shares, uint256 rate)
        internal
        override(HasEpochs, Epochs)
    {
        emit AddedToEpochs(depositedAt, amount, shares, rate);
    }

    function _reduceInEpochs(uint256 depositedAt, uint256 oldDeposit, uint256 newDeposit, uint256 shares, uint256 rate)
        internal
        override(HasEpochs, Epochs)
    {
        emit EpochsReduced(depositedAt, oldDeposit, newDeposit, shares, rate);
    }
    // helper

    function simpleMint(address to, uint256 tokenId) external {
        _safeMint(to, tokenId);
    }
}

contract ChangeMultiplierInactiveSub is DepositableFacet {
    uint256 public constant CONV = 10;
    uint24 public constant OLD_MULTI = 999;
    uint24 public constant NEW_MULTI = 2222;

    uint256 public constant OLD_DEPOSITED_AT = 1234;
    uint256 public constant OLD_AMOUNT = 2345;
    uint256 public constant REDUCED_AMOUNT = 55433;
    uint256 public constant NEW_DEPOSITED_AT = 44444;
    uint256 public constant NEW_AMOUNT = 55555;

    uint256 public constant TOTAL_DEPOSITED = 9876;

    constructor(SubSettings memory settings) initializer {
        __Rate_init_unchained(settings.rate);
        __Epochs_init_unchained(settings.epochSize);
        __UserData_init_unchained(settings.lock);
        __PaymentToken_init_unchained(settings.token);
    }

    function _changeMultiplier(uint256 tokenId, uint24 multi)
        internal
        virtual
        override(HasUserData, UserData)
        returns (bool isActive_, MultiplierChange memory c)
    {
        emit MultiChange(tokenId, multi);

        isActive_ = false;
        c.oldMultiplier = OLD_MULTI;
    }
    // helper

    function simpleMint(address to, uint256 tokenId) external {
        _safeMint(to, tokenId);
    }
}

contract TipSub is DepositableFacet {
    uint256 public constant CONV = 10;

    uint256 public constant TIPS = 1234;
    uint256 public constant ALL_TIPS = 2345;
    uint256 public constant CLAIMED_TIPS = 6789;

    uint256 public claimable_;

    constructor(SubSettings memory settings, uint256 _claimable) initializer {
        __PaymentToken_init_unchained(settings.token);
        claimable_ = _claimable;
    }

    function _scanEpochs(uint256, uint256)
        internal
        view
        override(HasEpochs, Epochs)
        returns (uint256 amount, uint256 a, uint256 b)
    {
        amount = claimable_;
        a = 0;
        b = 0;
    }

    function _addTip(uint256 tokenId, uint256 amount) internal override(HasTips, Tips) {
        emit TipAdded(tokenId, amount);
    }

    function _tips(uint256) internal pure override(HasTips, Tips) returns (uint256) {
        return TIPS;
    }

    function _allTips() internal pure override(HasTips, Tips) returns (uint256) {
        return ALL_TIPS;
    }
    // helper

    function simpleMint(address to, uint256 tokenId) external {
        _safeMint(to, tokenId);
    }

    function setFlags(uint256 flags) external {
        _setFlags(flags);
    }
}
