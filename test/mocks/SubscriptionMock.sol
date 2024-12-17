// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/subscription/ISubscription.sol";
import {ERC721Mock} from "./ERC721Mock.sol";

// THIS IS A WORK IN PROGRESS, MAKE CHANGES AND ADDITIONS AS NEEDED
/**
 * @notice This implementation is intended to be used by tests that just need some sub. It does not fail
 * @notice THIS IS A WORK IN PROGRESS, MAKE CHANGES AND ADDITIONS AS NEEDED
 *
 */
contract SubscriptionMock is Depositable, Withdrawable, Burnable, ERC721Mock {
    mapping(uint256 => uint256) private _spentAmounts;

    constructor() ERC721Mock("test", "test") {}

    function renew(uint256 tokenId, uint256 amount, string calldata message) external payable {}

    function withdraw(uint256 tokenId, uint256 amount) external {}

    function cancel(uint256 tokenId) external {}

    function changeMultiplier(uint256 tokenId, uint24 multiplier) external {}

    function isActive(uint256 tokenId) external view returns (bool) {}

    function multiplier(uint256 tokenId) external view returns (uint24) {}

    function expiresAt(uint256 tokenId) external view returns (uint256) {}

    // the amount of tokens ever deposited reduced by the withdrawn amount.
    function deposited(uint256 tokenId) external view returns (uint256) {}

    // the amount of tokens spent in the subscription
    function spent(uint256 tokenId) external view returns (uint256) {
        return _spentAmounts[tokenId];
    }

    function setSpent(uint256 tokenId, uint256 amount) external {
        _spentAmounts[tokenId] = amount;
    }

    // the amount of deposited tokens that have not been spend yet
    function unspent(uint256 tokenId) external view returns (uint256) {}

    function withdrawable(uint256 tokenId) external view returns (uint256) {}

    function activeSubShares() external view returns (uint256) {}

    // adds funds to the subscription, but does not extend an active sub
    function tip(uint256 tokenId, uint256 amount, string calldata message) external payable {}

    function tips(uint256 tokenId) external view returns (uint256) {}

    /// @notice "Mints" a new subscription token
    function mint(uint256 amount, uint24 multiplier, string calldata message) external payable returns (uint256) {}

    /// @notice "Burns" a subscription token, deletes all achieved subscription
    ///         data and does not withdraw any withdrawable funds
    function burn(uint256 tokenId) public override(Burnable, ERC721Mock) {
        super.burn(tokenId);
    }
}
