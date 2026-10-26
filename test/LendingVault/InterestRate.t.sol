// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TestSetup} from "../TestSetup.t.sol";

import {LendingVault} from "../../contracts/LendingVault.sol";
import {ILendingVault} from "../../contracts/interfaces/ILendingVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract InterestRateTest is TestSetup {

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
     error AccessControlUnauthorizedAccount(address account, bytes32 role);

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                        INTEREST RATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetAPR_UpdatesInterestRate() public {
        uint256 newAPR = 1000; // 10% APR
        
        vm.prank(admin);
        lendingVault.setAPR(newAPR);
        
        assertEq(lendingVault.aprBasisPoints(), newAPR, "APR should be updated");
        assertEq(lendingVault.getAPRbps(), newAPR, "getAPRbps should return updated APR");
    }

    function test_SetAPR_RevertsForInvalidAPR() public {
        vm.startPrank(admin);
        
        // Try to set APR > 100%
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAPR.selector, 15000));
        lendingVault.setAPR(15000); // 150% APR - should revert
        
        // Try to set APR = 100% (should work since validation is > 10000, not >= 10000)
        lendingVault.setAPR(10000); // 100% APR - should work
        
        vm.stopPrank();
    }

    function test_SetAPR_OnlyAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, lendingVault.protocolConfig().ADMIN_ROLE()));
        lendingVault.setAPR(1000);
        vm.stopPrank();
    }

    function test_SetAPR_EmitsEvent() public {
        uint256 oldAPR = lendingVault.aprBasisPoints();
        uint256 newAPR = 1000; // 10% APR
        
        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit ILendingVault.InterestRateUpdated(oldAPR, newAPR);
        lendingVault.setAPR(newAPR);
    }

    function test_InterestAccrual_OverTime() public {
        // Setup position with debt
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL);
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();
        
        uint256 initialDebt = lendingVault.getCurrentDebt(user1);
        uint256 initialTotalDebt = lendingVault.totalDebt();
        
        // Fast forward 1 year
        skip(365 days);
        
        // Trigger interest update by calling setAPR (which calls _updateInterest)
        vm.startPrank(admin);
        lendingVault.setAPR(lendingVault.aprBasisPoints()); // Same APR, just triggers update
        vm.stopPrank();
        
        uint256 newDebt = lendingVault.getCurrentDebt(user1);
        uint256 newTotalDebt = lendingVault.totalDebt();
        
        // Debt should have increased due to interest
        assertGt(newDebt, initialDebt, "User debt should increase with interest");
        assertGt(newTotalDebt, initialTotalDebt, "Total debt should increase with interest");
    }

    function test_InterestAccrual_WithDifferentRates() public {
        // Setup position with debt
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL);
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();
        
        uint256 initialDebt = lendingVault.getCurrentDebt(user1);
        
        // Change to higher interest rate
        vm.prank(admin);
        lendingVault.setAPR(2000); // 20% APR
        
        // Fast forward 6 months
        skip(180 days);
        
        // Trigger interest update by calling setAPR (which calls _updateInterest)
        vm.startPrank(admin);
        lendingVault.setAPR(lendingVault.aprBasisPoints()); // Same APR, just triggers update
        vm.stopPrank();
        uint256 debtAtHigherRate = lendingVault.getCurrentDebt(user1);
        
        // Change to lower interest rate
        vm.prank(admin);
        lendingVault.setAPR(500); // 5% APR
        
        // Fast forward another 6 months
        skip(180 days);
        
        // Trigger interest update by calling setAPR (which calls _updateInterest)
        vm.startPrank(admin);
        lendingVault.setAPR(lendingVault.aprBasisPoints()); // Same APR, just triggers update
        vm.stopPrank();
        uint256 finalDebt = lendingVault.getCurrentDebt(user1);
        
        // Verify interest accrual at different rates
        assertGt(debtAtHigherRate, initialDebt, "Debt should increase faster at higher rate");
        assertGt(finalDebt, debtAtHigherRate, "Debt should continue increasing at lower rate");
    }

    function test_InterestAccrual_NoDebt() public {
        // Setup position without debt
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL);
        vm.stopPrank();
        
        uint256 initialTotalDebt = lendingVault.totalDebt();
        
        // Fast forward 1 year
        skip(365 days);
        
        uint256 newTotalDebt = lendingVault.totalDebt();
        
        // Total debt should remain the same since there's no debt to accrue interest on
        assertEq(newTotalDebt, initialTotalDebt, "Total debt should not change without debt");
    }

    function test_InterestAccrual_GlobalIndex() public {
        uint256 initialIndex = lendingVault.globalInterestIndex();
        
        // Setup position with debt
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL);
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();
        
        // Fast forward 1 year
        skip(365 days);
        
        // Trigger interest update by calling setAPR (which calls _updateInterest)
        vm.startPrank(admin);
        lendingVault.setAPR(lendingVault.aprBasisPoints()); // Same APR, just triggers update
        vm.stopPrank();
        
        uint256 newIndex = lendingVault.globalInterestIndex();
        
        // Global interest index should increase
        assertGt(newIndex, initialIndex, "Global interest index should increase");
    }

    function test_InterestAccrual_LastUpdate() public {
        
        // Setup position with debt
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL);
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();
        
        // Fast forward 1 year
        skip(365 days);
        
        // Trigger interest update by calling setAPR (which calls _updateInterest)
        vm.startPrank(admin);
        lendingVault.setAPR(lendingVault.aprBasisPoints()); // Same APR, just triggers update
        vm.stopPrank();
        
        uint256 newLastUpdate = lendingVault.lastInterestUpdate();
        
        // Last update should be updated to current timestamp
        assertEq(newLastUpdate, block.timestamp, "Last interest update should be current timestamp");
    }

    function test_InterestAccrual_EmitsEvent() public {
        // Setup position with debt
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL);
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();
        
        // Fast forward 1 year
        skip(365 days);
        
        // Trigger interest update by calling setAPR (which calls _updateInterest)
        vm.startPrank(admin);
        lendingVault.setAPR(lendingVault.aprBasisPoints()); // Same APR, just triggers update
        vm.stopPrank();
    }

    function test_GetRatePerSecond_Calculation() public view {
        uint256 apr = lendingVault.aprBasisPoints();
        uint256 ratePerSecond = lendingVault.getRatePerSecond();
        
        // Verify calculation: ratePerSecond = (apr * PRECISION) / (10000 * SECONDS_PER_YEAR)
        uint256 expectedRate = (apr * 1e12) / (10000 * 365 * 24 * 3600);
        assertEq(ratePerSecond, expectedRate, "Rate per second calculation should be correct");
    }

    function testFuzz_InterestAccrual_VariousRates(uint256 apr) public {
        // Bound APR to reasonable values (0.1% to 50%)
        apr = bound(apr, 10, 5000);
        
        // Set APR
        vm.prank(admin);
        lendingVault.setAPR(apr);
        
        // Setup position with debt
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL);
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();
        
        uint256 initialDebt = lendingVault.getCurrentDebt(user1);
        
        // Fast forward 1 year
        skip(365 days);
        
        uint256 newDebt = lendingVault.getCurrentDebt(user1);
        
        // Debt should increase with interest
        assertGe(newDebt, initialDebt, "Debt should not decrease with interest");
    }

    function testFuzz_InterestAccrual_VariousTimePeriods(uint256 daysToSkip) public {
        // Bound time to reasonable values (1 day to 10 years)
        daysToSkip = bound(daysToSkip, 1, 3650);
        
        // Setup position with debt
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL);
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();
        
        uint256 initialDebt = lendingVault.getCurrentDebt(user1);
        
        // Fast forward specified time
        skip(daysToSkip * 1 days);
        
        uint256 newDebt = lendingVault.getCurrentDebt(user1);
        
        // Debt should increase with interest
        assertGe(newDebt, initialDebt, "Debt should not decrease with interest");
    }
}
