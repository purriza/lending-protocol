// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ITreasury} from "../../contracts/interfaces/ITreasury.sol";
import {Treasury} from "../../contracts/Treasury.sol";
import {MockSwapRouter} from "../mocks/MockSwapRouter.sol";
import {TestSetup} from "../TestSetup.t.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {console} from "forge-std/console.sol";

contract RepayBackstopIouTest is TestSetup {

    error AccessControlUnauthorizedAccount(address account, bytes32 role);

    uint256 public constant MINT_AMOUNT = 1_000 ether;
    uint256 public constant IOU_AMOUNT = 10 ether;

    uint256 wstETHAmount;

    function setUp() public override {
        super.setUp();

        vm.prank(admin);
        mockSwapRouter.setSlippageRate(address(wstETH), address(pusd), 0);

        vm.prank(address(lendingVault));
        pusd.mint(address(admin), MINT_AMOUNT);

        vm.startPrank(admin);
        pusd.approve(address(treasury), MINT_AMOUNT);
        treasury.receivePUSD(MINT_AMOUNT);
        vm.stopPrank();

        // Provide backstop funds - this creates an IOU in Treasury
        vm.prank(address(lendingVault));
        treasury.provideBackstopFunds(MINT_AMOUNT + IOU_AMOUNT);

        // Register the IOU in StabilityFund (simulating what LiquidationEngine would do)
        vm.prank(address(liquidationEngine));
        stabilityFund.receiveLiquidationReturns(0, 0, IOU_AMOUNT);

        // Mint PUSD to admin to repay backstop IOU
        vm.prank(address(lendingVault));
        pusd.mint(address(admin), IOU_AMOUNT);

        // Mint WstETH to admin to repay backstop IOU
        wstETHAmount = IOU_AMOUNT / 3000;
        wstETH.mint(address(admin), wstETHAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    function test_RepayBackstop_WithPUSDUpdatesState() public {
        assertEq(treasury.pusdBalance(), 0);
        assertEq(treasury.backstopIouPusd(), IOU_AMOUNT);
        assertEq(treasury.totalBackstopUsed(), MINT_AMOUNT);
        assertEq(pusd.balanceOf(address(treasury)), 0);
        assertEq(treasury.wstETHBalance(), 0);

        vm.startPrank(admin);
        pusd.approve(address(treasury), IOU_AMOUNT);
        treasury.repayBackstopIou(IOU_AMOUNT, 0);
        vm.stopPrank();

        assertEq(treasury.pusdBalance(), 0);
        assertEq(treasury.backstopIouPusd(), 0);
        assertEq(treasury.totalBackstopUsed(), MINT_AMOUNT);
        assertEq(pusd.balanceOf(address(treasury)), 0);
        assertEq(pusd.balanceOf(admin), 0);
        assertEq(pusd.balanceOf(address(treasury)), 0);
        assertEq(pusd.balanceOf(address(stabilityFund)), IOU_AMOUNT);
        assertEq(treasury.wstETHBalance(), 0);
    }

    function test_RepayBackstop_WithWstETHUpdatesState() public {
        assertEq(treasury.pusdBalance(), 0);
        assertEq(treasury.backstopIouPusd(), IOU_AMOUNT);
        assertEq(treasury.totalBackstopUsed(), MINT_AMOUNT);
        assertEq(pusd.balanceOf(address(treasury)), 0);
        assertEq(treasury.wstETHBalance(), 0);

        uint256 pusdAmountAfterSwap = mockSwapRouter.quote(address(wstETH), address(pusd), IOU_AMOUNT / 3000);

        vm.startPrank(admin);
        wstETH.approve(address(treasury), wstETHAmount);
        treasury.repayBackstopIou(0, wstETHAmount);
        vm.stopPrank();

        assertEq(treasury.pusdBalance(), 0);
        assertEq(treasury.backstopIouPusd(), IOU_AMOUNT - pusdAmountAfterSwap);
        assertEq(treasury.totalBackstopUsed(), MINT_AMOUNT);
        assertEq(pusd.balanceOf(address(treasury)), 0);
        assertEq(pusd.balanceOf(address(stabilityFund)), pusdAmountAfterSwap);
        assertEq(treasury.wstETHBalance(), 0);
    }

    function test_RepayBackstop_WithBothUpdatesState_KeepsExcessPUSD() public {
        assertEq(treasury.pusdBalance(), 0);
        assertEq(treasury.backstopIouPusd(), IOU_AMOUNT);
        assertEq(treasury.totalBackstopUsed(), MINT_AMOUNT);
        assertEq(pusd.balanceOf(address(treasury)), 0);
        assertEq(treasury.wstETHBalance(), 0);
        assertEq(pusd.balanceOf(address(stabilityFund)), 0);

        uint256 pusdAmountAfterSwap = mockSwapRouter.quote(address(wstETH), address(pusd), IOU_AMOUNT / 3000);

        vm.startPrank(admin);
        wstETH.approve(address(treasury), wstETHAmount);
        pusd.approve(address(treasury), IOU_AMOUNT / 2);
        treasury.repayBackstopIou(IOU_AMOUNT / 2, wstETHAmount);
        vm.stopPrank();

         uint256 treasuryPusdBalance = treasury.pusdBalance();

        assertEq(treasury.backstopIouPusd(), 0);

        // Treasury' PUSD balance should be PUSD sent + Pusd received from swap - IOU amount sent to stability fund
        assertEq(treasuryPusdBalance, ((IOU_AMOUNT / 2) + pusdAmountAfterSwap) - IOU_AMOUNT);
        assertEq(pusd.balanceOf(address(treasury)), treasuryPusdBalance);

        assertEq(treasury.totalBackstopUsed(), MINT_AMOUNT);
        assertEq(pusd.balanceOf(address(stabilityFund)), IOU_AMOUNT);
        assertEq(treasury.wstETHBalance(), 0);
        assertEq(wstETH.balanceOf(address(treasury)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    function test_emitBackstopRepaidEvent() public {
        uint256 pusdAmountAfterSwap = mockSwapRouter.quote(address(wstETH), address(pusd), wstETHAmount);
        uint256 totalPusdRepayment = (IOU_AMOUNT / 2) + pusdAmountAfterSwap;
        
        // Since IOU_AMOUNT is 10 ether and totalPusdRepayment will be more than that,
        // the pusdValueUsed will be capped at IOU_AMOUNT (the full IOU gets repaid)
        uint256 expectedPusdValueUsed = totalPusdRepayment > IOU_AMOUNT ? IOU_AMOUNT : totalPusdRepayment;
        uint256 expectedRemainingIOU = IOU_AMOUNT > expectedPusdValueUsed ? IOU_AMOUNT - expectedPusdValueUsed : 0;
        
        vm.startPrank(admin);
        pusd.approve(address(treasury), IOU_AMOUNT / 2);
        wstETH.approve(address(treasury), wstETHAmount);

        vm.expectEmit(true, false, false, true);
        emit ITreasury.BackstopIouRepaid(admin, IOU_AMOUNT / 2, wstETHAmount, expectedPusdValueUsed, expectedRemainingIOU);
        treasury.repayBackstopIou(IOU_AMOUNT / 2, wstETHAmount);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RepayBackstopIouRevertsIfNowAdmin() public {
        vm.startPrank(admin);
        pusd.approve(address(treasury), IOU_AMOUNT / 2);
        wstETH.approve(address(treasury), wstETHAmount);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, treasury.protocolConfig().ADMIN_ROLE()));
        vm.startPrank(user1);
        treasury.repayBackstopIou(IOU_AMOUNT / 2, wstETHAmount);
        vm.stopPrank();
    }

    function test_RepayBackstopIouRevertsIfPaused() public {
        vm.startPrank(admin);
        pusd.approve(address(treasury), IOU_AMOUNT / 2);
        wstETH.approve(address(treasury), wstETHAmount);

        treasury.pause();

        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        treasury.repayBackstopIou(IOU_AMOUNT / 2, wstETHAmount);
         vm.stopPrank();
    }

    function test_RepayBackstopIouRevertsIfAmountsAreZero() public {
        vm.startPrank(admin);
        pusd.approve(address(treasury), IOU_AMOUNT / 2);
        wstETH.approve(address(treasury), wstETHAmount);

        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAmount.selector));
        treasury.repayBackstopIou(0, 0);
        vm.stopPrank();
    }

    function test_RepayBackstopIouRevertsIfNoIOUOpen() public {
        vm.startPrank(admin);
        pusd.approve(address(treasury), IOU_AMOUNT / 2);
        wstETH.approve(address(treasury), wstETHAmount);
        treasury.repayBackstopIou(IOU_AMOUNT / 2, wstETHAmount);

        assertEq(treasury.backstopIouPusd(), 0);

        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__NoIOUOpen.selector));
        treasury.repayBackstopIou(IOU_AMOUNT / 2, wstETHAmount);
        vm.stopPrank();
    }

    function test_RepayBackstopIouRevertsOnInsufficientAllowance() public{
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(treasury), 0, IOU_AMOUNT / 2));
        treasury.repayBackstopIou(IOU_AMOUNT / 2, wstETHAmount);
        vm.stopPrank();
    }
    
    function test_RepayBackstopIouRevertsOnInsufficientBalance() public{
        // Transfer funds out of admin wallet
        vm.startPrank(admin);
        pusd.transfer(user1, IOU_AMOUNT);
        wstETH.transfer(user1, wstETHAmount);
        pusd.approve(address(treasury), IOU_AMOUNT / 2);
        wstETH.approve(address(treasury), wstETHAmount);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, admin, 0, IOU_AMOUNT / 2));
        treasury.repayBackstopIou(IOU_AMOUNT / 2, wstETHAmount);
        vm.stopPrank();
    }

    function test_RepayBackstopIou_SwapCoverage() public {
        // Setup treasury with backstop IOU
        _setupTreasuryForLiquidation();
        
        // Create a backstop IOU by requesting more than available
        vm.startPrank(address(lendingVault));
        uint256 requestAmount = 2000 ether;
        uint256 provided = treasury.provideBackstopFunds(requestAmount);
        uint256 newIou = requestAmount > provided ? requestAmount - provided : 0;
        vm.stopPrank();
        
        // Register the additional IOU in StabilityFund (only if non-zero)
        if (newIou > 0) {
            vm.prank(address(liquidationEngine));
            stabilityFund.receiveLiquidationReturns(0, 0, newIou);
        }
        
        // Verify IOU exists (from setUp, which creates 10 ether IOU)
        assertGt(treasury.backstopIouPusd(), 0);
        
        // Repay with wstETH to trigger _swapWstETHToPusd internal function
        vm.startPrank(admin);
        wstETH.mint(admin, 500 ether);
        wstETH.approve(address(treasury), 500 ether);
        
        // This will trigger the internal swap functions and their return statements
        treasury.repayBackstopIou(0, 500 ether);
        vm.stopPrank();
    }

    /**
     * @notice Additional coverage test for the _applyRepaymentToIOU function return
     * @dev Ensures the return statement in _applyRepaymentToIOU is hit
     */
    function test_RepayBackstopIou_ApplyRepaymentCoverage() public {
        // Setup treasury with backstop IOU
        _setupTreasuryForLiquidation();
        
        // Verify existing IOU from class setup (10 ether)
        assertEq(treasury.backstopIouPusd(), IOU_AMOUNT);
        
        // Request funds that can be fully provided (no new IOU created)
        vm.startPrank(address(lendingVault));
        uint256 requestAmount = 1500 ether;
        uint256 provided = treasury.provideBackstopFunds(requestAmount);
        uint256 newIou = requestAmount > provided ? requestAmount - provided : 0;
        vm.stopPrank();
        
        // Register any new IOU in StabilityFund
        if (newIou > 0) {
            vm.prank(address(liquidationEngine));
            stabilityFund.receiveLiquidationReturns(0, 0, newIou);
        }
        
        // Verify no new IOU was created since treasury has sufficient funds
        assertEq(treasury.backstopIouPusd(), IOU_AMOUNT); // Still 10 ether from setup
        
        // Repay with PUSD to trigger _applyRepaymentToIOU
        vm.startPrank(address(lendingVault));
        pusd.mint(admin, 200 ether);
        vm.stopPrank();
        
        vm.startPrank(admin);
        pusd.approve(address(treasury), 200 ether);
        
        // This will trigger _applyRepaymentToIOU and its return statement
        (uint256 pusdValueUsed, uint256 remainingIOU) = treasury.repayBackstopIou(200 ether, 0);
        
        // Only 10 ether IOU existed, so only 10 ether is used for repayment
        assertEq(pusdValueUsed, IOU_AMOUNT); // 10 ether
        assertEq(remainingIOU, 0); // IOU fully paid off
        vm.stopPrank();
    }
}

