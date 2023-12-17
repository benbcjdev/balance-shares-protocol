// SPDX-License-Identifier: MIT
// Balance Shares Protocol Contracts

pragma solidity ^0.8.20;

type ERC20Asset is address;

/**
 * @title ERC20AssetLibrary
 * @author Ben Jett - @BCJdevelopment
 * @notice Defines gas-optimized transfer functions for ERC20 assets.
 * @author Safe transfer logic was modified from Solady (https://github.com/vectorized/solady/blob/main/src/utils/SafeTransferLib.sol)
 * @dev Assumes address(0) is the native currency (such as ETH)
 */
library ERC20AssetLibrary {

    /// @dev The ETH transfer has failed.
    error ETHTransferFailed();

    /// @dev The ERC20 `transferFrom` has failed.
    error TransferFromFailed();

    /// @dev The ERC20 `transfer` has failed.
    error TransferFailed();

    /// @dev Invalid msg.value
    error InvalidMsgValue(uint256 expected, uint256 actual);

    /// @dev Suggested gas stipend for contract receiving ETH to perform a few
    /// storage reads and writes, but low enough to prevent griefing.
    uint256 internal constant GAS_STIPEND_NO_GRIEF = 100_000;

    function transferTo(ERC20Asset asset, address to, uint256 amount) internal {
        // For native currency, forceSafeTransferETH
        if (ERC20Asset.unwrap(asset) == address(0)) {
            // Force sends `amount` (in wei) ETH to `to`, with `GAS_STIPEND_NO_GRIEF`.
            assembly ("memory-safe") {
                if lt(selfbalance(), amount) {
                    mstore(0x00, 0xb12d13eb) // `ETHTransferFailed()`.
                    revert(0x1c, 0x04)
                }
                if iszero(call(GAS_STIPEND_NO_GRIEF, to, amount, codesize(), 0x00, codesize(), 0x00)) {
                    mstore(0x00, to) // Store the address in scratch space.
                    mstore8(0x0b, 0x73) // Opcode `PUSH20`.
                    mstore8(0x20, 0xff) // Opcode `SELFDESTRUCT`.
                    if iszero(create(amount, 0x0b, 0x16)) { revert(codesize(), codesize()) } // For gas estimation.
                }
            }
        // For ERC20, perform safeTransfer to the receiver
        } else {
            assembly ("memory-safe") {
                mstore(0x14, to) // Store the `to` argument.
                mstore(0x34, amount) // Store the `amount` argument.
                mstore(0x00, 0xa9059cbb000000000000000000000000) // `transfer(address,uint256)`.
                // Perform the transfer, reverting upon failure.
                if iszero(
                    and( // The arguments of `and` are evaluated from right to left.
                        or(
                            eq(mload(0x00), 1), // Returned 1
                            and(gt(extcodesize(asset), 0), iszero(returndatasize())) // Returned nothing and exists
                        ),
                        call(gas(), asset, 0, 0x10, 0x44, 0x00, 0x20)
                    )
                ) {
                    mstore(0x00, 0x90b8ec18) // `TransferFailed()`.
                    revert(0x1c, 0x04)
                }
                mstore(0x34, 0) // Restore the part of the free memory pointer that was overwritten.
            }
        }
    }

    function receiveFrom(ERC20Asset asset, address from, uint256 amount) internal {
        // For native currency, ensure msg.value is equal to the expected amount
        if (ERC20Asset.unwrap(asset) == address(0)) {
            if (msg.value != amount) {
                revert InvalidMsgValue(amount, msg.value);
            }
        // For ERC20, perform safeTransferFrom to this address
        } else {
            assembly ("memory-safe") {
                let m := mload(0x40) // Cache the free memory pointer.
                mstore(0x60, amount) // Store the `amount` argument.
                mstore(0x40, address()) // Store the `to` argument (this contract).
                mstore(0x2c, shl(96, from)) // Store the `from` argument.
                mstore(0x0c, 0x23b872dd000000000000000000000000) // `transferFrom(address,address,uint256)`.
                // Perform the transfer, reverting upon failure.
                if iszero(
                    and( // The arguments of `and` are evaluated from right to left.
                        or(
                            eq(mload(0x00), 1), // Returned 1
                            and(gt(extcodesize(asset), 0), iszero(returndatasize())) // Returned nothing and exists
                        ),
                        call(gas(), asset, 0, 0x1c, 0x64, 0x00, 0x20)
                    )
                ) {
                    mstore(0x00, 0x7939f424) // `TransferFromFailed()`.
                    revert(0x1c, 0x04)
                }
                mstore(0x60, 0) // Restore the zero slot to zero.
                mstore(0x40, m) // Restore the free memory pointer.
            }
        }
    }

}