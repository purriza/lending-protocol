// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../../contracts/PUSD.sol";
import "../NetworkAddresses.sol";

/**
 * @title ConfigurePUSD
 * @notice Configuration script for PUSD contract
 * @dev Sets up essential contract relationships and parameters
 */
contract ConfigurePUSD is Script {
    address public PUSD_ADDRESS;
    address public LENDING_VAULT_ADDRESS;
    address public STABILITY_FUND_ADDRESS;
    
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        PUSD_ADDRESS = NetworkAddresses.pusd();
        LENDING_VAULT_ADDRESS = NetworkAddresses.lendingVault();
        STABILITY_FUND_ADDRESS = NetworkAddresses.stabilityFund();

        console.log("Configuring PUSD contract...");
        console.log("PUSD Address:", PUSD_ADDRESS);
        console.log("Deployer:", msg.sender);
        
        PUSD pusd = PUSD(PUSD_ADDRESS);
        
        // Configure contract relationships
        console.log("\n1. Setting LendingVault in PUSD...");
        pusd.setLendingVault(LENDING_VAULT_ADDRESS);
        console.log("SUCCESS: LendingVault set successfully");
        
        console.log("\n2. Setting StabilityFund in PUSD...");
        pusd.setStabilityFund(STABILITY_FUND_ADDRESS);
        console.log("SUCCESS: StabilityFund set successfully");
        
        vm.stopBroadcast();
        
        // Log configuration summary
        logConfigurationSummary();
    }
    
    function logConfigurationSummary() internal view {
        console.log("\n=== PUSD CONFIGURATION SUMMARY ===");
        console.log("Network:", block.chainid);
        console.log("Block:", block.number);
        console.log("Timestamp:", block.timestamp);
        console.log("");
        console.log("Contract Addresses:");
        console.log("- PUSD (target):     ", PUSD_ADDRESS);
        console.log("- LendingVault:      ", LENDING_VAULT_ADDRESS);
        console.log("- StabilityFund:     ", STABILITY_FUND_ADDRESS);
        console.log("");
        console.log("Configuration completed successfully!");
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify configuration on Etherscan");
        console.log("2. Verify contract relationships");
    }
} 