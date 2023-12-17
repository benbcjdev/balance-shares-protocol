// SPDX-License-Identifier: MIT
// Primordium Contracts

pragma solidity ^0.8.20;

import {StorageLayout} from "./StorageLayout.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IBalanceShareAllocations} from "../interfaces/IBalanceShareAllocations.sol";
import {ERC20Asset, ERC20AssetLibrary} from "../types/ERC20Asset.sol";

/**
 * @title Balance share processing functions for BalanceSharesSingleton
 * @author Ben Jett - @BCJdevelopment
 * @notice Balance shares are stored under a mapping of uint256 balance share identifiers, where each balance share ID
 * represents a unique balance share for the specified client.
 *
 * Therefore, client address (0xaa)'s balance share ID uint256(1) is a completely separate balance share than client
 * address (0xbb)'s balance share ID uint256(1), even though the balance share ID is the same.
 *
 * Each of the balance share allocation functions below require specifying both the client address and the client's
 * balance share ID in order to apply the allocations to the correct balance share.
 */
contract BalanceShareAllocations is StorageLayout, IBalanceShareAllocations {
    using ERC20AssetLibrary for ERC20Asset;

    error BalanceShareInactive(address client, uint256 balanceShareId);
    error InvalidAllocationAmount(uint256 amountToAllocate);
    error InvalidMsgValue(uint256 expectedValue, uint256 actualValue);

    /**
     * Emitted when an asset is allocated to a balance share for the specified client and balance share ID.
     * @dev The new asset remainder will only be included if the amountAllocated is zero.
     */
    event BalanceShareAssetAllocated(
        address indexed client,
        uint256 indexed balanceShareId,
        address indexed asset,
        uint256 amountAllocated,
        uint256 newAssetRemainder
    );

    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return
            interfaceId == type(IBalanceShareAllocations).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IBalanceShareAllocations
    function getBalanceShareTotalBPS(
        address client,
        uint256 balanceShareId
    ) public view override returns (uint256 totalBps) {
        totalBps = _getCurrentBalanceSumCheckpoint(_getBalanceShare(client, balanceShareId)).totalBps;
    }

    /// @inheritdoc IBalanceShareAllocations
    function getBalanceShareAllocation(
        address client,
        uint256 balanceShareId,
        address asset,
        uint256 balanceIncreasedBy
    ) public view override returns (uint256 amountToAllocate) {
        (amountToAllocate,,) = _calculateBalanceShareAllocation(
            _getBalanceShare(client, balanceShareId),
            asset,
            balanceIncreasedBy,
            false
        );
    }

    /// @inheritdoc IBalanceShareAllocations
    function getBalanceShareAllocationWithRemainder(
        address client,
        uint256 balanceShareId,
        address asset,
        uint256 balanceIncreasedBy
    ) public view override returns (uint256 amountToAllocate, bool remainderIncrease) {
        uint256 newAssetRemainder;
        (amountToAllocate, newAssetRemainder,) = _calculateBalanceShareAllocation(
            _getBalanceShare(client, balanceShareId),
            asset,
            balanceIncreasedBy,
            true
        );
        remainderIncrease = newAssetRemainder < MAX_BPS;
    }

    function _calculateBalanceShareAllocation(
        BalanceShare storage _balanceShare,
        address asset,
        uint256 balanceIncreasedBy,
        bool useRemainder
    ) internal view returns (
        uint256 amountToAllocate,
        uint256 newAssetRemainder,
        BalanceSumCheckpoint storage _currentBalanceSumCheckpoint
    ) {
        _currentBalanceSumCheckpoint = _getCurrentBalanceSumCheckpoint(_balanceShare);

        if (!useRemainder) {
            newAssetRemainder = MAX_BPS;
        }

        uint256 totalBps = _currentBalanceSumCheckpoint.totalBps;
        if (totalBps > 0) {
            if (useRemainder) {
                uint256 currentAssetRemainder = _getBalanceSum(_currentBalanceSumCheckpoint, asset).remainder;
                balanceIncreasedBy += currentAssetRemainder;
                // Asset remainder is the mulmod
                newAssetRemainder = mulmod(balanceIncreasedBy, totalBps, MAX_BPS);
            }

            // Use muldiv to protect against potential overflow
            amountToAllocate = Math.mulDiv(balanceIncreasedBy, totalBps, MAX_BPS);
        }
    }

    /// @inheritdoc IBalanceShareAllocations
    function allocateToBalanceShare(
        address client,
        uint256 balanceShareId,
        address asset,
        uint256 amountToAllocate
    ) public payable override {
        if (amountToAllocate == 0) {
            revert InvalidAllocationAmount(amountToAllocate);
        }

        BalanceShare storage _balanceShare = _getBalanceShare(client, balanceShareId);
        BalanceSumCheckpoint storage _currentBalanceSumCheckpoint = _getCurrentBalanceSumCheckpoint(_balanceShare);

        // Check that the balance share is active
        if (_currentBalanceSumCheckpoint.totalBps == 0) {
            revert BalanceShareInactive(client, balanceShareId);
        }

        // Add the amount to the share (use MAX_BPS for remainder to signal no change)
        _addAssetToBalanceShare(
            _balanceShare,
            _getCurrentBalanceSumCheckpoint(_balanceShare),
            asset,
            amountToAllocate,
            MAX_BPS
        );

        emit BalanceShareAssetAllocated(client, balanceShareId, asset, amountToAllocate, 0);
    }

    /// @inheritdoc IBalanceShareAllocations
    function allocateToBalanceShareWithRemainder(
        uint256 balanceShareId,
        address asset,
        uint256 balanceIncreasedBy
    ) public payable override {
        if (balanceIncreasedBy > 0) {
            BalanceShare storage _balanceShare = _getBalanceShare(msg.sender, balanceShareId);

            // Calculate the amount to allocate and asset remainder internally
            (
                uint256 amountToAllocate,
                uint256 newAssetRemainder,
                BalanceSumCheckpoint storage _currentBalanceSumCheckpoint
            ) = _calculateBalanceShareAllocation(_balanceShare, asset, balanceIncreasedBy, true);

            _addAssetToBalanceShare(
                _balanceShare,
                _currentBalanceSumCheckpoint,
                asset,
                amountToAllocate,
                newAssetRemainder
            );

            emit BalanceShareAssetAllocated(msg.sender, balanceShareId, asset, amountToAllocate, newAssetRemainder);
        }
    }

    /**
     * @dev Helper function that adds the provided asset amount to the balance sum checkpoint. Transfers the
     * amountToAllocate of the ERC20 asset from msg.sender to this contract (or checks that msg.value is equal to the
     * amountToAllocate for an address(0) asset). Also updates the asset remainder unless newAssetRemainder is equal to
     * the MAX_BPS.
     * @notice This function assumes the provided _currentBalanceSumCheckpoint is the CURRENT checkpoint (at the current
     * balanceSumCheckpointIndex).
     */
    function _addAssetToBalanceShare(
        BalanceShare storage _balanceShare,
        BalanceSumCheckpoint storage _currentBalanceSumCheckpoint,
        address asset,
        uint256 amountToAllocate,
        uint256 newAssetRemainder
    ) internal {
        if (amountToAllocate == 0 && newAssetRemainder == MAX_BPS) {
            return;
        }

        BalanceSumCheckpoint storage _balanceSumCheckpoint = _currentBalanceSumCheckpoint;

        // Transfer the asset to this contract
        ERC20Asset.wrap(asset).receiveFrom(msg.sender, amountToAllocate);

        unchecked {
            BalanceSum storage _currentBalanceSum = _getBalanceSum(_balanceSumCheckpoint, asset);

            uint256 maxBalanceSum = MAX_BALANCE_SUM_BALANCE;
            uint256 maxBps = MAX_BPS;
            assembly ("memory-safe") {
                // Cache the packed BalanceSumCheckpoint
                let balanceSumCheckpointPacked := sload(_balanceSumCheckpoint.slot)

                // Check that "hasBalances" is true, or else mark it as true
                if iszero(and(shr(16, balanceSumCheckpointPacked), 0xff)) {
                    // We don't need to mask the current value, because we already know the 1 bool byte is zero
                    balanceSumCheckpointPacked := or(balanceSumCheckpointPacked, shl(16, 0x01))
                    sstore(_balanceSumCheckpoint.slot, balanceSumCheckpointPacked)
                }

                // Cache packed BalanceSum slot
                let balanceSumPacked := sload(_currentBalanceSum.slot)

                // Load current remainder (first 48 bits)
                let assetRemainder := and(balanceSumPacked, MASK_UINT48)
                // Update to new remainder if the new one is less than MAX_BPS
                if lt(newAssetRemainder, maxBps) {
                    assetRemainder := newAssetRemainder
                }

                // Load current balance (shift BalanceSum slot right by 48 bits)
                let assetBalance := shr(48, balanceSumPacked)

                // Add to the balance sum, looping to avoid overflow as needed
                for { } true { } {
                    // Set the balance increase amount (do not allow overflow of BalanceSum.balance)
                    let balanceIncrease := sub(maxBalanceSum, assetBalance)
                    if lt(amountToAllocate, balanceIncrease) {
                        balanceIncrease := amountToAllocate
                    }

                    // Add to the current balance
                    assetBalance := add(assetBalance, balanceIncrease)

                    // Update the slot cache, then store
                    balanceSumPacked := or(assetRemainder, shl(48, assetBalance))
                    sstore(_currentBalanceSum.slot, balanceSumPacked)

                    // Finished once the allocation reaches zero
                    amountToAllocate := sub(amountToAllocate, balanceIncrease)
                    if iszero(amountToAllocate) {
                        break
                    }

                    // If more to allocate, start a new balance sum checkpoint (and copy the totalBps)
                    mstore(0, add(sload(_balanceShare.slot), 0x01)) // Store incremented checkpoint index in scratch
                    sstore(_balanceShare.slot, mload(0)) // Update the checkpoint index in storage

                    // Update the storage reference to the new BalanceSumCheckpoint
                    // keccak256(_balanceShare.balanceSumCheckpointIndex . _balanceShare.balanceSumCheckpoints.slot))
                    mstore(0x20, add(_balanceShare.slot, 0x01))
                    _balanceSumCheckpoint.slot := keccak256(0, 0x40)

                    // Copy over the previous packed checkpoint
                    sstore(_balanceSumCheckpoint.slot, balanceSumCheckpointPacked)

                    // Reset the current balance to zero
                    assetBalance := 0

                    // Update the BalanceSum reference
                    // keccak256(address . _balanceSumCheckpoint.balanceSums.slot))
                    mstore(0, asset)
                    mstore(0x20, add(_balanceSumCheckpoint.slot, 0x01))
                    _currentBalanceSum.slot := keccak256(0, 0x40)
                }
            }
        }
    }
}