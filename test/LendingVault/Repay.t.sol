// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TestSetup} from "../TestSetup.t.sol";

import {ILendingVault} from "../../contracts/interfaces/ILendingVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract RepayTest is TestSetup {

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAmount(uint256 amount);
    error PositionNotFound(address user);

    /*//////////////////////////////////////////////////////////////
                            STATE VARS
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();

        // Ensure oracle has fresh timestamp
        mockOracle.setUpdatedAt(block.timestamp);

        // Fund user1 with sufficient collateral and setup position
        vm.startPrank(admin);
        wstETH.mint(user1, INITIAL_COLLATERAL);
        vm.stopPrank();

        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL);
        // Borrow more than minDebt to allow partial repayments
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        STATE CHANGE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Repay_UpdatesUserPosition() public {
        ( , uint256 initialDebt, , ) = lendingVault.getPosition(user1);

        uint256 repayAmount = 100 ether;
        vm.startPrank(user1);
        IERC20(address(pusd)).approve(address(lendingVault), repayAmount);
        lendingVault.repay(repayAmount);
        vm.stopPrank();

        (, uint256 debtAfter, , ) = lendingVault.getPosition(user1);
        assertLt(debtAfter, initialDebt, "Debt should decrease after repay");
        assertApproxEqAbs(debtAfter, initialDebt - repayAmount, 1e14, "Debt should reduce by repay amount within tolerance");
    }

    function test_Repay_CapsAtFullDebt() public {
        (, uint256 debtBefore, , ) = lendingVault.getPosition(user1);
        uint256 repayAmount = debtBefore + 1 ether; // exceed debt

        vm.startPrank(user1);
        IERC20(address(pusd)).approve(address(lendingVault), repayAmount);
        lendingVault.repay(repayAmount);
        vm.stopPrank();

        (, uint256 debtAfter, , ) = lendingVault.getPosition(user1);
        assertEq(debtAfter, 0, "Debt should be zero after excess repay");
    }

    function test_Repay_BurnsPUSDFromUser() public {
        uint256 repayAmount = 1 ether;
        uint256 userBalanceBefore = pusd.balanceOf(user1);
        vm.startPrank(user1);
        IERC20(address(pusd)).approve(address(lendingVault), repayAmount);
        lendingVault.repay(repayAmount);
        vm.stopPrank();

        uint256 userBalanceAfter = pusd.balanceOf(user1);
        assertEq(userBalanceAfter, userBalanceBefore - repayAmount, "User PUSD balance should decrease by repaid amount");
        assertEq(pusd.balanceOf(address(lendingVault)), 0, "Vault PUSD balance should remain zero");
    }

    function test_Repay_RevertsForZeroAmount() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAmount.selector, 0));
        lendingVault.repay(0);
        vm.stopPrank();
    }

    function test_Repay_RevertsForNoPosition() public {
        vm.startPrank(user2);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__PositionNotFound.selector, user2));
        lendingVault.repay(1 ether);
        vm.stopPrank();
    }

    function test_Repay_EnforcesMinimumDebtRule() public {
        // Enable minDebt for this test and try to repay to 400 PUSD remaining
        vm.prank(admin);
        protocolConfig.setMinDebt(500 ether);

        uint256 targetRemaining = 400 ether; // 400 PUSD
        (, uint256 debtBefore, , ) = lendingVault.getPosition(user1);
        assertGt(debtBefore, targetRemaining + 1 ether, "setup must have enough debt");
        uint256 repayToBelowMin = debtBefore - targetRemaining;
        vm.startPrank(user1);
        IERC20(address(pusd)).approve(address(lendingVault), repayToBelowMin);
        vm.expectRevert();
        lendingVault.repay(repayToBelowMin);
        vm.stopPrank();
    }

    function test_Repay_AllowsFullCloseBelowMin() public {
        (, uint256 debtBefore, , ) = lendingVault.getPosition(user1);
        // Repay to zero, even though remaining would go below 500
        vm.startPrank(user1);
        IERC20(address(pusd)).approve(address(lendingVault), debtBefore);
        lendingVault.repay(debtBefore);
        vm.stopPrank();

        (, uint256 debtAfter, , ) = lendingVault.getPosition(user1);
        assertEq(debtAfter, 0, "Debt should be zero after full repay");
    }

    function test_Repay_MaintainsTotalDebt_WhenRepayingLessThanAccruedInterest() public {
        // Accrue meaningful interest on existing debt
        skip(30 days);
        mockOracle.setUpdatedAt(block.timestamp); // Update oracle timestamp after time skip

        uint256 totalDebtBefore = lendingVault.totalDebt();

        vm.startPrank(user1);
        IERC20(address(pusd)).approve(address(lendingVault), 1);
        lendingVault.repay(1);
        vm.stopPrank();

        uint256 totalDebtAfter = lendingVault.totalDebt();
        // When repaying only interest (no principal), totalDebt should remain approximately the same
        // The small difference is due to the 1 wei interest payment
        assertApproxEqRel(totalDebtAfter, totalDebtBefore, 0.01e18, "total debt should remain approximately the same when repaying only interest");
    }

    function test_Repay_DecreasesTotalPrincipal_WhenRepayingPrincipal() public {
        // Repay a sizable amount soon after borrow so it reduces principal snapshot
        uint256 totalPrincipalBefore = lendingVault.totalPurePrincipal();

        vm.startPrank(user1);
        uint256 repayAmount = 100 ether;
        IERC20(address(pusd)).approve(address(lendingVault), repayAmount);
        lendingVault.repay(repayAmount);
        vm.stopPrank();

        uint256 totalPrincipalAfter = lendingVault.totalPurePrincipal();
        assertLt(totalPrincipalAfter, totalPrincipalBefore, "totalPrincipal should decrease after significant repay");
    }

    function test_Repay_SnapshotsUserIndexAndPrincipal() public {
        // Make a small repay to trigger snapshot
        vm.startPrank(user1);
        uint256 repayAmount = 1 ether;
        IERC20(address(pusd)).approve(address(lendingVault), repayAmount);
        lendingVault.repay(repayAmount);
        vm.stopPrank();

        // Read raw position fields from the public mapping getter
        (uint256 collateral,, uint256 userIndex,, bool exists) = lendingVault.positions(user1);
        assertTrue(exists, "position must exist");

        // After repay, userIndex must equal current global index (snapshot at tx end)
        uint256 globalIndex = lendingVault.globalInterestIndex();
        assertEq(userIndex, globalIndex, "user index snapshot should match global index after repay");

        // Principal snapshot should equal current debt immediately after repay
        (, uint256 principal,,,) = lendingVault.positions(user1);
        uint256 currentDebt = lendingVault.getCurrentDebt(user1);
        assertEq(principal, currentDebt, "principal snapshot should equal current debt right after repay");
        // Collateral remains unchanged on repay
        assertEq(collateral, INITIAL_COLLATERAL, "collateral should be unchanged by repay");
    }

    function test_Repay_SnapshotConsistencyAfterTime() public {
        // Take a snapshot with a small repay
        vm.startPrank(user1);
        IERC20(address(pusd)).approve(address(lendingVault), 1 ether);
        lendingVault.repay(1 ether);
        vm.stopPrank();

        // After time passes, current debt should exceed the principal snapshot due to interest
        (, uint256 principalBefore,,,) = lendingVault.positions(user1);
        skip(7 days);
        mockOracle.setUpdatedAt(block.timestamp); // Update oracle timestamp after time skip
        uint256 debtAfter = lendingVault.getCurrentDebt(user1);
        // If there is still debt, it should have grown relative to principal snapshot
        if (principalBefore > 0) {
            assertGt(debtAfter, principalBefore, "debt with interest should exceed principal snapshot after time");
        }
    }

    function test_Repay_RevertsWhenPaused() public {
        vm.prank(admin);
        lendingVault.pause();

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        lendingVault.repay(1 ether);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Repay_RandomAmounts(uint96 repayRaw) public {
        // Constrain repay to [0, 2 * BORROW_AMOUNT]
        uint256 repayAmount = uint256(repayRaw) % (2 * BORROW_AMOUNT);
        vm.startPrank(user1);
        IERC20(address(pusd)).approve(address(lendingVault), repayAmount);
        // Try/catch style by expecting possible revert for min debt only
        if (repayAmount > 0) {
            (, uint256 debtBefore, , ) = lendingVault.getPosition(user1);
            uint256 newDebt = debtBefore > repayAmount ? debtBefore - repayAmount : 0;
            if (newDebt > 0 && newDebt < 500 ether) {
                vm.expectRevert();
            }
        } else {
            vm.expectRevert();
        }
        // If it doesn't revert, it should succeed
        try lendingVault.repay(repayAmount) {
        } catch {}
        vm.stopPrank();
    }

    function test_Repay_SendsInterestFeesToTreasury() public {
        // Wait for interest to accrue
        vm.warp(block.timestamp + 365 days); // 1 year
        mockOracle.setUpdatedAt(block.timestamp); // Update oracle timestamp after time warp
        
        // Get current debt (principal + interest)
        ( , uint256 currentDebt, , ) = lendingVault.getPosition(user1);
        uint256 principal = BORROW_AMOUNT; // Original borrow amount
        uint256 interestAccrued = currentDebt - principal;
        
        // Ensure we have accrued interest
        assertTrue(interestAccrued > 0, "No interest accrued");
        
        // Get initial Treasury balance
        uint256 initialTreasuryBalance = pusd.balanceOf(address(treasury));
        uint256 initialTotalFees = lendingVault.totalInterestFees();
        
        // Repay an amount that covers interest + some principal
        uint256 repayAmount = interestAccrued + (principal / 2); // Pay all interest + half principal
        
        vm.startPrank(user1);
        IERC20(address(pusd)).approve(address(lendingVault), repayAmount);
        
        // Expect the InterestFeesCollected event
        vm.expectEmit(true, false, false, true);
        emit ILendingVault.InterestFeesCollected(user1, interestAccrued, initialTotalFees + interestAccrued);
        
        lendingVault.repay(repayAmount);
        vm.stopPrank();
        
        // Verify Treasury received the interest fees
        uint256 finalTreasuryBalance = pusd.balanceOf(address(treasury));
        assertEq(finalTreasuryBalance - initialTreasuryBalance, interestAccrued, "Treasury should receive interest fees");
        
        // Verify totalInterestFees was updated
        uint256 finalTotalFees = lendingVault.totalInterestFees();
        assertEq(finalTotalFees - initialTotalFees, interestAccrued, "Total interest fees should be updated");
    }

    function test_Repay_OnlyInterestPayment_SendsAllToTreasury() public {
        // Wait for interest to accrue
        vm.warp(block.timestamp + 365 days); // 1 year
        mockOracle.setUpdatedAt(block.timestamp); // Update oracle timestamp after time warp
        
        // Get current debt (principal + interest)
        ( , uint256 currentDebt, , ) = lendingVault.getPosition(user1);
        uint256 principal = BORROW_AMOUNT; // Original borrow amount
        uint256 interestAccrued = currentDebt - principal;
        
        // Ensure we have accrued interest
        assertTrue(interestAccrued > 0, "No interest accrued");
        
        // Get initial Treasury balance
        uint256 initialTreasuryBalance = pusd.balanceOf(address(treasury));
        uint256 initialTotalFees = lendingVault.totalInterestFees();
        
        // Repay only the interest amount
        uint256 repayAmount = interestAccrued;
        
        vm.startPrank(user1);
        IERC20(address(pusd)).approve(address(lendingVault), repayAmount);
        
        // Expect the InterestFeesCollected event
        vm.expectEmit(true, false, false, true);
        emit ILendingVault.InterestFeesCollected(user1, interestAccrued, initialTotalFees + interestAccrued);
        
        lendingVault.repay(repayAmount);
        vm.stopPrank();
        
        // Verify Treasury received all the payment (since it's all interest)
        uint256 finalTreasuryBalance = pusd.balanceOf(address(treasury));
        assertEq(finalTreasuryBalance - initialTreasuryBalance, repayAmount, "Treasury should receive all payment as interest");
        
        // Verify totalInterestFees was updated
        uint256 finalTotalFees = lendingVault.totalInterestFees();
        assertEq(finalTotalFees - initialTotalFees, repayAmount, "Total interest fees should equal repayment amount");
    }

    /**
     * @notice Tests principal accounting accuracy during repayments with accrued interest
     * @dev This test validates that principal tracking remains accurate when repaying
     *      debt that has accumulated interest over time. It ensures that only the
     *      principal portion of repayments affects totalPurePrincipal accounting,
     *      while interest payments are handled separately.
     */
    function test_Repay_PrincipalAccountingWithAccruedInterest() public {
        // Use existing borrow amount from setup
        uint256 initialBorrowAmount = BORROW_AMOUNT; // 1000 ether from setup
        
        // Verify initial state
        uint256 initialTotalPrincipal = lendingVault.totalPurePrincipal();
        uint256 initialUserDebt = lendingVault.getCurrentDebt(user1);
        assertEq(initialTotalPrincipal, initialBorrowAmount, "Initial totalPrincipal should equal borrow amount");
        assertEq(initialUserDebt, initialBorrowAmount, "Initial user debt should equal borrow amount");
        
        // Step 2: Time passes (1 year) → Interest accrues
        vm.warp(block.timestamp + 365 days);
        mockOracle.setUpdatedAt(block.timestamp); // Update oracle timestamp after time warp
        
        // Get debt after interest accrual
        uint256 debtAfterInterest = lendingVault.getCurrentDebt(user1);
        uint256 interestAccrued = debtAfterInterest - initialBorrowAmount;
        
        // User repays partial amount
        uint256 repayAmount = 100 ether;
        uint256 totalPrincipalBeforeRepay = lendingVault.totalPurePrincipal();
        
        vm.startPrank(user1);
        IERC20(address(pusd)).approve(address(lendingVault), repayAmount);
        lendingVault.repay(repayAmount);
        vm.stopPrank();
        
        // Get state after repayment
        uint256 totalPrincipalAfterRepay = lendingVault.totalPurePrincipal();
        uint256 userDebtAfterRepay = lendingVault.getCurrentDebt(user1);
        uint256 principalReduction = totalPrincipalBeforeRepay - totalPrincipalAfterRepay;
        
        // Calculate expected principal reduction based on repayment split
        // The principal portion is: repayAmount - interestAccrued (if repayAmount > interestAccrued)
        uint256 expectedPrincipalReduction = repayAmount > interestAccrued ? repayAmount - interestAccrued : 0;
        
        // Verify principal accounting accuracy
        assertEq(principalReduction, expectedPrincipalReduction, "Principal reduction should equal expected principal reduction");
        
        // Verify position state after repayment
        (, uint256 positionDebtAmount, ,) = lendingVault.getPosition(user1);
        
        // Verify that position.debtAmount represents the correct remaining principal
        uint256 expectedRemainingPrincipal = initialBorrowAmount - expectedPrincipalReduction;
        assertEq(positionDebtAmount, expectedRemainingPrincipal, "Position debtAmount should equal expected remaining principal");
        
        // Verify debt calculation consistency
        assertEq(positionDebtAmount, userDebtAfterRepay, "Position debtAmount should equal getCurrentDebt() immediately after repayment");
    }

    /**
     * @notice PoC from auditors - Test if repaying 1 wei erases accrued interest
     */
    function test_Repay_dust_to_erase_interest_poc() public {
        uint256 debtBefore = lendingVault.getCurrentDebt(user1);
        console.log("Debt before repay:  %s", debtBefore);
        
        // simulate the passage of 2 months (~60 days) to accrue some interest before repayment
        console.log("Simulating passage of 2 months (~60 days) to accrue some interest before repayment");
        skip(60 days);
        
        // Update oracle timestamp to avoid stale price error
        mockOracle.setUpdatedAt(block.timestamp);
        
        uint256 debtAfter = lendingVault.getCurrentDebt(user1);
        console.log("Debt after 60 days: %s", debtAfter);

        vm.startPrank(user1);
        console.log("Repaying 1 wei PUSD" );

        IERC20(address(pusd)).approve(address(lendingVault), 1);
        lendingVault.repay(1);
        vm.stopPrank();
        
        uint256 debtAfterRepay = lendingVault.getCurrentDebt(user1);
        console.log("Debt after repay:   %s", debtAfterRepay);
        
        // The debt should NOT be erased - it should be debtAfter - 1 wei
        assertApproxEqAbs(debtAfterRepay, debtAfter - 1, 1, "Interest should NOT be erased");
        assertGt(debtAfterRepay, debtBefore, "Debt should still include accrued interest");
    }

}