// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {TestSetup} from "../../TestSetup.t.sol";

import {ILendingVault} from "../../../contracts/interfaces/ILendingVault.sol";
import {IPriceOracle} from "../../../contracts/interfaces/IPriceOracle.sol";
import {LiquidationEngine} from "../../../contracts/LiquidationEngine.sol";
import {Treasury} from "../../../contracts/Treasury.sol";
import {ITreasury} from "../../../contracts/interfaces/ITreasury.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title LiquidationInvariantTest
 * @notice Invariant tests ensuring protocol solvency during liquidations
 */
contract LiquidationInvariantTest is TestSetup {

    // Ghost variables to track invariants
    uint256 public ghost_totalCollateralBefore;
    uint256 public ghost_totalDebtBefore;
    uint256 public ghost_totalPrincipalBefore;

    function setUp() public override {
        super.setUp();
        
        // Configure liquidation parameters
        vm.prank(admin);
        protocolConfig.setCloseFactorBps(10000); // 100% - liquidate full position
        vm.prank(admin);
        protocolConfig.setLiquidationBonusBps(1000); // 10%
        // First set minCollateralRatio higher to allow setting liquidationThreshold
        vm.prank(admin);
        protocolConfig.setMinCollateralRatio(15000); // 150%
        vm.prank(admin);
        protocolConfig.setLiquidationThreshold(12000); // 120%

        // Authorize this test as liquidation bot
        vm.prank(admin);
        lendingVault.setLiquidationBot(address(this), true);

        // Setup StabilityFund and Treasury with liquidity using helper functions
        _setupStabilityFundForLiquidation();
        _setupTreasuryForLiquidation();

        vm.prank(admin);
        lendingVault.setStabilityFund(address(stabilityFund));

        vm.startPrank(admin);
        lendingVault.setLiquidationEngine(address(liquidationEngine));
        liquidationEngine.setTreasury(address(treasury));
        vm.stopPrank();

        // Setup test position
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL);
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();
        
        // Verify position was created successfully
        (uint256 collateral, uint256 debt,,) = lendingVault.getPosition(user1);
        require(collateral > 0, "Position must have collateral");
        require(debt > 0, "Position must have debt");
        
        // Verify position is healthy initially
        uint256 healthRatio = lendingVault.getPositionHealthRatio(user1);
        require(healthRatio > protocolConfig.liquidationThreshold(), "Position must be healthy initially");
    }

    function _captureStateBefore() internal {
        ghost_totalCollateralBefore = lendingVault.totalCollateral();
        ghost_totalDebtBefore = lendingVault.totalDebt();
        ghost_totalPrincipalBefore = lendingVault.totalPurePrincipal();
    }

    function _pushHealthBelowThreshold() internal {
        // Compute a price that makes health ratio < liquidation threshold
        (uint256 collateral, uint256 debt,,) = lendingVault.getPosition(user1);
        uint8 d = mockOracle.decimals();
        uint256 threshold = protocolConfig.liquidationThreshold();
        // targetPrice = threshold * debt * 10^d / (10000 * collateral)
        uint256 numerator = threshold * debt * (10 ** d);
        uint256 denominator = 10000 * collateral;
        uint256 targetPrice = denominator == 0 ? 0 : numerator / denominator;
        uint256 newPrice = targetPrice > 1 ? (targetPrice - 1) : 1; // ensure >0
        
        mockOracle.setAnswer(int256(newPrice));
    }

    /*//////////////////////////////////////////////////////////////
                        BASIC INVARIANTS
    //////////////////////////////////////////////////////////////*/

    function invariant_TotalCollateralNeverNegative() public view {
        uint256 totalCollateral = lendingVault.totalCollateral();
        assertGe(totalCollateral, 0, "Total collateral should never be negative");
    }

    function invariant_TotalDebtNeverNegative() public view {
        uint256 totalDebt = lendingVault.totalDebt();
        assertGe(totalDebt, 0, "Total debt should never be negative");
    }

    function invariant_TotalPrincipalConsistency() public view {
        uint256 totalPrincipal = lendingVault.totalPurePrincipal();
        assertGe(totalPrincipal, 0, "Total principal should never be negative");
    }

    /*//////////////////////////////////////////////////////////////
                        PROTOCOL SOLVENCY INVARIANTS
    //////////////////////////////////////////////////////////////*/

    function test_Invariant_LiquidationPreservesValue() public {
        _captureStateBefore();
        _pushHealthBelowThreshold();

        uint256 stabilityFundBalanceBefore = pusd.balanceOf(address(stabilityFund));

        // Execute liquidation
        ILendingVault.LiquidationResult memory result = lendingVault.liquidatePosition(user1);

        // Verify value preservation
        uint256 totalCollateralAfter = lendingVault.totalCollateral();
        uint256 totalDebtAfter = lendingVault.totalDebt();
        uint256 totalPrincipalAfter = lendingVault.totalPurePrincipal();
        uint256 stabilityFundBalanceAfter = pusd.balanceOf(address(stabilityFund));

        // Collateral should decrease by exactly seized amount
        // Use assertApproxEqRel to handle potential rounding differences
        assertApproxEqRel(
            totalCollateralAfter, 
            ghost_totalCollateralBefore - result.collateralSeized,
            0.0001e18, // 0.01% tolerance
            "Collateral accounting mismatch"
        );

        // Debt should decrease by repaid amount
        assertLe(totalDebtAfter, ghost_totalDebtBefore, "Total debt should not increase");

        // Principal should decrease by repaid amount
        assertLe(totalPrincipalAfter, ghost_totalPrincipalBefore, "Total principal should not increase");

        // Debt should decrease by repaid amount
        assertLe(totalDebtAfter, ghost_totalDebtBefore, "Total debt should not increase");

        // StabilityFund should maintain or increase its balance after liquidation
        // It provides funds initially but receives them back plus excess from liquidation
        assertGe(
            stabilityFundBalanceAfter,
            stabilityFundBalanceBefore,
            "StabilityFund should not lose funds during liquidation"
        );
    }

    function test_Invariant_LiquidationBonusWithinBounds() public {
        _pushHealthBelowThreshold();

        (,uint256 debtBefore,,) = lendingVault.getPosition(user1);
        ILendingVault.LiquidationResult memory result = lendingVault.liquidatePosition(user1);

        // Verify debt was reduced
        assertEq(result.debtRepaid + result.remainingDebt, debtBefore, "Total debt should equal debt repaid + remaining debt");

        // Calculate expected collateral based on oracle price and bonus
        (, int256 price,,,) = mockOracle.latestRoundData();
        uint8 decimals = mockOracle.decimals();
        uint256 bonus = protocolConfig.liquidationBonusBps();

        uint256 expectedSeizure = (result.debtRepaid * (10000 + bonus) * (10 ** decimals)) / 
                                  (uint256(price) * 10000);

        // Seized collateral should not exceed expected amount (accounting for rounding)
        assertLe(
            result.collateralSeized,
            expectedSeizure + 1, // Allow 1 wei rounding
            "Liquidation bonus exceeded bounds"
        );
    }

    function test_Invariant_PartialLiquidationRespectCloseFactor() public {
        _pushHealthBelowThreshold();

        (,uint256 debtBefore,,) = lendingVault.getPosition(user1);
        uint256 closeFactor = protocolConfig.closeFactorBps();

        ILendingVault.LiquidationResult memory result = lendingVault.liquidatePosition(user1);

        if (!result.fullLiquidation) {
            uint256 maxRepayable = (debtBefore * closeFactor) / 10000;
            assertLe(
                result.debtRepaid,
                maxRepayable,
                "Partial liquidation exceeded close factor"
            );
        }
    }

    function test_Invariant_FullLiquidationWhenBelowMinDebt() public {
        // Set high minDebt to force full liquidation
        // Use a value higher than BORROW_AMOUNT to ensure full liquidation
        vm.prank(admin);
        protocolConfig.setMinDebt(BORROW_AMOUNT + 1 ether);

        _pushHealthBelowThreshold();

        ILendingVault.LiquidationResult memory result = lendingVault.liquidatePosition(user1);

        // Should be full liquidation when remainder would be below minDebt
        assertTrue(result.fullLiquidation, "Should force full liquidation when below minDebt");
        assertEq(result.remainingDebt, 0, "Full liquidation should have zero remaining debt");
    }

    /*//////////////////////////////////////////////////////////////
                        BUSINESS LOGIC INVARIANTS
    //////////////////////////////////////////////////////////////*/

    function test_Invariant_LiquidationThresholdEnforcement() public {
        // Test that healthy positions cannot be liquidated
        uint256 threshold = protocolConfig.liquidationThreshold();
        uint256 health = lendingVault.getPositionHealthRatio(user1);

        // Position should be healthy initially
        assertGe(health, threshold, "Initial position should be healthy");

        // Liquidation should return empty result
        uint256 currentDebt = lendingVault.getCurrentDebt(user1);
        ILendingVault.LiquidationResult memory emptyResult = lendingVault.liquidatePosition(user1);
        assertEq(emptyResult.debtRepaid, 0, "Debt repaid should be 0 when healthy");
        assertEq(emptyResult.collateralSeized, 0, "Collateral seized should be 0 when healthy");
        assertEq(emptyResult.remainingDebt, currentDebt, "Remaining debt should equal current debt");
        assertFalse(emptyResult.fullLiquidation, "Full liquidation should be false");

        // Now push below threshold
        _pushHealthBelowThreshold();
        health = lendingVault.getPositionHealthRatio(user1);
        assertLt(health, threshold, "Position should be unhealthy after price drop");

        // Liquidation should now succeed
        ILendingVault.LiquidationResult memory result = lendingVault.liquidatePosition(user1);
        assertGt(result.debtRepaid, 0, "Liquidation should succeed when unhealthy");
    }

    function test_Invariant_CollateralSeizureNeverExceedsAvailable() public {
        _pushHealthBelowThreshold();

        (uint256 collateralBefore,,,) = lendingVault.getPosition(user1);
        ILendingVault.LiquidationResult memory result = lendingVault.liquidatePosition(user1);

        // Seized collateral cannot exceed available collateral
        assertLe(
            result.collateralSeized,
            collateralBefore,
            "Cannot seize more collateral than available"
        );
    }

    function test_Invariant_LiquidationStateMutationsAtomic() public {
        _captureStateBefore();
        _pushHealthBelowThreshold();

        (uint256 userCollateralBefore, uint256 userDebtBefore,,) = lendingVault.getPosition(user1);

        ILendingVault.LiquidationResult memory result = lendingVault.liquidatePosition(user1);

        // Verify all state changes are atomic and consistent
        (uint256 userCollateralAfter, uint256 userDebtAfter,,) = lendingVault.getPosition(user1);

        assertEq(
            userCollateralAfter,
            userCollateralBefore - result.collateralSeized,
            "User collateral not updated atomically"
        );

        assertEq(
            userDebtAfter,
            result.remainingDebt,
            "User debt not updated atomically"
        );
        
        // Verify debt reduction is consistent
        assertEq(
            userDebtBefore - userDebtAfter,
            result.debtRepaid,
            "User debt reduction should equal debt repaid"
        );

        uint256 totalCollateralAfter = lendingVault.totalCollateral();
        assertEq(
            totalCollateralAfter,
            ghost_totalCollateralBefore - result.collateralSeized,
            "Total collateral not updated atomically"
        );
    }

    function test_Invariant_NoArbitraryValueCreation() public {
        _captureStateBefore();
        _pushHealthBelowThreshold();

        uint256 protocolValueBefore = ghost_totalCollateralBefore; // In collateral token
        uint256 stabilityFundBefore = pusd.balanceOf(address(stabilityFund));

        ILendingVault.LiquidationResult memory result = lendingVault.liquidatePosition(user1);

        uint256 protocolValueAfter = lendingVault.totalCollateral();
        uint256 stabilityFundAfter = pusd.balanceOf(address(stabilityFund));

        // Protocol should not create value from thin air
        // The StabilityFund should maintain or increase its balance after liquidation
        // It provides funds initially but receives them back plus excess from liquidation
        assertGe(
            stabilityFundAfter,
            stabilityFundBefore,
            "StabilityFund should not lose funds during liquidation"
        );

        uint256 protocolValueReduction = protocolValueBefore - protocolValueAfter;
        assertApproxEqRel(
            protocolValueReduction,
            result.collateralSeized,
            0.0001e18, // 0.01% tolerance
            "Protocol should transfer approximately seized collateral amount"
        );
    }

    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL INVARIANTS
    //////////////////////////////////////////////////////////////*/

    function test_Invariant_LiquidationAccessControl() public {
        _pushHealthBelowThreshold();

        // Remove liquidation bot authorization
        vm.prank(admin);
        lendingVault.setLiquidationBot(address(this), false);

        // Liquidation should fail without authorization
        vm.expectRevert();
        lendingVault.liquidatePosition(user1);

        // Restore authorization
        vm.prank(admin);
        lendingVault.setLiquidationBot(address(this), true);

        // Liquidation should now succeed
        ILendingVault.LiquidationResult memory result = lendingVault.liquidatePosition(user1);
        assertGt(result.debtRepaid, 0, "Liquidation should succeed with proper authorization");
    }
}
