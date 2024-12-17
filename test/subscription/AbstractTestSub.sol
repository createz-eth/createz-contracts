// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "../../src/subscription/Subscription.sol";
import "../../src/subscription/Epochs.sol";
import {SubData} from "../../src/subscription/UserData.sol";

import {OzInitializable, OzInitializableBind} from "../../src/dependency/OzInitializable.sol";

abstract contract TestSubEvents {
    event Burned(uint256 indexed tokenId);

    event SubCreated(uint256 indexed tokenId, uint256 indexed amount, uint24 indexed multiplier);
    event AddedToEpochs(uint256 depositedAt, uint256 indexed amount, uint256 shares, uint256 rate);

    event SubExtended(uint256 indexed tokenId, uint256 indexed amount);
    event EpochsExtended(
        uint256 indexed depositedAt,
        uint256 indexed oldDeposit,
        uint256 indexed newDeposit,
        uint256 shares,
        uint256 rate
    );

    event SubWithdrawn(uint256 indexed tokenId, uint256 indexed amount);
    event EpochsReduced(
        uint256 indexed depositedAt,
        uint256 indexed oldDeposit,
        uint256 indexed newDeposit,
        uint256 shares,
        uint256 rate
    );

    event MultiChange(uint256 indexed tokenId, uint24 indexed multiplier);

    event TipAdded(uint256 indexed tokenId, uint256 indexed amount);
}

/**
 * @notice Abstract Sub implementation for testing
 * @dev inherits basic ERC721 and other CRUD functions
 *  providing basic functionality in order to test Subscription functions. It
 *  does not inherit UserData and Epochs implementation but contains revert
 *  functions instead. Override these functions for testing as needed
 *
 */
