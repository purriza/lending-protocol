// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import "../../contracts/mocks/MockCollateralToken.sol";
import "../../contracts/mocks/MockOracle.sol";
import "../../contracts/mocks/SwapRouterV3Adapter.sol";
import "../NetworkAddresses.sol";

/**
 * @title DeployMock
 * @notice Deploys testnet-only mocks (MockCollateralToken, MockOracle)
 */
contract DeployMock is Script {
    address public owner;

    address public collateralToken;
    address public oracle;
    address public routerV3Adapter;

	// MockOracle parameters
	uint8 public constant ORACLE_DECIMALS_DEFAULT = 8;
	int256 public constant ORACLE_INITIAL_ANSWER_DEFAULT = int256(3000e8);

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        owner = msg.sender;
        // uint8 oracleDecimals = ORACLE_DECIMALS_DEFAULT;
        // int256 oracleInitialAnswer = ORACLE_INITIAL_ANSWER_DEFAULT;

        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying mocks (testnet only)...");

        // Deploy MockCollateralToken
        /*{
            console.log("Deploying MockCollateralToken...");
            MockCollateralToken token = new MockCollateralToken(
                owner,
                "Mock Wrapped Staked ETH",
                "mwstETH"
            );
            collateralToken = address(token);
            console.log("MockCollateralToken deployed at:", collateralToken);
        }*/

        // Deploy SwapRouterV3Adapter pointing to Uniswap Sepolia SwapRouter02
        {
            console.log("Deploying SwapRouterV3Adapter...");
            // Official Sepolia SwapRouter02 per Uniswap docs
            address swapRouter02 = NetworkAddresses.swapRouter();
            SwapRouterV3Adapter adapter = new SwapRouterV3Adapter(swapRouter02);
            routerV3Adapter = address(adapter);
            console.log("SwapRouterV3Adapter deployed at:", routerV3Adapter);
        }

        // Deploy MockOracle
        /*{
            console.log("Deploying MockOracle...");
            MockOracle mockOracle = new MockOracle(oracleDecimals, oracleInitialAnswer, block.timestamp);
            oracle = address(mockOracle);
            console.log("MockOracle deployed at:", oracle);
        }*/

        vm.stopBroadcast();

        console.log("\n=== MOCK DEPLOY SUMMARY ===");
        console.log("Owner:", owner);
        //console.log("MockCollateralToken:", collateralToken);
        console.log("MockOracle:        ", oracle);
        console.log("SwapRouterV3Adapter:", routerV3Adapter);
        console.log("==========================\n");
    }
}


