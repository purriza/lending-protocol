// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../../contracts/StabilityFund.sol";
import "../NetworkAddresses.sol";

/**
 * @title ConfigureStabilityFund
 * @notice Configuration script for StabilityFund contract
 * @dev Sets up essential contract relationships and parameters
 */
contract ConfigureStabilityFund is Script {
    address public STABILITY_FUND_ADDRESS;
    address public LENDING_VAULT_ADDRESS;
    address public LIQUIDATION_ENGINE_ADDRESS;
    address public TREASURY_ADDRESS;
    
    // ===== CONFIGURATION PARAMETERS =====
    uint256 public constant MIN_DEPOSIT_AMOUNT = 0.001 ether; // 0.001 PUSD minimum deposit
    
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        STABILITY_FUND_ADDRESS = NetworkAddresses.stabilityFund();
        LENDING_VAULT_ADDRESS = NetworkAddresses.lendingVault();
        // Resolve via LendingVault plumbing
        LIQUIDATION_ENGINE_ADDRESS = address(StabilityFund(STABILITY_FUND_ADDRESS).liquidationEngine());
        TREASURY_ADDRESS = address(StabilityFund(STABILITY_FUND_ADDRESS).treasury());

        console.log("Configuring StabilityFund contract...");
        console.log("StabilityFund Address:", STABILITY_FUND_ADDRESS);
        console.log("Deployer:", msg.sender);
        
        StabilityFund stabilityFund = StabilityFund(STABILITY_FUND_ADDRESS);
        
        // Configure contract relationships
        console.log("\n1. Setting LendingVault in StabilityFund...");
        stabilityFund.setLendingVault(LENDING_VAULT_ADDRESS);
        console.log("SUCCESS: LendingVault set successfully");
        
        console.log("\n2. Setting LiquidationEngine in StabilityFund...");
        stabilityFund.setLiquidationEngine(LIQUIDATION_ENGINE_ADDRESS);
        console.log("SUCCESS: LiquidationEngine set successfully");
        
        console.log("\n3. Setting Treasury in StabilityFund...");
        stabilityFund.setTreasury(TREASURY_ADDRESS);
        console.log("SUCCESS: Treasury set successfully");
        
        console.log("\n4. Setting Min Deposit Amount in StabilityFund...");
        stabilityFund.setMinDepositAmount(MIN_DEPOSIT_AMOUNT);
        console.log("SUCCESS: Min Deposit Amount set successfully");
        
        vm.stopBroadcast();
        
        // Log configuration summary
        logConfigurationSummary();
    }
    
    function logConfigurationSummary() internal view {
        console.log("\n=== STABILITY FUND CONFIGURATION SUMMARY ===");
        console.log("Network:", block.chainid);
        console.log("Block:", block.number);
        console.log("Timestamp:", block.timestamp);
        console.log("");
        console.log("Contract Addresses:");
        console.log("- StabilityFund (target):", STABILITY_FUND_ADDRESS);
        console.log("- LendingVault:      ", LENDING_VAULT_ADDRESS);
        console.log("- LiquidationEngine: ", LIQUIDATION_ENGINE_ADDRESS);
        console.log("- Treasury:          ", TREASURY_ADDRESS);
        console.log("");
        console.log("Configuration Parameters:");
        console.log("- Min Deposit Amount:", MIN_DEPOSIT_AMOUNT, "(0.001 PUSD)");
        console.log("");
        console.log("Configuration completed successfully!");
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify configuration on Etherscan");
        console.log("2. Verify contract relationships");
    }
} 