// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../../contracts/LendingVault.sol";
import "../NetworkAddresses.sol";

/**
 * @title ConfigureLendingVault
 * @notice Configuration script for LendingVault contract
 * @dev Sets up essential contract relationships and parameters
 */
contract ConfigureLendingVault is Script {
    // Addresses
    address public LENDING_VAULT_ADDRESS;
    address public PROTOCOL_CONFIG_ADDRESS;
    address public STABILITY_FUND_ADDRESS;
    address public TREASURY_ADDRESS;
    address public LIQUIDATION_ENGINE_ADDRESS;
    
    // ===== CONFIGURATION PARAMETERS =====
    uint256 public constant APR_BASIS_POINTS = 50; // 0.5% APR in basis points
    
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Resolve addresses for current chain
        LENDING_VAULT_ADDRESS = NetworkAddresses.lendingVault();
        PROTOCOL_CONFIG_ADDRESS = NetworkAddresses.protocolConfig();
        // Discover related via LendingVault/ProtocolConfig
        LendingVault lendingVault = LendingVault(LENDING_VAULT_ADDRESS);
        STABILITY_FUND_ADDRESS = address(lendingVault.stabilityFund());
        TREASURY_ADDRESS = address(lendingVault.treasury());
        LIQUIDATION_ENGINE_ADDRESS = address(lendingVault.liquidationEngine());

        console.log("Configuring LendingVault contract...");
        console.log("LendingVault Address:", LENDING_VAULT_ADDRESS);
        console.log("Deployer:", msg.sender);
        
        // Configure parameters
        console.log("\n1. Setting ProtocolConfig in LendingVault...");
        lendingVault.setProtocolConfig(PROTOCOL_CONFIG_ADDRESS);
        console.log("SUCCESS: ProtocolConfig set successfully");
        
        console.log("\n2. Setting StabilityFund in LendingVault...");
        lendingVault.setStabilityFund(STABILITY_FUND_ADDRESS);
        console.log("SUCCESS: StabilityFund set successfully");

        console.log("\n3. Setting Treasury in LendingVault...");
        lendingVault.setTreasury(TREASURY_ADDRESS);
        console.log("SUCCESS: Treasury set successfully");

        console.log("\n4. Setting LiquidationEngine in LendingVault...");
        lendingVault.setLiquidationEngine(LIQUIDATION_ENGINE_ADDRESS);
        console.log("SUCCESS: LiquidationEngine set successfully");
        
        console.log("\n5. Setting APR in LendingVault...");
        lendingVault.setAPR(APR_BASIS_POINTS); // 0.5% APR in basis points
        console.log("SUCCESS: APR set successfully");
        
        vm.stopBroadcast();
        
        // Log configuration summary
        logConfigurationSummary();
    }
    
    function logConfigurationSummary() internal view {
        console.log("\n=== LENDING VAULT CONFIGURATION SUMMARY ===");
        console.log("Network:", block.chainid);
        console.log("Block:", block.number);
        console.log("Timestamp:", block.timestamp);
        console.log("");
        console.log("Contract Addresses:");
        console.log("- LendingVault (target):", LENDING_VAULT_ADDRESS);
        console.log("- ProtocolConfig:    ", PROTOCOL_CONFIG_ADDRESS);
        console.log("- StabilityFund:     ", STABILITY_FUND_ADDRESS);
        console.log("- Treasury:          ", TREASURY_ADDRESS);
        console.log("- LiquidationEngine: ", LIQUIDATION_ENGINE_ADDRESS);
        console.log("");
        console.log("Configuration Parameters:");
        console.log("- APR:               ", APR_BASIS_POINTS, "(5% APR)");
        console.log("");
        console.log("Configuration completed successfully!");
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify configuration on Etherscan");
        console.log("2. Verify contract relationships");
    }
} 