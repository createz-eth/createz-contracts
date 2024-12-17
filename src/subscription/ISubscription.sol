// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import {IERC721Metadata} from "openzeppelin-contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC721Enumerable} from "openzeppelin-contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {IERC4906} from "openzeppelin-contracts/interfaces/IERC4906.sol";

import {IOwnable} from "../IOwnable.sol";
import {IHasFlags} from "../FlagSettings.sol";

import {IMetadata} from "./Metadata.sol";

/**
 * @title Subscription Events
 * @notice Marker interface containing Subscription related events
 */
interface SubscriptionEvents {
    /**
     * @notice Renew event is emitted when a subscription is prolonged
     */
    event SubscriptionRenewed(
        uint256 indexed tokenId,
        uint256 indexed addedAmount,
        address indexed depositor,
        uint256 deposited,
        string message
    );

    /**
     * @notice Withdrawn event is emitted when an active subscription is reduced by withdrawing funds
     */
    event SubscriptionWithdrawn(
        uint256 indexed tokenId, uint256 indexed removedAmount, address indexed receiver, uint256 deposited
    );

    /**
     * @notice Tipped event is emitted when a tip was deposited into a subscription
     */
    event Tipped(
        uint256 indexed tokenId, uint256 indexed amount, address indexed depositor, uint256 deposited, string message
    );

    /**
     * @notice MutliplierChanged event is emitted if the multiplier of a sub is changed
     */
    event MultiplierChanged(
        uint256 indexed tokenId, address indexed executor, uint24 oldMultiplier, uint24 newMultiplier
    );
}

/**
 * @title Subscription contract metadata
 * @notice contains general properties of subscription
 */
struct MetadataStruct {
    /**
     * @notice Description of the subscription plan
     */
    string description;
    /**
     * @notice An image related to the subscription
     */
    string image;
    /**
     * @notice An external URL pointing to further resources and documentation
     */
    string externalUrl;
}

/**
 * @title Subscription settings
 * @notice Contains immutable settings that are applied to new subscription and are the base for any internal computations
 */
struct SubSettings {
    /**
     * @notice The payment ERC20 token to be used in a subscription
     */
    address token;
    /**
     * @notice The rate describes the amount of tokens to be paid per time unit
     * @dev The rate is based on 18 decimals and is to be paid per time unit
     */
    uint256 rate;
    /**
     * @notice The percentage amount of tokens to be locked in the subscription on a new deposit
     * @dev The percentage amount is denominated in values from 0 (0%) to 10_000 (100%)
     */
    uint24 lock;
    /**
     * @notice The size of an epoch measured in the underlying time unit
     * @dev Epochs are generally counted from the 'beginning' of time, depending on the underlying time unit
     */
    uint256 epochSize;
    /**
     * @notice The maximum supply of subscription that can be minted
     */
    uint256 maxSupply;
}

/**
 * @title Subscription Contract metadata
 * @notice enforces access subscription contract related information
 */
interface SubscriptionMetadata {
    /**
     * @notice Provides general information related to the contract
     */
    function contractURI() external view returns (string memory);
}

/**
 * @title Subscription depositable view
 * @notice provides methods for subscribers to deposit funds into their subscription
 */
interface Depositable is SubscriptionEvents, IERC4906 {
    /**
     * @notice Mints a new subscription and adds funds to it. The multiplier cannot be changed after this point
     * @dev the multiplier is set on creation and cannot be changed
     * @param amount amount of payment tokens to add
     * @param multiplier multiplier to set for this subscription. The multiplier is applied to the rate. Value can range from 100 (1x) to 10_000 (10x)
     * @param message message that is emitted on a successful renewal
     * @return the token id of the new subscription
     */
    function mint(uint256 amount, uint24 multiplier, string calldata message) external payable returns (uint256);

    /**
     * @notice Adds funds to an existing subscription and extends it
     * @param tokenId id of the subscription token
     * @param amount amount of payment tokens to add
     * @param message message that is emitted on a successful renewal
     */
    function renew(uint256 tokenId, uint256 amount, string calldata message) external payable;

