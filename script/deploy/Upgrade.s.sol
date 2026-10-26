// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../../contracts/ProtocolConfig.sol";
import "../../contracts/PUSD.sol";
import "../../contracts/wPUSD.sol";
import "../../contracts/StabilityFund.sol";
import "../../contracts/Treasury.sol";
import "../../contracts/LiquidationEngine.sol";
import "../../contracts/LendingVault.sol";
import "../NetworkAddresses.sol";

/**
 * @title Upgrade
 * @notice Upgrade script for specific Lending Protocol contracts
 * @dev Allows upgrading only selected contracts instead of all at once
 */
contract Upgrade is Script {
    // Proxy addresses
    address public PUSD_PROXY;
    address public WPUSD_PROXY;
    address public PROTOCOL_CONFIG_PROXY;
    address public LENDING_VAULT_PROXY;
    address public STABILITY_FUND_PROXY;
    address public TREASURY_PROXY;
    address public LIQUIDATION_ENGINE_PROXY;
    
    // New implementation addresses (will be set during deployment)
    address public protocolConfigImpl;
    address public pusdImpl;
    address public wpusdImpl;
    address public lendingVaultImpl;
    address public stabilityFundImpl;
    address public treasuryImpl;
    address public liquidationEngineImpl;

    // Configuration
    address public owner;
    
    // Upgrade flags - set these to true for contracts you want to upgrade
    bool public upgradeProtocolConfig = false;
    bool public upgradePUSD = false;
    bool public upgradeWPUSD = false;
    bool public upgradeLendingVault = false;
    bool public upgradeStabilityFund = false;
    bool public upgradeTreasury = false;
    bool public upgradeLiquidationEngine = true;

    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        
        // Initialize proxy addresses
        PUSD_PROXY = NetworkAddresses.pusd();
        WPUSD_PROXY = NetworkAddresses.wpusd();
        PROTOCOL_CONFIG_PROXY = NetworkAddresses.protocolConfig();
        LENDING_VAULT_PROXY = NetworkAddresses.lendingVault();
        STABILITY_FUND_PROXY = NetworkAddresses.stabilityFund();
        TREASURY_PROXY = NetworkAddresses.treasury();
        LIQUIDATION_ENGINE_PROXY = NetworkAddresses.liquidationEngine();
        
        // Show which contracts to upgrade
        showUpgradeFlags();
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Upgrade of Lending Protocol contracts...");
        console.log("Deployer:", msg.sender);
        
        // 1. Deploy new implementations for contracts that need upgrading
        console.log("\n1. Deploying new implementations...");
        deployNewImplementations();
        
        // 2. Upgrade selected proxies
        console.log("\n2. Upgrading selected proxies...");
        upgradeSelectedProxies();
        
        vm.stopBroadcast();
        
        // 4. Log upgrade summary
        logUpgradeSummary();
    }
    
    function showUpgradeFlags() internal view {
        console.log("Upgrade flags set:");
        console.log("- ProtocolConfig:", upgradeProtocolConfig);
        console.log("- PUSD:", upgradePUSD);
        console.log("- wPUSD:", upgradeWPUSD);
        console.log("- StabilityFund:", upgradeStabilityFund);
        console.log("- Treasury:", upgradeTreasury);
        console.log("- LiquidationEngine:", upgradeLiquidationEngine);
        console.log("- LendingVault:", upgradeLendingVault);
        
        console.log("\nProxy addresses:");
        console.log("- ProtocolConfig Proxy:", PROTOCOL_CONFIG_PROXY);
        console.log("- PUSD Proxy:", PUSD_PROXY);
        console.log("- wPUSD Proxy:", WPUSD_PROXY);
        console.log("- StabilityFund Proxy:", STABILITY_FUND_PROXY);
        console.log("- Treasury Proxy:", TREASURY_PROXY);
        console.log("- LiquidationEngine Proxy:", LIQUIDATION_ENGINE_PROXY);
        console.log("- LendingVault Proxy:", LENDING_VAULT_PROXY);
    }
    
    function deployNewImplementations() internal {
        // Deploy new implementation contracts only for those that need upgrading
        
        if (upgradeProtocolConfig) {
            console.log("Deploying new ProtocolConfig implementation...");
            ProtocolConfig newProtocolConfig = new ProtocolConfig();
            protocolConfigImpl = address(newProtocolConfig);
        }
        
        if (upgradePUSD) {
            console.log("Deploying new PUSD implementation...");
            PUSD newPUSD = new PUSD();
            pusdImpl = address(newPUSD);
        }
        
        if (upgradeWPUSD) {
            console.log("Deploying new wPUSD implementation...");
            wPUSD newWPUSD = new wPUSD();
            wpusdImpl = address(newWPUSD);
        }
        
        if (upgradeStabilityFund) {
            console.log("Deploying new StabilityFund implementation...");
            StabilityFund newStabilityFund = new StabilityFund();
            stabilityFundImpl = address(newStabilityFund);
        }
        
        if (upgradeTreasury) {
            console.log("Deploying new Treasury implementation...");
            Treasury newTreasury = new Treasury();
            treasuryImpl = address(newTreasury);
        }
        
        if (upgradeLiquidationEngine) {
            console.log("Deploying new LiquidationEngine implementation...");
            LiquidationEngine newLiquidationEngine = new LiquidationEngine();
            liquidationEngineImpl = address(newLiquidationEngine);
        }
        
        if (upgradeLendingVault) {
            console.log("Deploying new LendingVault implementation...");
            LendingVault newLendingVault = new LendingVault();
            lendingVaultImpl = address(newLendingVault);
        }
    }
    
    function upgradeSelectedProxies() internal {
        // Upgrade core contracts
        upgradeCoreContracts();
        // Upgrade vault contracts
        upgradeVaultContracts();
    }
    
    function upgradeCoreContracts() internal {
        if (upgradeProtocolConfig) {
            console.log("Upgrading ProtocolConfig proxy...");
            try ProtocolConfig(PROTOCOL_CONFIG_PROXY).upgradeToAndCall(protocolConfigImpl, "") {
                console.log("ProtocolConfig upgraded successfully");
            } catch Error(string memory reason) {
                console.log("ProtocolConfig upgrade failed:", reason);
            }
        }
        
        if (upgradePUSD) {
            console.log("Upgrading PUSD proxy...");
            try PUSD(PUSD_PROXY).upgradeToAndCall(pusdImpl, "") {
                console.log("PUSD upgraded successfully");
            } catch Error(string memory reason) {
                console.log("PUSD upgrade failed:", reason);
            }
        }
        
        if (upgradeWPUSD) {
            console.log("Upgrading wPUSD proxy...");
            try wPUSD(WPUSD_PROXY).upgradeToAndCall(wpusdImpl, "") {
                console.log("wPUSD upgraded successfully");
            } catch Error(string memory reason) {
                console.log("wPUSD upgrade failed:", reason);
            }
        }
    }
    
    function upgradeVaultContracts() internal {
        if (upgradeStabilityFund) {
            console.log("Upgrading StabilityFund proxy...");
            try StabilityFund(STABILITY_FUND_PROXY).upgradeToAndCall(stabilityFundImpl, "") {
                console.log("StabilityFund upgraded successfully");
            } catch Error(string memory reason) {
                console.log("StabilityFund upgrade failed:", reason);
            }
        }
        
        if (upgradeTreasury) {
            console.log("Upgrading Treasury proxy...");
            try Treasury(TREASURY_PROXY).upgradeToAndCall(treasuryImpl, "") {
                console.log("Treasury upgraded successfully");
            } catch Error(string memory reason) {
                console.log("Treasury upgrade failed:", reason);
            }
        }
        
        if (upgradeLiquidationEngine) {
            console.log("Upgrading LiquidationEngine proxy...");
            try LiquidationEngine(LIQUIDATION_ENGINE_PROXY).upgradeToAndCall(liquidationEngineImpl, "") {
                console.log("LiquidationEngine upgraded successfully");
            } catch Error(string memory reason) {
                console.log("LiquidationEngine upgrade failed:", reason);
            }
        }
        
        if (upgradeLendingVault) {
            console.log("Upgrading LendingVault proxy...");
            try LendingVault(LENDING_VAULT_PROXY).upgradeToAndCall(lendingVaultImpl, "") {
                console.log("LendingVault upgraded successfully");
            } catch Error(string memory reason) {
                console.log("LendingVault upgrade failed:", reason);
            }
        }
    }
    
    function logUpgradeSummary() internal view {
        console.log("\n=== LENDING PROTOCOL UPGRADE SUMMARY ===");
        console.log("Network:", block.chainid);
        console.log("Block:", block.number);
        console.log("Timestamp:", block.timestamp);
        console.log("");
        console.log("Upgraded Contracts:");
        
        if (upgradeProtocolConfig) {
            console.log("- ProtocolConfig:    ", protocolConfigImpl);
        }
        if (upgradePUSD) {
            console.log("- PUSD:              ", pusdImpl);
        }
        if (upgradeWPUSD) {
            console.log("- wPUSD:             ", wpusdImpl);
        }
        if (upgradeStabilityFund) {
            console.log("- StabilityFund:     ", stabilityFundImpl);
        }
        if (upgradeTreasury) {
            console.log("- Treasury:          ", treasuryImpl);
        }
        if (upgradeLiquidationEngine) {
            console.log("- LiquidationEngine: ", liquidationEngineImpl);
        }
        if (upgradeLendingVault) {
            console.log("- LendingVault:      ", lendingVaultImpl);
        }
        
        console.log("");
        console.log("Upgrade completed successfully!");
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify new implementations on Etherscan");
        console.log("2. Test protocol functionality");
        console.log("3. Monitor for any issues");
        console.log("4. Update documentation if needed");
    }
} 