abstract contract AbstractTestSub is
    OzInitializableBind,
    TestSubEvents,
    // actual impl
    MaxSupply,
    TokenIdProvider,
    Metadata,
    Rate,
    PaymentToken,
    FlagSettings,
    /**
     * omitted for mocking
     * Epochs,
     * UserData,
     *
     */
    Subscription
{
    address private _owner;
    uint256 private epochSize;
    uint24 private lock;

    constructor(
        address owner_,
        string memory tokenName,
        string memory tokenSymbol,
        MetadataStruct memory _metadata,
        SubSettings memory _settings
    ) {
        _owner = owner_;

        initialize(tokenName, tokenSymbol, _metadata, _settings);
    }

    function initialize(
        string memory tokenName,
        string memory tokenSymbol,
        MetadataStruct memory _metadata,
        SubSettings memory _settings
    ) public override initializer {
        __ERC721_init_unchained(tokenName, tokenSymbol);
        __FlagSettings_init_unchained();
        __Rate_init_unchained(_settings.rate);
        __PaymentToken_init_unchained(_settings.token);
        __MaxSupply_init_unchained(_settings.maxSupply);
        __TokenIdProvider_init_unchained(0);
        __Metadata_init_unchained(_metadata.description, _metadata.image, _metadata.externalUrl);

        epochSize = _settings.epochSize;
        lock = _settings.lock;
    }

    // helpers
    function simpleMint(address to, uint256 tokenId) external {
        _safeMint(to, tokenId);
    }

    // override HandleOwned
    function _checkOwner() internal view override {
        require(_msgSender() == _owner, "Not Owner");
    }

    function _isValidSigner(address acc) internal view override returns (bool) {
        return acc == _owner;
    }

    function owner() public view override returns (address) {
        return _owner;
    }

    // TimeAware
    function _now() internal view override returns (uint256) {
        return block.number;
    }

    // UserData
    function _lock() internal pure override returns (uint24) {
        revert("SUB: not implemented");
    }

    function _isActive(uint256) internal pure override returns (bool) {
        revert("SUB: not implemented");
    }

    function _expiresAt(uint256) internal pure override returns (uint256) {
        revert("SUB: not implemented");
    }

    function _deleteSubscription(uint256) internal virtual override {
        revert("SUB: not implemented");
    }

    function _createSubscription(uint256, uint256, uint24) internal virtual override {
        revert("SUB: not implemented");
    }

    function _extendSubscription(uint256, uint256)
        internal
        virtual
        override
        returns (uint256, uint256, uint256, bool)
    {
        revert("SUB: not implemented");
    }

    function _withdrawableFromSubscription(uint256) internal view virtual override returns (uint256) {
        revert("SUB: not implemented");
    }

    function _withdrawFromSubscription(uint256, uint256)
        internal
        virtual
        override
        returns (uint256, uint256, uint256)
    {
        revert("SUB: not implemented");
    }

    function _changeMultiplier(uint256, uint24) internal virtual override returns (bool, MultiplierChange memory) {
        revert("SUB: not implemented");
    }

    function _spent(uint256) internal pure override returns (uint256, uint256) {
        revert("SUB: not implemented");
    }

    function _totalDeposited(uint256) internal pure virtual override returns (uint256) {
        revert("SUB: not implemented");
    }

    function _multiplier(uint256) internal pure virtual override returns (uint24) {
        revert("SUB: not implemented");
    }

    function _lastDepositedAt(uint256) internal pure override returns (uint256) {
        revert("SUB: not implemented");
    }

    function _addTip(uint256, uint256) internal virtual override {
        revert("SUB: not implemented");
    }

    function _tips(uint256) internal pure virtual override returns (uint256) {
        revert("SUB: not implemented");
    }

    function _allTips() internal pure virtual override returns (uint256) {
        revert("SUB: not implemented");
    }

    function _claimedTips() internal pure virtual override returns (uint256) {
        revert("SUB: not implemented");
    }

    function _claimableTips() internal view virtual override returns (uint256) {
        revert("SUB: not implemented");
    }

    function _claimTips() internal virtual override returns (uint256) {
        revert("SUB: not implemented");
    }

    function _getSubData(uint256) internal pure override returns (SubData memory) {
        revert("SUB: not implemented");
    }

    // Epochs
    function _epochSize() internal pure override returns (uint256) {
        revert("SUB: not implemented");
    }

    function _currentEpoch() internal pure virtual override returns (uint256) {
        revert("SUB: not implemented");
    }

    function _lastProcessedEpoch() internal pure virtual override returns (uint256) {
        revert("SUB: not implemented");
    }

    function _activeSubShares() internal pure override returns (uint256) {
        revert("SUB: not implemented");
    }

    function _claimed() internal pure virtual override returns (uint256) {
        revert("SUB: not implemented");
    }

    function _scanEpochs(uint256, uint256) internal view virtual override returns (uint256, uint256, uint256) {
        revert("SUB: not implemented");
    }

    function _claimEpochs(uint256 rate, uint256 upToEpoch) internal virtual override returns (uint256) {
        revert("SUB: not implemented");
    }

    function _addToEpochs(uint256, uint256, uint256, uint256) internal virtual override {
        revert("SUB: not implemented");
    }

    function _extendInEpochs(uint256, uint256, uint256, uint256, uint256) internal virtual override {
        revert("SUB: not implemented");
    }

    function _reduceInEpochs(uint256, uint256, uint256, uint256, uint256) internal virtual override {
        revert("SUB: not implemented");
    }

    function _asInternal(uint256) internal view virtual override returns (uint256) {
        revert("SUB: not implemented");
    }

    function _asExternal(uint256) internal view virtual override returns (uint256) {
        revert("SUB: not implemented");
    }
}

contract SimpleTestSub is AbstractTestSub {
    constructor(
        address owner_,
        string memory tokenName,
        string memory tokenSymbol,
        MetadataStruct memory _metadata,
        SubSettings memory _settings
    ) AbstractTestSub(owner_, tokenName, tokenSymbol, _metadata, _settings) {}
}
