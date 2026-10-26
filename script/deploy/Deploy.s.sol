// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../../contracts/ProtocolConfig.sol";
import "../../contracts/PUSD.sol";
import "../../contracts/wPUSD.sol";
import "../../contracts/StabilityFund.sol";
import "../../contracts/Treasury.sol";
import "../../contracts/LiquidationEngine.sol";
import "../../contracts/LendingVault.sol";
import "../NetworkAddresses.sol";

/**
 * @title Deploy
 * @notice Deployment script for the lending protocol contracts
 * @dev Allows deploying only selected contracts with proxy pattern for upgradeability
 */
contract Deploy is Script {
    // Deployment addresses
    address public protocolConfig;
    address public pusd;
    address public wpusd;
    address public lendingVault;
    address public stabilityFund;
    address public treasury;
    address public liquidationEngine;

    address public collateralToken;
	address public treasuryWallet;

	// Runtime configuration addresses
	address public admin;
    address public upgrader;
	address public oracle; // Used by ProtocolConfig
	address public ammRouter; // Used by ProtocolConfig
	address public quoter; // Used by ProtocolConfig

	address public pusdAddress;
	address public wPusdAddress;
	address public protocolConfigAddress;
	address public lendingVaultAddress;
	address public stabilityFundAddress;
    address public treasuryAddress;
	address public liquidationEngineAddress;

    // Deployment flags - set these to true for contracts you want to deploy
    bool public deployProtocolConfig = true;
    bool public deployPUSD = true;
    bool public deployWPUSD = true;
    bool public deployLendingVault = true;
    bool public deployStabilityFund = true;
    bool public deployTreasury = true;
    bool public deployLiquidationEngine = true;
    
    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        // Set admin to the deployer by default to avoid admin issues during deploy
        admin = vm.addr(deployerPrivateKey);
        
        // External addresses
        oracle = NetworkAddresses.oracle();
        ammRouter = NetworkAddresses.swapRouter();
        quoter = NetworkAddresses.quoter();
        collateralToken = NetworkAddresses.collateralToken();
        
        // Wallet addresses
        treasuryWallet = NetworkAddresses.treasuryWallet();

        // Contract addresses
        pusdAddress = NetworkAddresses.pusd();
        wPusdAddress = NetworkAddresses.wpusd();
        protocolConfigAddress = NetworkAddresses.protocolConfig();
        lendingVaultAddress = NetworkAddresses.lendingVault();
        stabilityFundAddress = NetworkAddresses.stabilityFund();
        treasuryAddress = NetworkAddresses.treasury();
        liquidationEngineAddress = NetworkAddresses.liquidationEngine();

        // Show which contracts to deploy
        showDeployFlags();
        
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Deployment of Lending Protocol contracts...");
        console.log("Deployer:", msg.sender);
        console.log("Admin:", admin);
        
        // Deploy selected contracts
        console.log("\n1. Deploying selected contracts...");
        deploySelectedContracts();
        
        // Configure contract relationships
        console.log("\n2. Configuring contract relationships...");
        configureContracts();
        
        vm.stopBroadcast();
        
        // Log deployment summary
        logDeploymentSummary();
    }
    
    function showDeployFlags() internal view {
        console.log("Deploy flags set:");
        console.log("- ProtocolConfig:", deployProtocolConfig);
        console.log("- PUSD:", deployPUSD);
        console.log("- wPUSD:", deployWPUSD);
        console.log("- LendingVault:", deployLendingVault);
        console.log("- StabilityFund:", deployStabilityFund);  
        console.log("- Treasury:", deployTreasury);
        console.log("- LiquidationEngine:", deployLiquidationEngine);
    }
    
    function deploySelectedContracts() internal {
        // Deploy contracts in dependency order
        // Core contracts first (ProtocolConfig, PUSD, wPUSD), then the rest
        
        // 1. Core contracts (no dependencies)
        deployCoreContracts();
        
        // 2. All other contracts (depend on core contracts)
        deployAllOtherContracts();
    }
    
    function deployCoreContracts() internal {
        // Deploy core contracts first (ProtocolConfig, PUSD, wPUSD)
        // These have no dependencies and are needed by other contracts
        
        if (deployProtocolConfig) {
            console.log("Deploying ProtocolConfig...");
            protocolConfig = deployProtocolConfigContract();
            console.log("ProtocolConfig deployed at:", protocolConfig);
        }

        if (deployPUSD) {
            console.log("Deploying PUSD...");
            pusd = deployPUSDContract();
            console.log("PUSD deployed at:", pusd);
        }
        
        if (deployWPUSD) {
            console.log("Deploying wPUSD...");
            wpusd = deployWPUSDContract();
            console.log("wPUSD deployed at:", wpusd);
        }
    }
    
    function deployAllOtherContracts() internal {
        // Deploy all contracts that depend on core contracts
        
        if (deployLendingVault) {
            console.log("Deploying LendingVault...");
            lendingVault = deployLendingVaultContract();
            console.log("LendingVault deployed at:", lendingVault);
        }
        
        if (deployStabilityFund) {
            console.log("Deploying StabilityFund...");
            stabilityFund = deployStabilityFundContract();
            console.log("StabilityFund deployed at:", stabilityFund);
        }
        
        if (deployLiquidationEngine) {
            console.log("Deploying LiquidationEngine...");
            liquidationEngine = deployLiquidationEngineContract();
            console.log("LiquidationEngine deployed at:", liquidationEngine);
        }
        
        if (deployTreasury) {
            console.log("Deploying Treasury...");
            treasury = deployTreasuryContract();
            console.log("Treasury deployed at:", treasury);
        }
    }
    
    function deployProtocolConfigContract() internal returns (address) {
        ProtocolConfig implementation = new ProtocolConfig();
        
        bytes memory initData = abi.encodeCall(
            ProtocolConfig.initialize,
            (oracle, ammRouter, quoter, collateralToken)
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        return address(proxy);
    }
    
    function deployPUSDContract() internal returns (address) {
        PUSD implementation = new PUSD();

        address protocolConfigAddr = deployProtocolConfig ? protocolConfig : protocolConfigAddress;
        
        bytes memory initData = abi.encodeCall(
            PUSD.initialize,
            (protocolConfigAddr)
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        return address(proxy);
    }
    
    function deployWPUSDContract() internal returns (address) {
        wPUSD implementation = new wPUSD();

        address protocolConfigAddr = deployProtocolConfig ? protocolConfig : protocolConfigAddress;
        
        bytes memory initData = abi.encodeCall(
            wPUSD.initialize,
            (protocolConfigAddr)
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        return address(proxy);
    }
    
    function deployLendingVaultContract() internal returns (address) {
        LendingVault implementation = new LendingVault();
        
        // Use deployed contract addresses or hardcoded addresses if deployed before
        address pusdAddr = deployPUSD ? pusd : pusdAddress;
        address protocolConfigAddr = deployProtocolConfig ? protocolConfig : protocolConfigAddress;
        
        bytes memory initData = abi.encodeCall(
            LendingVault.initialize,
            (pusdAddr, protocolConfigAddr, collateralToken)
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        return address(proxy);
    }
    
    function deployStabilityFundContract() internal returns (address) {
        StabilityFund implementation = new StabilityFund();
        
        // Use deployed contract addresses or hardcoded addresses if deployed before
        address pusdAddr = deployPUSD ? pusd : pusdAddress;
        address wpusdAddr = deployWPUSD ? wpusd : wPusdAddress;
        address protocolConfigAddr = deployProtocolConfig ? protocolConfig : protocolConfigAddress;

        bytes memory initData = abi.encodeCall(
            StabilityFund.initialize,
            (protocolConfigAddr, pusdAddr, wpusdAddr)
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        return address(proxy);
    }

    function deployTreasuryContract() internal returns (address) {
        Treasury implementation = new Treasury();
        
        // Use deployed contract addresses or hardcoded addresses if deployed before
        address protocolConfigAddr = deployProtocolConfig ? protocolConfig : protocolConfigAddress;
        address pusdAddr = deployPUSD ? pusd : pusdAddress;
        
        bytes memory initData = abi.encodeCall(
            Treasury.initialize,
            (protocolConfigAddr, pusdAddr, collateralToken)
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        return address(proxy);
    }

    function deployLiquidationEngineContract() internal returns (address) {
        LiquidationEngine implementation = new LiquidationEngine();
        
        // Use deployed contract addresses or hardcoded addresses if deployed before
        address protocolConfigAddr = deployProtocolConfig ? protocolConfig : protocolConfigAddress;
        address pusdAddr = deployPUSD ? pusd : pusdAddress;
        
        bytes memory initData = abi.encodeCall(
            LiquidationEngine.initialize,
            (protocolConfigAddr, pusdAddr)
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        return address(proxy);
    }
    
    function configureContracts() internal {
        console.log("\n=== COMPREHENSIVE CONTRACT CONFIGURATION ===");
        
        // Configure ProtocolConfig references
        configureProtocolConfig();

        // Configure PUSD references
        configurePUSD();
        
        // Configure wPUSD references  
        configureWPUSD();
        
        // Configure LendingVault references
        configureLendingVault();
        
        // Configure StabilityFund references
        configureStabilityFund();
        
        // Configure LiquidationEngine references
        configureLiquidationEngine();

        // Configure Treasury references
        configureTreasury();
        
        console.log("Contract relationships configured successfully");
    }
    
    function configureProtocolConfig() internal {
        if (!deployProtocolConfig) return;
        
        console.log("\nConfiguring ProtocolConfig references...");
        
        // Set Treasury Wallet in ProtocolConfig
        console.log("Setting Treasury Wallet in ProtocolConfig:", treasuryWallet);
        ProtocolConfig(protocolConfig).setTreasuryWallet(treasuryWallet);
    }

    function configurePUSD() internal {
        if (!deployPUSD) return;
        
        console.log("\nConfiguring PUSD references...");
        
        // Set LendingVault in PUSD
        address lendingVaultAddr = deployLendingVault ? lendingVault : lendingVaultAddress;
        console.log("Setting LendingVault in PUSD:", lendingVaultAddr);
        PUSD(pusd).setLendingVault(lendingVaultAddr);

        // Set StabilityFund in PUSD
        address stabilityFundAddr = deployStabilityFund ? stabilityFund : stabilityFundAddress;
        console.log("Setting StabilityFund in PUSD:", stabilityFundAddr);
        PUSD(pusd).setStabilityFund(stabilityFundAddr);
    }
    
    function configureWPUSD() internal {
        if (!deployWPUSD) return;
        
        console.log("\nConfiguring wPUSD references...");
        
        // Set StabilityFund in wPUSD
        address stabilityFundAddr = deployStabilityFund ? stabilityFund : stabilityFundAddress;
        console.log("Setting StabilityFund in wPUSD:", stabilityFundAddr);
        wPUSD(wpusd).setStabilityFund(stabilityFundAddr);
    }
    
    function configureLendingVault() internal {
        if (!deployLendingVault) return;
        
        console.log("\nConfiguring LendingVault references...");
        
        // Set LiquidationEngine in LendingVault
        address liquidationEngineAddr = deployLiquidationEngine ? liquidationEngine : liquidationEngineAddress;
        console.log("Setting LiquidationEngine in LendingVault:", liquidationEngineAddr);
        LendingVault(lendingVault).setLiquidationEngine(liquidationEngineAddr);
        
        // Set StabilityFund in LendingVault
        address stabilityFundAddr = deployStabilityFund ? stabilityFund : stabilityFundAddress;
        console.log("Setting StabilityFund in LendingVault:", stabilityFundAddr);
        LendingVault(lendingVault).setStabilityFund(stabilityFundAddr);
        
        // Set Treasury in LendingVault 
        address treasuryAddr = deployTreasury ? treasury : treasuryAddress;
        console.log("Updating Treasury in LendingVault:", treasuryAddr);
        LendingVault(lendingVault).setTreasury(treasuryAddr);
    }
    
    function configureStabilityFund() internal {
        if (!deployStabilityFund) return;
        
        console.log("\nConfiguring StabilityFund references...");
        
        // Set LendingVault in StabilityFund
        address lendingVaultAddr = deployLendingVault ? lendingVault : lendingVaultAddress;
        console.log("Setting LendingVault in StabilityFund:", lendingVaultAddr);
        StabilityFund(stabilityFund).setLendingVault(lendingVaultAddr);
        
        // Set LiquidationEngine in StabilityFund
        address liquidationEngineAddr = deployLiquidationEngine ? liquidationEngine : liquidationEngineAddress;
        console.log("Setting LiquidationEngine in StabilityFund:", liquidationEngineAddr);
        StabilityFund(stabilityFund).setLiquidationEngine(liquidationEngineAddr);
        
        // Set Treasury in StabilityFund
        address treasuryAddr = deployTreasury ? treasury : treasuryAddress;
        console.log("Setting Treasury in StabilityFund:", treasuryAddr);
        StabilityFund(stabilityFund).setTreasury(treasuryAddr);
    }
    
    function configureTreasury() internal {
        if (!deployTreasury) return;
        
        console.log("\nConfiguring Treasury references...");
        
        // Set LendingVault in Treasury 
        address lendingVaultAddr = deployLendingVault ? lendingVault : lendingVaultAddress;
        console.log("Updating LendingVault in Treasury:", lendingVaultAddr);
        Treasury(treasury).setLendingVault(lendingVaultAddr);

        // Set StabilityFund in Treasury
        address stabilityFundAddr = deployStabilityFund ? stabilityFund : stabilityFundAddress;
        console.log("Setting StabilityFund in Treasury:", stabilityFundAddr);
        Treasury(treasury).setStabilityFund(stabilityFundAddr);

        // Set LiquidationEngine in Treasury
        address liquidationEngineAddr = deployLiquidationEngine ? liquidationEngine : liquidationEngineAddress;
        console.log("Setting LiquidationEngine in Treasury:", liquidationEngineAddr);
        Treasury(treasury).setLiquidationEngine(liquidationEngineAddr);   
    }

    function configureLiquidationEngine() internal {
        if (!deployLiquidationEngine) return;
        
        console.log("\nConfiguring LiquidationEngine references...");

        // Set LendingVault in LiquidationEngine 
        address lendingVaultAddr = deployLendingVault ? lendingVault : lendingVaultAddress;
        console.log("Updating LendingVault in LiquidationEngine:", lendingVaultAddr);
        LiquidationEngine(liquidationEngine).setLendingVault(lendingVaultAddr);
            
        // Set StabilityFund in LiquidationEngine
        address stabilityFundAddr = deployStabilityFund ? stabilityFund : stabilityFundAddress;
        console.log("Setting StabilityFund in LiquidationEngine:", stabilityFundAddr);
        LiquidationEngine(liquidationEngine).setStabilityFund(stabilityFundAddr);
            
        // Set Treasury in LiquidationEngine 
        address treasuryAddr = deployTreasury ? treasury : treasuryAddress;
        console.log("Setting Treasury in LiquidationEngine:", treasuryAddr);
        LiquidationEngine(liquidationEngine).setTreasury(treasuryAddr);   
    }

    function logDeploymentSummary() internal view {
        console.log("\n=== LENDING PROTOCOL DEPLOYMENT SUMMARY ===");
        console.log("Network:", block.chainid);
        console.log("Block:", block.number);
        console.log("Timestamp:", block.timestamp);
        console.log("");
        console.log("Deployed Contract Addresses:");
        
        if (deployProtocolConfig) {
            console.log("- ProtocolConfig:    ", protocolConfig);
        }
        if (deployPUSD) {
            console.log("- PUSD:              ", pusd);
        }
        if (deployWPUSD) {
            console.log("- wPUSD:             ", wpusd);
        }
        if (deployLendingVault) {
            console.log("- LendingVault:      ", lendingVault);
        }
        if (deployStabilityFund) {
            console.log("- StabilityFund:     ", stabilityFund);
        }
        if (deployTreasury) {
            console.log("- Treasury:          ", treasury);
        }
        if (deployLiquidationEngine) {
            console.log("- LiquidationEngine: ", liquidationEngine);
        }

        console.log("");
        console.log("Configuration:");
        console.log("- admin:             ", admin);
        console.log("- Oracle:            ", oracle);
        console.log("- AMM Router:        ", ammRouter);
        console.log("- Quoter:            ", quoter);
        console.log("");
        console.log("");
        console.log("Deployment completed successfully!");
        console.log("");
        console.log("Next steps:");
        console.log("1. Verify contracts on Etherscan");
        console.log("2. Set up oracle with real price feeds");
        console.log("3. Configure collateral token (wstETH for mainnet)");
        console.log("4. Set up AMM router for liquidations");
        console.log("5. Test protocol functionality");
    }
} 