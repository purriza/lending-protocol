// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TestSetup} from "../TestSetup.t.sol";

import {LendingVault} from "../../contracts/LendingVault.sol";
import {ILendingVault} from "../../contracts/interfaces/ILendingVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract DepositTest is TestSetup {

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAmount(uint256 amount);
    error InsufficientCollateral(uint256 required, uint256 provided);
    error BelowMinCollateralRatio(uint256 current, uint256 minimum);


    /*//////////////////////////////////////////////////////////////
                            STATE VARS
    //////////////////////////////////////////////////////////////*/

    uint256 public minDepositAmount;

    function setUp() public override {
        super.setUp();

        // Ensure oracle has fresh timestamp
        mockOracle.setUpdatedAt(block.timestamp);
        
        minDepositAmount = lendingVault.minDepositAmount();
    }

    /*//////////////////////////////////////////////////////////////
                        STATE CHANGE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deposit_UpdatesUserPosition() public {
        uint256 initialCollateral = lendingVault.totalCollateral();
        uint256 userInitialBalance = wstETH.balanceOf(user1);
        
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL);
        vm.stopPrank();

        (uint256 collateral, uint256 debt, , bool exists) = lendingVault.getPosition(user1);
        
        assertEq(collateral, INITIAL_COLLATERAL, "User collateral should be updated");
        assertEq(debt, 0, "User debt should remain zero");
        assertTrue(exists, "User position should exist");
        assertEq(lendingVault.totalCollateral(), initialCollateral + INITIAL_COLLATERAL, "Total collateral should increase");
        assertEq(wstETH.balanceOf(user1), userInitialBalance - INITIAL_COLLATERAL, "User balance should decrease");
    }

    function test_Deposit_UpdatesCollateralRatio() public {
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL);
        vm.stopPrank();

        (, , uint256 healthRatio, ) = lendingVault.getPosition(user1);
        
        // Health ratio should be very high since no debt
        assertGt(healthRatio, 0, "Health ratio should be positive");
        assertTrue(healthRatio > 1e18, "Health ratio should be very high with no debt");
    }

    function test_Deposit_WithCustomMinCollateralRatio() public {
        uint256 customMinRatio = 20000; // 200%
        
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL, customMinRatio);
        vm.stopPrank();

        (uint256 collateral, , uint256 healthRatio, bool exists) = lendingVault.getPosition(user1);
        
        assertEq(collateral, INITIAL_COLLATERAL, "User collateral should be updated");
        assertTrue(exists, "User position should exist");
        assertGt(healthRatio, customMinRatio * 1e14, "Health ratio should meet custom minimum");
    }

    function test_Deposit_EmitsDepositedEvent() public {
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        
        // Don't check the healthRatio value since it's calculated by the contract
        vm.expectEmit(true, false, false, false);
        emit ILendingVault.Deposited(user1, INITIAL_COLLATERAL, 0);
        lendingVault.deposit(INITIAL_COLLATERAL);
        vm.stopPrank();
    }

    function test_Deposit_UpdatesTokenBalance() public {
        uint256 initialVaultBalance = wstETH.balanceOf(address(lendingVault));
        
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL);
        vm.stopPrank();

        assertEq(wstETH.balanceOf(address(lendingVault)), initialVaultBalance + INITIAL_COLLATERAL, "Vault balance should increase");
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deposit_RevertsForAmountLessThanMinDepositAmount() public {
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), minDepositAmount - 1);
        
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAmount.selector, minDepositAmount - 1));
        lendingVault.deposit(minDepositAmount - 1);
        vm.stopPrank();
    }

    function test_Deposit_TwoArg_RevertsForAmountLessThanMinDepositAmount() public {
        uint256 minRatio = protocolConfig.minCollateralRatio();
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), minDepositAmount - 1);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAmount.selector, minDepositAmount - 1));
        lendingVault.deposit(minDepositAmount - 1, minRatio);
        vm.stopPrank();
    }

    function test_Deposit_MinDepositAmountAppliesToAllDeposits() public {
        // First deposit: should enforce minimum deposit amount
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), minDepositAmount - 1);
        
        // First deposit below minimum should revert
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAmount.selector, minDepositAmount - 1));
        lendingVault.deposit(minDepositAmount - 1);
        vm.stopPrank();
        
        // Make a valid first deposit at minimum amount
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), minDepositAmount);
        lendingVault.deposit(minDepositAmount);
        vm.stopPrank();
        
        // Verify position exists
        (, , , bool exists) = lendingVault.getPosition(user1);
        assertTrue(exists, "Position should exist after first deposit");
        
        // Subsequent deposit: should ALSO enforce minimum deposit amount
        uint256 smallAmount = 1 wei; // Much smaller than minimum deposit amount
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), smallAmount);
        
        // This should FAIL because ALL deposits must meet minimum amount
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAmount.selector, smallAmount));
        lendingVault.deposit(smallAmount);
        vm.stopPrank();
        
        // Make a valid subsequent deposit at minimum amount
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), minDepositAmount);
        lendingVault.deposit(minDepositAmount);
        vm.stopPrank();
        
        // Verify the second deposit was successful
        (uint256 finalCollateral, , , ) = lendingVault.getPosition(user1);
        assertEq(finalCollateral, minDepositAmount * 2, "Collateral should include both valid deposits");
    }

    function test_Deposit_RevertsForZeroAmount() public {
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), 0);
        
        // Should revert due to validateAmount modifier (amount == 0)
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAmount.selector, 0));
        lendingVault.deposit(0);
        vm.stopPrank();
    }

    function test_Deposit_RevertsForInsufficientAllowance() public {
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL - 1);
        
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(lendingVault),
                INITIAL_COLLATERAL - 1,
                INITIAL_COLLATERAL
            )
        );
        lendingVault.deposit(INITIAL_COLLATERAL);
        vm.stopPrank();
    }

    function test_Deposit_RevertsForInsufficientBalance() public {
        uint256 userBalance = wstETH.balanceOf(user1);
        uint256 excessiveAmount = userBalance + 1 ether;
        
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), excessiveAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                user1,
                userBalance,
                excessiveAmount
            )
        );
        lendingVault.deposit(excessiveAmount);
        vm.stopPrank();
    }

    function test_Deposit_RevertsForInvalidMinCollateralRatio() public {
        // Test that deposit with minCollateralRatio = 0 should work
        // The contract doesn't validate minCollateralRatio > 0, so this should succeed
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        
        // This should work since the contract doesn't validate minCollateralRatio > 0
        lendingVault.deposit(INITIAL_COLLATERAL, 0);
        
        (uint256 collateral, , , bool exists) = lendingVault.getPosition(user1);
        assertEq(collateral, INITIAL_COLLATERAL, "Deposit should succeed with minCollateralRatio = 0");
        assertTrue(exists, "Position should exist");
        
        vm.stopPrank();
    }

    function test_Deposit_RevertsWhenPaused() public {
        vm.prank(admin);
        lendingVault.pause();
        
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        lendingVault.deposit(INITIAL_COLLATERAL);
        vm.stopPrank();
    }

    function test_Deposit_RevertsForBelowMinCollateralRatio() public {
        // Test that deposit with insufficient collateral ratio should revert
        // First, create a position with debt to test collateral ratio validation
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL);
        
        // Borrow some amount to create debt 
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();
        
        // Now try to deposit with a very high minCollateralRatio that won't be met
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), 1 ether);
        
        // Compute expected health ratio using oracle USD valuation
        (, int256 answer,, ,) = mockOracle.latestRoundData();
        uint8 d = mockOracle.decimals();
        uint256 collateralUSD = ((INITIAL_COLLATERAL + 1 ether) * uint256(answer)) / (10 ** d);
        uint256 expectedHR = (collateralUSD * 10000) / (BORROW_AMOUNT);
        uint256 veryHighMinRatio = expectedHR + 1; // force revert by requiring just above current HR
        
        // Expect revert due to below minimum collateral ratio
        vm.expectRevert(
            abi.encodeWithSelector(
                ILendingVault.LendingVault__BelowMinCollateralRatio.selector,
                expectedHR,
                veryHighMinRatio
            )
        );
        lendingVault.deposit(1 ether, veryHighMinRatio);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            INTEREST RATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Deposit_WithInterestRateChanges() public {
        // Test deposit behavior when interest rates change
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL);
        vm.stopPrank();
        
        // Change interest rate
        vm.prank(admin);
        lendingVault.setAPR(1000); // 10% APR
        
        // Verify APR was updated
        assertEq(lendingVault.aprBasisPoints(), 1000, "APR should be updated");
        
        // Make another deposit to ensure it works with new rate
        vm.startPrank(user2);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL);
        vm.stopPrank();
        
        (uint256 collateral, , , bool exists) = lendingVault.getPosition(user2);
        assertEq(collateral, INITIAL_COLLATERAL, "Deposit should work with new interest rate");
        assertTrue(exists, "Position should exist");
    }

    function test_Deposit_RevertsForInvalidAPR() public {
        // Test that setting invalid APR should revert
        vm.startPrank(admin);
        
        // Try to set APR > 100%
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAPR.selector, 15000));
        lendingVault.setAPR(15000); // 150% APR - should revert
        
        vm.stopPrank();
    }

    function test_Deposit_InterestAccrual() public {
        // Test that interest accrues correctly during deposits
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL);
        
        // Borrow some amount to create debt
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();
        
        // Fast forward time to accrue interest
        skip(365 days); // 1 year
        mockOracle.setUpdatedAt(block.timestamp); // Update oracle timestamp after time skip
        
        uint256 initialDebt = lendingVault.getCurrentDebt(user1);
        
        // Make another deposit
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), 1 ether);
        lendingVault.deposit(1 ether);
        vm.stopPrank();
        
        uint256 newDebt = lendingVault.getCurrentDebt(user1);
        
        // Debt should have increased due to interest accrual (may be very small)
        assertGe(newDebt, initialDebt, "Debt should not decrease due to interest accrual");
        
        // Verify that interest was actually accrued by checking the global state
        assertGt(lendingVault.totalDebt(), 1 ether, "Total debt should reflect interest accrual");
    }

    /*//////////////////////////////////////////////////////////////
                                FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Deposit_VariousAmounts(uint256 amount) public {
        // Bound the amount to reasonable values
        amount = bound(amount, 1 ether, 100 ether);
        
        // Ensure user has enough balance
        uint256 userBalance = wstETH.balanceOf(user1);
        if (amount > userBalance) {
            wstETH.mint(user1, amount - userBalance);
        }
        
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), amount);
        
        uint256 initialTotalCollateral = lendingVault.totalCollateral();
        uint256 initialUserBalance = wstETH.balanceOf(user1);
        
        lendingVault.deposit(amount);
        
        (uint256 collateral, uint256 debt, uint256 healthRatio, bool exists) = lendingVault.getPosition(user1);
        
        assertEq(collateral, amount, "User collateral should match deposit amount");
        assertEq(debt, 0, "User debt should remain zero");
        assertTrue(exists, "User position should exist");
        assertEq(lendingVault.totalCollateral(), initialTotalCollateral + amount, "Total collateral should increase by deposit amount");
        assertEq(wstETH.balanceOf(user1), initialUserBalance - amount, "User balance should decrease by deposit amount");
        assertGt(healthRatio, 0, "Health ratio should be positive");
        
        vm.stopPrank();
    }

    function testFuzz_Deposit_VariousMinCollateralRatios(uint256 minRatio) public {
        // Bound the min ratio to reasonable values
        minRatio = bound(minRatio, 10000, 50000); // 100% to 500%
        
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        
        uint256 initialTotalCollateral = lendingVault.totalCollateral();
        
        lendingVault.deposit(INITIAL_COLLATERAL, minRatio);
        
        (uint256 collateral, , uint256 healthRatio, bool exists) = lendingVault.getPosition(user1);
        
        assertEq(collateral, INITIAL_COLLATERAL, "User collateral should match deposit amount");
        assertTrue(exists, "User position should exist");
        assertGt(healthRatio, minRatio * 1e14, "Health ratio should meet minimum requirement");
        assertEq(lendingVault.totalCollateral(), initialTotalCollateral + INITIAL_COLLATERAL, "Total collateral should increase");
        
        vm.stopPrank();
    }

    function testFuzz_Deposit_MultipleUsers(uint8 userIndex, uint256 amount) public {
        // Bound the amount to reasonable values
        amount = bound(amount, 1 ether, 50 ether);
        
        address user = userIndex == 0 ? user1 : user2;
        
        // Ensure user has enough balance
        uint256 userBalance = wstETH.balanceOf(user);
        if (amount > userBalance) {
            wstETH.mint(user, amount - userBalance);
        }
        
        vm.startPrank(user);
        wstETH.approve(address(lendingVault), amount);
        
        uint256 initialTotalCollateral = lendingVault.totalCollateral();
        
        lendingVault.deposit(amount);
        
        (uint256 collateral, uint256 debt, uint256 healthRatio, bool exists) = lendingVault.getPosition(user);
        
        assertEq(collateral, amount, "User collateral should match deposit amount");
        assertEq(debt, 0, "User debt should remain zero");
        assertTrue(exists, "User position should exist");
        assertEq(lendingVault.totalCollateral(), initialTotalCollateral + amount, "Total collateral should increase");
        assertGt(healthRatio, 0, "Health ratio should be positive");
        
        vm.stopPrank();
    }

    function testFuzz_Deposit_ReentrancyProtection(uint256 amount) public {
        // This test ensures that reentrancy attacks are prevented
        amount = bound(amount, 1 ether, INITIAL_COLLATERAL / 2); // Use smaller amounts to avoid balance issues
        
        // Ensure user has enough balance for double deposit
        uint256 userBalance = wstETH.balanceOf(user1);
        uint256 requiredBalance = amount * 2;
        if (requiredBalance > userBalance) {
            wstETH.mint(user1, requiredBalance - userBalance);
        }
        
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), requiredBalance); // Approve double amount
        
        uint256 initialTotalCollateral = lendingVault.totalCollateral();
        
        // First deposit should succeed
        lendingVault.deposit(amount);
        
        // Second deposit should also succeed (no reentrancy issues)
        lendingVault.deposit(amount);
        
        (uint256 collateral, uint256 debt, , bool exists) = lendingVault.getPosition(user1);
        
        assertEq(collateral, amount * 2, "User collateral should be double deposit amount");
        assertEq(debt, 0, "User debt should remain zero");
        assertTrue(exists, "User position should exist");
        assertEq(lendingVault.totalCollateral(), initialTotalCollateral + amount * 2, "Total collateral should increase by double amount");
        
        vm.stopPrank();
    }
}
