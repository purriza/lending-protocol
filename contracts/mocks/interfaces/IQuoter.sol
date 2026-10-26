// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IQuoter
 * @notice Mock interface for Uniswap V3 Quoter
 * @dev Simplified interface for testing purposes based on Uniswap V3 QuoterV2
 */
interface IQuoter {
    
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    struct QuoteExactOutputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountOut;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    /*//////////////////////////////////////////////////////////////
                            QUOTE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the amount out received for a given exact input swap without executing the swap
     * @param params The params for the quote, encoded as `QuoteExactInputSingleParams`
     * @return amountOut The amount of `tokenOut` that would be received
     * @return sqrtPriceX96After The sqrt price of the pool after the swap
     * @return initializedTicksCrossed The number of initialized ticks that the swap crossed
     * @return gasEstimate The estimated amount of gas that the swap consumes
     */
    function quoteExactInputSingle(QuoteExactInputSingleParams memory params)
        external
        view
        returns (
            uint256 amountOut,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
            uint256 gasEstimate
        );

    /**
     * @notice Returns the amount in required for a given exact output swap without executing the swap
     * @param params The params for the quote, encoded as `QuoteExactOutputSingleParams`
     * @return amountIn The amount of `tokenIn` that would be required
     * @return sqrtPriceX96After The sqrt price of the pool after the swap
     * @return initializedTicksCrossed The number of initialized ticks that the swap crossed
     * @return gasEstimate The estimated amount of gas that the swap consumes
     */
    function quoteExactOutputSingle(QuoteExactOutputSingleParams memory params)
        external
        view
        returns (
            uint256 amountIn,
            uint160 sqrtPriceX96After,
            uint32 initializedTicksCrossed,
            uint256 gasEstimate
        );

    /*//////////////////////////////////////////////////////////////
                        LEGACY FUNCTIONS (QuoterV1)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the amount out received for a given exact input swap without executing the swap
     * @param path The path of the swap, i.e. each token pair and the pool fee
     * @param amountIn The desired input amount
     * @return amountOut The amount of the final token that would be received
     * @return sqrtPriceX96AfterList List of the sqrt price after the swap for each pool in the path
     * @return initializedTicksCrossedList List of the initialized ticks that the swap crossed for each pool in the path
     * @return gasEstimate The estimated amount of gas that the swap consumes
     */
    function quoteExactInput(bytes memory path, uint256 amountIn)
        external
        view
        returns (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        );

    /**
     * @notice Returns the amount in required to receive the given exact output amount without executing the swap
     * @param path The path of the swap, i.e. each token pair and the pool fee
     * @param amountOut The desired output amount
     * @return amountIn The amount of the first token that would be required
     * @return sqrtPriceX96AfterList List of the sqrt price after the swap for each pool in the path
     * @return initializedTicksCrossedList List of the initialized ticks that the swap crossed for each pool in the path
     * @return gasEstimate The estimated amount of gas that the swap consumes
     */
    function quoteExactOutput(bytes memory path, uint256 amountOut)
        external
        view
        returns (
            uint256 amountIn,
            uint160[] memory sqrtPriceX96AfterList,
            uint32[] memory initializedTicksCrossedList,
            uint256 gasEstimate
        );

    /*//////////////////////////////////////////////////////////////
                        LEGACY FUNCTIONS (QuoterV1)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Legacy function for backward compatibility with QuoterV1
     * @dev This is the most commonly used function for simple price quotes
     */
    function quoteExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountIn,
        uint160 sqrtPriceLimitX96
    ) external view returns (uint256 amountOut);

    /**
     * @notice Legacy function for backward compatibility with QuoterV1
     */
    function quoteExactOutputSingle(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint256 amountOut,
        uint160 sqrtPriceLimitX96
    ) external view returns (uint256 amountIn);
}
