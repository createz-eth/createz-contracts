// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {OzInitializableBind} from "../../src/dependency/OzInitializable.sol";
import {ERC20DecimalsMock} from "../mocks/ERC20DecimalsMock.sol";
import "../../src/subscription/PaymentToken.sol";

contract TestPaymentToken is OzInitializableBind, PaymentToken {
    constructor(address _token) initializer {
        __PaymentToken_init(_token);
    }

    function paymentToken() public view returns (address) {
        return _paymentToken();
    }

    function decimals() public view returns (uint8) {
        return _decimals();
    }

    function paymentTokenSend(address payable to, uint256 amount) public {
        _paymentTokenSend(to, amount);
    }

    function paymentTokenReceive(address from, uint256 amount) public payable {
        // this has to be payable as the surrounding function has to be payable
        _paymentTokenReceive(from, amount);
    }

    receive() external payable {
        revert("receive failed");
    }
}

contract PaymentTokenTest is Test {
    ERC20DecimalsMock private token;
    TestPaymentToken private pt;

    function setUp() public {}

    function testSetPaymentToken_erc20(uint8 _decimals) public {
        token = new ERC20DecimalsMock(_decimals);
        pt = new TestPaymentToken(address(token));

        assertEq(_decimals, pt.decimals(), "decimals set");
        assertEq(address(token), address(pt.paymentToken()), "token set");
    }

    function testSetPaymentToken_native() public {
        pt = new TestPaymentToken(address(0));

        assertEq(18, pt.decimals(), "decimals set");
        assertEq(address(0), address(pt.paymentToken()), "token set");
    }

    function testPaymentTokenSend_erc20(uint8 _decimals, address payable to, uint256 mint, uint256 amount) public {
        vm.assume(to != address(0));
        mint = bound(mint, 1 ether, type(uint256).max);
        amount = bound(amount, 0, mint);
        token = new ERC20DecimalsMock(_decimals);
        pt = new TestPaymentToken(address(token));

        token.mint(address(pt), mint);
        assertEq(0, token.balanceOf(to), "to does not have any tokens");

        pt.paymentTokenSend(to, amount);
        assertEq(amount, token.balanceOf(to), "token amount sent");
    }

    function testPaymentTokenSend_native(address payable to, uint256 mint, uint256 amount) public {
        assumePayable(to);
        assumeNotPrecompile(to);
        vm.assume(to.balance == 0);
        mint = bound(mint, 1 ether, type(uint256).max);
        amount = bound(amount, 0, mint);
        pt = new TestPaymentToken(address(0));

        deal(address(pt), mint);
        pt.paymentTokenSend(to, amount);
        assertEq(amount, to.balance, "eth amount sent");
    }

    function testPaymentTokenSend_native_receiveFail(uint256 mint, uint256 amount) public {
        mint = bound(mint, 1 ether, type(uint256).max);
        amount = bound(amount, 0, mint);
        token = new ERC20DecimalsMock(18);
        pt = new TestPaymentToken(address(0));

        deal(address(pt), mint);
        vm.expectRevert();
        pt.paymentTokenSend(payable(address(token)), amount);
    }

    function testPaymentTokenReceive_erc20(uint8 _decimals, address from, uint256 mint, uint256 amount) public {
        vm.assume(from != address(0));
        mint = bound(mint, 1 ether, type(uint256).max);
        amount = bound(amount, 0, mint);
        token = new ERC20DecimalsMock(_decimals);
        pt = new TestPaymentToken(address(token));

        assertEq(0, token.balanceOf(address(pt)), "contract does not have any tokens");
        token.mint(from, mint);

        vm.prank(from);
        token.approve(address(pt), amount);

        pt.paymentTokenReceive(from, amount);

        assertEq(amount, token.balanceOf(address(pt)), "token amount sent");
    }

    function testPaymentTokenReceive_native(address from, uint256 mint, uint256 amount) public {
        mint = bound(mint, 1 ether, type(uint256).max);
        amount = bound(amount, 0, mint);
        pt = new TestPaymentToken(address(0));

        assertEq(0, address(pt).balance, "contract does not have any eth");
        deal(from, mint);

        vm.prank(from);
        pt.paymentTokenReceive{value: amount}(from, amount);

        assertEq(amount, address(pt).balance, "eth amount sent");
    }

    function testPaymentTokenReceive_native_otherAmount(address from, uint256 mint, uint256 amount) public {
        mint = bound(mint, 1 ether, type(uint256).max);
        amount = bound(amount, 0, mint - 1);
        pt = new TestPaymentToken(address(0));

        assertEq(0, address(pt).balance, "contract does not have any eth");
        deal(from, mint);

        vm.startPrank(from);
        vm.expectRevert();
        pt.paymentTokenReceive{value: amount}(from, mint);
    }
}
