// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../../contracts/LendingVault.sol";
import "../../../contracts/ProtocolConfig.sol";
import "../../NetworkAddresses.sol";

// Minimal interface for mock/oracle contracts that expose setAnswer
interface IOracleWithSetAnswer {
    function setAnswer(int256 answer_) external;
}

contract ManipulateOraclePrice is Script {
    // Testing wallets
    uint256[] private testingWallets = [
        vm.envUint("LIQUIDATION_TESTING_1_PRIVATE_KEY"),
        vm.envUint("LIQUIDATION_TESTING_2_PRIVATE_KEY"),
        vm.envUint("LIQUIDATION_TESTING_3_PRIVATE_KEY"),
        vm.envUint("LIQUIDATION_TESTING_4_PRIVATE_KEY"),
        vm.envUint("LIQUIDATION_TESTING_5_PRIVATE_KEY")
    ];
    
    // Tester key used to broadcast oracle admin actions
    uint256 private testerPrivateKey = vm.envUint("TESTER_PRIVATE_KEY");
    
    // Additional monitored wallets (public addresses)
    address[] private additionalWallets = [
        address(0) // target wallet
    ];

    function run() external view {
        console.log("=== ORACLE PRICE UTILITIES ===");
        _checkCurrentPrice();
    }
    
    function _checkCurrentPrice() internal view {
        console.log("\n--- Current Price Information ---");
        IPriceOracle oracle = ProtocolConfig(NetworkAddresses.protocolConfig()).oracle();
        (uint80 roundId, int256 answer, , uint256 updatedAt, ) = oracle.latestRoundData();
        uint8 dec = oracle.decimals();
        console.log("Oracle: %s", address(oracle));
        console.log("Round ID: %s", roundId);
        console.log("Decimals: %s", dec);
        console.log("Price (scaled): %s", uint256(answer));
        console.log("Price (human): $%s", uint256(answer) / (10 ** dec));
        console.log("Updated: %s seconds ago", block.timestamp - updatedAt);
    }

    // (No extra public helpers; use run() to read, and setOraclePriceUSD() to update)
    
    function _checkLiquidationStatus() internal view {
        console.log("  Checking liquidation status...");
        address wallet = vm.addr(testingWallets[0]);
        LendingVault lendingVault = LendingVault(NetworkAddresses.lendingVault());
        (uint256 collateral, uint256 debt, , bool exists) = lendingVault.getPosition(wallet);
        if (!exists) {
            console.log("    No position found");
            return;
        }
        (, int256 answer, , ,) = ProtocolConfig(NetworkAddresses.protocolConfig()).oracle().latestRoundData();
        uint256 collateralValueUSD = (collateral * uint256(answer)) / 1e8;
        uint256 ltv = collateralValueUSD > 0 ? (debt * 10000) / collateralValueUSD : 0;
        console.log("    LTV: %s basis points", ltv);
        bool isLiquidatable = lendingVault.isLiquidatable(wallet);
        console.log("    Liquidatable: %s", isLiquidatable ? "YES" : "NO");
        if (isLiquidatable) {
            console.log("    WARNING: POSITION IS LIQUIDATABLE!");
        } else if (ltv >= 7000) {
            console.log("    WARNING: Position at risk (LTV >= 70%%)");
        } else {
            console.log("    OK: Position safe");
        }
    }
    
    // Removed setPriceDrop and scenario helpers to keep only precise price setting.

    function setOraclePriceUSD(uint256 priceUsd) external {
        IPriceOracle oracle = ProtocolConfig(NetworkAddresses.protocolConfig()).oracle();
        uint8 dec = oracle.decimals();
        uint256 scaled = priceUsd * (10 ** dec);
        console.log("=== SETTING ORACLE ABSOLUTE PRICE ===");
        console.log("Oracle: %s", address(oracle));
        console.log("Price USD: %s", priceUsd);
        console.log("Scaled (decimals %s): %s", dec, scaled);
        console.log("Tester wallet: %s", vm.addr(testerPrivateKey));
        vm.startBroadcast(testerPrivateKey);
        IOracleWithSetAnswer(address(oracle)).setAnswer(int256(scaled));
        vm.stopBroadcast();
        _checkCurrentPrice();
    }
    
    function checkCurrentPosition() external view {
        console.log("=== CHECKING ALL WALLET POSITIONS ===");
        LendingVault lendingVault = LendingVault(NetworkAddresses.lendingVault());
        ProtocolConfig protocolConfig = ProtocolConfig(NetworkAddresses.protocolConfig());
        console.log("\n--- TESTING WALLETS ---");
        for (uint256 i = 0; i < testingWallets.length; i++) {
            address wallet = vm.addr(testingWallets[i]);
            console.log("\nWallet %s: %s", i + 1, wallet);
            _checkWalletPosition(lendingVault, protocolConfig, wallet);
        }
        console.log("\n--- ADDITIONAL MONITORED WALLETS ---");
        for (uint256 i = 0; i < additionalWallets.length; i++) {
            address wallet = additionalWallets[i];
            string memory walletName = i == 0 ? "Target Wallet" : "Additional Wallet";
            console.log("\n%s: %s", walletName, wallet);
            _checkWalletPosition(lendingVault, protocolConfig, wallet);
        }
    }
    
    function _checkWalletPosition(LendingVault lendingVault, ProtocolConfig protocolConfig, address wallet) internal view {
        (uint256 collateral, uint256 debt, uint256 healthRatio, bool exists) = lendingVault.getPosition(wallet);
        if (!exists) {
            console.log("  No position found");
            return;
        }
        console.log("  Collateral: %s wstETH", collateral);
        console.log("  Debt: %s PUSD", debt);
        console.log("  Health Ratio: %s", healthRatio);
        (, int256 answer, , ,) = protocolConfig.oracle().latestRoundData();
        uint256 currentPrice = uint256(answer);
        uint256 collateralValueUSD = (collateral * currentPrice) / 1e8;
        uint256 ltv = collateralValueUSD > 0 ? (debt * 10000) / collateralValueUSD : 0;
        console.log("  LTV: %s basis points", ltv);
        bool isLiquidatable = lendingVault.isLiquidatable(wallet);
        console.log("  Liquidatable: %s", isLiquidatable ? "YES" : "NO");
        if (isLiquidatable) {
            console.log("  WARNING: POSITION IS LIQUIDATABLE!");
        } else if (ltv >= 7000) {
            console.log("  WARNING: Position at risk (LTV >= 70%%)");
        } else {
            console.log("  OK: Position safe");
        }
    }
}