    /**
     * @notice changes the mutliplier of a given subscription
     * @notice the current subscription streak, if any, is ended and a new streak with the new multiplier is started
     * @param tokenId id of the subscription token
     * @param multiplier the new multiplier to apply
     */
    function changeMultiplier(uint256 tokenId, uint24 multiplier) external;

    /**
     * @notice Adds a tip to the given subscription, the sent amount does not extend the subscription, but increases the tip counter
     * @dev amount is based on the payment token decimals
     * @param tokenId id of the subscription token
     * @param amount amount of payment tokens to add as a tip
     * @param message message that is emitted on a successful renewal
     */
    function tip(uint256 tokenId, uint256 amount, string calldata message) external payable;

    /**
     * @notice Checks if a subscription is still valid
     * @param tokenId id of the subscription token
     * @return whether or not the given subscription is still valid
     */
    function isActive(uint256 tokenId) external view returns (bool);

    /**
     * @notice Retrieves the multiplier of a given token
     * @dev valid values are between 100 (100% or 1x) and 10_000
     * @param tokenId id of the subscription token
     * @return multiplier value
     */
    function multiplier(uint256 tokenId) external view returns (uint24);

    /**
     * @notice Queries the expiration time of a given subscription
     * @param tokenId id of the subscription token
     * @return the time unit on which the subscription expires
     */
    function expiresAt(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Queries the amount of funds ever deposited into the subscription
     * @dev This includes all used funds and still active funds that can be withdrawn
     * @param tokenId id of the subscription token
     * @return the amount of funds ever deposited into the subscription
     */
    function deposited(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Queries the amount of funds spent in the subscription
     * @dev All the funds that were actually 'used'
     * @param tokenId id of the subscription token
     * @return the amount of funds spent in the subscription
     */
    function spent(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Queries the amount of deposited funds that were not yet spent on the subscription
     * @dev This is based on the active deposit and might include locked and withdrawable funds
     * @param tokenId id of the subscription token
     * @return the amount of funds not yet spent in the subscription
     */
    function unspent(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Queries the amount of deposited funds that can be withdrawn from an active subscription
     * @dev The amount of unspent funds that are not locked
     *  @return the amount of funds that can be withdrawn
     */
    function activeSubShares() external view returns (uint256);

    /**
     * @notice Queries the amount of tipped funds
     * @param tokenId id of the subscription token
     *  @return the amount of tipped funds
     */
    function tips(uint256 tokenId) external view returns (uint256);
}

/**
 * @title Subscription withdrawable view
 * @notice provides methods for subscribers to withdraw funds from their subscription
 */
interface Withdrawable is SubscriptionEvents, IERC4906 {
    /**
     * @notice Removes withdrawable funds from an active subscription and reduces the subscription time
     * @dev amount is based on the payment token decimals
     * @param tokenId id of the subscription token
     * @param amount amount of payment tokens to remove
     */
    function withdraw(uint256 tokenId, uint256 amount) external;

    /**
     * @notice Removes all withdrawable funds from an active subscription and reduces the subscription time to a minimum
     * @notice this method should be used to remove all possible funds as the withdrawable amount shrinks with each time unit and can cause reverts
     * @param tokenId id of the subscription token
     */
    function cancel(uint256 tokenId) external;

    /**
     * @notice Queries the amount of deposited funds that can be withdrawn from an active subscription
     * @dev The amount of unspent fund that are not locked
     * @param tokenId id of the subscription token
     * @return the amount of funds that can be withdrawn
     */
    function withdrawable(uint256 tokenId) external view returns (uint256);
}

/**
 * @title Subscription burnable view
 * @notice provides methods for subscribers to burn their subscription
 */
interface Burnable {
    /**
     * @notice "Burns" a subscription token, deletes all achieved subscription data and does not withdraw any withdrawable funds
     * @param tokenId token to burn
     */
    function burn(uint256 tokenId) external;
}

/**
 * @title Claim events interface
 * @notice contains interfaces related to owner claiming
 */
interface ClaimEvents {
    /**
     * @notice Claimed event is emitted when the owner claims funds from the subscription plan
     */
    event FundsClaimed(uint256 amount, uint256 totalClaimed);

    /**
     * @notice Claimed event is emitted when the owner claims tips
     */
    event TipsClaimed(uint256 amount, uint256 totalClaimed);
}

/**
 * @title Owner Claiming
 * @notice contains methods related to claiming funds by the owner
 */
interface Claimable is ClaimEvents {
    /**
     * @notice Claim spent subscription funds from completed epochs. Claims are
     * calculated from the last processed epoch to the given epoch
     * @dev The given epoch should usually be the current epoch. Smaller values
     * between the last processed epoch and the current epoch should be used to
     * claim smaller batches of epochs.
     * @param to address to send funds to
     * @param endEpoch epoch up until to claim to (exclusive)
     */
    // function claim(address to, uint256 endEpoch) external;

    /**
     * @notice Claim spent subscription funds from completed epochs.
     * @param to address to send funds to
     */
    function claim(address payable to) external;

    /**
     * @notice Queries the amount of funds that can be claimed by the owner
     * @dev claimable funds originate from completed epochs that were not claimed before
     * @return amount of claimable subscription funds for the given time span
     * @param startEpoch epoch the claim should start from (inclusive)
     * @param endEpoch epoch the claim should end at (exclusive)
     */
    // function claimable(uint256 startEpoch, uint256 endEpoch) external view returns (uint256);

    /**
     * @notice Queries the amount of funds that can be claimed by the owner
     * @dev claimable funds originate from completed epochs that were not claimed before
     * @return amount of currently claimable subscription funds
     */
    function claimable() external view returns (uint256);

    /**
     * @notice Queries the amount of subscription funds that were claimed up until now
     * @dev only returns subscription funds, tips are excluded
     * @return amount of claimed funds originating from subscriptions
     */
    function claimed() external view returns (uint256);

    /**
     * @notice Claim tips
     * @param to address to send funds to
     */
    function claimTips(address payable to) external;

    /**
     * @notice Queries the amount of tipping funds that can be claimed by the owner
     * @return amount of currently claimable tips
     */
    function claimableTips() external view returns (uint256);

    /**
     * @notice Queries the amount of tipping funds that were claimed up until now
     * @dev only returns tipping funds, subscription related funds are excluded
     * @return amount of claimed funds originating from tipping
     */
    function claimedTips() external view returns (uint256);
}

interface SubscriptionProperties {
    function settings()
        external
        view
        returns (address token, uint256 rate, uint24 lock, uint256 epochSize, uint256 maxSupply_);

    function epochState() external view returns (uint256 currentEpoch, uint256 lastProcessedEpoch);

    function setFlags(uint256 flags) external;

    function setDescription(string calldata _description) external;

    function setImage(string calldata _image) external;

    function setExternalUrl(string calldata _externalUrl) external;
}

/**
 * @title Flag settings
 * @notice constants relating to flags
 */
abstract contract SubscriptionFlags {
    uint256 public constant MINTING_PAUSED = 0x1;
    uint256 public constant RENEWAL_PAUSED = 0x2;
    uint256 public constant TIPPING_PAUSED = 0x4;

    uint256 public constant ALL_FLAGS = 0x7;
}

/**
 * @title Subscription Initializer
 * @notice initializer interface for upgradeable subscription contracts
 */
interface SubscriptionInitialize {
    function initialize(
        string calldata tokenName,
        string calldata tokenSymbol,
        MetadataStruct calldata _metadata,
        SubSettings calldata _settings
    ) external;
}

/**
 * @title Subscription God interface
 */
interface ISubscription is
    IERC721,
    IERC721Metadata,
    IERC721Enumerable,
    IERC4906,
    IOwnable,
    IHasFlags,
    IMetadata,
    Claimable,
    Depositable,
    Withdrawable,
    Burnable,
    SubscriptionMetadata,
    SubscriptionInitialize
{}

/**
 * @title Subscription Godless interface
 */
interface ISubscriptionInternal is ISubscription, SubscriptionProperties {}
