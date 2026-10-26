// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title DataTypes
 * @notice Library containing data structures used across the lending protocol
 */
library DataTypes {
    
    /**
     * @notice Structure containing liquidation order details
     * @param debtor Address of the user being liquidated
     * @param collateralToSell Amount of collateral to be sold
     * @param debtPaidBySF Amount of debt paid by StabilityFund
     * @param debtPaidByTreasury Amount of debt paid by Treasury
     */
    struct LiquidationOrder {
        address debtor;
        uint256 collateralToSell;
        uint256 debtPaidBySF;         // Amount contributed by the StabilityFund
        uint256 debtPaidByTreasury;   // Amount contributed by the Treasury
    }
}
