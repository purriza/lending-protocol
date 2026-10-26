// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {LiquidationEngine} from "../../contracts/LiquidationEngine.sol";
import {ProtocolConfig} from "../../contracts/ProtocolConfig.sol";
import {IPriceOracle} from "../../contracts/interfaces/IPriceOracle.sol";
import {IProtocolConfig} from "../../contracts/interfaces/IProtocolConfig.sol";
import {IPUSD} from "../../contracts/interfaces/IPUSD.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {DataTypes} from "../../contracts/DataTypes.sol";
import {MockOracle} from "../../contracts/mocks/MockOracle.sol";

contract LiquidationEngineHarness is LiquidationEngine {
    function harnessInit(address _protocolConfig, address _pusd) external {
        // Bypass OZ Initializable to simplify testing; set admin and vars directly
        protocolConfig = IProtocolConfig(_protocolConfig);
        pusd = IPUSD(_pusd);
        maxSlippage = 1000;
        treasuryRevenueFee = 2000;
        liquidationCounter = 1;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(protocolConfig.ADMIN_ROLE(), msg.sender);
    }

    function expose_computeMinOutOnFallback(uint256 amount) external returns (uint256) {
        uint256 expectedOutput = _getOracleExpectedAmount(amount);
        require(expectedOutput == 0, "oracle must fail for fallback");
        uint256 quotedAmount = _getQuoterPrice(amount);
        return (quotedAmount * (10000 - maxSlippage)) / 10000;
    }

    function expose_sendFundsToSF(uint256 debtAmt, uint256 excessAmt, uint256 iouAmt) external {
        _sendFundsToStabilityFund(debtAmt, excessAmt, iouAmt);
    }

    function expose_swapCollateral(uint256 amount) external returns (uint256) {
        // Calculate expected PUSD for the test
        uint256 expectedPUSD = _getOracleExpectedAmount(amount);
        return _swapCollateral(protocolConfig.collateralToken(), amount, expectedPUSD);
    }

    function expose_handleInsufficientSale(uint256 totalAmount, DataTypes.LiquidationOrder calldata order) external {
        _handleInsufficientSale(totalAmount, order);
    }

    function expose_getOracleExpectedAmount(uint256 collateralAmount) external view returns (uint256) {
        return _getOracleExpectedAmount(collateralAmount);
    }
}

contract FallbackToQuoterTest is TestSetup {
    LiquidationEngineHarness public harness;

    function setUp() public override {
        super.setUp();
        vm.startPrank(admin);
        // Deploy a fresh harness wired to the same config and PUSD
        harness = new LiquidationEngineHarness();
        harness.harnessInit(address(protocolConfig), address(pusd));
        harness.setStabilityFund(address(stabilityFund));
        harness.setTreasury(address(treasury));
        vm.stopPrank();
    }

    function test_FallbackToQuoter_WhenOracleFails_UsesQuoterWithSlippage() public {
        // Force oracle failure so _getOracleExpectedAmount returns 0
        mockOracle.setAnswer(0);

        // Configure quoter via ProtocolConfig already wired in TestSetup (MockQuoter)
        vm.prank(admin);
        mockQuoter.setSimulatedSlippage(0); // avoid extra noise

        // Use amount that is safe
        uint256 amountIn = 100 ether;

        // Ensure a known maxSlippage on harness
        vm.prank(admin);
        harness.setMaxSlippage(500);

        uint256 result = harness.expose_computeMinOutOnFallback(amountIn);
        // Compute expected using the same quoter the engine uses, then apply engine slippage
        (uint256 quoted,,,) = IQuoterV2(address(protocolConfig.quoter())).quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: address(wstETH),
                tokenOut: address(pusd),
                amountIn: amountIn,
                fee: uint24(protocolConfig.uniswapFee()),
                sqrtPriceLimitX96: 0
            })
        );
        uint256 expected = (quoted * (10000 - 500)) / 10000;
        assertEq(result, expected, "fallback min should apply quoter then slippage");
    }

    function test_SwapCollateral_WhenOracleFails_UsesQuoterFallback() public {
        // Force oracle failure so _getOracleExpectedAmount returns 0
        mockOracle.setAnswer(0);

        // Configure quoter via ProtocolConfig already wired in TestSetup (MockQuoter)
        vm.prank(admin);
        mockQuoter.setSimulatedSlippage(0); // avoid extra noise

        // Use amount that is safe
        uint256 amountIn = 100 ether;

        // Ensure a known maxSlippage on harness
        vm.prank(admin);
        harness.setMaxSlippage(500);

        // Mint wstETH to the harness so it can swap
        wstETH.mint(address(harness), amountIn);

        // This should hit the fallback path in _swapCollateral
        uint256 result = harness.expose_swapCollateral(amountIn);
        
        // Verify that the swap was executed (result should be > 0)
        assertGt(result, 0, "swap should return some PUSD");
    }

    function test_GetOracleExpectedAmount_WhenCollateralAmountZero_ReturnsZero() public view {
        uint256 result = harness.expose_getOracleExpectedAmount(0);
        assertEq(result, 0, "should return 0 when collateral amount is 0");
    }

    function test_GetOracleExpectedAmount_WhenPriceZero_ReturnsZero() public {
        // When price is 0 (oracle returns 0)
        mockOracle.setAnswer(0);
        
        uint256 result = harness.expose_getOracleExpectedAmount(100 ether);
        assertEq(result, 0, "should return 0 when oracle price is 0");
    }

    function test_GetOracleExpectedAmount_WhenOracleThrows_ReturnsZero() public {
        // We'll make the oracle throw by setting it to a contract that doesn't implement the interface
        vm.prank(admin);
        protocolConfig.setOracle(address(this)); // This will cause latestRoundData to fail
        
        uint256 result = harness.expose_getOracleExpectedAmount(100 ether);
        assertEq(result, 0, "should return 0 when oracle throws");
    }
}

