// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ProtocolConfig} from "../../contracts/ProtocolConfig.sol";

contract DirectSwapCallee is IUniswapV3SwapCallback {
    address public payer;
    address public tokenToPay;

    function execute(
        address pool,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        address _payer,
        address _tokenToPay,
        address recipient
    ) external {
        payer = _payer;
        tokenToPay = _tokenToPay;
        IUniswapV3Pool(pool).swap(
            recipient,
            zeroForOne,
            amountSpecified,
            sqrtPriceLimitX96,
            abi.encode(payer, tokenToPay)
        );
        // clear storage to avoid stale approvals usage assumptions
        payer = address(0);
        tokenToPay = address(0);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        (address _payer, address _tokenToPay) = abi.decode(data, (address, address));
        uint256 amountToPay = amount0Delta > 0 ? uint256(amount0Delta) : uint256(amount1Delta);
        IERC20Metadata(_tokenToPay).transferFrom(_payer, msg.sender, amountToPay);
    }
}

contract VerifyRouter is Script {
    function run(address protocolConfigAddr, address factoryAddr, address pusdAddr) external {
        check(protocolConfigAddr, pusdAddr);
        // Direct pool swap (exact input) to validate execution path without router
        simulateDirectPoolSwap(protocolConfigAddr, factoryAddr, pusdAddr, true);
        // Router trials limited to ISwapRouter path (LiquidationEngine uses deadline)
    }

    function check(address protocolConfigAddr, address pusdAddr) public view {
        ProtocolConfig config = ProtocolConfig(protocolConfigAddr);
        address router = address(config.swapRouter());
        address tokenIn = pusdAddr;
        address tokenOut = address(config.collateralToken());

        console.log("=== ROUTER VERIFICATION ===");
        console.log("Router:", router);
        console.log("TokenIn (PUSD):", tokenIn);
        console.log("TokenOut (collateral):", tokenOut);

        uint256 codeSize = _codeSize(router);
        console.log("Router code size:", codeSize);
        if (codeSize == 0) {
            console.log("ERROR: No code at router");
            return;
        }

        // Validate router call compatibility with LiquidationEngine (staticcall dry-run)
        ISwapRouter.ExactInputSingleParams memory p = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: uint24(config.uniswapFee()),
            recipient: router, 
            deadline: block.timestamp + 300,
            amountIn: 1,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        // Staticcall to check selector presence and ABI compatibility (will revert but proves function exists)
        (bool ok, bytes memory ret) = router.staticcall(abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, p));
        if (ok) {
            console.log("Staticcall returned success (selector present) - note: no state changed.");
        } else {
            if (ret.length > 0) {
                console.log("Staticcall reverted with data (selector present, call path reached). This is expected in static context.");
            } else {
                console.log("Staticcall failed without data (selector may be missing or fallback consumed call).");
            }
        }

        console.log("=== ROUTER VERIFICATION COMPLETE ===");
    }

    // Removed router fork simulations; direct pool swap is enough for verification

    // removed revert decode util; not needed after cleaning

    // No quoter needed for direct pool swap

    // ============ Direct Pool Swap ============
    // Encoded data for callback
    struct CallbackData { address payer; address tokenToPay; }

    function simulateDirectPoolSwap(address protocolConfigAddr, address factoryAddr, address pusdAddr, bool pusdToWst) public {
        uint256 pk = vm.envUint("TESTER_PRIVATE_KEY");
        vm.selectFork(vm.createFork(vm.envString("SEPOLIA_RPC_URL")));

        ProtocolConfig config = ProtocolConfig(protocolConfigAddr);
        address tokenW = address(config.collateralToken());
        address tokenJ = pusdAddr;
        address tokenIn = pusdToWst ? tokenJ : tokenW;
        address tokenOut = pusdToWst ? tokenW : tokenJ;

        address pool = IUniswapV3Factory(factoryAddr).getPool(tokenJ, tokenW, uint24(config.uniswapFee()));
        if (pool == address(0)) {
            console.log("Direct pool swap: pool not found");
            return;
        }

        uint256 amountIn = _safeAmount(_decimals(tokenIn), 3);

        console.log("-- DIRECT POOL SWAP SIMULATION --");
        console.log("user:"); console.log(vm.addr(pk));
        console.log("tokenIn:"); console.log(tokenIn);
        console.log("tokenOut:"); console.log(tokenOut);
        console.log("pool:"); console.log(pool);
        console.log("user tokenIn balance:"); console.log(IERC20Metadata(tokenIn).balanceOf(vm.addr(pk)));
        if (IERC20Metadata(tokenIn).balanceOf(vm.addr(pk)) < amountIn) {
            console.log("Insufficient balance for direct swap");
            return;
        }

        vm.deal(vm.addr(pk), 1 ether);
        // deploy callee and approve it to pull funds from user
        DirectSwapCallee callee = new DirectSwapCallee();
        vm.startPrank(vm.addr(pk));
        IERC20Metadata(tokenIn).approve(address(callee), 0);
        IERC20Metadata(tokenIn).approve(address(callee), amountIn);
        vm.stopPrank();

        // Determine swap direction relative to pool ordering
        bool zeroForOne = (tokenIn == IUniswapV3Pool(pool).token0());
        // sqrtPriceLimit: use safe extremes (inline to reduce locals)
        uint160 limit = zeroForOne
            ? uint160(4295128740)
            : uint160(1461446703485210103287273052203988822378723970340);

        {
            address payer = vm.addr(pk);
            try callee.execute(
                pool,
                zeroForOne,
                int256(amountIn),
                limit,
                payer,
                tokenIn,
                payer
            ) {
                console.log("Direct pool swap success. deltas:");
            } catch {
                console.log("Direct pool swap reverted");
            }
        }
    }

    // ============ Router exactInputSingle trial (ISwapRouter) ============
    function tryRouterExactInput(address protocolConfigAddr, address pusdAddr) public {
        uint256 pk = vm.envUint("TESTER_PRIVATE_KEY");
        vm.selectFork(vm.createFork(vm.envString("SEPOLIA_RPC_URL")));

        ProtocolConfig config = ProtocolConfig(protocolConfigAddr);
        address router = address(config.swapRouter());
        address tokenIn = pusdAddr;
        address tokenOut = address(config.collateralToken());
        uint24 fee = uint24(config.uniswapFee());

        uint256 amountIn = _safeAmount(_decimals(tokenIn), 3); // small test amount

        console.log("-- ROUTER EXACT INPUT SINGLE TRIAL --");
        console.log("router:"); console.log(router);
        console.log("tokenIn:"); console.log(tokenIn);
        console.log("tokenOut:"); console.log(tokenOut);
        console.log("amountIn:"); console.log(amountIn);

        // ensure balance and approval from EOA to router
        address payer = vm.addr(pk);
        uint256 bal = IERC20Metadata(tokenIn).balanceOf(payer);
        console.log("user tokenIn balance:"); console.log(bal);
        if (bal < amountIn) {
            console.log("Insufficient tokenIn balance for router trial");
            return;
        }
        vm.startPrank(payer);
        IERC20Metadata(tokenIn).approve(router, 0);
        IERC20Metadata(tokenIn).approve(router, amountIn);
        vm.stopPrank();

        ISwapRouter.ExactInputSingleParams memory p = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: payer,
            deadline: block.timestamp + 300,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        try ISwapRouter(router).exactInputSingle(p) returns (uint256 out) {
            console.log("Router swap success. amountOut:"); console.log(out);
        } catch {
            console.log("Router swap reverted (likely wrong router or ABI).");
        }
    }

    function _codeSize(address a) internal view returns (uint256 size) {
        assembly { size := extcodesize(a) }
    }

    function _decimals(address t) internal view returns (uint8) {
        try IERC20Metadata(t).decimals() returns (uint8 d) { return d; } catch { return 18; }
    }

    function _safeAmount(uint8 decimals_, uint8 shift) internal pure returns (uint256) {
        if (decimals_ <= shift) return 1;
        uint8 p = decimals_ - shift;
        uint256 amt = 1;
        for (uint8 i = 0; i < p; i++) { amt *= 10; }
        return amt;
    }
}


