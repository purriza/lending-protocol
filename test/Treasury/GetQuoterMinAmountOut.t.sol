// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";

import {TestSetup, TreasuryHarness} from "../TestSetup.t.sol";

import {MockSwapRouter} from "../mocks/MockSwapRouter.sol";

import {ITreasury} from "../../contracts/interfaces/ITreasury.sol";
import {IProtocolConfig} from "../../contracts/interfaces/IProtocolConfig.sol";
import {Treasury} from "../../contracts/Treasury.sol";

contract TreasuryGetQuoterMinAmountOutTest is TestSetup {
    TreasuryHarness public treasuryHarnessImpl;
    TreasuryHarness public treasuryHarness;
    ERC1967Proxy public treasuryHarnessProxy;

    function setUp() public override {
        super.setUp();
    }

    function _deployTreasuryHarness() internal returns (TreasuryHarness) {
        treasuryHarnessImpl = new TreasuryHarness();
        bytes memory data = abi.encodeWithSelector(
            Treasury.initialize.selector,
            address(protocolConfig),
            address(pusd),
            address(wstETH)
        );
        treasuryHarnessProxy = new ERC1967Proxy(address(treasuryHarnessImpl), data);
        return TreasuryHarness(address(treasuryHarnessProxy));
    }

    function _deployAndConfigureTreasuryHarness() internal returns (TreasuryHarness h) {
         vm.startPrank(admin);

        h = _deployTreasuryHarness();
        
        h.grantRole(protocolConfig.ADMIN_ROLE(), admin);
        h.grantRole(protocolConfig.UPGRADER_ROLE(), upgrader);
        h.setLiquidationEngine(address(liquidationEngine));
        h.setLendingVault(address(lendingVault));
        h.setProtocolConfig(address(protocolConfig));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        getQuoterMinAmountOut TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getQuoterMinAmountOut_HasMinTrue_ComputesTreasurySlippage() public {
        TreasuryHarness h = _deployAndConfigureTreasuryHarness();

        uint256 amountIn = 1_000 ether;

        // Configure quoter to 1:1 and zero slippage for clean math
        vm.startPrank(admin);
        mockQuoter.setExchangeRate(address(pusd), address(wstETH), 1e18); // 1:1 rate in 18 decimals
        mockQuoter.setSimulatedSlippage(0); // 0% slippage
        vm.stopPrank();

        (bool hasMin, uint256 quoterMinOut) = h.getQuoterMinAmountOut(address(pusd), address(wstETH), amountIn);

        // Quoter out = amountIn -> 997 (0.3% fee adjustment) -> 947.15 (5% treasury slippage)
        uint256 expectedAfterFee = (amountIn * (10_000 - 30)) / 10_000; // 997 (0.3% fee adjustment for 0.3% pool)
        uint256 expected = (expectedAfterFee * (10_000 - 500)) / 10_000; // 947.15
        assertTrue(hasMin);
        assertEq(quoterMinOut, expected);
    }

    function test_getQuoterMinAmountOut_AppliesRouterThenTreasurySlippage() public {
        TreasuryHarness h = _deployAndConfigureTreasuryHarness();

        uint256 amountIn = 1_000 ether;

        // Quoter: 1:1 with 10% slippage; Treasury: default 5% slippage
        vm.startPrank(admin);
        mockQuoter.setExchangeRate(address(pusd), address(wstETH), 1e18); // 1:1 rate in 18 decimals
        mockQuoter.setSimulatedSlippage(1000); // 10% slippage
        vm.stopPrank();

        (bool hasMin, uint256 quoterMinOut) = h.getQuoterMinAmountOut(address(pusd), address(wstETH), amountIn);

        // Quoter out: 1000 -> 900 (10% slippage) -> 897.3 (0.3% fee adjustment) -> 852.435 (5% treasury slippage)
        uint256 expectedQuoterOut = (amountIn * (10_000 - 1000)) / 10_000; // 900
        uint256 expectedAfterFee = (expectedQuoterOut * (10_000 - 30)) / 10_000; // 897.3 (0.3% fee adjustment for 0.3% pool)
        uint256 expected = (expectedAfterFee * (10_000 - 500)) / 10_000; // 852.435
        assertTrue(hasMin);
        assertEq(quoterMinOut, expected);
    }

    function test_getQuoterMinAmountOut_UnsetQuoterReturnsFalseZero() public {
        TreasuryHarness h = _deployAndConfigureTreasuryHarness();

        // Simulate quoter unavailable by reverting the quote call
        vm.mockCallRevert(
            address(mockQuoter),
            abi.encodeWithSelector(
                IQuoterV2.quoteExactInputSingle.selector,
                IQuoterV2.QuoteExactInputSingleParams({
                    tokenIn: address(pusd),
                    tokenOut: address(wstETH),
                    amountIn: 123 ether,
                    fee: uint24(protocolConfig.uniswapFee()),
                    sqrtPriceLimitX96: 0
                })
            ),
            "quote revert"
        );

        (bool hasMin, uint256 quoterMinOut) = h.getQuoterMinAmountOut(address(pusd), address(wstETH), 123 ether);
        assertFalse(hasMin);
        assertEq(quoterMinOut, 0);
    }

    function test_getQuoterMinAmountOut_RevertFromQuoterReturnsFalseZero() public {
        TreasuryHarness h = _deployAndConfigureTreasuryHarness();

        uint256 amountIn = 500 ether;

        // Force the quoter call to revert using a mocked revert on quoteExactInputSingle
        bytes memory callData = abi.encodeWithSelector(
            IQuoterV2.quoteExactInputSingle.selector,
            IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: address(pusd),
                tokenOut: address(wstETH),
                amountIn: amountIn,
                fee: uint24(protocolConfig.uniswapFee()),
                sqrtPriceLimitX96: 0
            })
        );
        vm.mockCallRevert(address(mockQuoter), callData, "quote revert");

        (bool hasMin, uint256 quoterMinOut) = h.getQuoterMinAmountOut(address(pusd), address(wstETH), amountIn);
        assertFalse(hasMin);
        assertEq(quoterMinOut, 0);
    }
}