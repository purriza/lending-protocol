// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ProtocolConfig} from "../../contracts/ProtocolConfig.sol";

contract VerifyPool is Script {
    function run(address protocolConfigAddr, address factoryAddr, address pusdAddr) external view {
        check(protocolConfigAddr, factoryAddr, pusdAddr);
    }

    function check(address protocolConfigAddr, address factoryAddr, address pusdAddr) public view {
        ProtocolConfig config = ProtocolConfig(protocolConfigAddr);
        address tokenA = address(config.collateralToken());
        address tokenB = pusdAddr;
        uint24 fee = uint24(config.uniswapFee());

        console.log("=== POOL VERIFICATION ===");
        console.log("Factory:", factoryAddr);
        console.log("TokenA (collateral):", tokenA);
        console.log("TokenB (PUSD):", tokenB);
        console.log("Fee:", fee);

        address pool = IUniswapV3Factory(factoryAddr).getPool(tokenA, tokenB, fee);
        console.log("Pool:", pool);
        if (pool == address(0)) {
            console.log("ERROR: pool not found");
            return;
        }
        if (_codeSize(pool) == 0) {
            console.log("ERROR: no code at pool");
            return;
        }

        // Identify actual token ordering in pool
        address p0 = IUniswapV3Pool(pool).token0();
        address p1 = IUniswapV3Pool(pool).token1();
        console.log("pool.token0:", p0);
        console.log("pool.token1:", p1);

        // Basic pool state
        try IUniswapV3Pool(pool).liquidity() returns (uint128 liq) {
            console.log("liquidity:", uint256(liq));
        } catch {
            console.log("ERROR: pool.liquidity() failed");
        }
        try IUniswapV3Pool(pool).slot0() returns (uint160 sqrtPriceX96, int24 tick, uint16, uint16 obsCard, uint16, uint8, bool unlocked) {
            console.log("slot0 sqrtPriceX96:", sqrtPriceX96);
            console.log("slot0 tick:", tick);
            console.log("slot0 obsCard:", obsCard);
            console.log("slot0 unlocked:", unlocked);
        } catch {
            console.log("ERROR: pool.slot0() failed");
        }
        try IUniswapV3Pool(pool).fee() returns (uint24 pf) {
            console.log("pool.fee:", pf);
        } catch {}
        try IUniswapV3Pool(pool).tickSpacing() returns (int24 spacing) {
            console.log("tickSpacing:", spacing);
        } catch {}

        // Pool token balances
        try IERC20Metadata(p0).balanceOf(pool) returns (uint256 bal0) {
            console.log("pool balance token0:", bal0);
        } catch {}
        try IERC20Metadata(p1).balanceOf(pool) returns (uint256 bal1) {
            console.log("pool balance token1:", bal1);
        } catch {}

        // Scan nearby initialized ticks
        _scanNearbyTicks(pool, 8); // scan +/- 8 tick intervals

        console.log("=== POOL VERIFICATION COMPLETE ===");
    }

    function _scanNearbyTicks(address pool, uint256 intervals) internal view {
        int24 spacing;
        int24 currentTick;
        try IUniswapV3Pool(pool).tickSpacing() returns (int24 s) { spacing = s; } catch { return; }
        try IUniswapV3Pool(pool).slot0() returns (uint160, int24 t, uint16, uint16, uint16, uint8, bool) { currentTick = t; } catch { return; }

        int24 base = (currentTick / spacing) * spacing; // round toward zero
        console.log("scan base tick:", base);

        for (int256 i = -int256(intervals); i <= int256(intervals); i++) {
            int24 t = base + int24(i) * spacing;
            // ticks(t) returns: liquidityGross, liquidityNet, feeGrowthOutside0X128, feeGrowthOutside1X128, tickCumulativeOutside, secondsPerLiquidityOutsideX128, secondsOutside, initialized
            try IUniswapV3Pool(pool).ticks(t) returns (
                uint128 gross,
                int128 net,
                uint256,
                uint256,
                int56,
                uint160,
                uint32,
                bool initialized
            ) {
                if (initialized || gross > 0 || net != 0) {
                    console.log("tick:", t);
                    console.log(" liquidityGross:", uint256(gross));
                    console.log(" liquidityNet:", int256(net));
                    console.log(" initialized:", initialized);
                }
            } catch {
                // ignore
            }
        }
    }

    function _codeSize(address a) internal view returns (uint256 size) {
        assembly { size := extcodesize(a) }
    }
}