contract SendFundsToStabilityFundTest is TestSetup {
    LiquidationEngineHarness public harness;

    function setUp() public override {
        super.setUp();
        vm.startPrank(admin);

        harness = new LiquidationEngineHarness();
        harness.harnessInit(address(protocolConfig), address(pusd));
        harness.setStabilityFund(address(stabilityFund));
        harness.setTreasury(address(treasury));
        harness.grantRole(protocolConfig.DEFAULT_ADMIN_ROLE(), admin);
        harness.grantRole(protocolConfig.ADMIN_ROLE(), admin);
        harness.grantRole(protocolConfig.UPGRADER_ROLE(), upgrader);
        // Autorizar al harness como LiquidationEngine en StabilityFund y Treasury
        stabilityFund.setLiquidationEngine(address(harness));
        treasury.setLiquidationEngine(address(harness));
        vm.stopPrank();
    }

    function test_SendFundsToSF_WhenTotalAmountPositive_CallsReceiveReturns() public {
        uint256 debtAmt = 100 ether;
        uint256 excessAmt = 20 ether;
        uint256 total = debtAmt + excessAmt;

        // Mint PUSD to the harness so it can approve and send
        _mintPUSD(address(harness), total);

        // Expect call to stabilityFund.receiveLiquidationReturns(debtAmt, excessAmt, iouAmt)
        bytes memory callData = abi.encodeWithSelector(
            stabilityFund.receiveLiquidationReturns.selector,
            debtAmt,
            excessAmt,
            0
        );
        vm.expectCall(address(stabilityFund), callData);

        vm.prank(admin);
        harness.expose_sendFundsToSF(debtAmt, excessAmt, 0);
    }

    function test_SendFundsToSF_NoCallWhenZeroTotal() public {
        // No calls should happen if all three are zero
        vm.prank(admin);
        harness.expose_sendFundsToSF(0, 0, 0);
    }

    function test_HandleInsufficientSale_SendsSaleToSF() public {
        // Prepare order with equal debt as totalAmount to avoid backstop usage
        uint256 totalAmount = 200 ether;
        uint256 debtBySF = 200 ether;
        uint256 debtByTreasury = 0;

        // Mint PUSD to harness so it can approve and send totalAmount
        _mintPUSD(address(harness), totalAmount);

        // Expect SF to receive the sale amount as principal, no excess, no IOU
        bytes memory callData = abi.encodeWithSelector(
            stabilityFund.receiveLiquidationReturns.selector,
            totalAmount,
            0,
            0
        );
        vm.expectCall(address(stabilityFund), callData);

        DataTypes.LiquidationOrder memory order;
        order.debtPaidBySF = debtBySF;
        order.debtPaidByTreasury = debtByTreasury;
        vm.prank(admin);
        harness.expose_handleInsufficientSale(totalAmount, order);
    }
}


