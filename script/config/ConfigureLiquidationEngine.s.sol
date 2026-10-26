// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../../contracts/LiquidationEngine.sol";
import "../NetworkAddresses.sol";

/**
 * @title ConfigureLiquidationEngine
 * @notice Configuration script for LiquidationEngine contract
 * @dev Sets up essential contract relationships and parameters
 */
contract ConfigureLiquidationEngine is Script {
    address public LIQUIDATION_ENGINE_ADDRESS;
    address public PROTOCOL_CONFIG_ADDRESS;
    address public LENDING_VAULT_ADDRESS;
    address public STABILITY_FUND_ADDRESS;
    address public TREASURY_ADDRESS;

    // ===== CONFIGURATION PARAMETERS =====
    uint256 public constant MAX_SLIPPAGE = 1000; // 10% max slippage in basis points
    uint256 public constant TREASURY_REVENUE_FEE = 2000; // 20% treasury revenue fee in basis points
    
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        LIQUIDATION_ENGINE_ADDRESS = NetworkAddresses.liquidationEngine();
        PROTOCOL_CONFIG_ADDRESS = NetworkAddresses.protocolConfig();
        LENDING_VAULT_ADDRESS = NetworkAddresses.lendingVault();
        STABILITY_FUND_ADDRESS = NetworkAddresses.stabilityFund();
        TREASURY_ADDRESS = NetworkAddresses.treasury();

        console.log("Configuring LiquidationEngine contract...");
        console.log("LiquidationEngine Address:", LIQUIDATION_ENGINE_ADDRESS);
        console.log("Deployer:", msg.sender);
        
        LiquidationEngine liquidationEngine = LiquidationEngine(LIQUIDATION_ENGINE_ADDRESS);
        
        // Configure contract relationships
        console.log("\n1. Setting ProtocolConfig in LiquidationEngine...");
        liquidationEngine.setProtocolConfig(PROTOCOL_CONFIG_ADDRESS);
        console.log("SUCCESS: ProtocolConfig set successfully");

        console.log("\n2. Setting LendingVault in LiquidationEngine...");
        liquidationEngine.setLendingVault(LENDING_VAULT_ADDRESS);
        console.log("SUCCESS: LendingVault set successfully");
        
        console.log("\n3. Setting StabilityFund in LiquidationEngine...");
        liquidationEngine.setStabilityFund(STABILITY_FUND_ADDRESS);
        console.log("SUCCESS: StabilityFund set successfully");
        
        console.log("\n4. Setting Treasury in LiquidationEngine...");
        liquidationEngine.setTreasury(TREASURY_ADDRESS);
        console.log("SUCCESS: Treasury set successfully");
        
        console.log("\n5. Setting Max Slippage in LiquidationEngine...");
        liquidationEngine.setMaxSlippage(MAX_SLIPPAGE);
        console.log("SUCCESS: Max Slippage set successfully");
        
        console.log("\n6. Setting Treasury Revenue Fee in LiquidationEngine...");
        liquidationEngine.setTreasuryRevenueFee(TREASURY_REVENUE_FEE);
        console.log("SUCCESS: Treasury Revenue Fee set successfully");
        
        vm.stopBroadcast();
        
        // Log configuration summary
        logConfigurationSummary();
    }
    
    function logConfigurationSummary() internal view {
        console.log("\n=== LIQUIDATION ENGINE CONFIGURATION SUMMARY ===");
        console.log("Network:", block.chainid);
        console.log("Block:", block.number);
        console.log("Timestamp:", block.timestamp);
        console.log("");
        console.log("Contract Addresses:");
        console.log("- LiquidationEngine (target):", LIQUIDATION_ENGINE_ADDRESS);
        console.log("- ProtocolConfig:    ", PROTOCOL_CONFIG_ADDRESS);
        console.log("- LendingVault:      ", LENDING_VAULT_ADDRESS);
        console.log("- StabilityFund:     ", STABILITY_FUND_ADDRESS);
        console.log("- Treasury:          ", TREASURY_ADDRESS);
        console.log("");
        console.log("Configuration Parameters:");
        console.log("- Max Slippage:      ", MAX_SLIPPAGE, "(10%)");
        console.log("- Treasury Revenue Fee:", TREASURY_REVENUE_FEE, "(20%)");
        console.log("");
        console.log("Configuration completed successfully!");
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify configuration on Etherscan");
        console.log("2. Verify contract relationships");
    }
} 