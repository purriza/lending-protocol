// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../../contracts/wPUSD.sol";
import "../NetworkAddresses.sol";

/**
 * @title ConfigureWPUSD
 * @notice Configuration script for wPUSD contract
 * @dev Sets up essential contract relationships and parameters
 */
contract ConfigureWPUSD is Script {
    address public WPUSD_ADDRESS;
    address public STABILITY_FUND_ADDRESS;
    
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        WPUSD_ADDRESS = NetworkAddresses.wpusd();
        STABILITY_FUND_ADDRESS = NetworkAddresses.stabilityFund();

        console.log("Configuring wPUSD contract...");
        console.log("wPUSD Address:", WPUSD_ADDRESS);
        console.log("Deployer:", msg.sender);
        
        wPUSD wpusd = wPUSD(WPUSD_ADDRESS);
        
        // Configure contract relationships
        console.log("\n1. Setting StabilityFund in wPUSD...");
        wpusd.setStabilityFund(STABILITY_FUND_ADDRESS);
        console.log("SUCCESS: StabilityFund set successfully");
        
        vm.stopBroadcast();
        
        // Log configuration summary
        logConfigurationSummary();
    }
    
    function logConfigurationSummary() internal view {
        console.log("\n=== WPUSD CONFIGURATION SUMMARY ===");
        console.log("Network:", block.chainid);
        console.log("Block:", block.number);
        console.log("Timestamp:", block.timestamp);
        console.log("");
        console.log("Contract Addresses:");
        console.log("- wPUSD (target):    ", WPUSD_ADDRESS);
        console.log("- StabilityFund:     ", STABILITY_FUND_ADDRESS);
        console.log("");
        console.log("Configuration completed successfully!");
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify configuration on Etherscan");
        console.log("2. Verify contract relationships");
    }
} 