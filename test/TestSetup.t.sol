// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {ProtocolConfig} from "../contracts/ProtocolConfig.sol";
import {PUSD} from "../contracts/PUSD.sol";
import {wPUSD} from "../contracts/wPUSD.sol";
import {LendingVault} from "../contracts/LendingVault.sol";
import {StabilityFund} from "../contracts/StabilityFund.sol";
import {LiquidationEngine} from "../contracts/LiquidationEngine.sol";
import {Treasury} from "../contracts/Treasury.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockOracle} from "../contracts/mocks/MockOracle.sol";
import {MockSwapRouter} from "../contracts/mocks/MockSwapRouter.sol";
import {MockQuoter} from "../contracts/mocks/MockQuoter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract TestSetup is Test {
    // PUSD contracts
    PUSD public pusdImpl;
    PUSD public pusd;
    ERC1967Proxy public pusdProxy;

    // wPUSD contracts
    wPUSD public wpusdImpl;
    wPUSD public wpusd;
    ERC1967Proxy public wpusdProxy;

    // ProtocolConfig contracts
    ProtocolConfig public protocolConfigImpl;
    ProtocolConfig public protocolConfig;
    ERC1967Proxy public protocolConfigProxy;  

    // LendingVault contracts
    LendingVault public lendingVaultImpl;
    LendingVault public lendingVault;
    ERC1967Proxy public lendingVaultProxy;

    // StabilityFund contracts
    StabilityFund public stabilityFund;
    StabilityFund public stabilityFundImpl;
    ERC1967Proxy stabilityFundProxy;

    // LiquidationEngine contracts
    LiquidationEngine public liquidationEngine;
    LiquidationEngine public liquidationEngineImpl;
    ERC1967Proxy liquidationEngineProxy;

    // Treasury contracts
    Treasury public treasury;
    Treasury public treasuryImpl;
    ERC1967Proxy treasuryProxy;      
    
    // Mock contracts
    MockOracle public mockOracle;
    MockSwapRouter public mockSwapRouter;
    MockQuoter public mockQuoter;

    // wstETH
    MockERC20 public wstETH;
    
    // Users
    address public admin = makeAddr("admin");
    address public upgrader = makeAddr("upgrader");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    address public treasuryWallet = makeAddr("treasuryWallet");

    // Constants
    uint256 public constant INITIAL_PUSD_AMOUNT = 1_000_000 ether;
    uint256 public constant INITIAL_COLLATERAL = 5 ether; // 5 wstETH = 15,000 PUSD at 3000:1 rate
    uint256 public constant BORROW_AMOUNT = 10_000 ether; // 10k PUSD for realistic 1.5:1 collateral ratio

    uint256 public constant LIQUIDATION_AMOUNT = 1_000 ether;
    uint256 public constant YIELD_AMOUNT = 100 ether;

    uint256 public constant BACKSTOP_THRESHOLD = 1_000_000 ether;

    function setUp() public virtual {
        vm.startPrank(admin);

        // Deploy mock wstETH
        wstETH = new MockERC20("wstETH", "wstETH");
        
        // Deploy mock oracle with 8 decimals and price = 3000 USD
        mockOracle = new MockOracle(8, 3000e8, block.timestamp);
        
        // Deploy mock swap router
        mockSwapRouter = new MockSwapRouter();
        
        // Deploy mock quoter
        mockQuoter = new MockQuoter(admin);

        // Deploy ProtocolConfig
        protocolConfig = _deployProtocolConfig();

        // Deploy mock PUSD and wPUSD
        pusd = _deployPUSD();
        wpusd = _deployWPUSD();
        
        // Deploy LendingVault
        lendingVault = _deployLendingVault();
        
        // Deploy LiquidationEngine 
        liquidationEngine = _deployLiquidationEngine();
        
        // Deploy Treasury
        treasury = _deployTreasury();
        
        // Deploy StabilityFund
        stabilityFund = _deployStabilityFund();

        // Setup mock components
        _setupMockComponents();

        // Setup contract connections 
        _setupContractConnections();
        
        // Grant UPGRADER_ROLE to upgrader for upgrade tests
        protocolConfig.grantRole(protocolConfig.UPGRADER_ROLE(), upgrader);
        lendingVault.grantRole(protocolConfig.UPGRADER_ROLE(), upgrader);
        pusd.grantRole(protocolConfig.UPGRADER_ROLE(), upgrader);
        wpusd.grantRole(protocolConfig.UPGRADER_ROLE(), upgrader);
        liquidationEngine.grantRole(protocolConfig.UPGRADER_ROLE(), upgrader);
        stabilityFund.grantRole(protocolConfig.UPGRADER_ROLE(), upgrader);
        treasury.grantRole(protocolConfig.UPGRADER_ROLE(), upgrader);

        // Setup Mock AMM with liquidity for swaps 
        _setupMockAMM();
        
        // Configure ProtocolConfig uniswap fee for testing
        vm.stopPrank(); // Stop current prank context
        vm.startPrank(admin); // Start fresh prank as admin

        // Mint initial tokens to users
        wstETH.mint(user1, INITIAL_COLLATERAL * 2);
        wstETH.mint(user2, INITIAL_COLLATERAL * 2);
        
        vm.stopPrank();
    }
    
    /// @notice Setup all mock components and testing configurations
    /// @dev This function configures mocks, exchange rates, and testing parameters
    function _setupMockComponents() internal {
        // Setup MockSwapRouter
        _setupMockSwapRouter();
        
        // Setup MockQuoter with exchange rates 
        _setupMockQuoter();
    }

    /// @notice Setup all contract connections and dependencies
    /// @dev This function connects all deployed contracts together
    function _setupContractConnections() internal {
        // Configure ProtocolConfig to collateral token, AMM Router and Quoter
        protocolConfig.setCollateralToken(address(wstETH));
        protocolConfig.setSwapRouter(address(mockSwapRouter));
        protocolConfig.setQuoter(address(mockQuoter));
        protocolConfig.setTreasuryWallet(treasuryWallet);
        
        // Connect PUSD to LendingVault and StabilityFund
        pusd.setLendingVault(address(lendingVault));
        pusd.setStabilityFund(address(stabilityFund));

        // Connect wPUSD to StabilityFund
        wpusd.setStabilityFund(address(stabilityFund));
        
        // Connect LendingVault to LiquidationEngine, StabilityFund, and Treasury
        lendingVault.setLiquidationEngine(address(liquidationEngine));
        lendingVault.setStabilityFund(address(stabilityFund));
        lendingVault.setTreasury(address(treasury));
        
        // Connect StabilityFund to LendingVault, LiquidationEngine, and Treasury
        stabilityFund.setLendingVault(address(lendingVault));
        stabilityFund.setLiquidationEngine(address(liquidationEngine));
        stabilityFund.setTreasury(address(treasury));

        // Connect LiquidationEngine to LendingVault, Treasury and StabilityFund
        liquidationEngine.setLendingVault(address(lendingVault));
        liquidationEngine.setTreasury(address(treasury));
        liquidationEngine.setStabilityFund(address(stabilityFund));

        // Connect Treasury to LiquidationEngine and LendingVault 
        treasury.setLiquidationEngine(address(liquidationEngine));
        treasury.setLendingVault(address(lendingVault));
        treasury.setStabilityFund(address(stabilityFund));
    }

    function _deployProtocolConfig() internal returns (ProtocolConfig) {
        protocolConfigImpl = new ProtocolConfig();
        bytes memory protocolConfigData = abi.encodeWithSelector(
            ProtocolConfig.initialize.selector,
            address(mockOracle),
            address(mockSwapRouter),
            address(mockQuoter),
            address(wstETH)
        );
        protocolConfigProxy = new ERC1967Proxy(address(protocolConfigImpl), protocolConfigData);
        
        return ProtocolConfig(address(protocolConfigProxy));
    }

    function _deployPUSD() internal returns (PUSD) {
        pusdImpl = new PUSD();
        bytes memory pusdData = abi.encodeWithSelector(
            PUSD.initialize.selector,
            address(protocolConfig)
        );
        pusdProxy = new ERC1967Proxy(address(pusdImpl), pusdData);
        
        return PUSD(address(pusdProxy));
    }

    function _deployWPUSD() internal returns (wPUSD) {
        wpusdImpl = new wPUSD();
        bytes memory wpusdData = abi.encodeWithSelector(
            wPUSD.initialize.selector,
            address(protocolConfig)
        );
        wpusdProxy = new ERC1967Proxy(address(wpusdImpl), wpusdData);
        
        return wPUSD(address(wpusdProxy));
    }

    function _deployLendingVault() internal returns (LendingVault) {
        lendingVaultImpl = new LendingVault();
        bytes memory lendingVaultData = abi.encodeWithSelector(
            LendingVault.initialize.selector,
            address(pusd),
            address(protocolConfig),
            address(wstETH)
        );
        lendingVaultProxy = new ERC1967Proxy(
            address(lendingVaultImpl),
            lendingVaultData
        );

        return LendingVault(address(lendingVaultProxy));
    }

    function _deployStabilityFund() internal returns (StabilityFund) {
        stabilityFundImpl = new StabilityFund();
        bytes memory stabilityFundData = abi.encodeWithSelector(
            StabilityFund.initialize.selector,
            address(protocolConfig),
            address(pusd),
            address(wpusd)
        );
        stabilityFundProxy = new ERC1967Proxy(
            address(stabilityFundImpl),
            stabilityFundData
        );
        
        return StabilityFund(address(stabilityFundProxy));
    }

    function _deployLiquidationEngine() internal returns (LiquidationEngine) {
        liquidationEngineImpl = new LiquidationEngine();
        bytes memory liquidationEngineData = abi.encodeWithSelector(
            LiquidationEngine.initialize.selector,
            address(protocolConfig),
            address(pusd)
        );
        liquidationEngineProxy = new ERC1967Proxy(address(liquidationEngineImpl), liquidationEngineData);
        
        return LiquidationEngine(address(liquidationEngineProxy));
    }

    function _deployTreasury() internal returns (Treasury) {
        treasuryImpl = new Treasury();
        bytes memory treasuryData = abi.encodeWithSelector(
            Treasury.initialize.selector,
            address(protocolConfig),
            address(pusd),
            address(wstETH)
        );
        treasuryProxy = new ERC1967Proxy(address(treasuryImpl), treasuryData);
        return Treasury(address(treasuryProxy));
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _mintPUSD(address to, uint256 amount) internal {
        // Ensure lendingVault is properly configured before minting
        require(address(lendingVault) != address(0), "LendingVault not deployed");
        require(address(pusd) != address(0), "PUSD not deployed");
        
        vm.startPrank(address(lendingVault));
        pusd.mint(to, amount);
        vm.stopPrank();   
    }

    function _setupMockSwapRouter() internal {
        // Set up default testing parameters with production-like values
        // wstETH ~$3000, PUSD $1, low slippage for predictable tests
        // Rate calculation: amountOut = (amountIn * rate) / 10000
        // For 1 wstETH → 3000 PUSD: rate = 3000 * 10000
        
        mockSwapRouter.setExchangeRate(address(wstETH), address(pusd), 30000000); // 3000:1 rate 
        mockSwapRouter.setSlippageRate(address(wstETH), address(pusd), 50); // 0.5% slippage for predictable tests
    }

    function _setupMockQuoter() internal {
        // Set up default testing parameters for MockQuoter
        
        // Verify addresses are valid before setting exchange rates
        require(address(wstETH) != address(0), "wstETH address is zero");
        require(address(pusd) != address(0), "PUSD address is zero");
        require(address(mockQuoter) != address(0), "MockQuoter address is zero");
        
        // Set exchange rate: 1 wstETH = 3000 PUSD
        mockQuoter.setExchangeRate(address(wstETH), address(pusd), 3000e18); // 3000:1 rate
        mockQuoter.setSimulatedSlippage(50); // 0.5% slippage
        
        // Also set up common pairs for better compatibility
        mockQuoter.setupCommonPairs(address(wstETH), address(pusd));
    }

    /// @notice Setup mock AMM with realistic liquidity (oracle must be configured separately)
    function _setupMockAMM() internal {
        // Provide liquidity to mock AMM for wstETH <-> PUSD swaps

        // Mint wstETH and PUSD to provide liquidity
        uint256 ammLiquidity = 10_000_000 ether; // 10M ether of each token to handle large liquidation swaps
        // Mint wstETH for AMM liquidity (requires owner context)
        wstETH.mint(admin, ammLiquidity);
        
        // Mint PUSD for AMM liquidity using the lendingVault (which is authorized to mint)
        _mintPUSD(admin, ammLiquidity);

        vm.startPrank(admin);
        wstETH.approve(address(mockSwapRouter), ammLiquidity);
        pusd.approve(address(mockSwapRouter), ammLiquidity);
        mockSwapRouter.addToken(address(wstETH), ammLiquidity);
        mockSwapRouter.addToken(address(pusd), ammLiquidity);
        vm.stopPrank();
    }

    function _sendLiquidationFundsAndSwapCollateral(uint256 _liquidationAmount, uint256 _yieldAmount) internal {
        vm.startPrank(address(lendingVault));
        stabilityFund.sendLiquidationFunds(_liquidationAmount);
        vm.stopPrank();   

        // Mock the Liquidation engine swapping the users seized collateral for more PUSD than was requested
        _mintPUSD(address(liquidationEngine), _liquidationAmount + _yieldAmount);
    }

    function _setupStabilityFundForLiquidation() internal {
        // Mint PUSD to StabilityFund for liquidation liquidity
        _mintPUSD(address(stabilityFund), 1000000 ether); // 1M PUSD for liquidation
    }

    function _setupTreasuryForLiquidation() internal {
        // Mint PUSD to Treasury for liquidation liquidity
        _mintPUSD(address(admin), 1000000 ether); 
        
        // Then transfer to Treasury using its receivePUSD function
        vm.startPrank(admin);
        pusd.approve(address(treasury), 1000000 ether);
        treasury.receivePUSD(1000000 ether);
        vm.stopPrank();
    }
}

