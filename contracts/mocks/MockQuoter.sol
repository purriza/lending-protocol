// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./interfaces/IQuoter.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockQuoter
 * @notice Mock implementation of Uniswap V3 Quoter for testing
 * @dev Provides configurable quotes for testing liquidation scenarios
 */
contract MockQuoter is IQuoter, Ownable {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // Mock exchange rates: tokenIn => tokenOut => rate (in 18 decimals)
    mapping(address => mapping(address => uint256)) public exchangeRates;
    
    // Fee adjustments for different pool fees
    mapping(uint24 => uint256) public feeAdjustments;
    
    // Global slippage simulation (basis points)
    uint256 public simulatedSlippage;
    
    // Whether to simulate quote failures
    bool public simulateFailure;

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    // Mock values for unused return parameters
    uint160 private constant MOCK_SQRT_PRICE = uint160(79228162514264337593543950336);
    uint32 private constant MOCK_TICKS_CROSSED = 1;
    uint256 private constant MOCK_GAS_ESTIMATE_SINGLE = 150000;
    uint256 private constant MOCK_GAS_ESTIMATE_MULTI = 200000;

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _owner) Ownable(_owner) {
        // Default fee adjustments (basis points to subtract)
        // Uniswap V3 fee tiers: 100 (0.01%), 500 (0.05%), 3000 (0.3%), 10000 (1%)
        // Map to basis points to subtract from quotes accordingly
        feeAdjustments[100] = 1;     // 0.01% pool = 0.01% adjustment
        feeAdjustments[500] = 5;     // 0.05% pool = 0.05% adjustment
        feeAdjustments[3000] = 30;   // 0.3% pool = 0.3% adjustment
        feeAdjustments[10000] = 100; // 1% pool = 1% adjustment
        
        simulatedSlippage = 100; // 1% default slippage simulation
    }

    /*//////////////////////////////////////////////////////////////
                            QUOTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                            QUOTER V2 FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function quoteExactInputSingle(IQuoter.QuoteExactInputSingleParams memory params)
        external
        view
        override
        returns (
            uint256 amountOut,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
            uint256 gasEstimate
        )
    {
        if (simulateFailure) {
            revert("MockQuoter: Simulated failure");
        }
        
        uint256 rate = exchangeRates[params.tokenIn][params.tokenOut];
        if (rate == 0) {
            rate = 1e18; // Default 1:1 rate
        }
        
        // Calculate base amount
        amountOut = (params.amountIn * rate) / 1e18;
        
        // Apply fee adjustment
        uint256 feeAdjustment = feeAdjustments[params.fee];
        if (feeAdjustment > 0) {
            amountOut = (amountOut * (10000 - feeAdjustment)) / 10000;
        }
        
        // Apply slippage simulation
        if (simulatedSlippage > 0) {
            amountOut = (amountOut * (10000 - simulatedSlippage)) / 10000;
        }
        
        // Return mock values for unused parameters
        sqrtPriceX96After = MOCK_SQRT_PRICE;
        initializedTicksCrossed = MOCK_TICKS_CROSSED;
        gasEstimate = MOCK_GAS_ESTIMATE_SINGLE;
    }

    function quoteExactOutputSingle(IQuoter.QuoteExactOutputSingleParams memory params)
        external
        view
        override
        returns (
            uint256 amountIn,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
            uint256 gasEstimate
        )
    {
        if (simulateFailure) {
            revert("MockQuoter: Simulated failure");
        }
        
        uint256 rate = exchangeRates[params.tokenIn][params.tokenOut];
        if (rate == 0) {
            rate = 1e18; // Default 1:1 rate
        }
        
        // Calculate base amount (inverse of exactInput)
        amountIn = (params.amountOut * 1e18) / rate;
        
        // Apply fee adjustment (increase input needed)
        uint256 feeAdjustment = feeAdjustments[params.fee];
        if (feeAdjustment > 0) {
            amountIn = (amountIn * 10000) / (10000 - feeAdjustment);
        }
        
        // Apply slippage simulation (increase input needed)
        if (simulatedSlippage > 0) {
            amountIn = (amountIn * 10000) / (10000 - simulatedSlippage);
        }
        
        // Return mock values for unused parameters
        sqrtPriceX96After = MOCK_SQRT_PRICE;
        initializedTicksCrossed = MOCK_TICKS_CROSSED;
        gasEstimate = MOCK_GAS_ESTIMATE_SINGLE;
    }

    /*//////////////////////////////////////////////////////////////
                        LEGACY FUNCTIONS (QuoterV1)
    //////////////////////////////////////////////////////////////*/

    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 /* sqrtPriceLimitX96 */
    ) external view override returns (uint256 amountOut) {
        if (simulateFailure) {
            revert("MockQuoter: Simulated failure");
        }
        
        uint256 rate = exchangeRates[tokenIn][tokenOut];
        if (rate == 0) {
            return 0; // No quote available
        }
        
        // Calculate base amount
        amountOut = (amountIn * rate) / 1e18;
        
        // Apply fee adjustment
        uint256 feeAdjustment = feeAdjustments[fee];
        if (feeAdjustment > 0) {
            amountOut = (amountOut * (10000 - feeAdjustment)) / 10000;
        }
        
        // Apply slippage simulation
        if (simulatedSlippage > 0) {
            amountOut = (amountOut * (10000 - simulatedSlippage)) / 10000;
        }
        
        // Safety check: prevent extremely large values
        if (amountOut > amountIn * 10000) {
            amountOut = amountIn * 10000; // Cap at 10000x input (allows for high-value assets)
        }
    }

    function quoteExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountOut,
        uint160 /* sqrtPriceLimitX96 */
    ) external view override returns (uint256 amountIn) {
        if (simulateFailure) {
            revert("MockQuoter: Simulated failure");
        }
        
        uint256 rate = exchangeRates[tokenIn][tokenOut];
        if (rate == 0) {
            return 0; // No quote available
        }
        
        // Calculate base amount (inverse of exactInput)
        amountIn = (amountOut * 1e18) / rate;
        
        // Apply fee adjustment (increase input needed)
        uint256 feeAdjustment = feeAdjustments[fee];
        if (feeAdjustment > 0) {
            amountIn = (amountIn * 10000) / (10000 - feeAdjustment);
        }
        
        // Apply slippage simulation (increase input needed)
        if (simulatedSlippage > 0) {
            amountIn = (amountIn * 10000) / (10000 - simulatedSlippage);
        }
        
        // Safety check: prevent extremely large values
        if (amountIn > amountOut * 10000) {
            amountIn = amountOut * 10000; // Cap at 10000x output (allows for high-value assets)
        }
    }

    function quoteExactInput(bytes memory /* path */, uint256 amountIn)
        external
        view
        override
        returns (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        )
    {
        if (simulateFailure) {
            revert("MockQuoter: Simulated failure");
        }
        
        // Simplified multi-hop simulation
        amountOut = amountIn; // 1:1 for simplicity
        
        // Apply some slippage for multi-hop
        if (simulatedSlippage > 0) {
            uint256 multiHopSlippage = simulatedSlippage * 2; // More slippage for multi-hop
            amountOut = (amountOut * (10000 - multiHopSlippage)) / 10000;
        }
        
        // Safety check: prevent extremely large values
        if (amountOut > amountIn * 1000) {
            amountOut = amountIn * 1000; // Cap at 1000x input
        }
        
        // Return mock arrays with single hop data
        sqrtPriceX96AfterList = new uint160[](1);
        sqrtPriceX96AfterList[0] = MOCK_SQRT_PRICE;
        
        initializedTicksCrossedList = new uint32[](1);
        initializedTicksCrossedList[0] = MOCK_TICKS_CROSSED;
        
        gasEstimate = MOCK_GAS_ESTIMATE_MULTI;
    }

    function quoteExactOutput(bytes memory /* path */, uint256 amountOut)
        external
        view
        override
        returns (
            uint256 amountIn,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        )
    {
        if (simulateFailure) {
            revert("MockQuoter: Simulated failure");
        }
        
        // Simplified multi-hop simulation
        amountIn = amountOut; // 1:1 for simplicity
        
        // Apply some slippage for multi-hop
        if (simulatedSlippage > 0) {
            uint256 multiHopSlippage = simulatedSlippage * 2;
            amountIn = (amountIn * 10000) / (10000 - multiHopSlippage);
        }
        
        // Return mock arrays with single hop data
        sqrtPriceX96AfterList = new uint160[](1);
        sqrtPriceX96AfterList[0] = MOCK_SQRT_PRICE;
        
        initializedTicksCrossedList = new uint32[](1);
        initializedTicksCrossedList[0] = MOCK_TICKS_CROSSED;
        
        gasEstimate = MOCK_GAS_ESTIMATE_MULTI;
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set exchange rate between two tokens
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param rate Exchange rate in 18 decimals (how much tokenOut per tokenIn)
     */
    function setExchangeRate(address tokenIn, address tokenOut, uint256 rate) external onlyOwner {
        exchangeRates[tokenIn][tokenOut] = rate;
    }

    /**
     * @notice Set fee adjustment for a specific pool fee tier
     * @param fee Pool fee in basis points
     * @param adjustment Adjustment in basis points to subtract from quote
     */
    function setFeeAdjustment(uint24 fee, uint256 adjustment) external onlyOwner {
        require(adjustment <= 2000, "Adjustment too high"); // Max 20%
        feeAdjustments[fee] = adjustment;
    }

    /**
     * @notice Set simulated slippage for all quotes
     * @param slippage Slippage in basis points
     */
    function setSimulatedSlippage(uint256 slippage) external onlyOwner {
        require(slippage <= 1000, "Slippage too high"); // Max 10%
        simulatedSlippage = slippage;
    }

    /**
     * @notice Toggle failure simulation for testing error handling
     * @param shouldFail Whether quotes should fail
     */
    function setSimulateFailure(bool shouldFail) external onlyOwner {
        simulateFailure = shouldFail;
    }

    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set up common token pairs for testing
     * @param wstETH wstETH token address
     * @param pusd PUSD token address
     */
    function setupCommonPairs(address wstETH, address pusd) external onlyOwner {
        // wstETH to PUSD: assume 1 wstETH = 2000 PUSD (roughly 1 ETH = $2000)
        exchangeRates[wstETH][pusd] = 2000e18;
        
        // PUSD to wstETH: reverse rate
        exchangeRates[pusd][wstETH] = 5e14; // 0.0005 wstETH per PUSD
    }

    /**
     * @notice Simulate market conditions
     * @param condition 0=normal, 1=high_volatility, 2=low_liquidity, 3=market_crash
     */
    function simulateMarketConditions(uint8 condition) external onlyOwner {
        if (condition == 0) {
            // Normal conditions
            simulatedSlippage = 100; // 1%
            simulateFailure = false;
        } else if (condition == 1) {
            // High volatility
            simulatedSlippage = 500; // 5%
            simulateFailure = false;
        } else if (condition == 2) {
            // Low liquidity
            simulatedSlippage = 1000; // 10%
            simulateFailure = false;
        } else if (condition == 3) {
            // Market crash / oracle issues
            simulatedSlippage = 2000; // 20%
            simulateFailure = true;
        }
    }
}
