// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ProtocolConfig} from "../../contracts/ProtocolConfig.sol";

contract VerifyQuoter is Script {
    function run(address protocolConfigAddr, address factoryAddr, address pusdAddr) external {
        check(protocolConfigAddr, factoryAddr, pusdAddr);
    }

    function check(address protocolConfigAddr, address factoryAddr, address pusdAddr) public {
        ProtocolConfig config = ProtocolConfig(protocolConfigAddr);
        address factory = factoryAddr;
        address quoter = address(config.quoter());
        address token0 = address(config.collateralToken());
        address token1 = pusdAddr;
        uint24 fee = uint24(config.uniswapFee());

        console.log("=== QUOTER VERIFICATION ===");
        console.log("Factory:", factory);
        console.log("Quoter:", quoter);
        console.log("Token0 (collateral):", token0);
        console.log("Token1 (PUSD):", token1);
        console.log("Fee:", fee);

        // Check contracts exist
        if (_codeSize(factory) == 0) console.log("ERROR: no code at factory");
        if (_codeSize(quoter) == 0) console.log("ERROR: no code at quoter");

        // Check pool exists and is initialized
        address pool = IUniswapV3Factory(factory).getPool(token0, token1, fee);
        console.log("Pool:", pool);
        if (pool == address(0)) {
            console.log("ERROR: pool not found");
            return;
        }
        if (_codeSize(pool) == 0) {
            console.log("ERROR: no code at pool");
            return;
        }

        // Read basic pool state
        try IUniswapV3Pool(pool).liquidity() returns (uint128 liq) {
            console.log("liquidity:", uint256(liq));
        } catch {
            console.log("ERROR: pool.liquidity() failed");
        }
        // Verify actual token ordering in the pool
        try IUniswapV3Pool(pool).token0() returns (address pTok0) {
            console.log("pool.token0:", pTok0);
        } catch {}
        try IUniswapV3Pool(pool).token1() returns (address pTok1) {
            console.log("pool.token1:", pTok1);
        } catch {}
        try IUniswapV3Pool(pool).slot0() returns (uint160 sqrtPriceX96, int24 tick, uint16, uint16 obsCard, uint16, uint8, bool unlocked) {
            console.log("slot0 sqrtPriceX96:", sqrtPriceX96);
            console.log("slot0 tick:", tick);
            console.log("slot0 obsCard:", obsCard);
            console.log("slot0 unlocked:", unlocked);
        } catch {
            console.log("ERROR: pool.slot0() failed");
        }

        // Minimal quote attempts with adaptive amounts (no state change)
        if (pool != address(0)) {
            uint8 dec0 = _decimals(token0);
            uint8 dec1 = _decimals(token1);
            uint256 amt0 = _safeAmount(dec0, 6); // 10^(dec0-6)
            uint256 amt1 = _safeAmount(dec1, 6);

            // token0 -> token1 (V2)
            tryQuote(quoter, token0, token1, fee, amt0);

            // token1 -> token0 (V2)
            tryQuote(quoter, token1, token0, fee, amt1);
        }

        console.log("=== QUOTER VERIFICATION COMPLETE ===");
    }

    function tryQuote(address quoter, address tokenIn, address tokenOut, uint24 fee, uint256 amountIn) internal {
        IQuoterV2.QuoteExactInputSingleParams memory p = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            amountIn: amountIn,
            fee: fee,
            sqrtPriceLimitX96: 0
        });
        try IQuoterV2(quoter).quoteExactInputSingle(p) returns (uint256 out, uint160 sp, uint32 ticks, uint256 gasEst) {
            console.log("quote success");
            console.log(" amountOut:");
            console.log(out);
            console.log(" sqrtPriceAfter:");
            console.log(uint256(sp));
            console.log(" ticks:");
            console.log(uint256(ticks));
            console.log(" gasEstimate:");
            console.log(gasEst);
        } catch {
            console.log("quote reverted");
            console.log(" tokenIn:");
            console.log(tokenIn);
            console.log(" tokenOut:");
            console.log(tokenOut);
        }
    }

    function _decimals(address t) internal view returns (uint8) {
        try IERC20Metadata(t).decimals() returns (uint8 d) { return d; } catch { return 18; }
    }

    function _safeAmount(uint8 decimals_, uint8 shift) internal pure returns (uint256) {
        if (decimals_ <= shift) return 1;
        uint8 p = decimals_ - shift;
        // 10^p with overflow guard for p>77 (won't happen for ERC20)
        uint256 amt = 1;
        for (uint8 i = 0; i < p; i++) { amt *= 10; }
        return amt;
    }

    function _codeSize(address a) internal view returns (uint256 size) {
        assembly { size := extcodesize(a) }
    }
}


