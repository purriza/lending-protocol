// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../../contracts/ProtocolConfig.sol";
import "../NetworkAddresses.sol";

contract ConfigureProtocolConfig is Script {
    // Parameters
    uint256 public constant LIQUIDATION_THRESHOLD = 12000; // 120%
    uint256 public constant MIN_COLLATERAL_RATIO = 15000; // 150%
    uint256 public constant DEBT_CEILING = 1000000 ether; // 1M
    uint256 public constant MIN_DEBT = 500 ether; // 500 PUSD
    uint256 public constant CLOSE_FACTOR_BPS = 5000; // 50%
    uint256 public constant LIQUIDATION_BONUS_BPS = 1000; // 10%
    uint256 public constant UNISWAP_FEE = 3000; // 0.3%

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address protocolConfigAddr = NetworkAddresses.protocolConfig();
        ProtocolConfig protocolConfig = ProtocolConfig(protocolConfigAddr);
        console.log("Configuring ProtocolConfig contract...");
        console.log("ProtocolConfig Address:", protocolConfigAddr);
        console.log("Deployer:", msg.sender);

        // Discover addresses from current state (keeps scripts network-agnostic)
        address oracleAddr = address(protocolConfig.oracle());
        address routerAddr = address(protocolConfig.swapRouter());
        address quoterAddr = address(protocolConfig.quoter());
        address collateralAddr = protocolConfig.collateralToken();

        // Only set if zero; otherwise leave as-is
        if (oracleAddr == address(0)) {
            // Fallback known oracle per network
            oracleAddr = NetworkAddresses.oracle();
            protocolConfig.setOracle(oracleAddr);
            console.log("Oracle set:", oracleAddr);
        }
        if (routerAddr == address(0)) {
            console.log("Swap Router not set; please set via setSwapRouter after deployment.");
        }
        if (quoterAddr == address(0)) {
            console.log("Quoter not set; please set via setQuoter after deployment.");
        }
        if (collateralAddr == address(0)) {
            collateralAddr = NetworkAddresses.collateralToken();
            protocolConfig.setCollateralToken(collateralAddr);
            console.log("Collateral Token set:", collateralAddr);
        }

        // Treasury wallet
        protocolConfig.setTreasuryWallet(NetworkAddresses.treasuryWallet());

        // Risk params
        protocolConfig.setLiquidationThreshold(LIQUIDATION_THRESHOLD);
        protocolConfig.setMinCollateralRatio(MIN_COLLATERAL_RATIO);
        protocolConfig.setDebtCeiling(DEBT_CEILING);
        protocolConfig.setMinDebt(MIN_DEBT);
        protocolConfig.setCloseFactorBps(CLOSE_FACTOR_BPS);
        protocolConfig.setLiquidationBonusBps(LIQUIDATION_BONUS_BPS);
        protocolConfig.setUniswapFee(UNISWAP_FEE);

        vm.stopBroadcast();

        logConfigurationSummary(protocolConfigAddr, oracleAddr, routerAddr, quoterAddr, collateralAddr);
    }

    function logConfigurationSummary(
        address protocolConfigAddr,
        address oracleAddr,
        address routerAddr,
        address quoterAddr,
        address collateralAddr
    ) internal view {
        console.log("\n=== PROTOCOL CONFIG CONFIGURATION SUMMARY ===");
        console.log("Network:", block.chainid);
        console.log("Block:", block.number);
        console.log("Timestamp:", block.timestamp);
        console.log("");
        console.log("Contract Addresses:");
        console.log("- ProtocolConfig (target):", protocolConfigAddr);
        console.log("- Oracle:            ", oracleAddr);
        console.log("- Swap Router:       ", routerAddr);
        console.log("- Quoter:            ", quoterAddr);
        console.log("- Collateral Token:  ", collateralAddr);
        console.log("- Treasury Wallet:   ", NetworkAddresses.treasuryWallet());
        console.log("");
        console.log("Configuration Parameters:");
        console.log("- Liquidation Threshold:", LIQUIDATION_THRESHOLD);
        console.log("- Min Collateral Ratio:", MIN_COLLATERAL_RATIO);
        console.log("- Debt Ceiling:      ", DEBT_CEILING);
        console.log("- Min Debt:          ", MIN_DEBT);
        console.log("- Close Factor:      ", CLOSE_FACTOR_BPS);
        console.log("- Liquidation Bonus: ", LIQUIDATION_BONUS_BPS);
        console.log("- Uniswap Fee:       ", UNISWAP_FEE);
    }
} 