// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
/**
* @title MockSwapRouter
* @notice Mock implementation of a swap router for testing purposes
* @dev Simulates Uniswap-like behavior with configurable exchange rates
*/
contract MockSwapRouter is ISwapRouter, Ownable {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice Exchange rates: tokenIn => tokenOut => rate (in basis points, 10000 = 1:1)
    mapping(address => mapping(address => uint256)) public exchangeRates;
    /// @notice Slippage simulation (in basis points)
    mapping(address => mapping(address => uint256)) public slippageRates;
    /// @notice Whether to simulate swap failure
    mapping(address => mapping(address => bool)) public shouldFailSwap;
    /// @notice Total amount of tokens available for swaps (for liquidity simulation)
    mapping(address => uint256) public tokenLiquidity;
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event SwapExecuted(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        address indexed recipient
    );
    event ExchangeRateSet(address indexed tokenIn, address indexed tokenOut, uint256 rate);
    event SlippageRateSet(address indexed tokenIn, address indexed tokenOut, uint256 slippage);
    event LiquiditySet(address indexed token, uint256 amount);
    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/
    error SwapFailed();
    error InsufficientLiquidity();
    error ExcessiveSlippage();
    error InvalidTokens();
    error ZeroAmount();
    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor() Ownable(msg.sender) {}
    /*//////////////////////////////////////////////////////////////
                            SWAP FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        if (params.tokenIn == params.tokenOut) revert InvalidTokens();
        if (params.amountIn == 0) revert ZeroAmount();
        if (block.timestamp > params.deadline) revert SwapFailed();
        // Check if this swap should fail (for testing failure scenarios)
        if (shouldFailSwap[params.tokenIn][params.tokenOut]) {
            revert SwapFailed();
        }
        // Calculate output amount based on exchange rate
        uint256 rate = exchangeRates[params.tokenIn][params.tokenOut];
        if (rate == 0) {
            rate = 10000; // Default 1:1 if not set
        }
        // Apply exchange rate
        amountOut = (params.amountIn * rate) / 10000;
        // Apply slippage
        uint256 slippage = slippageRates[params.tokenIn][params.tokenOut];
        if (slippage > 0) {
            amountOut = amountOut - (amountOut * slippage / 10000);
        }
        // Check minimum output
        if (amountOut < params.amountOutMinimum) {
            revert ExcessiveSlippage();
        }
        // Check liquidity
        if (tokenLiquidity[params.tokenOut] > 0 && amountOut > tokenLiquidity[params.tokenOut]) {
            revert InsufficientLiquidity();
        }
        // Transfer tokens
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        // If we have the output token, send it
        if (IERC20(params.tokenOut).balanceOf(address(this)) >= amountOut) {
            IERC20(params.tokenOut).transfer(params.recipient, amountOut);
        } else {
            // Mock: assume we "mint" the output token for testing
            // In real scenario, this would come from liquidity pools
        }
        // Update liquidity if tracking it
        if (tokenLiquidity[params.tokenOut] > 0) {
            tokenLiquidity[params.tokenOut] -= amountOut;
        }
        if (tokenLiquidity[params.tokenIn] > 0) {
            tokenLiquidity[params.tokenIn] += params.amountIn;
        }
        emit SwapExecuted(params.tokenIn, params.tokenOut, params.amountIn, amountOut, params.recipient);
        return amountOut;
    }
    function exactInput(ExactInputParams calldata) external payable override returns (uint256) {
        // Simplified implementation - could be extended for multi-hop swaps
        revert("Multi-hop swaps not implemented in mock");
    }
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Set exchange rate between two tokens
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param rate Exchange rate in basis points (10000 = 1:1)
     */
    function setExchangeRate(address tokenIn, address tokenOut, uint256 rate) external onlyOwner {
        exchangeRates[tokenIn][tokenOut] = rate;
        emit ExchangeRateSet(tokenIn, tokenOut, rate);
    }
    /**
     * @notice Set slippage rate for a token pair
     * @param tokenIn Input token address
     * @param tokenOut Output token address 
     * @param slippage Slippage rate in basis points (500 = 5%)
     */
    function setSlippageRate(address tokenIn, address tokenOut, uint256 slippage) external onlyOwner {
        slippageRates[tokenIn][tokenOut] = slippage;
        emit SlippageRateSet(tokenIn, tokenOut, slippage);
    }
    /**
     * @notice Set whether a swap should fail (for testing)
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param shouldFail Whether the swap should fail
     */
    function setShouldFailSwap(address tokenIn, address tokenOut, bool shouldFail) external onlyOwner {
        shouldFailSwap[tokenIn][tokenOut] = shouldFail;
    }
    /**
     * @notice Set liquidity for a token (for testing liquidity constraints)
     * @param token Token address
     * @param amount Amount of liquidity
     */
    function setTokenLiquidity(address token, uint256 amount) external onlyOwner {
        tokenLiquidity[token] = amount;
        emit LiquiditySet(token, amount);
    }
    /**
     * @notice Add tokens to the router for testing
     * @param token Token address
     * @param amount Amount to add
     */
    function addToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }
    /**
     * @notice Emergency withdraw function
     * @param token Token to withdraw
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        IERC20(token).transfer(owner(), amount);
    }
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Get current exchange rate between tokens
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @return rate Exchange rate in basis points
     */
    function getExchangeRate(address tokenIn, address tokenOut) external view returns (uint256 rate) {
        rate = exchangeRates[tokenIn][tokenOut];
        if (rate == 0) rate = 10000; // Default 1:1
    }
    /**
     * @notice Quote a swap without executing it
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Input amount
     * @return amountOut Expected output amount
     */
    function quote(address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (uint256 amountOut)
    {
        uint256 rate = exchangeRates[tokenIn][tokenOut];
        if (rate == 0) rate = 10000;
        amountOut = (amountIn * rate) / 10000;
        uint256 slippage = slippageRates[tokenIn][tokenOut];
        if (slippage > 0) {
            amountOut = amountOut - (amountOut * slippage / 10000);
        }
    }

    /**
     * @notice Quoter-compatible function mirroring quote logic for Treasury min-out checks
     * @dev Matches Uniswap V3 IQuoter signature; includes mock slippage to mirror router behavior
     */
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 /* fee */,
        uint256 amountIn,
        uint160 /* sqrtPriceLimitX96 */
    ) external view returns (uint256 amountOut) {
        uint256 rate = exchangeRates[tokenIn][tokenOut];
        if (rate == 0) rate = 10000;
        amountOut = (amountIn * rate) / 10000;
        uint256 slippage = slippageRates[tokenIn][tokenOut];
        if (slippage > 0) {
            amountOut = amountOut - (amountOut * slippage / 10000);
        }
    }
}