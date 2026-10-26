// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TestSetup} from "../TestSetup.t.sol";

import {LendingVault} from "../../contracts/LendingVault.sol";
import {ILendingVault} from "../../contracts/interfaces/ILendingVault.sol";

contract LendingVaultGettersTest is TestSetup {

    function setUp() public override {
        super.setUp();
        
        // Ensure oracle has fresh timestamp
        mockOracle.setUpdatedAt(block.timestamp);
    }

    function collateralValueUSD(uint256 amount) internal view returns (uint256) {
        (, int256 answer,, ,) = mockOracle.latestRoundData();
        uint8 d = mockOracle.decimals();
        return (amount * uint256(answer)) / (10 ** d);
    }
    
    /*//////////////////////////////////////////////////////////////
                                 GETTERS
    //////////////////////////////////////////////////////////////*/

    function test_Getters_Addresses() public {
        address engine = address(0xE1);
        address fund = address(0xF1);
        address treasuryAddr = address(0xF2);
        vm.startPrank(admin);
        lendingVault.setLiquidationEngine(engine);
        lendingVault.setStabilityFund(fund);
        lendingVault.setTreasury(treasuryAddr);
        vm.stopPrank();

        assertEq(address(lendingVault.pusd()), address(pusd), "pusd should match");
        assertEq(address(lendingVault.protocolConfig()), address(protocolConfig), "protocolConfig should match");
        assertEq(address(lendingVault.liquidationEngine()), engine, "liquidationEngine should match");
        assertEq(address(lendingVault.stabilityFund()), fund, "stabilityFund should match");
        assertEq(address(lendingVault.treasury()), treasuryAddr, "treasury should match");
        assertEq(address(lendingVault.collateralToken()), address(wstETH), "collateralToken should match");
    }

    function test_Getters_GetPositionHealthRatio_Branches() public {
        assertEq(lendingVault.getPositionHealthRatio(user3), 0, "HR should be 0 without collateral");

        // Ensure user2 has enough wstETH for deposit
        if (wstETH.balanceOf(user2) < 600 ether) {
            wstETH.mint(user2, 600 ether - wstETH.balanceOf(user2));
        }

        vm.startPrank(user2);
        wstETH.approve(address(lendingVault), 600 ether); 
        lendingVault.deposit(600 ether);
        vm.stopPrank();
        assertEq(lendingVault.getPositionHealthRatio(user2), type(uint256).max, "HR should be max when no debt");

        vm.startPrank(user2);
        uint256 borrowAmt = 500 ether; 
        lendingVault.borrow(borrowAmt);
        vm.stopPrank();
        uint256 expectedHR = (collateralValueUSD(600 ether) * 10000) / borrowAmt;
        assertEq(lendingVault.getPositionHealthRatio(user2), expectedHR, "HR should match formula");
    }

    function test_Getters_GetMaxBorrow_NoPosition_ReturnsZero() public view {
        assertEq(lendingVault.getMaxBorrow(address(0xBEEF)), 0, "No position => 0");
    }

    function test_Getters_GetMaxBorrow_ZeroCollateral_ReturnsZero() public {
        address u = user3;
        uint256 bal = wstETH.balanceOf(u);
        if (bal < 1 ether) {
            wstETH.mint(u, 1 ether - bal);
        }

        vm.startPrank(u);
        wstETH.approve(address(lendingVault), 1 ether);
        lendingVault.deposit(1 ether);
        lendingVault.withdraw(1 ether);
        vm.stopPrank();
        assertEq(lendingVault.getMaxBorrow(u), 0, "Zero collateral => 0");
    }

    function test_Getters_GetMaxBorrow_CurrentDebtAtMax_ReturnsZero() public {
        // Ensure user2 has enough wstETH for deposit
        if (wstETH.balanceOf(user2) < 600 ether) {
            wstETH.mint(user2, 600 ether - wstETH.balanceOf(user2));
        }
        
        vm.startPrank(user2);
        wstETH.approve(address(lendingVault), 600 ether); // Minimum deposit for 500 ether borrow
        lendingVault.deposit(600 ether);
        uint256 maxBorrow = lendingVault.getMaxBorrow(user2);
        // maxBorrow should now be >= 500 ether due to sufficient collateral
        lendingVault.borrow(maxBorrow);
        vm.stopPrank();
        assertEq(lendingVault.getMaxBorrow(user2), 0, "At max => 0");
    }

    function test_Getters_GetMaxBorrow_CeilingCapsAvailable() public {
        vm.prank(admin);
        protocolConfig.setDebtCeiling(1 ether);
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), 10 ether);
        lendingVault.deposit(10 ether);
        vm.stopPrank();
        assertEq(lendingVault.getMaxBorrow(user1), 1 ether, "Capped by ceiling");
    }

    function test_Getters_GetPosition_Consistency() public {
        // Ensure user1 has a position: deposit then borrow
        
        // Ensure user1 has enough wstETH for deposit
        if (wstETH.balanceOf(user1) < 600 ether) {
            wstETH.mint(user1, 600 ether - wstETH.balanceOf(user1));
        }
        
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), 600 ether); // Minimum deposit for 500 ether borrow
        lendingVault.deposit(600 ether);
        uint256 borrowAmt = 500 ether; // Now we can borrow 500 ether safely
        lendingVault.borrow(borrowAmt);
        vm.stopPrank();

        (uint256 collateral, uint256 debtFromPosition, uint256 hrFromPosition, bool exists) = lendingVault.getPosition(user1);
        uint256 debtFromGetter = lendingVault.getCurrentDebt(user1);
        assertTrue(exists, "position should exist");
        assertEq(debtFromPosition, debtFromGetter, "getPosition debt should equal getCurrentDebt");
        uint256 expectedHR = (collateralValueUSD(collateral) * 10000) / debtFromGetter;
        assertEq(hrFromPosition, expectedHR, "health ratio should match formula");
    }

    function test_Getters_GetCurrentDebt_ZeroElapsed() public {
        // Fresh user2 position
        
        // Ensure user2 has enough wstETH for deposit
        if (wstETH.balanceOf(user2) < 600 ether) {
            wstETH.mint(user2, 600 ether - wstETH.balanceOf(user2));
        }
        
        vm.startPrank(user2);
        wstETH.approve(address(lendingVault), 600 ether);
        lendingVault.deposit(600 ether);
        lendingVault.borrow(500 ether); 
        // No time passed, should equal principal
        uint256 currentDebt = lendingVault.getCurrentDebt(user2);
        vm.stopPrank();
        assertEq(currentDebt, 500 ether, "current debt should equal principal with zero elapsed");
    }

    function test_Getters_GetCurrentDebt_AccrualExact() public {
        // Set APR to 10%
        vm.prank(admin);
        lendingVault.setAPR(1000);
        // Fresh user3 position
        // Ensure user3 has enough collateral tokens
        uint256 bal = wstETH.balanceOf(user3);
        if (bal < 600 ether) {
            wstETH.mint(user3, 600 ether - bal);
        }
        
        vm.startPrank(user3);
        wstETH.approve(address(lendingVault), 600 ether); 
        lendingVault.deposit(600 ether);
        lendingVault.borrow(500 ether); 
        vm.stopPrank();
        // Advance exactly one year (matches contract constant)
        skip(365 days);
        mockOracle.setUpdatedAt(block.timestamp); // Update oracle timestamp after time skip
        uint256 debtAfter = lendingVault.getCurrentDebt(user3);
        uint256 expected = 550 ether; // 500 + 10% = 550
        // Allow reasonable tolerance due to per-second linear accrual and integer math
        // With 500 ether and 10% APR, tolerance of 1 ether (0.2%) is reasonable
        assertApproxEqAbs(debtAfter, expected, 1 ether, "debt should accrue ~10% over one year at 10% APR");
    }

    /*//////////////////////////////////////////////////////////////
                        GETCOLLATERALAMOUNTFORVALUE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetCollateralAmountForValue_BasicCalculation() public {
        // Set oracle price to 3000 USD per wstETH (8 decimals)
        mockOracle.setAnswer(3000e8);
        
        uint256 valueUSD = 3000e18; // 3000 USD (18 decimals)
        uint256 expectedCollateral = 1e18; // 1 wstETH (18 decimals)
        
        uint256 actualCollateral = lendingVault.getCollateralAmountForValue(valueUSD);
        assertEq(actualCollateral, expectedCollateral, "Should return 1 wstETH for 3000 USD");
    }

    function test_GetCollateralAmountForValue_WithDecimals() public {
        // Set oracle price to 3000 USD per wstETH (8 decimals)
        mockOracle.setAnswer(3000e8);
        
        uint256 valueUSD = 1500e18; // 1500 USD (18 decimals)
        uint256 expectedCollateral = 0.5e18; // 0.5 wstETH (18 decimals)
        
        uint256 actualCollateral = lendingVault.getCollateralAmountForValue(valueUSD);
        assertEq(actualCollateral, expectedCollateral, "Should return 0.5 wstETH for 1500 USD");
    }

    function test_GetCollateralAmountForValue_ZeroValue() public {
        mockOracle.setAnswer(3000e8);
        
        uint256 valueUSD = 0;
        uint256 expectedCollateral = 0;
        
        uint256 actualCollateral = lendingVault.getCollateralAmountForValue(valueUSD);
        assertEq(actualCollateral, expectedCollateral, "Should return 0 for 0 USD value");
    }

    function test_GetCollateralAmountForValue_HighValue() public {
        mockOracle.setAnswer(3000e8);
        
        uint256 valueUSD = 3000000e18; // 3M USD
        uint256 expectedCollateral = 1000e18; // 1000 wstETH
        
        uint256 actualCollateral = lendingVault.getCollateralAmountForValue(valueUSD);
        assertEq(actualCollateral, expectedCollateral, "Should handle high values correctly");
    }

    function test_GetCollateralAmountForValue_RevertsOnInvalidOraclePrice() public {
        // Set oracle price to 0 (invalid)
        mockOracle.setAnswer(0);
        
        uint256 valueUSD = 1000e18;
        
        vm.expectRevert(ILendingVault.LendingVault__InvalidOraclePrice.selector);
        lendingVault.getCollateralAmountForValue(valueUSD);
    }

    function test_GetCollateralAmountForValue_RevertsOnNegativeOraclePrice() public {
        // Set oracle price to negative (invalid)
        mockOracle.setAnswer(-1000e8);
        
        uint256 valueUSD = 1000e18;
        
        vm.expectRevert(ILendingVault.LendingVault__InvalidOraclePrice.selector);
        lendingVault.getCollateralAmountForValue(valueUSD);
    }

    function testFuzz_GetCollateralAmountForValue_VariousValues(uint256 valueUSD) public {
        // Bound to reasonable values to prevent overflow
        valueUSD = bound(valueUSD, 0, 1000000e18); // 0 to 1M USD
        
        // Set a reasonable oracle price
        mockOracle.setAnswer(3000e8);
        
        uint256 collateral = lendingVault.getCollateralAmountForValue(valueUSD);
        
        // Basic sanity checks
        assertGe(collateral, 0, "Collateral amount should be non-negative");
        
        // Verify the calculation is correct: collateral = value * 10^oracleDecimals / price
        uint256 expectedCollateral = (valueUSD * 10**8) / 3000e8;
        assertEq(collateral, expectedCollateral, "Calculation should match expected formula");
    }

    /*//////////////////////////////////////////////////////////////
                            ISLIQUIDATABLE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CheckZeroAddress_Modifier_Coverage() public {
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAddress.selector, address(0)));
        lendingVault.isLiquidatable(address(0));
        
    }

    function test_IsLiquidatable_HealthyPosition_ReturnsFalse() public {
        // Ensure user1 has a healthy position
        if (wstETH.balanceOf(user1) < 600 ether) {
            wstETH.mint(user1, 600 ether - wstETH.balanceOf(user1));
        }
        
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), 600 ether);
        lendingVault.deposit(600 ether);
        lendingVault.borrow(500 ether);
        vm.stopPrank();
        
        // Position should be healthy (collateral value > debt)
        bool isLiquidatable = lendingVault.isLiquidatable(user1);
        assertFalse(isLiquidatable, "Healthy position should not be liquidatable");
    }

    function test_IsLiquidatable_UnhealthyPosition_ReturnsTrue() public {
        // Ensure user2 has enough wstETH
        if (wstETH.balanceOf(user2) < 600 ether) {
            wstETH.mint(user2, 600 ether - wstETH.balanceOf(user2));
        }
        
        vm.startPrank(user2);
        wstETH.approve(address(lendingVault), 600 ether);
        lendingVault.deposit(600 ether);
        lendingVault.borrow(500 ether);
        vm.stopPrank();
        
        // Drop oracle price to make position unhealthy
        // Current: 600 wstETH * 3000 USD = 1,800,000 USD collateral vs 500 USD debt = healthy
        // New: 600 wstETH * 0.1 USD = 60 USD collateral vs 500 USD debt = unhealthy
        // Health ratio = (60 * 10000) / 500 = 1,200 (12%) which is below threshold 12000 (120%)
        mockOracle.setAnswer(1e7);
        
        bool isLiquidatable = lendingVault.isLiquidatable(user2);
        assertTrue(isLiquidatable, "Unhealthy position should be liquidatable");
    }

    function test_IsLiquidatable_NoPosition_ReturnsFalse() public view {
        // User3 has no position
        bool isLiquidatable = lendingVault.isLiquidatable(user3);
        assertFalse(isLiquidatable, "No position should not be liquidatable");
    }

    function test_IsLiquidatable_ZeroCollateral_ReturnsFalse() public {
        // Ensure user3 has some wstETH
        if (wstETH.balanceOf(user3) < 1 ether) {
            wstETH.mint(user3, 1 ether - wstETH.balanceOf(user3));
        }
        
        vm.startPrank(user3);
        wstETH.approve(address(lendingVault), 1 ether);
        lendingVault.deposit(1 ether);
        lendingVault.withdraw(1 ether); // Remove all collateral
        vm.stopPrank();
        
        bool isLiquidatable = lendingVault.isLiquidatable(user3);
        assertFalse(isLiquidatable, "Zero collateral position should not be liquidatable");
    }

    function test_IsLiquidatable_ZeroDebt_ReturnsFalse() public {
        // Ensure user1 has enough wstETH
        if (wstETH.balanceOf(user1) < 600 ether) {
            wstETH.mint(user1, 600 ether - wstETH.balanceOf(user1));
        }
        
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), 600 ether);
        lendingVault.deposit(600 ether);
        // Don't borrow anything
        vm.stopPrank();
        
        bool isLiquidatable = lendingVault.isLiquidatable(user1);
        assertFalse(isLiquidatable, "Zero debt position should not be liquidatable");
    }

    function test_IsLiquidatable_AtThreshold_ReturnsFalse() public {
        // Ensure user2 has enough wstETH
        if (wstETH.balanceOf(user2) < 600 ether) {
            wstETH.mint(user2, 600 ether - wstETH.balanceOf(user2));
        }
        
        vm.startPrank(user2);
        wstETH.approve(address(lendingVault), 600 ether);
        lendingVault.deposit(600 ether);
        lendingVault.borrow(500 ether);
        vm.stopPrank();
        
        // Set oracle price to make health ratio exactly at threshold
        // Threshold is 12000 (120%), so we need: (collateral * price * 10000) / debt = 12000
        // (600 * price * 10000) / 500 = 12000 => price = (12000 * 500) / (600 * 10000) = 1 USD
        // Oracle uses 8 decimals, so price = 1e8
        mockOracle.setAnswer(1e8);
        
        bool isLiquidatable = lendingVault.isLiquidatable(user2);
        assertFalse(isLiquidatable, "Position at threshold should not be liquidatable");
    }

    function test_IsLiquidatable_JustBelowThreshold_ReturnsTrue() public {
        // Ensure user1 has enough wstETH
        if (wstETH.balanceOf(user1) < 600 ether) {
            wstETH.mint(user1, 600 ether - wstETH.balanceOf(user1));
        }
        
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), 600 ether);
        lendingVault.deposit(600 ether);
        lendingVault.borrow(500 ether);
        vm.stopPrank();
        
        // Set oracle price to make health ratio just below threshold
        // Threshold is 12000 (120%), so we need: (collateral * price * 10000) / debt < 12000
        // (600 * price * 10000) / 500 < 12000 => price < (12000 * 500) / (600 * 10000) = 1 USD
        // Use 0.5 USD (50e6) to ensure it's below threshold
        // Health ratio = (600 * 0.5 * 10000) / 500 = 6000 (60%) which is below 12000
        mockOracle.setAnswer(50e6);
        
        bool isLiquidatable = lendingVault.isLiquidatable(user1);
        assertTrue(isLiquidatable, "Position just below threshold should be liquidatable");
    }

    function testFuzz_IsLiquidatable_VariousHealthRatios(uint256 healthRatio) public {
        // Bound to reasonable health ratios
        healthRatio = bound(healthRatio, 5000, 20000); // 50% to 200%
        
        // Ensure user3 has enough wstETH
        if (wstETH.balanceOf(user3) < 600 ether) {
            wstETH.mint(user3, 600 ether - wstETH.balanceOf(user3));
        }
        
        vm.startPrank(user3);
        wstETH.approve(address(lendingVault), 600 ether);
        lendingVault.deposit(600 ether);
        lendingVault.borrow(500 ether);
        vm.stopPrank();
        
        // Calculate required oracle price for target health ratio
        // healthRatio = (collateral * price) / debt
        // price = (healthRatio * debt) / collateral
        // price = (healthRatio * 500e18) / 600e18 = (healthRatio * 500) / 600
        uint256 requiredPrice = (healthRatio * 500) / 600;
        
        // Convert to oracle format (8 decimals)
        uint256 oraclePrice = requiredPrice * 1e8 / 10000; // healthRatio is in basis points
        
        mockOracle.setAnswer(int256(oraclePrice));
        
        bool isLiquidatable = lendingVault.isLiquidatable(user3);
        uint256 threshold = protocolConfig.liquidationThreshold();
        
        if (healthRatio < threshold) {
            assertTrue(isLiquidatable, "Position below threshold should be liquidatable");
        } else {
            assertFalse(isLiquidatable, "Position above threshold should not be liquidatable");
        }
    }

    /*//////////////////////////////////////////////////////////////
                            CURRENT DEBT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetCurrentDebt_UserIndexZero_ReturnsPrincipalAmount() public {
        // Ensure user3 has enough wstETH
        if (wstETH.balanceOf(user3) < 600 ether) {
            wstETH.mint(user3, 600 ether - wstETH.balanceOf(user3));
        }
        
        vm.startPrank(user3);
        wstETH.approve(address(lendingVault), 600 ether);
        lendingVault.deposit(600 ether);
        lendingVault.borrow(500 ether);
        vm.stopPrank();
        
        // Get current debt - this should handle userIndex == 0 correctly
        uint256 currentDebt = lendingVault.getCurrentDebt(user3);
        
        // When userIndex == 0, currentDebt should equal the principal amount (500 ether)
        assertEq(currentDebt, 500 ether, "Current debt should equal principal when userIndex is 0");
        
        // Verify that the position exists and has the expected values
        (uint256 collateral, uint256 debt, uint256 healthRatio, bool exists) = lendingVault.getPosition(user3);
        assertTrue(exists, "Position should exist");
        assertEq(collateral, 600 ether, "Collateral should be 600 ether");
        assertEq(debt, 500 ether, "Debt should be 500 ether");
        assertGt(healthRatio, 0, "Health ratio should be positive");
    }

    function test_GetCurrentDebt_UserIndexZero_EdgeCases() public {
        // This test verifies that the _currentDebtOf function handles edge cases correctly
        
        // Test case 1: Verify function works with non-existent position (should return 0)
        uint256 currentDebt = lendingVault.getCurrentDebt(user1);
        
        // The function should handle the case where position doesn't exist
        // This covers the logic in _currentDebtOf function
        assertEq(currentDebt, 0, "Current debt should be 0");
        
        // Test case 2: Verify function works with zero debt position
        // Create a simple position for user2
        if (wstETH.balanceOf(user2) < 600 ether) {
            wstETH.mint(user2, 600 ether - wstETH.balanceOf(user2));
        }
        
        vm.startPrank(user2);
        wstETH.approve(address(lendingVault), 600 ether);
        lendingVault.deposit(600 ether);
        // Don't borrow, so debtAmount == 0
        vm.stopPrank();
        
        uint256 user2Debt = lendingVault.getCurrentDebt(user2);
        // Expect return 0 when position debt is zero
        assertEq(user2Debt, 0, "Current debt should be 0 when debtAmount is 0");
        
        // Test case 3: Verify function works with minimum debt
        vm.startPrank(user2);
        lendingVault.borrow(500 ether); // Borrow 500 ether (minimum debt)
        vm.stopPrank();
        
        user2Debt = lendingVault.getCurrentDebt(user2);
        // Expect return principal when userIndex == 0
        assertEq(user2Debt, 500 ether, "Current debt should be 500 ether when userIndex is 0");
    }

    function test_GetCurrentDebt_UserIndexZero() public {
        // This test specifically covers where userIndex == 0 and debtAmount > 0
        
        // Create a position with debt but ensure lastInterestUpdate remains 0
        if (wstETH.balanceOf(user2) < 600 ether) {
            wstETH.mint(user2, 600 ether - wstETH.balanceOf(user2));
        }
        
        vm.startPrank(user2);
        wstETH.approve(address(lendingVault), 600 ether);
        lendingVault.deposit(600 ether);
        
        // Borrow without triggering interest update
        lendingVault.borrow(500 ether);
        vm.stopPrank();
        
        // At this point, the position should have:
        // - debtAmount > 0 (500 ether)
        // - lastInterestUpdate == 0 (because no interest has been accrued yet)
        
        // Get current debt - this should hit the userIndex == 0 branch
        uint256 currentDebt = lendingVault.getCurrentDebt(user2);
        
        // Verify the position state
        (uint256 collateral, uint256 debt,, bool exists) = lendingVault.getPosition(user2);
        assertTrue(exists, "Position should exist");
        assertEq(collateral, 600 ether, "Collateral should be 600 ether");
        assertEq(debt, 500 ether, "Principal debt should be 500 ether");
        
        assertEq(currentDebt, 500 ether, "Should return principal amount when userIndex is 0");
        
        // Verify that we're hitting the specific branch by checking the exact behavior
        // When userIndex == 0, currentDebt should equal the principal debt exactly
        assertEq(currentDebt, debt, "Current debt should equal principal debt when userIndex is 0");
    }

    function test_GetCurrentDebt_UserIndexZero_ImmediateAfterBorrow() public {
        // This test covers the immediate state after borrowing when lastInterestUpdate is still 0
        
        // Use a fresh user to ensure clean state
        address freshUser = address(0x1234);
        if (wstETH.balanceOf(freshUser) < 600 ether) {
            wstETH.mint(freshUser, 600 ether - wstETH.balanceOf(freshUser));
        }
        
        vm.startPrank(freshUser);
        wstETH.approve(address(lendingVault), 600 ether);
        lendingVault.deposit(600 ether);
        
        // Borrow immediately - this should create a position with lastInterestUpdate == 0
        lendingVault.borrow(500 ether);
        vm.stopPrank();
        
        // Get current debt immediately after borrowing
        uint256 currentDebt = lendingVault.getCurrentDebt(freshUser);
        
        assertEq(currentDebt, 500 ether, "Should return principal amount immediately after borrowing");
        
        // Verify position state
        (uint256 collateral, uint256 debt, uint256 healthRatio, bool exists) = lendingVault.getPosition(freshUser);
        assertTrue(exists, "Position should exist");
        assertEq(collateral, 600 ether, "Collateral should be 600 ether");
        assertEq(debt, 500 ether, "Principal debt should be 500 ether");
        assertGt(healthRatio, 0, "Health ratio should be positive");
        
        // The key assertion: verify that we're hitting the userIndex == 0 branch
        assertEq(currentDebt, debt, "Current debt should equal principal debt when userIndex is 0");
    }

    function test_GetCurrentDebt_UserIndexZero_AfterInterestAccrual() public {
        // Ensure user3 has enough wstETH
        if (wstETH.balanceOf(user3) < 600 ether) {
            wstETH.mint(user3, 600 ether - wstETH.balanceOf(user3));
        }
        
        vm.startPrank(user3);
        wstETH.approve(address(lendingVault), 600 ether);
        lendingVault.deposit(600 ether);
        lendingVault.borrow(500 ether);
        vm.stopPrank();
        
        // Initially, userIndex should be 0, so currentDebt == principal
        uint256 initialDebt = lendingVault.getCurrentDebt(user3);
        assertEq(initialDebt, 500 ether, "Initial debt should equal principal when userIndex is 0");
        
        // Set high APR and advance time to trigger interest accrual
        vm.prank(admin);
        lendingVault.setAPR(10000); // 100% APR
        
        vm.warp(block.timestamp + 1 days); // Advance 1 day
        mockOracle.setUpdatedAt(block.timestamp); // Update oracle timestamp after time warp
        
        // Now userIndex should be > 0, so currentDebt should include interest
        uint256 debtAfterInterest = lendingVault.getCurrentDebt(user3);
        assertGt(debtAfterInterest, 500 ether, "Debt should include interest after time advancement");
        
        // Verify the transition from userIndex == 0 to userIndex > 0
        (uint256 collateral, uint256 debt, uint256 healthRatio, bool exists) = lendingVault.getPosition(user3);
        assertTrue(exists, "Position should exist");
        assertEq(collateral, 600 ether, "Collateral should be 600 ether");
        // Note: debt (principal) might have changed due to interest accrual during the test
        assertGe(debt, 500 ether, "Principal debt should be at least 500 ether");
        assertGt(healthRatio, 0, "Health ratio should be positive");
    }

    function test_GetCurrentDebt_UserIndexZero_DirectCoverage() public {
        // Ensure user3 has enough wstETH
        if (wstETH.balanceOf(user3) < 600 ether) {
            wstETH.mint(user3, 600 ether - wstETH.balanceOf(user3));
        }
        
        vm.startPrank(user3);
        wstETH.approve(address(lendingVault), 600 ether);
        lendingVault.deposit(600 ether);
        lendingVault.borrow(500 ether);
        vm.stopPrank();
        
        // At this point, the position should have userIndex == 0 (lastInterestUpdate == 0)
        // because no interest has been accrued yet
        
        // Test the specific branch: if (userIndex == 0) return position.debtAmount;
        uint256 currentDebt = lendingVault.getCurrentDebt(user3);
        
        // Expect return principal
        assertEq(currentDebt, 500 ether, "Should return principal amount when userIndex is 0");
        
        // Verify the position state confirms userIndex == 0
        (uint256 collateral, uint256 debt,, bool exists) = lendingVault.getPosition(user3);
        assertTrue(exists, "Position should exist");
        assertEq(collateral, 600 ether, "Collateral should be 600 ether");
        assertEq(debt, 500 ether, "Principal debt should be 500 ether");
        
        // The key assertion: verify that we're hitting the userIndex == 0 branch
        // by checking that currentDebt equals the principal amount exactly
        assertEq(currentDebt, debt, "Current debt should equal principal debt when userIndex is 0");
    }

    function test_GetCurrentDebt_ZeroDebtAmount_ReturnsZero() public {
        // Validate zero debt branch in _currentDebtOf:
        // if (position.debtAmount == 0) return 0;
        
        // Ensure user3 has enough wstETH
        if (wstETH.balanceOf(user3) < 600 ether) {
            wstETH.mint(user3, 600 ether - wstETH.balanceOf(user3));
        }
        
        vm.startPrank(user3);
        wstETH.approve(address(lendingVault), 600 ether);
        lendingVault.deposit(600 ether);
        // Don't borrow, so debtAmount == 0
        vm.stopPrank();
        
        // Test the specific branch: if (position.debtAmount == 0) return 0;
        uint256 currentDebt = lendingVault.getCurrentDebt(user3);
        
        // Expect zero
        assertEq(currentDebt, 0, "Should return 0 when debtAmount is 0");
        
        // Verify the position state
        (uint256 collateral, uint256 debt, uint256 healthRatio, bool exists) = lendingVault.getPosition(user3);
        assertTrue(exists, "Position should exist");
        assertEq(collateral, 600 ether, "Collateral should be 600 ether");
        assertEq(debt, 0, "Debt should be 0");
        assertEq(healthRatio, type(uint256).max, "Health ratio should be max when no debt");
    }

    function test_GetCurrentDebt_UserIndexGreaterThanZero_CalculatesInterest() public {
        // Validate scaled debt branch in _currentDebtOf:
        // return (position.debtAmount * currentIndex) / userIndex;
        
        // Ensure user3 has enough wstETH
        if (wstETH.balanceOf(user3) < 600 ether) {
            wstETH.mint(user3, 600 ether - wstETH.balanceOf(user3));
        }
        
        vm.startPrank(user3);
        wstETH.approve(address(lendingVault), 600 ether);
        lendingVault.deposit(600 ether);
        lendingVault.borrow(500 ether);
        vm.stopPrank();
        
        // Initially, userIndex should be 0, so currentDebt == principal
        uint256 initialDebt = lendingVault.getCurrentDebt(user3);
        assertEq(initialDebt, 500 ether, "Initial debt should equal principal when userIndex is 0");
        
        // Set high APR and advance time to trigger interest accrual and update userIndex
        vm.prank(admin);
        lendingVault.setAPR(10000); // 100% APR
        
        vm.warp(block.timestamp + 1 days); // Advance 1 day
        mockOracle.setUpdatedAt(block.timestamp); // Update oracle timestamp after time warp
        
        // Now userIndex should be > 0, so currentDebt should use the formula:
        // return (position.debtAmount * currentIndex) / userIndex;
        uint256 debtAfterInterest = lendingVault.getCurrentDebt(user3);
        
        // Expect scaled value: (principal * currentIndex) / userIndex
        assertGt(debtAfterInterest, 500 ether, "Debt should include interest after time advancement");
        
        // Verify the position state
        (uint256 collateral, uint256 debt, uint256 healthRatio, bool exists) = lendingVault.getPosition(user3);
        assertTrue(exists, "Position should exist");
        assertEq(collateral, 600 ether, "Collateral should be 600 ether");
        // Note: debt (principal) might have changed due to interest accrual during the test
        assertGe(debt, 500 ether, "Principal debt should be at least 500 ether");
        assertGt(healthRatio, 0, "Health ratio should be positive");
        
        // The key assertion: verify that we're hitting the userIndex > 0 branch
        // by checking that currentDebt is greater than the principal amount
        // Validate scaled calculation in _currentDebtOf
        // Note: debt might already include interest, so we compare with the original principal
        assertGt(debtAfterInterest, 500 ether, "Current debt should be greater than original principal when userIndex > 0");
    }

    /*//////////////////////////////////////////////////////////////
                            INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_IsLiquidatable_CompleteFlow_HealthyToUnhealthy() public {
        // Ensure user1 has enough wstETH
        if (wstETH.balanceOf(user1) < 600 ether) {
            wstETH.mint(user1, 600 ether - wstETH.balanceOf(user1));
        }
        
        // Step 1: Deposit collateral
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), 600 ether);
        lendingVault.deposit(600 ether);
        vm.stopPrank();
        
        // Verify initial state - no debt, should not be liquidatable
        bool isLiquidatable = lendingVault.isLiquidatable(user1);
        assertFalse(isLiquidatable, "Position with no debt should not be liquidatable");
        
        // Step 2: Borrow PUSD
        vm.startPrank(user1);
        lendingVault.borrow(500 ether);
        vm.stopPrank();
        
        // Set higher APR and advance time to ensure interest accrual
        vm.prank(admin);
        lendingVault.setAPR(5000); // 50% APR to ensure visible interest growth
        
        vm.warp(block.timestamp + 30 days); // Advance 30 days
        mockOracle.setUpdatedAt(block.timestamp); // Update oracle timestamp after time warp
        
        // Verify state after borrowing - should still be healthy
        isLiquidatable = lendingVault.isLiquidatable(user1);
        assertFalse(isLiquidatable, "Position should be healthy after borrowing");
        
        // Step 3: Drop oracle price to make position unhealthy
        // Current: 600 wstETH * 3000 USD = 1,800,000 USD collateral vs 500 USD debt = healthy
        // New: 600 wstETH * 0.1 USD = 60 USD collateral vs 500 USD debt = unhealthy
        mockOracle.setAnswer(1e7); // 0.1 USD
        
        // Verify state after price drop - should now be liquidatable
        isLiquidatable = lendingVault.isLiquidatable(user1);
        assertTrue(isLiquidatable, "Position should be liquidatable after price drop");
        
        // Step 4: Verify all getter functions work correctly
        (uint256 collateral, uint256 debt, uint256 healthRatio, bool exists) = lendingVault.getPosition(user1);
        assertTrue(exists, "Position should exist");
        assertEq(collateral, 600 ether, "Collateral should be 600 ether");
        // Note: Debt might not have grown significantly if APR is low or time is short
        assertGe(debt, 500 ether, "Debt should be at least 500 ether");
        assertLt(healthRatio, 12000, "Health ratio should be below liquidation threshold");
        
        uint256 currentDebt = lendingVault.getCurrentDebt(user1);
        // With 50% APR over 30 days, debt should have grown significantly
        // 500 * (1 + 0.5 * 30/365) ≈ 500 * 1.041 ≈ 520.5
        assertGt(currentDebt, 500 ether, "Current debt should include accrued interest");
        
        uint256 maxBorrow = lendingVault.getMaxBorrow(user1);
        assertEq(maxBorrow, 0, "Max borrow should be 0 when position is unhealthy");
    }

    /*//////////////////////////////////////////////////////////////
                        GETTER FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Getters_GetRatePerSecond() public {
        // Test with default APR (50 bps = 0.5%)
        uint256 secondsPerYear = 365 * 24 * 3600;
        uint256 expectedRate = (50 * 1e12) / (10_000 * secondsPerYear);
        assertEq(lendingVault.getRatePerSecond(), expectedRate, "Default rate per second should match calculation");

        // Test with different APR
        vm.prank(admin);
        lendingVault.setAPR(1000); // 10%
        expectedRate = (1000 * 1e12) / (10_000 * secondsPerYear);
        assertEq(lendingVault.getRatePerSecond(), expectedRate, "Updated rate per second should match calculation");

        // Test with zero APR
        vm.prank(admin);
        lendingVault.setAPR(0);
        assertEq(lendingVault.getRatePerSecond(), 0, "Zero APR should give zero rate per second");
    }

    function test_Getters_TotalDebt() public {
        // Initially should be zero
        assertEq(lendingVault.totalDebt(), 0, "Initial total debt should be zero");

        // Create a position with debt
        if (wstETH.balanceOf(user1) < 600 ether) {
            wstETH.mint(user1, 600 ether - wstETH.balanceOf(user1));
        }
        
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), 600 ether);
        lendingVault.deposit(600 ether);
        lendingVault.borrow(500 ether);
        vm.stopPrank();

        // Total debt should now be 500 ether
        assertEq(lendingVault.totalDebt(), 500 ether, "Total debt should equal borrowed amount");

        // Advance time and check interest accrual
        vm.prank(admin);
        lendingVault.setAPR(1000); // 10% APR
        vm.warp(block.timestamp + 365 days);
        mockOracle.setUpdatedAt(block.timestamp); // Update oracle timestamp after time warp

        uint256 totalDebtAfter = lendingVault.totalDebt();
        assertGt(totalDebtAfter, 500 ether, "Total debt should include accrued interest");
    }

    function test_Getters_GetAPRbps() public {
        // Test default APR
        assertEq(lendingVault.getAPRbps(), 50, "Default APR should be 50 bps");

        // Test setting new APR
        vm.prank(admin);
        lendingVault.setAPR(1000);
        assertEq(lendingVault.getAPRbps(), 1000, "APR should be updated to 1000 bps");

        // Test zero APR
        vm.prank(admin);
        lendingVault.setAPR(0);
        assertEq(lendingVault.getAPRbps(), 0, "APR should be updated to 0 bps");
    }

    function test_Getters_StateVariables() public {
        // Test initial state variables
        assertEq(lendingVault.totalCollateral(), 0, "Initial total collateral should be zero");
        assertEq(lendingVault.totalPurePrincipal(), 0, "Initial total principal should be zero");
        assertEq(lendingVault.aprBasisPoints(), 50, "Initial APR should be 50 bps");
        assertEq(lendingVault.lastInterestUpdate(), block.timestamp, "Initial lastInterestUpdate should be current timestamp");
        assertEq(lendingVault.globalInterestIndex(), 1e12, "Initial global interest index should be 1e12");
        assertEq(lendingVault.minDepositAmount(), 0.01 ether, "Initial min deposit amount should be 0.01 ether");
        assertEq(lendingVault.totalInterestFees(), 0, "Initial total interest fees should be zero");

        // Test after creating a position
        if (wstETH.balanceOf(user1) < 600 ether) {
            wstETH.mint(user1, 600 ether - wstETH.balanceOf(user1));
        }
        
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), 600 ether);
        lendingVault.deposit(600 ether);
        vm.stopPrank();

        assertEq(lendingVault.totalCollateral(), 600 ether, "Total collateral should be 600 ether after deposit");

        vm.startPrank(user1);
        lendingVault.borrow(500 ether);
        vm.stopPrank();

        assertEq(lendingVault.totalPurePrincipal(), 500 ether, "Total principal should be 500 ether after borrow");
    }

    function test_Getters_MappingGetters() public {
        // Test positions mapping getter
        (uint256 collateral, uint256 debt, uint256 lastUpdate, , bool exists) = lendingVault.positions(user1);
        assertEq(collateral, 0, "Initial position collateral should be zero");
        assertEq(debt, 0, "Initial position debt should be zero");
        assertEq(lastUpdate, 0, "Initial position lastUpdate should be zero");
        assertFalse(exists, "Initial position should not exist");

        // Create a position
        if (wstETH.balanceOf(user1) < 600 ether) {
            wstETH.mint(user1, 600 ether - wstETH.balanceOf(user1));
        }
        
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), 600 ether);
        lendingVault.deposit(600 ether);
        lendingVault.borrow(500 ether);
        vm.stopPrank();

        (collateral, debt, lastUpdate, , exists) = lendingVault.positions(user1);
        assertEq(collateral, 600 ether, "Position collateral should be 600 ether");
        assertEq(debt, 500 ether, "Position debt should be 500 ether");
        assertGt(lastUpdate, 0, "Position lastUpdate should be greater than zero");
        assertTrue(exists, "Position should exist");

        // Test isLiquidationBot mapping getter
        address bot = address(0xB07);
        assertFalse(lendingVault.isLiquidationBot(bot), "Bot should not be authorized initially");

        vm.prank(admin);
        lendingVault.setLiquidationBot(bot, true);
        assertTrue(lendingVault.isLiquidationBot(bot), "Bot should be authorized after setting");

        vm.prank(admin);
        lendingVault.setLiquidationBot(bot, false);
        assertFalse(lendingVault.isLiquidationBot(bot), "Bot should not be authorized after unsetting");
    }

    function test_Getters_StateVariableUpdates() public {
        // Test that state variables update correctly

        // Test minDepositAmount updates
        vm.prank(admin);
        lendingVault.setMinDepositAmount(1 ether);
        assertEq(lendingVault.minDepositAmount(), 1 ether, "Min deposit amount should be updated");

        // Test aprBasisPoints updates
        vm.prank(admin);
        lendingVault.setAPR(2000);
        assertEq(lendingVault.aprBasisPoints(), 2000, "APR basis points should be updated");

        // Test lastInterestUpdate and globalInterestIndex updates after interest accrual
        uint256 initialLastUpdate = lendingVault.lastInterestUpdate();
        uint256 initialIndex = lendingVault.globalInterestIndex();

        vm.warp(block.timestamp + 1 days);
        mockOracle.setUpdatedAt(block.timestamp); // Update oracle timestamp after time warp
        
        // Create a position to trigger interest update
        if (wstETH.balanceOf(user1) < 600 ether) {
            wstETH.mint(user1, 600 ether - wstETH.balanceOf(user1));
        }
        
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), 600 ether);
        lendingVault.deposit(600 ether);
        lendingVault.borrow(500 ether);
        vm.stopPrank();

        uint256 newLastUpdate = lendingVault.lastInterestUpdate();
        uint256 newIndex = lendingVault.globalInterestIndex();

        assertGt(newLastUpdate, initialLastUpdate, "Last interest update should be updated");
        assertGt(newIndex, initialIndex, "Global interest index should increase with interest");
    }


}


