// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {IStabilityFund} from "../../contracts/interfaces/IStabilityFund.sol";
import {StabilityFund} from "../../contracts/StabilityFund.sol";
import {LendingVault} from "../../contracts/LendingVault.sol";

contract SendLiquidationFundsTest is TestSetup {

    uint256 public constant AMOUNT_TO_SEND = 1_000 ether;
    uint256 public constant MORE_THAN_BALANCE = AMOUNT_TO_SEND + 100 ether;
    uint256 public constant PARTIAL_AMOUNT = 500 ether;

    function setUp() public override {
        super.setUp();

        // Give StabilityFund some PUSD to send.
        _mintPUSD(user1, INITIAL_PUSD_AMOUNT);

        vm.startPrank(user1);
        pusd.approve(address(stabilityFund), AMOUNT_TO_SEND);
        stabilityFund.depositPUSD(AMOUNT_TO_SEND);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    function test_SendLiquidationFunds_Success() public {
        uint256 initialLendingVaultBalance = pusd.balanceOf(address(lendingVault));
        uint256 initialStabilityFundBalance = pusd.balanceOf(address(stabilityFund));

        assertEq(initialLendingVaultBalance, 0);
        assertEq(initialStabilityFundBalance, AMOUNT_TO_SEND);

        assertEq(stabilityFund.totalPusdLocked(), AMOUNT_TO_SEND);

        vm.prank(address(lendingVault));
        uint256 sentAmount = stabilityFund.sendLiquidationFunds(AMOUNT_TO_SEND);

        assertEq(sentAmount, AMOUNT_TO_SEND);
        assertEq(pusd.balanceOf(address(lendingVault)), initialLendingVaultBalance + AMOUNT_TO_SEND);
        assertEq(pusd.balanceOf(address(stabilityFund)), initialStabilityFundBalance - AMOUNT_TO_SEND);
        assertEq(stabilityFund.totalPusdLocked(), AMOUNT_TO_SEND);
    }

    function test_SendLiquidationFunds_Success_PartialSend() public {
        uint256 initialLendingVaultBalance = pusd.balanceOf(address(lendingVault));
        uint256 initialStabilityFundBalance = pusd.balanceOf(address(stabilityFund));

        assertEq(initialLendingVaultBalance, 0);
        assertEq(initialStabilityFundBalance, AMOUNT_TO_SEND);

        assertEq(stabilityFund.totalPusdLocked(), AMOUNT_TO_SEND);

        vm.prank(address(lendingVault));
        uint256 sentAmount = stabilityFund.sendLiquidationFunds(PARTIAL_AMOUNT);

        assertEq(sentAmount, PARTIAL_AMOUNT);
        assertEq(pusd.balanceOf(address(lendingVault)), initialLendingVaultBalance + PARTIAL_AMOUNT);
        assertEq(pusd.balanceOf(address(stabilityFund)), initialStabilityFundBalance - PARTIAL_AMOUNT);
        assertEq(stabilityFund.totalPusdLocked(), AMOUNT_TO_SEND);
    }

    function test_SendLiquidationFunds_Success_MoreThanBalance() public {
        uint256 initialLendingVaultBalance = pusd.balanceOf(address(lendingVault));
        uint256 initialStabilityFundBalance = pusd.balanceOf(address(stabilityFund));

        assertEq(initialLendingVaultBalance, 0);
        assertEq(initialStabilityFundBalance, AMOUNT_TO_SEND);

        assertEq(stabilityFund.totalPusdLocked(), AMOUNT_TO_SEND);

        vm.prank(address(lendingVault));
        uint256 sentAmount = stabilityFund.sendLiquidationFunds(MORE_THAN_BALANCE);

        assertEq(sentAmount, AMOUNT_TO_SEND);
        assertEq(pusd.balanceOf(address(lendingVault)), initialLendingVaultBalance + AMOUNT_TO_SEND);
        assertEq(pusd.balanceOf(address(stabilityFund)), initialStabilityFundBalance - AMOUNT_TO_SEND);
        assertEq(stabilityFund.totalPusdLocked(), AMOUNT_TO_SEND);
    }

    function test_SendLiquidationFunds_Success_ZeroBalance() public {
        // First drain the StabilityFund by sending all available funds
        vm.prank(address(lendingVault));
        stabilityFund.sendLiquidationFunds(AMOUNT_TO_SEND);

        // Verify StabilityFund has zero balance
        assertEq(pusd.balanceOf(address(stabilityFund)), 0);
        assertEq(stabilityFund.totalPusdLocked(), AMOUNT_TO_SEND);

        uint256 initialLendingVaultBalance = pusd.balanceOf(address(lendingVault));
        uint256 requestedAmount = 100 ether;

        // Try to send funds when balance is zero
        vm.prank(address(lendingVault));
        uint256 sentAmount = stabilityFund.sendLiquidationFunds(requestedAmount);

        // Should return 0 and not transfer anything
        assertEq(sentAmount, 0);
        assertEq(pusd.balanceOf(address(lendingVault)), initialLendingVaultBalance);
        assertEq(pusd.balanceOf(address(stabilityFund)), 0);
        assertEq(stabilityFund.totalPusdLocked(), AMOUNT_TO_SEND);
    }

    function test_SendLiquidationFunds_ExplicitZeroTransferCoverage() public {
        // This test creates a scenario where the PUSD balance is manually drained
        // but totalPusdLocked is artificially manipulated to test edge case coverage
        
        // First confirm we have PUSD in StabilityFund from setUp
        assertEq(pusd.balanceOf(address(stabilityFund)), AMOUNT_TO_SEND);
        assertEq(stabilityFund.totalPusdLocked(), AMOUNT_TO_SEND);
        
        // Manually transfer the PUSD out of StabilityFund to create imbalance
        // This simulates a scenario where balance is 0 but totalPusdLocked is non-zero
        vm.prank(address(stabilityFund));
        pusd.transfer(user1, AMOUNT_TO_SEND);
        
        // Verify the imbalanced state: zero PUSD balance but non-zero totalPusdLocked
        assertEq(pusd.balanceOf(address(stabilityFund)), 0);
        assertEq(stabilityFund.totalPusdLocked(), AMOUNT_TO_SEND);
        
        uint256 initialLendingVaultBalance = pusd.balanceOf(address(lendingVault));
        
        // This call will result in transferAmount = 0 since balance is 0
        // but will still execute the subtraction and transfer operations
        vm.prank(address(lendingVault));
        uint256 sentAmount = stabilityFund.sendLiquidationFunds(100 ether);
        
        // Verify the zero transfer behavior
        assertEq(sentAmount, 0);
        assertEq(pusd.balanceOf(address(lendingVault)), initialLendingVaultBalance);
        assertEq(pusd.balanceOf(address(stabilityFund)), 0);
        // totalPusdLocked should remain the same since 0 was subtracted
        assertEq(stabilityFund.totalPusdLocked(), AMOUNT_TO_SEND);
    }

    /*//////////////////////////////////////////////////////////////
                            EVENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SendLiquidationFunds_EmitsCorrectEventWhenAmountLessThanBalance() public {

        vm.expectEmit(true, false, false, false);
        emit IStabilityFund.LiquidationFundsSent(address(lendingVault), PARTIAL_AMOUNT);

        vm.prank(address(lendingVault));
        stabilityFund.sendLiquidationFunds(PARTIAL_AMOUNT);
    }

    function test_SendLiquidationFunds_EmitsCorrectEventWhenAmountGreaterThanBalance() public {
        vm.expectEmit(true, false, false, false);
        emit IStabilityFund.LiquidationFundsSent(address(lendingVault), AMOUNT_TO_SEND);

        vm.prank(address(lendingVault));
        stabilityFund.sendLiquidationFunds(MORE_THAN_BALANCE);
    }

    function test_SendLiquidationFunds_EmitsCorrectEventWhenZeroBalance() public {
        // First drain the StabilityFund
        vm.prank(address(lendingVault));
        stabilityFund.sendLiquidationFunds(AMOUNT_TO_SEND);

        // Expect event with 0 amount when balance is zero
        vm.expectEmit(true, false, false, false);
        emit IStabilityFund.LiquidationFundsSent(address(lendingVault), 0);

        vm.prank(address(lendingVault));
        stabilityFund.sendLiquidationFunds(100 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SendLiquidationFunds_FailsWhenAmountIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(IStabilityFund.StabilityFund__InvalidAmount.selector, 0));
        vm.prank(address(lendingVault));
        stabilityFund.sendLiquidationFunds(0);
    }

    function test_SendLiquidationFunds_FailsWhenNotLendingVault() public {
        vm.expectRevert(abi.encodeWithSelector(IStabilityFund.StabilityFund__UnauthorizedCaller.selector, user1));
        vm.prank(user1);
        stabilityFund.sendLiquidationFunds(AMOUNT_TO_SEND);
    }
}