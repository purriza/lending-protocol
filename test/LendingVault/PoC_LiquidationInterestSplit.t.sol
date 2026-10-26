// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {ILendingVault} from "../../contracts/interfaces/ILendingVault.sol";
import {console} from "forge-std/console.sol";

/**
 * @title PoC_LiquidationInterestSplit
 * @notice Proof of Concept demonstrating that liquidations correctly split between principal and interest
 * @dev This test explicitly validates that:
 *      1. During liquidation, the debt payment is split between principal and interest
 *      2. Only the PRINCIPAL portion is burned from PUSD total supply
 *      3. The INTEREST portion goes to Treasury (totalInterestFees increases)
 *      4. Treasury receives all interest fees, preventing revenue loss
 * 
 * CONTEXT:
 * - This addresses the concern that liquidations might burn the full amount (principal + interest)
 * - The current implementation correctly mirrors the repay() logic
 * - Both full liquidations (liquidatePosition) and partial liquidations (_executePartialLiquidation) 
 *   properly split the payment
 */
contract PoC_LiquidationInterestSplit is TestSetup {

    // Test constants
    uint256 constant COLLATERAL_AMOUNT = 100 ether;
    uint256 constant POC_BORROW_AMOUNT = 10_000 ether; // 10k PUSD (matches other tests)
    uint256 constant TIME_ELAPSED = 180 days; // 6 months to accrue significant interest

    function setUp() public override {
        super.setUp();
        
        // Authorize this test as liquidation bot
        vm.prank(admin);
        lendingVault.setLiquidationBot(address(this), true);
        
        // Setup StabilityFund with liquidity for liquidations
        _setupStabilityFundForLiquidation();
        
        // Ensure user1 has enough wstETH
        if (wstETH.balanceOf(user1) < COLLATERAL_AMOUNT) {
            wstETH.mint(user1, COLLATERAL_AMOUNT - wstETH.balanceOf(user1));
        }
        
        // Setup user1 with a position that will accrue interest
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), COLLATERAL_AMOUNT);
        lendingVault.deposit(COLLATERAL_AMOUNT);
        lendingVault.borrow(POC_BORROW_AMOUNT);
        vm.stopPrank();
    }

    /**
     * @notice PROOF OF CONCEPT: Liquidation Interest/Principal Split Works Correctly
     * @dev This test proves that:
     *      - Interest portion increases totalInterestFees (goes to Treasury)
     *      - Principal portion decreases total supply (gets burned)
     *      - No revenue loss occurs
     */
    function test_PoC_Liquidation_CorrectlySplitsPrincipalAndInterest() public {
        console.log("\n========================================");
        console.log("PoC: LIQUIDATION INTEREST/PRINCIPAL SPLIT");
        console.log("========================================\n");

        // ============================================================
        // STEP 1: ADVANCE TIME TO ACCRUE INTEREST
        // ============================================================
        vm.warp(block.timestamp + TIME_ELAPSED);
        mockOracle.setUpdatedAt(block.timestamp);

        uint256 currentDebt = lendingVault.getCurrentDebt(user1);
        (,,,uint256 purePrincipal,) = lendingVault.positions(user1);
        uint256 accruedInterest = currentDebt - purePrincipal;

        console.log("INITIAL STATE:");
        console.log("- Pure Principal:    ", purePrincipal / 1e18, "PUSD");
        console.log("- Accrued Interest:  ", accruedInterest / 1e18, "PUSD");
        console.log("- Total Debt:        ", currentDebt / 1e18, "PUSD");
        console.log("");

        assertEq(purePrincipal, POC_BORROW_AMOUNT, "Pure principal should equal borrow amount");
        assertGt(accruedInterest, 0, "Interest should have accrued over 6 months");

        // ============================================================
        // STEP 2: MAKE POSITION LIQUIDATABLE
        // ============================================================
        _pushHealthBelowThreshold();
        
        uint256 closeFactorBps = lendingVault.protocolConfig().closeFactorBps();
        uint256 debtToLiquidate = (currentDebt * closeFactorBps) / 10000;

        console.log("LIQUIDATION PARAMETERS:");
        console.log("- Close Factor:      ", closeFactorBps / 100, "%");
        console.log("- Debt to Liquidate: ", debtToLiquidate / 1e18, "PUSD");
        console.log("");

        // ============================================================
        // STEP 3: CALCULATE EXPECTED SPLIT (WATERFALL PAYMENT)
        // ============================================================
        // The payment waterfall: Interest is paid FIRST, then principal
        // If payment > accrued interest: ALL interest is paid, rest goes to principal
        // If payment <= accrued interest: Only interest is paid, no principal
        uint256 expectedInterestPortion;
        uint256 expectedPrincipalPortion;
        
        if (debtToLiquidate <= accruedInterest) {
            expectedInterestPortion = debtToLiquidate;
            expectedPrincipalPortion = 0;
        } else {
            expectedInterestPortion = accruedInterest; // ALL interest paid first
            expectedPrincipalPortion = debtToLiquidate - accruedInterest; // Rest to principal
        }

        console.log("EXPECTED SPLIT:");
        console.log("- Interest Portion:  ", expectedInterestPortion / 1e18, "PUSD (to totalInterestFees)");
        console.log("- Principal Portion: ", expectedPrincipalPortion / 1e18, "PUSD (to burn)");
        console.log("");

        // ============================================================
        // STEP 4: RECORD PRE-LIQUIDATION STATE
        // ============================================================
        uint256 totalSupplyBefore = pusd.totalSupply();
        uint256 totalInterestFeesBefore = lendingVault.totalInterestFees();

        console.log("PRE-LIQUIDATION:");
        console.log("- Total Supply:      ", totalSupplyBefore / 1e18, "PUSD");
        console.log("- totalInterestFees: ", totalInterestFeesBefore / 1e18, "PUSD");
        console.log("");

        // ============================================================
        // STEP 5: EXECUTE LIQUIDATION
        // ============================================================
        ILendingVault.LiquidationResult memory result = lendingVault.liquidatePosition(user1);

        console.log("LIQUIDATION EXECUTED:");
        console.log("- Debt Repaid:       ", result.debtRepaid / 1e18, "PUSD");
        console.log("- Collateral Seized: ", result.collateralSeized / 1e18, "wstETH");
        console.log("");

        // ============================================================
        // STEP 6: VERIFY POST-LIQUIDATION STATE
        // ============================================================
        uint256 totalSupplyAfter = pusd.totalSupply();
        uint256 totalInterestFeesAfter = lendingVault.totalInterestFees();

        uint256 supplyDecrease = totalSupplyBefore - totalSupplyAfter;
        uint256 interestFeesIncrease = totalInterestFeesAfter - totalInterestFeesBefore;

        console.log("POST-LIQUIDATION:");
        console.log("- Total Supply:      ", totalSupplyAfter / 1e18, "PUSD");
        console.log("- totalInterestFees: ", totalInterestFeesAfter / 1e18, "PUSD");
        console.log("");

        console.log("CHANGES:");
        console.log("- Supply Decrease:   ", supplyDecrease / 1e18, "PUSD (principal burned)");
        console.log("- Interest Fees Inc: ", interestFeesIncrease / 1e18, "PUSD (interest collected)");
        console.log("");

        // ============================================================
        // CRITICAL ASSERTIONS - PROOF OF CORRECT BEHAVIOR
        // ============================================================
        
        // ASSERTION 1: totalInterestFees increased by the interest portion
        assertApproxEqRel(
            interestFeesIncrease, 
            expectedInterestPortion, 
            0.01e18, // 1% tolerance
            "FAILED: totalInterestFees should increase by interest portion"
        );

        // ASSERTION 2: Only principal was burned from supply
        assertApproxEqRel(
            supplyDecrease, 
            expectedPrincipalPortion, 
            0.01e18, // 1% tolerance
            "FAILED: Only principal should be burned from supply"
        );

        // ASSERTION 3: The split adds up correctly
        assertApproxEqRel(
            interestFeesIncrease + supplyDecrease,
            debtToLiquidate,
            0.01e18,
            "FAILED: Interest + Principal should equal debt liquidated"
        );

        console.log("========================================");
        console.log("PASS: ALL ASSERTIONS PASSED");
        console.log("PASS: Interest correctly increases totalInterestFees");
        console.log("PASS: Only principal is burned from supply");
        console.log("PASS: No revenue loss occurs");
        console.log("PASS: Split is mathematically correct");
        console.log("========================================\n");
    }

    /**
     * @notice PROOF OF CONCEPT: Partial Liquidation Split Works Too
     * @dev Proves that even with insufficient funds (hybrid liquidation),
     *      the split is still calculated correctly
     */
    function test_PoC_PartialLiquidation_SplitWorksCorrectly() public {
        console.log("\n========================================");
        console.log("PoC: PARTIAL LIQUIDATION - SPLIT WORKS");
        console.log("========================================\n");

        // Accrue interest
        vm.warp(block.timestamp + TIME_ELAPSED);
        mockOracle.setUpdatedAt(block.timestamp);

        uint256 currentDebt = lendingVault.getCurrentDebt(user1);
        (,,,uint256 purePrincipal,) = lendingVault.positions(user1);
        uint256 accruedInterest = currentDebt - purePrincipal;

        console.log("INITIAL STATE:");
        console.log("- Pure Principal:    ", purePrincipal / 1e18, "PUSD");
        console.log("- Accrued Interest:  ", accruedInterest / 1e18, "PUSD");
        console.log("");

        // Make liquidatable
        _pushHealthBelowThreshold();
        
        uint256 debtToLiquidate = _calculateDebtToLiquidate(user1);
        
        // Create partial funding scenario
        _clearAllFunds();
        uint256 partialFunding = debtToLiquidate / 3; // Only 33% available
        _mintPUSD(address(stabilityFund), partialFunding);

        console.log("PARTIAL SCENARIO:");
        console.log("- Debt to Liquidate: ", debtToLiquidate / 1e18, "PUSD");
        console.log("- Available Funds:   ", partialFunding / 1e18, "PUSD (33%)");
        console.log("");

        // Calculate expected split for partial amount (waterfall logic)
        uint256 expectedInterestPortion;
        uint256 expectedPrincipalPortion;
        
        if (partialFunding <= accruedInterest) {
            expectedInterestPortion = partialFunding;
            expectedPrincipalPortion = 0;
        } else {
            expectedInterestPortion = accruedInterest;
            expectedPrincipalPortion = partialFunding - accruedInterest;
        }

        console.log("EXPECTED SPLIT:");
        console.log("- Interest Portion:  ", expectedInterestPortion / 1e18, "PUSD");
        console.log("- Principal Portion: ", expectedPrincipalPortion / 1e18, "PUSD");
        console.log("");

        // Record state
        uint256 totalSupplyBefore = pusd.totalSupply();
        uint256 totalInterestFeesBefore = lendingVault.totalInterestFees();

        // Execute
        ILendingVault.LiquidationResult memory result = lendingVault.liquidatePosition(user1);

        console.log("RESULT:");
        console.log("- Debt Repaid:       ", result.debtRepaid / 1e18, "PUSD");
        console.log("- Partial Liq:       ", result.fullLiquidation ? "NO" : "YES");
        console.log("");

        // Verify
        uint256 supplyDecrease = totalSupplyBefore - pusd.totalSupply();
        uint256 interestFeesIncrease = lendingVault.totalInterestFees() - totalInterestFeesBefore;

        console.log("CHANGES:");
        console.log("- Supply Decrease:   ", supplyDecrease / 1e18, "PUSD");
        console.log("- Interest Fees Inc: ", interestFeesIncrease / 1e18, "PUSD");
        console.log("");

        // Verify partial liquidation occurred
        assertEq(result.debtRepaid, partialFunding, "Should repay only available funds");
        assertFalse(result.fullLiquidation, "Should be partial liquidation");

        // Even in partial liquidations, split is correct
        assertApproxEqRel(
            interestFeesIncrease, 
            expectedInterestPortion, 
            0.01e18,
            "FAILED: Interest fees should increase correctly even in partial liquidation"
        );

        assertApproxEqRel(
            supplyDecrease, 
            expectedPrincipalPortion, 
            0.01e18,
            "FAILED: Only principal burned even in partial liquidation"
        );

        console.log("========================================");
        console.log("PASS: PARTIAL LIQUIDATION SPLIT WORKS");
        console.log("PASS: Interest handling is correct");
        console.log("PASS: No revenue loss in partial scenarios");
        console.log("========================================\n");
    }

    // ============================================================
    // HELPER FUNCTIONS
    // ============================================================

    function _pushHealthBelowThreshold() internal {
        // Get current position data
        (uint256 collateral, uint256 debt,,) = lendingVault.getPosition(user1);
        uint8 d = mockOracle.decimals();
        uint256 threshold = protocolConfig.liquidationThreshold();
        
        // Calculate target price: targetPrice = threshold * debt * 10^d / (10000 * collateral)
        uint256 numerator = threshold * debt * (10 ** d);
        uint256 denominator = 10000 * collateral;
        uint256 targetPrice = denominator == 0 ? 0 : numerator / denominator;
        uint256 newPrice = targetPrice > 1 ? (targetPrice - 1) : 1;
        
        mockOracle.setAnswer(int256(newPrice));
    }

    function _calculateDebtToLiquidate(address _user) internal view returns (uint256) {
        uint256 currentDebt = lendingVault.getCurrentDebt(_user);
        uint256 closeFactorBps = lendingVault.protocolConfig().closeFactorBps();
        return (currentDebt * closeFactorBps) / 10000;
    }

    function _clearAllFunds() internal {
        uint256 sfBalance = pusd.balanceOf(address(stabilityFund));
        if (sfBalance > 0) {
            vm.prank(address(stabilityFund));
            pusd.transfer(admin, sfBalance);
        }
        
        uint256 treasuryBalance = pusd.balanceOf(address(treasury));
        if (treasuryBalance > 0) {
            vm.prank(admin);
            treasury.withdrawPUSD(treasuryBalance);
        }
    }
}
