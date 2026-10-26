// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../../contracts/LendingVault.sol";
import "../../../contracts/ProtocolConfig.sol";
import "../../NetworkAddresses.sol";

contract GeneratePositions is Script {
    // ===== CONFIGURATION VARIABLES =====
    // Multiple wallet private keys for testing
    uint256[] private testingWallets = [
        vm.envUint("LIQUIDATION_TESTING_1_PRIVATE_KEY"),
        vm.envUint("LIQUIDATION_TESTING_2_PRIVATE_KEY"),
        vm.envUint("LIQUIDATION_TESTING_3_PRIVATE_KEY"),
        vm.envUint("LIQUIDATION_TESTING_4_PRIVATE_KEY"),
        vm.envUint("LIQUIDATION_TESTING_5_PRIVATE_KEY")
    ];
    
    // Contract addresses
    address private LENDING_VAULT;
    address private PROTOCOL_CONFIG;
    
    // Token addresses
    address PUSD;
    address wstETH;
    
    // Position parameters
    uint256 constant COLLATERAL_AMOUNT = 100 * 1e18; // 100 wstETH per position (increased for min debt)
    uint256 constant LIQUIDATION_THRESHOLD = 8000; // 80% LTV threshold
    uint256 constant MIN_DEBT = 500 * 1e18; // 500 PUSD minimum debt
    
    function run() external {
        LENDING_VAULT = NetworkAddresses.lendingVault();
        PROTOCOL_CONFIG = NetworkAddresses.protocolConfig();
        PUSD = NetworkAddresses.pusd();
        wstETH = NetworkAddresses.collateralToken();
        console.log("=== GENERATING POSITIONS ACROSS MULTIPLE WALLETS ===");
        
        // Create positions with different risk levels across all testing wallets
        _createRiskyPositionsAcrossWallets();
        
        console.log("\n=== POSITIONS GENERATION COMPLETE ===");
    }
    
    function _checkBalances(address user) internal view {
        console.log("\n=== CHECKING BALANCES ===");
        
        uint256 pusdBalance = IERC20(PUSD).balanceOf(user);
        uint256 wstETHBalance = IERC20(wstETH).balanceOf(user);
        
        console.log("PUSD balance: %s", pusdBalance);
        console.log("wstETH balance: %s", wstETHBalance);
        
        if (wstETHBalance < COLLATERAL_AMOUNT) {
            console.log("WARNING: Insufficient wstETH balance for position");
        }
    }
    
    function _createRiskyPositionsAcrossWallets() internal {
        // Create positions with different LTV ratios across different wallets
        // Each wallet gets one position with a specific risk level
        
        // Respect minCollateralRatio at open (e.g., 15000 → LTV max ≈ 6666 bps)
        uint256[] memory ltvRatios = new uint256[](5);
        ltvRatios[0] = 5000; // 50% LTV - safe
        ltvRatios[1] = 6000; // 60% LTV - moderate
        ltvRatios[2] = 6500; // 65% LTV - near limit
        ltvRatios[3] = 6600; // 66.0% LTV - near limit
        ltvRatios[4] = 6660; // ~66.6% LTV - at limit
        
        for (uint256 i = 0; i < testingWallets.length && i < ltvRatios.length; i++) {
            console.log("\n--- Creating Position %s in Wallet %s ---", i + 1, i + 1);
            _createRiskyPositionInWallet(testingWallets[i], ltvRatios[i]);
        }
    }
    
    function _createRiskyPositionInWallet(uint256 walletPrivateKey, uint256 targetLTV) internal {
        address wallet = vm.addr(walletPrivateKey);
        
        // Use fixed price for testing (wstETH = $3000)
        uint256 wstETHPrice = 3000 * 1e18;
        
        // Calculate debt amount to achieve target LTV, ensuring minimum debt requirement
        uint256 collateralValue = (COLLATERAL_AMOUNT * wstETHPrice) / 1e18;
        uint256 calculatedDebt = (collateralValue * targetLTV) / 10000;
        uint256 debtAmount = calculatedDebt < MIN_DEBT ? MIN_DEBT : calculatedDebt;
        
        console.log("Wallet: %s", wallet);
        console.log("Target LTV: %s basis points", targetLTV);
        console.log("Collateral amount: %s", COLLATERAL_AMOUNT);
        console.log("Debt amount: %s", debtAmount);
        
        // Check balances before creating position
        _checkBalances(wallet);
        
        vm.startBroadcast(walletPrivateKey);
        
        // Approve tokens
        IERC20(wstETH).approve(LENDING_VAULT, COLLATERAL_AMOUNT);
        IERC20(PUSD).approve(LENDING_VAULT, debtAmount);
        
        // Create position
        LendingVault lendingVault = LendingVault(LENDING_VAULT);
        lendingVault.deposit(COLLATERAL_AMOUNT);
        lendingVault.borrow(debtAmount);
        
        console.log("Risky position created successfully!");
        console.log("LTV: %s basis points", targetLTV);
        console.log("Status: %s", targetLTV >= LIQUIDATION_THRESHOLD ? "LIQUIDATABLE" : "AT RISK");
        
        vm.stopBroadcast();
    }
    
    // (No extra public helper functions; generation is performed in run())
}


