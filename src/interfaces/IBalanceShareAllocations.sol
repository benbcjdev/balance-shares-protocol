// SPDX-License-Identifier: MIT
// Balance Shares Protocol Contracts

pragma solidity ^0.8.20;

interface IBalanceShareAllocations {

    /**
     * Returns the current total BPS for the given balance share (the combined BPS share of all active account shares).
     * @param client The client address.
     * @param clientShareId The uint256 identifier for the client's balance share.
     * @return totalBps The current total BPS across all account shares for this balance share.
     */
    function getBalanceShareTotalBPS(
        address client,
        uint256 clientShareId
    ) external view returns (uint256 totalBps);

    /**
     * For the provided balance share and asset, returns the amount of the asset to send to this contract for the
     * provided amount that the balance increased by (as a function of the balance share's total BPS).
     * @param client The client address.
     * @param clientShareId The uint256 identifier for the client's balance share.
     * @param asset The ERC20 asset to process the balance share for (address(0) for ETH).
     * @param balanceIncreasedBy The amount that the total balance share increased by.
     * @return amountToAllocate The amount of the asset that should be allocated to the balance share. Mathematically:
     * amountToAllocate = balanceIncreasedBy * totalBps / 10_000
     */
    function getBalanceShareAllocation(
        address client,
        uint256 clientShareId,
        address asset,
        uint256 balanceIncreasedBy
    ) external view returns (uint256 amountToAllocate);

    /**
     * Same as {getBalanceShareAllocation}, but also includes integer remainders from the previous balance allocation.
     * This is useful for calculations with small balance increase amounts relative to the max BPS (10,000). Use this
     * in conjunction with {allocateToBalanceShareWithRemainder} to track the remainders over each allocation.
     * @param client The client address.
     * @param clientShareId The uint256 identifier of the client's balance share.
     * @param asset The ERC20 asset to process the balance share for (address(0) for ETH).
     * @param balanceIncreasedBy The amount that the total balance share increased by.
     * @return amountToAllocate The amount of the asset that should be allocated to the balance share. Mathematically:
     * amountToAllocate = (balanceIncreasedBy + previousAssetRemainder) * totalBps / 10_000
     * @return remainderIncrease A bool indicating whether or not the remainder increased as a result of this function.
     * Will return true if the remainder increased, even if the amountToAllocate is zero.
     */
    function getBalanceShareAllocationWithRemainder(
        address client,
        uint256 clientShareId,
        address asset,
        uint256 balanceIncreasedBy
    ) external view returns (uint256 amountToAllocate, bool remainderIncrease);

    /**
     * Transfers the specified amount to allocate of the given ERC20 asset from the msg.sender to this contract to be
     * split amongst the account shares for this balance share ID.
     * @param client The client address.
     * @param clientShareId The uint256 identifier of the client's balance share.
     * @param asset The ERC20 asset to process the balance share for (address(0) for ETH).
     * @param amountToAllocate The amount of the asset to transfer. If the asset is address(0), this must equal the
     * msg.value. Otherwise, this contract must be approved to transfer at least this amount of the ERC20 asset.
     */
    function allocateToBalanceShare(
        address client,
        uint256 clientShareId,
        address asset,
        uint256 amountToAllocate
    ) external payable;

    /**
     * Calculates the amount to allocate using the provided `balanceIncreasedBy` amount, adding in the integer remainder
     * from the last balance allocation, and transfers the amount to allocate to this contract. Tracks the resulting
     * remainder for the next function call as well.
     * @dev The msg.sender is used as the client address for this function, meaning only the client manager of a balance
     * share ID can process balance increases with the remainder included. This is to prevent an attack vector where
     * outside parties falsely increment the remainder right up to the threshold.
     * @param clientShareId The uint256 identifier of the client's balance share.
     * @param asset The ERC20 asset to process the balance share for (address(0) for ETH).
     * @param balanceIncreasedBy The amount of the asset to transfer. If the asset is address(0), this must equal the
     * msg.value. Otherwise, this contract must be approved to transfer at least this amount of the ERC20 asset.
     * @dev Use the {getBalanceShareAllocationWithRemainder} function to calculate the amount to allocate before calling
     * this function, so that the correct transfer amount is approved (or the correct msg.value is sent for asset
     * address(0)).
     */
    function allocateToBalanceShareWithRemainder(
        uint256 clientShareId,
        address asset,
        uint256 balanceIncreasedBy
    ) external payable;
}