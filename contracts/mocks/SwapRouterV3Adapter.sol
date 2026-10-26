// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

/**
 * @title SwapRouterV3Adapter
 * @notice Adapts ISwapRouter.exactInputSingle (with deadline) calls to SwapRouter02.exactInputSingle
 * @dev Pulls tokens from caller, approves underlying SwapRouter02, performs the swap, and forwards output to recipient
 */
interface IV3SwapRouter {
        struct ExactInputSingleParams {
            address tokenIn;
            address tokenOut;
            uint24 fee;
            address recipient;
            uint256 amountIn;
            uint256 amountOutMinimum;
            uint160 sqrtPriceLimitX96;
        }

        function exactInputSingle(ExactInputSingleParams calldata params)
            external
            payable
            returns (uint256 amountOut);
}

contract SwapRouterV3Adapter is ISwapRouter {
    address public immutable underlyingV3Router02;

    constructor(address _underlyingV3Router02) {
        underlyingV3Router02 = _underlyingV3Router02;
    }

    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        // Enforce deadline semantics as in ISwapRouter
        require(block.timestamp <= params.deadline, "Adapter: expired");

        // Pull tokens from caller to this adapter
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);

        // Approve underlying router for exact amount
        IERC20(params.tokenIn).approve(underlyingV3Router02, 0);
        IERC20(params.tokenIn).approve(underlyingV3Router02, params.amountIn);

        // Build params for Router02
        IV3SwapRouter.ExactInputSingleParams memory p = IV3SwapRouter.ExactInputSingleParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            fee: params.fee,
            recipient: params.recipient,
            amountIn: params.amountIn,
            amountOutMinimum: params.amountOutMinimum,
            sqrtPriceLimitX96: params.sqrtPriceLimitX96
        });

        amountOut = IV3SwapRouter(underlyingV3Router02).exactInputSingle(p);

        // Reset allowance
        IERC20(params.tokenIn).approve(underlyingV3Router02, 0);
    }

    function exactInput(ExactInputParams calldata) external payable override returns (uint256) {
        revert("Adapter: exactInput not supported");
    }

    function exactOutputSingle(ExactOutputSingleParams calldata) external payable override returns (uint256) {
        revert("Adapter: exactOutputSingle not supported");
    }

    function exactOutput(ExactOutputParams calldata) external payable override returns (uint256) {
        revert("Adapter: exactOutput not supported");
    }

    function uniswapV3SwapCallback(int256, int256, bytes calldata) external pure override {
        revert("Adapter: not a pool callback");
    }
}


