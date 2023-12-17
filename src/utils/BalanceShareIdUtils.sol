// SPDX-License-Identifier: MIT
// Balance Share Protocol Contracts

pragma solidity ^0.8.20;

/**
 * @title A utility library for calculating the balance share ID with a given client address and client share ID.
 * @dev The balance share ID is the keccak256 hash of the ABI-encoded client address and client share ID.
 */
library BalanceShareIdUtils {

    /**
     * Returns the balance share ID for the given client address and client share ID.
     * @param client The client address.
     * @param clientShareId The client-provided uint256 identifier of the client balance share.
     * @return balanceShareId The balance share ID, which is the keccak256 hash of the ABI-encoded client address and
     * uint256 client share ID.
     */
    function getBalanceShareId(address client, uint256 clientShareId) internal pure returns (uint256 balanceShareId) {
        assembly ("memory-safe") {
            mstore(0x00, client)
            mstore(0x20, clientShareId)
            balanceShareId := keccak256(0x00, 0x40)
        }
    }

}