// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";

abstract contract HasPaymentToken {
    address constant NATIVE_TOKEN_ADDRESS = address(0);
    uint8 constant NATIVE_TOKEN_DECIMALS = 18;

    function _paymentTokenSend(address payable to, uint256 amount) internal virtual;

    function _paymentTokenReceive(address from, uint256 amount) internal virtual;

    function _paymentToken() internal view virtual returns (address);

    function _decimals() internal view virtual returns (uint8);
}

abstract contract PaymentToken is Initializable, HasPaymentToken {
    using SafeERC20 for IERC20Metadata;
    using Address for address payable;

    struct PaymentTokenStorage {
        address _paymentToken;
        uint8 _decimals;
    }

    // keccak256(abi.encode(uint256(keccak256("createz.storage.subscription.PaymentToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PaymentTokenStorageLocation =
        0x6f5829cd7e76089adec788013c8fec4384896d2139d3621f34813ccb0ad48d00;

    function _getPaymentTokenStorage() private pure returns (PaymentTokenStorage storage $) {
        assembly {
            $.slot := PaymentTokenStorageLocation
        }
    }

    function __PaymentToken_init(address token) internal onlyInitializing {
        __PaymentToken_init_unchained(token);
    }

    function __PaymentToken_init_unchained(address token) internal onlyInitializing {
        PaymentTokenStorage storage $ = _getPaymentTokenStorage();
        $._paymentToken = token;

        if (token != NATIVE_TOKEN_ADDRESS) {
            // if it is not the native token, it has to be an ERC20
            $._decimals = IERC20Metadata(token).decimals();
        } else {
            $._decimals = NATIVE_TOKEN_DECIMALS;
        }
    }

    function _paymentTokenSend(address payable to, uint256 amount) internal virtual override {
        address token = _paymentToken();
        if (token == NATIVE_TOKEN_ADDRESS) {
            to.sendValue(amount);
        } else {
            // ERC20
            IERC20Metadata(token).safeTransfer(to, amount);
        }
    }

    function _paymentTokenReceive(address from, uint256 amount) internal virtual override {
        address token = _paymentToken();
        if (token == NATIVE_TOKEN_ADDRESS) {
            // cannot actually send native tokens from some other address, thus we check that the received
            // value checks out
            require(amount == msg.value, "PT: invalid ETH value");
        } else {
            // ERC20
            IERC20Metadata(token).safeTransferFrom(from, address(this), amount);
        }
    }

    function _paymentToken() internal view override returns (address) {
        PaymentTokenStorage storage $ = _getPaymentTokenStorage();
        return $._paymentToken;
    }

    function _decimals() internal view override returns (uint8) {
        PaymentTokenStorage storage $ = _getPaymentTokenStorage();
        return $._decimals;
    }
}