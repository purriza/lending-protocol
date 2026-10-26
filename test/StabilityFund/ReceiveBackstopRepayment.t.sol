// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {IStabilityFund} from "../../contracts/interfaces/IStabilityFund.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract ReceiveBackstopRepaymentTest is TestSetup {

    uint256 public constant DEPOSIT_AMOUNT = 1000 ether;
    uint256 public constant IOU_AMOUNT = 100 ether;

    function setUp() public override {
        super.setUp();

        // Setup: Create some wPUSD supply
        _mintPUSD(user1, DEPOSIT_AMOUNT);
        
        vm.startPrank(user1);
        pusd.approve(address(stabilityFund), DEPOSIT_AMOUNT);
        stabilityFund.depositPUSD(DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    function test_ReceiveBackstopRepayment_UpdatesState() public {
        // First, create an IOU by simulating a liquidation with shortfall
        vm.prank(address(liquidationEngine));
        stabilityFund.receiveLiquidationReturns(0, 0, IOU_AMOUNT);
        
        assertEq(stabilityFund.backstopIouAmount(), IOU_AMOUNT);
        
        // Calculate initial exchange rate
        uint256 initialExchangeRate = stabilityFund.exchangeRate();
        uint256 expectedReducedRate = ((DEPOSIT_AMOUNT - IOU_AMOUNT) * 1e18) / DEPOSIT_AMOUNT;
        assertEq(initialExchangeRate, expectedReducedRate);
        
        // Treasury repays the IOU
        _mintPUSD(address(treasury), IOU_AMOUNT);
        
        vm.startPrank(address(treasury));
        pusd.approve(address(stabilityFund), IOU_AMOUNT);
        uint256 iouReduction = stabilityFund.receiveBackstopRepayment(IOU_AMOUNT);
        vm.stopPrank();
        
        // Verify IOU was reduced
        assertEq(iouReduction, IOU_AMOUNT);
        assertEq(stabilityFund.backstopIouAmount(), 0);
        
        // Verify exchange rate increased back to 1:1
        uint256 finalExchangeRate = stabilityFund.exchangeRate();
        assertEq(finalExchangeRate, 1e18);
        
        // Verify StabilityFund received the PUSD
        assertEq(pusd.balanceOf(address(stabilityFund)), DEPOSIT_AMOUNT + IOU_AMOUNT);
    }

    function test_ReceiveBackstopRepayment_PartialRepayment() public {
        // Create an IOU
        vm.prank(address(liquidationEngine));
        stabilityFund.receiveLiquidationReturns(0, 0, IOU_AMOUNT);
        
        assertEq(stabilityFund.backstopIouAmount(), IOU_AMOUNT);
        
        // Treasury repays only half
        uint256 partialAmount = IOU_AMOUNT / 2;
        _mintPUSD(address(treasury), partialAmount);
        
        vm.startPrank(address(treasury));
        pusd.approve(address(stabilityFund), partialAmount);
        uint256 iouReduction = stabilityFund.receiveBackstopRepayment(partialAmount);
        vm.stopPrank();
        
        // Verify partial IOU reduction
        assertEq(iouReduction, partialAmount);
        assertEq(stabilityFund.backstopIouAmount(), IOU_AMOUNT - partialAmount);
        
        // Exchange rate should improve but not fully
        uint256 effectivePusd = DEPOSIT_AMOUNT - (IOU_AMOUNT - partialAmount);
        uint256 expectedRate = (effectivePusd * 1e18) / DEPOSIT_AMOUNT;
        assertEq(stabilityFund.exchangeRate(), expectedRate);
    }

    function test_ReceiveBackstopRepayment_OverpaymentCappedAtIOU() public {
        // Create an IOU
        vm.prank(address(liquidationEngine));
        stabilityFund.receiveLiquidationReturns(0, 0, IOU_AMOUNT);
        
        assertEq(stabilityFund.backstopIouAmount(), IOU_AMOUNT);
        
        // Treasury tries to repay MORE than the IOU
        uint256 overpayment = IOU_AMOUNT * 2;
        _mintPUSD(address(treasury), overpayment);
        
        vm.startPrank(address(treasury));
        pusd.approve(address(stabilityFund), overpayment);
        uint256 iouReduction = stabilityFund.receiveBackstopRepayment(overpayment);
        vm.stopPrank();
        
        // Verify IOU reduction is capped at the outstanding amount
        assertEq(iouReduction, IOU_AMOUNT);
        assertEq(stabilityFund.backstopIouAmount(), 0);
        
        // StabilityFund should receive the full overpayment amount
        assertEq(pusd.balanceOf(address(stabilityFund)), DEPOSIT_AMOUNT + overpayment);
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    function test_ReceiveBackstopRepayment_EmitsEvent() public {
        // Create an IOU
        vm.prank(address(liquidationEngine));
        stabilityFund.receiveLiquidationReturns(0, 0, IOU_AMOUNT);
        
        // Repay the IOU
        _mintPUSD(address(treasury), IOU_AMOUNT);
        
        vm.startPrank(address(treasury));
        pusd.approve(address(stabilityFund), IOU_AMOUNT);
        
        vm.expectEmit(true, true, true, true);
        emit IStabilityFund.BackstopIOURepaid(IOU_AMOUNT, 0, IOU_AMOUNT);
        stabilityFund.receiveBackstopRepayment(IOU_AMOUNT);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ReceiveBackstopRepayment_RevertsWhenNoOutstandingIOU() public {
        // No IOU has been created
        assertEq(stabilityFund.backstopIouAmount(), 0);
        
        // Treasury tries to repay
        _mintPUSD(address(treasury), IOU_AMOUNT);
        
        vm.startPrank(address(treasury));
        pusd.approve(address(stabilityFund), IOU_AMOUNT);
        
        vm.expectRevert(abi.encodeWithSelector(IStabilityFund.StabilityFund__NoOutstandingIOU.selector));
        stabilityFund.receiveBackstopRepayment(IOU_AMOUNT);
        
        vm.stopPrank();
    }

    function test_ReceiveBackstopRepayment_RevertsWhenCalledByNonTreasury() public {
        // Create an IOU first
        vm.prank(address(liquidationEngine));
        stabilityFund.receiveLiquidationReturns(0, 0, IOU_AMOUNT);
        
        // Random user tries to repay
        _mintPUSD(user1, IOU_AMOUNT);
        
        vm.startPrank(user1);
        pusd.approve(address(stabilityFund), IOU_AMOUNT);
        
        vm.expectRevert(abi.encodeWithSelector(IStabilityFund.StabilityFund__UnauthorizedCaller.selector, user1));
        stabilityFund.receiveBackstopRepayment(IOU_AMOUNT);
        
        vm.stopPrank();
    }

    function test_ReceiveBackstopRepayment_RevertsWhenAmountIsZero() public {
        // Create an IOU first
        vm.prank(address(liquidationEngine));
        stabilityFund.receiveLiquidationReturns(0, 0, IOU_AMOUNT);
        
        vm.startPrank(address(treasury));
        
        vm.expectRevert(abi.encodeWithSelector(IStabilityFund.StabilityFund__InvalidAmount.selector, 0));
        stabilityFund.receiveBackstopRepayment(0);
        
        vm.stopPrank();
    }

    function test_ReceiveBackstopRepayment_RevertsWhenPaused() public {
        // Create an IOU first
        vm.prank(address(liquidationEngine));
        stabilityFund.receiveLiquidationReturns(0, 0, IOU_AMOUNT);
        
        // Pause the contract
        vm.prank(admin);
        stabilityFund.pause();
        
        // Treasury tries to repay
        _mintPUSD(address(treasury), IOU_AMOUNT);
        
        vm.startPrank(address(treasury));
        pusd.approve(address(stabilityFund), IOU_AMOUNT);
        
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        stabilityFund.receiveBackstopRepayment(IOU_AMOUNT);
        
        vm.stopPrank();
    }

    function test_ReceiveBackstopRepayment_RevertsOnInsufficientAllowance() public {
        // Create an IOU first
        vm.prank(address(liquidationEngine));
        stabilityFund.receiveLiquidationReturns(0, 0, IOU_AMOUNT);
        
        _mintPUSD(address(treasury), IOU_AMOUNT);
        
        vm.startPrank(address(treasury));
        // Don't approve, or approve less than needed
        
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(stabilityFund), 0, IOU_AMOUNT));
        stabilityFund.receiveBackstopRepayment(IOU_AMOUNT);
        
        vm.stopPrank();
    }

    function test_ReceiveBackstopRepayment_RevertsOnInsufficientBalance() public {
        // Create an IOU first
        vm.prank(address(liquidationEngine));
        stabilityFund.receiveLiquidationReturns(0, 0, IOU_AMOUNT);
        
        // Treasury doesn't have enough PUSD
        vm.startPrank(address(treasury));
        pusd.approve(address(stabilityFund), IOU_AMOUNT);
        
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(treasury), 0, IOU_AMOUNT));
        stabilityFund.receiveBackstopRepayment(IOU_AMOUNT);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_ReceiveBackstopRepayment_RandomAmounts(uint256 iouAmount, uint256 repayAmount) public {
        // Bound the inputs to reasonable ranges
        iouAmount = bound(iouAmount, 1 ether, DEPOSIT_AMOUNT);
        repayAmount = bound(repayAmount, 1, iouAmount * 2); // Can overpay
        
        // Create an IOU
        vm.prank(address(liquidationEngine));
        stabilityFund.receiveLiquidationReturns(0, 0, iouAmount);
        
        assertEq(stabilityFund.backstopIouAmount(), iouAmount);
        
        // Calculate expected values
        uint256 expectedReduction = repayAmount > iouAmount ? iouAmount : repayAmount;
        uint256 expectedRemainingIOU = iouAmount - expectedReduction;
        
        // Treasury repays
        _mintPUSD(address(treasury), repayAmount);
        
        vm.startPrank(address(treasury));
        pusd.approve(address(stabilityFund), repayAmount);
        uint256 actualReduction = stabilityFund.receiveBackstopRepayment(repayAmount);
        vm.stopPrank();
        
        // Verify results
        assertEq(actualReduction, expectedReduction);
        assertEq(stabilityFund.backstopIouAmount(), expectedRemainingIOU);
        
        // Verify exchange rate calculation
        uint256 effectivePusd = DEPOSIT_AMOUNT - expectedRemainingIOU;
        uint256 expectedRate = (effectivePusd * 1e18) / wpusd.totalSupply();
        assertEq(stabilityFund.exchangeRate(), expectedRate);
    }
}

