// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {ClaimableFacet} from "../../../src/subscription/facet/ClaimableFacet.sol";

import {
    SubscriptionEvents,
    ClaimEvents,
    MetadataStruct,
    SubSettings,
    SubscriptionFlags
} from "../../../src/subscription/ISubscription.sol";

import {HasUserData, UserData} from "../../../src/subscription/UserData.sol";
import {HasEpochs, Epochs} from "../../../src/subscription/Epochs.sol";
import {HasTips, Tips} from "../../../src/subscription/Tips.sol";
import {HasBaseSubscription, BaseSubscription} from "../../../src/subscription/BaseSubscription.sol";

import {HasHandleOwned, HandleOwned} from "../../../src/handle/HandleOwned.sol";
import {IOwnable} from "../../../src/IOwnable.sol";

import {ERC20DecimalsMock} from "../../mocks/ERC20DecimalsMock.sol";

contract ClaimableFacetTest is Test, SubscriptionEvents, ClaimEvents, SubscriptionFlags {
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

    function testClaimable(uint256 claimable) public {
        claimable = bound(claimable, 0, type(uint192).max);
        ClaimSub _sub = new ClaimSub(owner, settings, claimable);

        assertEq(_sub.claimable(), claimable / _sub.CONV(), "Claimable as external");
    }

    function testClaim(address payable to, uint256 claimable) public {
        vm.assume(to != address(0) && to != alice);
        claimable = bound(claimable, 0, type(uint192).max);
        ClaimSub _sub = new ClaimSub(owner, settings, claimable);
        uint256 exClaimable = claimable / _sub.CONV();
        testToken.mint(address(_sub), exClaimable);

        vm.startPrank(owner);
        vm.expectEmit();
        emit FundsClaimed(exClaimable, _sub.TOTAL_CLAIMED() / _sub.CONV());

        _sub.claim(to);

        assertEq(testToken.balanceOf(to), exClaimable, "claimable funds transferred");
    }

    function testClaim_native(address payable to, uint256 claimable) public {
        assumePayable(to);
        vm.assume(to != address(0) && to.balance == 0 && to != alice);
        claimable = bound(claimable, 0, type(uint192).max);
        settings.token = address(0);
        ClaimSub _sub = new ClaimSub(owner, settings, claimable);
        uint256 exClaimable = claimable / _sub.CONV();
        deal(address(_sub), type(uint192).max);

        vm.startPrank(owner);
        vm.expectEmit();
        emit FundsClaimed(exClaimable, _sub.TOTAL_CLAIMED() / _sub.CONV());

        _sub.claim(to);

        assertEq(to.balance, exClaimable, "claimable funds transferred");
        assertEq(address(_sub).balance, type(uint192).max - exClaimable, "claimable funds transferred from contract");
    }

    function testClaimBatch(address payable to, uint256 claimable, uint256 upToEpoch) public {
        vm.assume(to != address(0) && to != alice);
        claimable = bound(claimable, 0, type(uint192).max);
        ClaimSub _sub = new ClaimSub(owner, settings, claimable);
        uint256 exClaimable = claimable / _sub.CONV();
        testToken.mint(address(_sub), exClaimable);

        vm.startPrank(owner);
        vm.expectEmit();
        emit FundsClaimed(exClaimable, _sub.TOTAL_CLAIMED() / _sub.CONV());

        _sub.claim(to, upToEpoch);

        assertEq(testToken.balanceOf(to), exClaimable, "claimable funds transferred");
    }

    function testClaimBatch_notOwner(address user, address payable to, uint256 claimable, uint256 upToEpoch) public {
        vm.assume(user != owner);
        claimable = bound(claimable, 0, type(uint192).max);
        ClaimSub _sub = new ClaimSub(owner, settings, claimable);

        vm.startPrank(user);
        vm.expectRevert();

        _sub.claim(to, upToEpoch);
    }

    function testClaim_notOwner(address user, address payable to, uint256 claimable) public {
        vm.assume(user != owner);
        claimable = bound(claimable, 0, type(uint192).max);
        ClaimSub _sub = new ClaimSub(owner, settings, claimable);

        vm.startPrank(user);
        vm.expectRevert();

        _sub.claim(to);
    }

    function testClaimTips(address payable to, uint256 claimable) public {
        vm.assume(to != address(0) && to != alice);
        claimable = bound(claimable, 0, type(uint192).max);
        ClaimTipSub _sub = new ClaimTipSub(owner, settings, claimable);
        testToken.mint(address(_sub), claimable);

        vm.startPrank(owner);

        vm.expectEmit();
        emit TipsClaimed(claimable, _sub.CLAIMED_TIPS());

        _sub.claimTips(to);

        assertEq(testToken.balanceOf(address(to)), claimable, "amount transferred");
    }

    function testClaimTips_native(address payable to, uint256 claimable) public {
        assumePayable(to);
        vm.assume(to != address(0) && to.balance == 0 && to != alice);
        claimable = bound(claimable, 0, type(uint192).max);
        settings.token = address(0);
        ClaimTipSub _sub = new ClaimTipSub(owner, settings, claimable);
        deal(address(_sub), type(uint192).max);

        vm.startPrank(owner);

        vm.expectEmit();
        emit TipsClaimed(claimable, _sub.CLAIMED_TIPS());

        _sub.claimTips(to);

        assertEq(to.balance, claimable, "claimable funds transferred");
        assertEq(address(_sub).balance, type(uint192).max - claimable, "claimable funds transferred from contract");
    }

    function testClaimTips_notOwner(address user, address payable to, uint256 claimable) public {
        vm.assume(user != owner);
        ClaimTipSub _sub = new ClaimTipSub(owner, settings, claimable);

        vm.prank(user);
        vm.expectRevert();
        _sub.claimTips(to);
    }
}

