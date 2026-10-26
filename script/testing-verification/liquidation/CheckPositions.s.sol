// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "../../../contracts/LendingVault.sol";
import "../../../contracts/ProtocolConfig.sol";
import "../../../contracts/interfaces/IPriceOracle.sol";
import "../../NetworkAddresses.sol";

contract CheckPositions is Script {
    enum Classification { None, Safe, AtRisk, Liquidatable }

    // Testing wallets
    uint256[] private testingWallets = [
        vm.envUint("LIQUIDATION_TESTING_1_PRIVATE_KEY"),
        vm.envUint("LIQUIDATION_TESTING_2_PRIVATE_KEY"),
        vm.envUint("LIQUIDATION_TESTING_3_PRIVATE_KEY"),
        vm.envUint("LIQUIDATION_TESTING_4_PRIVATE_KEY"),
        vm.envUint("LIQUIDATION_TESTING_5_PRIVATE_KEY")
    ];
    
    // Additional monitored wallets
    address constant TARGET_WALLET = address(0);
    
    function run() external view {
        console.log("=== COMPREHENSIVE POSITIONS MONITOR ===");
        console.log("Timestamp: %s", block.timestamp);
        
        _checkOracleInfo();
        _checkTestingWallets();
        _checkAdditionalWallets();
        _printSummary();
    }
    
    function _checkOracleInfo() internal view {
        console.log("\n=== ORACLE INFORMATION ===");
        
        ProtocolConfig protocolConfig = ProtocolConfig(NetworkAddresses.protocolConfig());
        IPriceOracle oracle = protocolConfig.oracle();
        
        (, int256 answer, , uint256 updatedAt, uint80 answeredInRound) = oracle.latestRoundData();
        
        console.log("Oracle Address: %s", address(oracle));
        console.log("Current wstETH Price: $%s", uint256(answer) / 1e8);
        console.log("Price Updated: %s seconds ago", block.timestamp - updatedAt);
        console.log("Round ID: %s", answeredInRound);
    }
    
    function _checkTestingWallets() internal view {
        console.log("\n=== TESTING WALLETS POSITIONS ===");
        
        (, int256 answer, , ,) = ProtocolConfig(NetworkAddresses.protocolConfig()).oracle().latestRoundData();
        uint256 currentPrice = uint256(answer);
        
        uint256 totalCollateral = 0;
        uint256 totalDebt = 0;
        uint256 liquidatableCount = 0;
        uint256 atRiskCount = 0;
        uint256 safeCount = 0;
        
        for (uint256 i = 0; i < testingWallets.length; i++) {
            address wallet = vm.addr(testingWallets[i]);
            console.log("\n--- Testing Wallet %s: %s ---", i + 1, wallet);
            
            (uint256 c, uint256 d, Classification cls) = _reportWallet(wallet, currentPrice);
            if (cls == Classification.None) {
                continue;
            }
            totalCollateral += c;
            totalDebt += d;
            if (cls == Classification.Liquidatable) {
                liquidatableCount++;
            } else if (cls == Classification.AtRisk) {
                atRiskCount++;
            } else if (cls == Classification.Safe) {
                safeCount++;
            }
        }
        
        console.log("\n=== TESTING WALLETS SUMMARY ===");
        console.log("Total Collateral: %s wstETH", totalCollateral / 1e18);
        console.log("Total Debt: %s PUSD", totalDebt / 1e18);
        console.log("Total Positions: %s", liquidatableCount + atRiskCount + safeCount);
        console.log("Liquidatable: %s", liquidatableCount);
        console.log("At Risk: %s", atRiskCount);
        console.log("Safe: %s", safeCount);
    }
    
    function _checkAdditionalWallets() internal view {
        console.log("\n=== ADDITIONAL MONITORED WALLETS ===");
        
        (, int256 answer, , ,) = ProtocolConfig(NetworkAddresses.protocolConfig()).oracle().latestRoundData();
        uint256 currentPrice = uint256(answer);
        
        _reportWalletNamed(TARGET_WALLET, "Target Wallet", currentPrice);
    }
    
    function _reportWalletNamed(address wallet, string memory walletName, uint256 currentPrice) internal view {
        console.log("\n--- %s: %s ---", walletName, wallet);
        _reportWallet(wallet, currentPrice);
    }

    function _reportWallet(address wallet, uint256 currentPrice) internal view returns (uint256 collateral, uint256 debt, Classification cls) {
        uint256 healthRatio;
        bool exists;
        (collateral, debt, healthRatio, exists) = LendingVault(NetworkAddresses.lendingVault()).getPosition(wallet);
        if (!exists) {
            console.log("  Status: NO POSITION");
            return (0, 0, Classification.None);
        }
        uint256 collateralValueUSD = (collateral * currentPrice) / 1e8;
        uint256 actualLTV = collateralValueUSD > 0 ? (debt * 10000) / collateralValueUSD : 0;
        bool isLiquid = LendingVault(NetworkAddresses.lendingVault()).isLiquidatable(wallet);

        console.log("  Collateral: %s wstETH", collateral / 1e18);
        console.log("  Debt: %s PUSD", debt / 1e18);
        console.log("  Collateral Value: $%s", collateralValueUSD / 1e18);
        console.log("  Health Ratio: %s", healthRatio);
        console.log("  LTV: %s basis points (%.2f%%)", actualLTV, actualLTV / 100);
        console.log("  Liquidatable: %s", isLiquid ? "YES" : "NO");

        if (isLiquid) {
            console.log("  Status: LIQUIDATABLE");
            return (collateral, debt, Classification.Liquidatable);
        }
        if (actualLTV >= 7000) {
            console.log("  Status: AT RISK");
            return (collateral, debt, Classification.AtRisk);
        }
        console.log("  Status: SAFE");
        return (collateral, debt, Classification.Safe);
    }
    
    function _printSummary() internal pure {
        console.log("\n=== MONITORING COMPLETE ===");
        console.log("All positions have been checked and reported above.");
    }
}

