// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../../contracts/Treasury.sol";
import "../NetworkAddresses.sol";

/**
 * @title ConfigureTreasury
 * @notice Configuration script for Treasury contract
 * @dev Sets up essential contract relationships and parameters
 */
contract ConfigureTreasury is Script {
    address public TREASURY_ADDRESS;
    address public PROTOCOL_CONFIG_ADDRESS;
    address public PUSD_ADDRESS;
    address public WSTETH_ADDRESS;
    address public LENDING_VAULT_ADDRESS;
    address public STABILITY_FUND_ADDRESS;
    address public LIQUIDATION_ENGINE_ADDRESS;
    
    // ===== CONFIGURATION PARAMETERS =====
    uint256 public constant SWAP_SLIPPAGE_BPS = 500; // 5% swap slippage in basis points
    uint256 public constant ORACLE_STALE_AFTER = 1 hours;
    uint256 public constant SWAP_DEADLINE_SECONDS = 60;

    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        TREASURY_ADDRESS = NetworkAddresses.treasury();
        PROTOCOL_CONFIG_ADDRESS = NetworkAddresses.protocolConfig();
        PUSD_ADDRESS = NetworkAddresses.pusd();
        WSTETH_ADDRESS = NetworkAddresses.collateralToken();
        LENDING_VAULT_ADDRESS = NetworkAddresses.lendingVault();
        // Resolve via LendingVault path
        LIQUIDATION_ENGINE_ADDRESS = address(Treasury(TREASURY_ADDRESS).liquidationEngine());
        STABILITY_FUND_ADDRESS = address(Treasury(TREASURY_ADDRESS).stabilityFund());

        console.log("Configuring Treasury contract...");
        console.log("Treasury Address:", TREASURY_ADDRESS);
        console.log("Deployer:", msg.sender);
        
        Treasury treasury = Treasury(TREASURY_ADDRESS);
        
        // Configure contract 
        console.log("\n1. Setting ProtocolConfig in Treasury...");
        treasury.setProtocolConfig(PROTOCOL_CONFIG_ADDRESS);
        console.log("SUCCESS: ProtocolConfig set successfully");

        console.log("\n2. Setting PUSD in Treasury...");
        treasury.setPUSD(PUSD_ADDRESS);
        console.log("SUCCESS: PUSD set successfully");

        console.log("\n3. Setting WstETH in Treasury...");
        treasury.setWstETH(WSTETH_ADDRESS);
        console.log("SUCCESS: WstETH set successfully");

        console.log("\n4. Setting LendingVault in Treasury...");
        treasury.setLendingVault(LENDING_VAULT_ADDRESS);
        console.log("SUCCESS: LendingVault set successfully");
        
        console.log("\n5. Setting StabilityFund in Treasury...");
        treasury.setStabilityFund(STABILITY_FUND_ADDRESS);
        console.log("SUCCESS: StabilityFund set successfully");

        console.log("\n6. Setting LiquidationEngine in Treasury...");
        treasury.setLiquidationEngine(LIQUIDATION_ENGINE_ADDRESS);
        console.log("SUCCESS: LiquidationEngine set successfully");
        
        console.log("\n7. Setting Swap Slippage Bps in Treasury...");
        treasury.setSwapSlippageBps(SWAP_SLIPPAGE_BPS);
        console.log("SUCCESS: Swap Slippage Bps set successfully");

        console.log("\n8. Setting Oracle Stale After in Treasury...");
        treasury.setOracleStaleAfter(ORACLE_STALE_AFTER);
        console.log("SUCCESS: Oracle Stale After set successfully");

        console.log("\n9. Setting Swap Deadline Seconds in Treasury...");
        treasury.setSwapDeadlineSeconds(SWAP_DEADLINE_SECONDS);
        console.log("SUCCESS: Swap Deadline Seconds set successfully");

        vm.stopBroadcast();
        
        // Log configuration summary
        logConfigurationSummary();
    }
    
    function logConfigurationSummary() internal view {
        console.log("\n=== TREASURY CONFIGURATION SUMMARY ===");
        console.log("Network:", block.chainid);
        console.log("Block:", block.number);
        console.log("Timestamp:", block.timestamp);
        console.log("");
        console.log("Contract Addresses:");
        console.log("- Treasury (target): ", TREASURY_ADDRESS);
        console.log("- ProtocolConfig:    ", PROTOCOL_CONFIG_ADDRESS);
        console.log("- WstETH:            ", WSTETH_ADDRESS);
        console.log("- PUSD:              ", PUSD_ADDRESS);
        console.log("- LendingVault:      ", LENDING_VAULT_ADDRESS);
        console.log("- StabilityFund:     ", STABILITY_FUND_ADDRESS);
        console.log("- LiquidationEngine: ", LIQUIDATION_ENGINE_ADDRESS);
        console.log("");
        console.log("Configuration Parameters:");
        console.log("- Swap Slippage Bps: ", SWAP_SLIPPAGE_BPS);
        console.log("- Oracle Stale After: ", ORACLE_STALE_AFTER);
        console.log("- Swap Deadline Seconds: ", SWAP_DEADLINE_SECONDS);
        console.log("");
        console.log("Configuration completed successfully!");
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify configuration on Etherscan");
        console.log("2. Verify contract relationships");
    }
} 