/*//////////////////////////////////////////////////////////////
                            TEST HARNESSES
//////////////////////////////////////////////////////////////*/

/**
 * @title StabilityFundHarness
 * @notice Test harness for StabilityFund that exposes internal functions for testing
 * @dev Used by UpdateExchangeRate.t.sol and invariant tests to test internal _updateExchangeRate
 */
contract StabilityFundHarness is StabilityFund {
    /**
     * @notice Exposes the internal _updateExchangeRate function for testing
     * @param newRate The new exchange rate to set
     */
    function updateExchangeRate(uint256 newRate) public {
        _updateExchangeRate(newRate);
    }
}

contract TreasuryHarness is Treasury {
    function swap(address _tokenIn, address _tokenOut, uint256 _amountIn) public returns (uint256 amountOut) {
        amountOut = _swap(_tokenIn, _tokenOut, _amountIn);
    }

    function computeMinAmountOut(address _tokenIn, address _tokenOut, uint256 _amountIn) public returns (uint256 minAmountOut) {
        return _computeMinAmountOut(_tokenIn, _tokenOut, _amountIn);
    }

    function getOraclePrice() public view returns (uint256 price, uint8 oracleDecimals) {
        return _getOraclePrice();
    }

    function getQuoterMinAmountOut(address _tokenIn, address _tokenOut, uint256 _amountIn) public returns (bool hasMin, uint256 quoterMinOut) {
        return _getQuoterMinAmountOut(_tokenIn, _tokenOut, _amountIn);
    }
}