// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/Subscription.sol";

import {SubscriptionEvents, ClaimEvents} from "../src/ISubscription.sol";

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TestToken} from "./token/TestToken.sol";

// TODO test mint/renew with amount==0
contract SubscriptionTest is Test, SubscriptionEvents, ClaimEvents {
    Subscription public subscription;
    IERC20 public testToken;
    uint256 public rate;
    uint256 public epochSize;

    address public owner;
    address public alice;
    address public bob;
    address public charlie;

    string public message;

    function setUp() public {
        owner = address(1);
        alice = address(10);
        bob = address(20);
        charlie = address(30);

        message = "Hello World";

        rate = 5;
        epochSize = 10;
        testToken = new TestToken(1_000_000, address(this));
        subscription = new Subscription(testToken, rate, epochSize);
        subscription.transferOwnership(owner);

        testToken.approve(address(subscription), type(uint256).max);

        testToken.transfer(alice, 10_000);
        testToken.transfer(bob, 20_000);
    }

    function testConstruct_not0token() public {
        vm.expectRevert("SUB: token cannot be 0 address");
        new Subscription(IERC20(address(0)), 10, 10);
    }

    function testConstruct_not0rate() public {
        vm.expectRevert("SUB: rate cannot be 0");
        new Subscription(testToken, 0, 10);
    }

    function testConstruct_not0epochSize() public {
        vm.expectRevert("SUB: invalid epochSize");
        new Subscription(testToken, 10, 0);
    }

    function mintToken(address user, uint256 amount)
        private
        returns (uint256 tokenId)
    {
        vm.expectEmit(true, true, true, true);
        emit SubscriptionRenewed(
            subscription.totalSupply() + 1,
            amount,
            amount,
            user,
            message
        );

        vm.startPrank(user);
        testToken.approve(address(subscription), amount);
        tokenId = subscription.mint(amount, message);
        vm.stopPrank();
        assertEq(
            testToken.balanceOf(address(subscription)),
            amount,
            "amount send to subscription contract"
        );
    }

    function testMint() public {
        uint256 tokenId = mintToken(alice, 100);

        bool active = subscription.isActive(tokenId);
        uint256 end = subscription.expiresAt(tokenId);

        assertEq(tokenId, 1, "subscription has first token id");
        assertEq(end, block.number + 20, "subscription ends at 20");
        assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");
        assertTrue(active, "subscription active");
    }

    function testIsActive() public {
        uint256 tokenId = mintToken(alice, 100);

        assertEq(tokenId, 1, "subscription has first token id");

        // fast forward
        vm.roll(block.number + 5);
        bool active = subscription.isActive(tokenId);

        assertTrue(active, "subscription active");
    }

    function testIsActive_lastBlock() public {
        uint256 tokenId = mintToken(alice, 100);

        assertEq(tokenId, 1, "subscription has first token id");

        // fast forward
        vm.roll(block.number + 19);
        bool active = subscription.isActive(tokenId);

        assertTrue(active, "subscription active");

        vm.roll(block.number + 1); // + 20
        active = subscription.isActive(tokenId);

        assertFalse(active, "subscription inactive");
    }

    function testRenew() public {
        uint256 tokenId = mintToken(alice, 100);

        uint256 initialEnd = subscription.expiresAt(tokenId);
        assertEq(
            initialEnd,
            block.number + 20,
            "subscription initially ends at 20"
        );
        assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");

        // fast forward
        vm.roll(block.number + 5);

        vm.expectEmit(true, true, true, true);
        emit SubscriptionRenewed(tokenId, 200, 300, address(this), message);

        subscription.renew(tokenId, 200, message);

        assertEq(
            testToken.balanceOf(address(subscription)),
            300,
            "all tokens deposited"
        );

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        uint256 end = subscription.expiresAt(tokenId);
        assertEq(end, initialEnd + 40, "subscription ends at 60");
        assertEq(subscription.deposited(tokenId), 300, "300 tokens deposited");
    }

    function testRenew_revert_nonExisting() public {
        uint256 tokenId = 100;

        vm.expectRevert("SUB: subscription does not exist");
        subscription.renew(tokenId, 200, message);

        assertEq(
            testToken.balanceOf(address(subscription)),
            0,
            "no tokens sent"
        );
    }

    function testRenew_afterMint() public {
        uint256 tokenId = mintToken(alice, 100);

        uint256 initialEnd = subscription.expiresAt(tokenId);
        assertEq(
            initialEnd,
            block.number + 20,
            "subscription initially ends at 20"
        );
        assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");

        vm.expectEmit(true, true, true, true);
        emit SubscriptionRenewed(tokenId, 200, 300, address(this), message);

        subscription.renew(tokenId, 200, message);

        assertEq(
            testToken.balanceOf(address(subscription)),
            300,
            "all tokens deposited"
        );

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        uint256 end = subscription.expiresAt(tokenId);
        assertEq(end, initialEnd + 40, "subscription ends at 60");
        assertEq(subscription.deposited(tokenId), 300, "300 tokens deposited");
    }

    function testRenew_inActive() public {
        uint256 tokenId = mintToken(alice, 100);

        uint256 initialEnd = subscription.expiresAt(tokenId);
        assertEq(
            initialEnd,
            block.number + 20,
            "subscription initially ends at 20"
        );

        // fast forward
        uint256 ff = 50;
        vm.roll(block.number + ff);
        assertFalse(subscription.isActive(tokenId), "subscription is inactive");
        assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");

        vm.expectEmit(true, true, true, true);
        emit SubscriptionRenewed(tokenId, 200, 300, address(this), message);

        subscription.renew(tokenId, 200, message);

        assertEq(
            testToken.balanceOf(address(subscription)),
            300,
            "all tokens deposited"
        );

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        uint256 end = subscription.expiresAt(tokenId);
        assertEq(end, block.number + 40, "subscription ends at 90");
        assertEq(subscription.deposited(tokenId), 300, "300 tokens deposited");
    }

    function testRenew_notOwner() public {
        uint256 tokenId = mintToken(alice, 100);

        uint256 initialEnd = subscription.expiresAt(tokenId);
        assertEq(
            initialEnd,
            block.number + 20,
            "subscription initially ends at 20"
        );

        uint256 amount = 200;
        vm.startPrank(bob);

        vm.expectEmit(true, true, true, true);
        emit SubscriptionRenewed(tokenId, 200, 300, bob, message);

        testToken.approve(address(subscription), amount);
        subscription.renew(tokenId, amount, message);

        vm.stopPrank();

        assertEq(
            testToken.balanceOf(address(subscription)),
            300,
            "all tokens deposited"
        );

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        uint256 end = subscription.expiresAt(tokenId);
        assertEq(
            end,
            initialEnd + (amount / rate),
            "subscription end extended"
        );
        assertEq(subscription.deposited(tokenId), 300, "300 tokens deposited");
    }

    function testWithdrawable() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        uint256 passed = 5;

        vm.roll(block.number + passed);

        assertTrue(subscription.isActive(tokenId), "subscription active");
        assertEq(
            subscription.withdrawable(tokenId),
            initialDeposit - (passed * rate),
            "withdrawable deposit 75"
        );
        assertEq(
            testToken.balanceOf(address(subscription)),
            initialDeposit,
            "token balance not changed"
        );
        assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");
    }

    function testWithdrawable_inActive() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        uint256 passed = 50;

        vm.roll(block.number + passed);

        assertFalse(subscription.isActive(tokenId), "subscription inactive");
        assertEq(
            subscription.withdrawable(tokenId),
            0,
            "withdrawable deposit 0"
        );
        assertEq(
            testToken.balanceOf(address(subscription)),
            initialDeposit,
            "token balance not changed"
        );
    }

    function testWithdrawable_afterMint() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        assertTrue(subscription.isActive(tokenId), "subscription active");
        assertEq(
            subscription.withdrawable(tokenId),
            initialDeposit,
            "withdrawable deposit 100"
        );

        assertEq(
            testToken.balanceOf(address(subscription)),
            initialDeposit,
            "token balance not changed"
        );
    }

    function testWithdraw() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);
        assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");

        uint256 passed = 5;
        vm.roll(block.number + passed);

        uint256 aliceBalance = testToken.balanceOf(alice);
        uint256 subBalance = testToken.balanceOf(address(subscription));
        uint256 withdrawable = subscription.withdrawable(tokenId);

        uint256 amount = 25;

        vm.expectEmit(true, true, true, true);
        emit SubscriptionWithdrawn(tokenId, 25, 75);

        vm.prank(alice);
        subscription.withdraw(tokenId, amount);

        assertEq(
            testToken.balanceOf(alice),
            aliceBalance + amount,
            "funds withdrawn to alice"
        );
        assertEq(
            testToken.balanceOf(address(subscription)),
            subBalance - amount,
            "funds withdrawn from contract"
        );
        assertEq(
            subscription.withdrawable(tokenId),
            withdrawable - amount,
            "withdrawable amount reduced"
        );

        assertTrue(subscription.isActive(tokenId), "subscription is active");
        assertEq(
            subscription.deposited(tokenId),
            initialDeposit - amount,
            "75 tokens deposited"
        );
    }

    function testWithdraw_all() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        uint256 passed = 5;
        vm.roll(block.number + passed);

        uint256 aliceBalance = testToken.balanceOf(alice);
        uint256 withdrawable = subscription.withdrawable(tokenId);

        uint256 amount = withdrawable;

        vm.expectEmit(true, true, true, true);
        emit SubscriptionWithdrawn(tokenId, amount, initialDeposit - amount);

        vm.prank(alice);
        subscription.withdraw(tokenId, amount);

        assertEq(
            testToken.balanceOf(alice),
            aliceBalance + initialDeposit - (passed * rate),
            "alice only reduced by 'used' amount"
        );
        assertEq(
            testToken.balanceOf(address(subscription)),
            passed * rate,
            "contract only contains 'used' amount"
        );
        assertEq(
            subscription.withdrawable(tokenId),
            0,
            "withdrawable amount is 0"
        );

        assertFalse(subscription.isActive(tokenId), "subscription is inactive");
        assertEq(
            subscription.deposited(tokenId),
            initialDeposit - amount,
            "25 tokens deposited"
        );
    }

    function testWithdraw_allAfterMint() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        assertEq(
            subscription.deposited(tokenId),
            initialDeposit,
            "100 tokens deposited"
        );

        uint256 amount = initialDeposit;
        assertTrue(subscription.isActive(tokenId), "subscription is active");

        vm.expectEmit(true, true, true, true);
        emit SubscriptionWithdrawn(tokenId, initialDeposit, 0);

        vm.prank(alice);
        subscription.withdraw(tokenId, amount);

        assertEq(
            testToken.balanceOf(alice),
            10_000,
            "alice retrieved all funds"
        );
        assertEq(
            testToken.balanceOf(address(subscription)),
            0,
            "contract is empty"
        );
        assertEq(subscription.withdrawable(tokenId), 0, "nothing to withdraw");

        assertFalse(subscription.isActive(tokenId), "subscription is inactive");
        assertEq(subscription.deposited(tokenId), 0, "0 tokens deposited");
    }

    function testWithdraw_revert_nonExisting() public {
        uint256 tokenId = 1000;

        vm.prank(alice);
        vm.expectRevert("SUB: subscription does not exist");
        subscription.withdraw(tokenId, 10000);
    }

    function testWithdraw_revert_notOwner() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        vm.prank(bob);
        vm.expectRevert("SUB: not the owner");
        subscription.withdraw(tokenId, 10000);
        assertEq(
            testToken.balanceOf(address(subscription)),
            initialDeposit,
            "token balance not changed"
        );
        assertEq(
            subscription.deposited(tokenId),
            initialDeposit,
            "100 tokens deposited"
        );
    }

    function testWithdraw_revert_largerAmount() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        vm.prank(alice);
        vm.expectRevert("SUB: amount exceeds withdrawable");
        subscription.withdraw(tokenId, initialDeposit + 1);
        assertEq(
            testToken.balanceOf(address(subscription)),
            initialDeposit,
            "token balance not changed"
        );
        assertEq(
            subscription.deposited(tokenId),
            initialDeposit,
            "100 tokens deposited"
        );
    }

    function testCancel() public {
        uint256 initialDeposit = 100;
        uint256 tokenId = mintToken(alice, initialDeposit);

        uint256 passed = 5;
        vm.roll(block.number + passed);

        uint256 aliceBalance = testToken.balanceOf(alice);

        uint256 amount = initialDeposit - passed * rate;

        assertEq(subscription.withdrawable(tokenId), amount, "withdrawable amount is 75");

        vm.expectEmit(true, true, true, true);
        emit SubscriptionWithdrawn(tokenId, amount, initialDeposit - amount);

        vm.prank(alice);
        subscription.cancel(tokenId);

        assertEq(
            testToken.balanceOf(alice),
            aliceBalance + amount,
            "alice only reduced by 'used' amount"
        );
        assertEq(
            testToken.balanceOf(address(subscription)),
            initialDeposit - amount,
            "contract only contains 'used' amount"
        );
        assertEq(
            subscription.withdrawable(tokenId),
            0,
            "withdrawable amount is 0"
        );

        assertFalse(subscription.isActive(tokenId), "subscription is inactive");
        assertEq(
            subscription.deposited(tokenId),
            initialDeposit - amount,
            "25 tokens deposited"
        );
    }

    function testCancel_revert_nonExisting() public {
        uint256 tokenId = 100;

        vm.prank(alice);
        vm.expectRevert("SUB: subscription does not exist");
        subscription.cancel(tokenId);
        assertEq(
            testToken.balanceOf(address(subscription)),
            0,
            "token balance not changed"
        );
    }

    function testClaimable() public {
        mintToken(alice, 1_000);

        vm.roll(block.number + (epochSize * 2));

        // partial epoch + complete epoch
        assertEq(
            subscription.claimable(),
            9 * rate + epochSize * rate,
            "claimable partial epoch"
        );
    }

    function testClaimable_epoch0() public {
        mintToken(alice, 1_000);

        vm.roll(block.number + (epochSize * 1));

        // epoch 0 is not processed on its own
        assertEq(subscription.claimable(), 0, "no funds claimable");
    }

    function testClaimable_expiring() public {
        uint256 tokenId = mintToken(alice, 100);

        vm.roll(block.number + (epochSize * 3));

        assertFalse(subscription.isActive(tokenId), "Subscription inactive");
        assertEq(subscription.claimable(), 100, "all funds claimable");
    }

    function testClaim() public {
        uint256 tokenId = mintToken(alice, 1_000);

        assertEq(
            subscription.activeSubscriptions(),
            0,
            "active subs not updated in current epoch"
        );
        vm.roll(block.number + (epochSize * 2));

        // partial epoch + complete epoch
        uint256 claimable = subscription.claimable();
        assertEq(
            claimable,
            9 * rate + epochSize * rate,
            "claimable partial epoch"
        );

        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(claimable, claimable);

        vm.prank(owner);
        subscription.claim();

        assertEq(
            testToken.balanceOf(owner),
            claimable,
            "claimable funds transferred to owner"
        );
        assertEq(
            subscription.activeSubscriptions(),
            1,
            "subscriptions updated"
        );

        assertEq(
            subscription.claimable(),
            0,
            "no funds claimable right after claim"
        );

        assertEq(
            subscription.deposited(tokenId),
            1_000,
            "1000 tokens deposited"
        );
    }

    function testClaim_onlyOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        subscription.claim();
    }

    function testClaim_nextEpoch() public {
        uint256 tokenId = mintToken(alice, 1_000);

        assertEq(
            subscription.activeSubscriptions(),
            0,
            "active subs not updated in current epoch"
        );
        vm.roll(block.number + (epochSize * 2));

        // partial epoch + complete epoch
        uint256 claimable = subscription.claimable();
        uint256 totalClaimed = claimable;
        assertEq(
            claimable,
            9 * rate + epochSize * rate,
            "claimable partial epoch"
        );
        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(claimable, totalClaimed);

        vm.prank(owner);
        subscription.claim();

        uint256 ownerBalance = testToken.balanceOf(owner);
        assertEq(
            ownerBalance,
            claimable,
            "claimable funds transferred to owner"
        );
        assertEq(
            subscription.activeSubscriptions(),
            1,
            "subscriptions updated"
        );

        assertEq(
            subscription.claimable(),
            0,
            "no funds claimable right after claim"
        );

        vm.roll(block.number + (epochSize));
        claimable = subscription.claimable();
        totalClaimed += claimable;
        assertEq(claimable, epochSize * rate, "new epoch claimable");

        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(claimable, totalClaimed);

        vm.prank(owner);
        subscription.claim();

        assertEq(
            testToken.balanceOf(owner),
            ownerBalance + claimable,
            "new funds transferred to owner"
        );
        assertEq(
            subscription.activeSubscriptions(),
            1,
            "subscriptions updated"
        );

        assertEq(
            subscription.deposited(tokenId),
            1_000,
            "1000 tokens deposited"
        );
    }

    function testClaim_expired() public {
        uint256 funds = 100;
        uint256 tokenId = mintToken(alice, funds);

        assertEq(
            subscription.activeSubscriptions(),
            0,
            "active subs not updated in current epoch"
        );
        vm.roll(block.number + (epochSize * 3));

        assertFalse(subscription.isActive(tokenId), "Subscription inactive");
        assertEq(subscription.claimable(), funds, "all funds claimable");

        vm.expectEmit(true, true, true, true);
        emit FundsClaimed(funds, funds);

        vm.prank(owner);
        subscription.claim();

        assertEq(
            testToken.balanceOf(owner),
            funds,
            "all funds transferred to owner"
        );

        assertEq(subscription.activeSubscriptions(), 0, "active subs updated");
        assertEq(
            subscription.claimable(),
            0,
            "no funds claimable right after claim"
        );

        assertEq(subscription.deposited(tokenId), 100, "100 tokens deposited");
    }
}
