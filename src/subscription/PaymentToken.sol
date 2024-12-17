// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {OzInitializable} from "../dependency/OzInitializable.sol";

import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "openzeppelin-contracts/utils/Address.sol";

library PaymentTokenLib {
    using SafeERC20 for IERC20Metadata;
    using Address for address payable;

    address constant NATIVE_TOKEN_ADDRESS = address(0);
    uint8 constant NATIVE_TOKEN_DECIMALS = 18;

    struct PaymentTokenStorage {
        address _paymentToken;
        uint8 _decimals;
    }

    // keccak256(abi.encode(uint256(keccak256("subsub.storage.subscription.PaymentToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PaymentTokenStorageLocation =
        0x3d4585da047dd26cb39358ad8dd06dcb27eefda57a17df92d96a802687493b00;

    function _getPaymentTokenStorage() private pure returns (PaymentTokenStorage storage $) {
        assembly {
            $.slot := PaymentTokenStorageLocation
        }
    }

    function init(address token) internal {
        PaymentTokenStorage storage $ = _getPaymentTokenStorage();
        $._paymentToken = token;

        if (token != NATIVE_TOKEN_ADDRESS) {
            // if it is not the native token, it has to be an ERC20
            $._decimals = IERC20Metadata(token).decimals();
        } else {
            $._decimals = NATIVE_TOKEN_DECIMALS;
        }
    }

    function paymentTokenSend(address payable to, uint256 amount) internal {
        address token = paymentToken();
        if (token == NATIVE_TOKEN_ADDRESS) {
            to.sendValue(amount);
        } else {
            // ERC20
            IERC20Metadata(token).safeTransfer(to, amount);
        }
    }

    function paymentTokenReceive(address from, uint256 amount) internal {
        address token = paymentToken();
        if (token == NATIVE_TOKEN_ADDRESS) {
            // cannot actually send native tokens from some other address, thus we check that the received
            // value checks out
            require(amount == msg.value, "PT: invalid ETH value");
        } else {
            // ERC20
            IERC20Metadata(token).safeTransferFrom(from, address(this), amount);
        }
    }

    function paymentToken() internal view returns (address) {
        PaymentTokenStorage storage $ = _getPaymentTokenStorage();
        return $._paymentToken;
    }

    function decimals() internal view returns (uint8) {
        PaymentTokenStorage storage $ = _getPaymentTokenStorage();
        return $._decimals;
    }
}

abstract contract HasPaymentToken {
    function _paymentTokenSend(address payable to, uint256 amount) internal virtual;

    function _paymentTokenReceive(address from, uint256 amount) internal virtual;

    function _paymentToken() internal view virtual returns (address);

    function _decimals() internal view virtual returns (uint8);
}

abstract contract PaymentToken is OzInitializable, HasPaymentToken {
    function __PaymentToken_init(address token) internal {
        __PaymentToken_init_unchained(token);
    }

    function __PaymentToken_init_unchained(address token) internal {
        __checkInitializing();
        PaymentTokenLib.init(token);
    }

    function _paymentTokenSend(address payable to, uint256 amount) internal virtual override {
        PaymentTokenLib.paymentTokenSend(to, amount);
    }

    function _paymentTokenReceive(address from, uint256 amount) internal virtual override {
        PaymentTokenLib.paymentTokenReceive(from, amount);
    }

    function _paymentToken() internal view override returns (address) {
        return PaymentTokenLib.paymentToken();
    }

    function _decimals() internal view override returns (uint8) {
        return PaymentTokenLib.decimals();
    }
}