contract ClaimSub is ClaimableFacet {
    address private _owner;

    uint256 public constant CONV = 10;

    uint256 public constant CURRENT_EPOCH = 1234;
    uint256 public constant LAST_PROCESSED_EPOCH = 2345;
    uint256 public constant TOTAL_CLAIMED = 9876;

    uint256 public claimable_;

    constructor(address owner_, SubSettings memory settings, uint256 _claimable)
        ClaimableFacet(address(0))
        initializer
    {
        _owner = owner_;
        __Rate_init_unchained(settings.rate);
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

    function _claimEpochs(uint256, uint256) internal view override(HasEpochs, Epochs) returns (uint256) {
        return claimable_;
    }

    function _currentEpoch() internal pure override(HasEpochs, Epochs) returns (uint256) {
        return CURRENT_EPOCH;
    }

    function _lastProcessedEpoch() internal pure override(HasEpochs, Epochs) returns (uint256) {
        return LAST_PROCESSED_EPOCH;
    }

    function _claimed() internal pure virtual override(HasEpochs, Epochs) returns (uint256) {
        return TOTAL_CLAIMED;
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

    // override HandleOwned

    function _checkOwner() internal view override(HasHandleOwned, HandleOwned) {
        require(_msgSender() == _owner, "Not Owner");
    }

    function _isValidSigner(address acc) internal view override(HasHandleOwned, HandleOwned) returns (bool) {
        return acc == _owner;
    }

    function owner() public view override(IOwnable, HandleOwned) returns (address) {
        return _owner;
    }

    function _disableInitializers() internal override {}
}

event TipAdded(uint256 indexed tokenId, uint256 indexed amount);

contract ClaimTipSub is ClaimableFacet {
    address private _owner;

    uint256 public constant CONV = 10;

    uint256 public constant TIPS = 1234;
    uint256 public constant ALL_TIPS = 2345;
    uint256 public constant CLAIMED_TIPS = 6789;

    uint256 public claimable_;

    constructor(address owner_, SubSettings memory settings, uint256 _claimable)
        ClaimableFacet(address(0))
        initializer
    {
        _owner = owner_;
        __Rate_init_unchained(settings.rate);
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

    function _claimedTips() internal pure override(HasTips, Tips) returns (uint256) {
        return CLAIMED_TIPS;
    }

    function _claimableTips() internal view override(HasTips, Tips) returns (uint256) {
        return claimable_;
    }

    function _claimTips() internal view override(HasTips, Tips) returns (uint256) {
        return claimable_;
    }

    // override HandleOwned
    function _checkOwner() internal view override(HasHandleOwned, HandleOwned) {
        require(_msgSender() == _owner, "Not Owner");
    }

    function _isValidSigner(address acc) internal view override(HasHandleOwned, HandleOwned) returns (bool) {
        return acc == _owner;
    }

    function owner() public view override(IOwnable, HandleOwned) returns (address) {
        return _owner;
    }

    function _disableInitializers() internal override {}
}
