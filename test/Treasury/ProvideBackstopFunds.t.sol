// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {Treasury} from "../../contracts/Treasury.sol";
import {ITreasury} from "../../contracts/interfaces/ITreasury.sol";

contract ProvideBackstopFundsTest is TestSetup {

    uint256 public constant MINT_AMOUNT = 1_000_000 ether; 

    function setUp() public override {
        super.setUp();

        // Setup Treasury with liquidity for liquidation tests
        _setupTreasuryForLiquidation();
    }

    /*//////////////////////////////////////////////////////////////
                            STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    function test_ProvideBackstopFundsByLiquidationEngineUpdatesState() public {
        assertEq(treasury.pusdBalance(), MINT_AMOUNT);
        assertEq(treasury.totalBackstopUsed(), 0);

        assertEq(pusd.balanceOf(address(treasury)), MINT_AMOUNT);
        assertEq(pusd.balanceOf(address(liquidationEngine)), 0);

        vm.prank(address(liquidationEngine));
        treasury.provideBackstopFunds(MINT_AMOUNT);

        assertEq(treasury.pusdBalance(), 0);
        assertEq(treasury.totalBackstopUsed(), MINT_AMOUNT);

        assertEq(pusd.balanceOf(address(treasury)), 0);
        assertEq(pusd.balanceOf(address(liquidationEngine)), MINT_AMOUNT);
    }

    function test_ProvideBackstopFundsByLendingVaultUpdatesState() public {
        assertEq(treasury.pusdBalance(), MINT_AMOUNT);
        assertEq(treasury.totalBackstopUsed(), 0);

        assertEq(pusd.balanceOf(address(treasury)), MINT_AMOUNT);
        assertEq(pusd.balanceOf(address(lendingVault)), 0);

        vm.prank(address(lendingVault));
        treasury.provideBackstopFunds(MINT_AMOUNT);

        assertEq(treasury.pusdBalance(), 0);
        assertEq(treasury.totalBackstopUsed(), MINT_AMOUNT);

        assertEq(pusd.balanceOf(address(treasury)), 0);
        assertEq(pusd.balanceOf(address(lendingVault)), MINT_AMOUNT);
    }

    function test_ProvideBackstopFundsProvidesPartialAmountWhenInsufficientPusdBalance() public {
        assertEq(treasury.pusdBalance(), MINT_AMOUNT);
        assertEq(pusd.balanceOf(address(treasury)), MINT_AMOUNT);
        assertEq(pusd.balanceOf(address(lendingVault)), 0);
        
        vm.prank(address(lendingVault));
        uint256 provided = treasury.provideBackstopFunds(MINT_AMOUNT + 1);
        assertEq(provided, MINT_AMOUNT);

        assertEq(treasury.pusdBalance(), 0);
        assertEq(treasury.totalBackstopUsed(), MINT_AMOUNT);

        assertEq(pusd.balanceOf(address(treasury)), 0);
        assertEq(pusd.balanceOf(address(lendingVault)), MINT_AMOUNT);
    }

    function test_ProvideBackstopFundsCreatesIOUWhenInsufficientPusdBalance() public {
        uint256 requestedAmount = MINT_AMOUNT + 10 ether;
        assertEq(treasury.pusdBalance(), MINT_AMOUNT);
        assertEq(treasury.totalBackstopUsed(), 0);
        assertEq(treasury.backstopIouPusd(), 0);

        vm.prank(address(lendingVault));
        treasury.provideBackstopFunds(requestedAmount);

        assertEq(treasury.pusdBalance(), 0);
        assertEq(treasury.totalBackstopUsed(), MINT_AMOUNT);
        assertEq(treasury.backstopIouPusd(), requestedAmount - MINT_AMOUNT);

        assertEq(pusd.balanceOf(address(treasury)), 0);
        assertEq(pusd.balanceOf(address(lendingVault)), MINT_AMOUNT);
    }


    function test_ProvideBackstopFundsAllowsPartialFulfillmentWhenInsufficientPusdBalance() public {
        assertEq(treasury.pusdBalance(), MINT_AMOUNT);
        assertEq(pusd.balanceOf(address(treasury)), MINT_AMOUNT);
        assertEq(pusd.balanceOf(address(lendingVault)), 0);

        // Request more than available; should send only available amount without reverting
        vm.prank(address(lendingVault));
        uint256 provided = treasury.provideBackstopFunds(MINT_AMOUNT + 1);
        assertEq(provided, MINT_AMOUNT);

        assertEq(treasury.pusdBalance(), 0);
        assertEq(treasury.totalBackstopUsed(), MINT_AMOUNT);

        assertEq(pusd.balanceOf(address(treasury)), 0);
        assertEq(pusd.balanceOf(address(lendingVault)), MINT_AMOUNT);
    }

    function test_ProvideBackstopFundsAddsToIOUWhenIOUAlreadyOpen() public {
        uint256 iouAmount = 10 ether;
        uint256 liquidationRequest = MINT_AMOUNT + iouAmount;
        uint256 secondLiquidationRequest = 1 ether;
        

        vm.prank(address(lendingVault));
        treasury.provideBackstopFunds(liquidationRequest);

        assertEq(treasury.backstopIouPusd(), iouAmount);
        assertEq(treasury.totalBackstopUsed(), MINT_AMOUNT);

        vm.prank(address(lendingVault));
        treasury.provideBackstopFunds(secondLiquidationRequest);

        assertEq(treasury.totalBackstopUsed(), MINT_AMOUNT);
        assertEq(treasury.backstopIouPusd(), iouAmount + secondLiquidationRequest);
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    function test_ActivateBackstopEvent() public {
        vm.expectEmit(false, false, false, false);
        emit ITreasury.BackstopFundsUsed(address(pusd), MINT_AMOUNT, MINT_AMOUNT, address(lendingVault));
        vm.prank(address(lendingVault));
        treasury.provideBackstopFunds(MINT_AMOUNT);
    }

    function test_ActivateBackstopEventCorrectlyWhenPartialAmountIsProvided() public {
        vm.expectEmit(false, false, false, false);
        emit ITreasury.BackstopFundsUsed(address(pusd), MINT_AMOUNT + 1, MINT_AMOUNT, address(lendingVault));
        vm.prank(address(lendingVault));
        treasury.provideBackstopFunds(MINT_AMOUNT + 1);
    }

    function test_ActivateBackstopEvent_ByLiquidationEngine() public {
        vm.expectEmit(false, false, false, false);
        emit ITreasury.BackstopFundsUsed(address(pusd), MINT_AMOUNT, MINT_AMOUNT, address(liquidationEngine));
        vm.prank(address(liquidationEngine));
        treasury.provideBackstopFunds(MINT_AMOUNT);
    }

    function test_EmitsBackstopIOUCreatedOnPartialFulfillment() public {
        uint256 requestedAmount = MINT_AMOUNT + 10;
        uint256 expectedProvided = MINT_AMOUNT;
        uint256 expectedShortfall = requestedAmount - expectedProvided;

        vm.expectEmit(false, false, false, true);
        emit ITreasury.BackstopIOUCreated(address(lendingVault), requestedAmount, expectedProvided, expectedShortfall);

        vm.prank(address(lendingVault));
        treasury.provideBackstopFunds(requestedAmount);
    }

    function test_EmitsBackstopIOUCreatedOnMultipleCalls() public {
        uint256 requestedAmount = MINT_AMOUNT + 10;
        uint256 secondRequestedAmount = 1 ether;
        uint256 expectedProvided = MINT_AMOUNT;
        uint256 expectedShortfall = requestedAmount - expectedProvided;

        vm.expectEmit(false, false, false, true);
        emit ITreasury.BackstopIOUCreated(address(lendingVault), requestedAmount, expectedProvided, expectedShortfall);

        vm.prank(address(lendingVault));
        treasury.provideBackstopFunds(requestedAmount);

        vm.expectEmit(false, false, false, true);
        emit ITreasury.BackstopIOUCreated(address(lendingVault), secondRequestedAmount, 0, secondRequestedAmount);

        vm.prank(address(lendingVault));
        treasury.provideBackstopFunds(secondRequestedAmount);
    }

    function test_ProvideBackstopFunds_SetsFullIOUWhenNoPusdBalance() public {
        // Drain treasury PUSD balance to zero
        vm.prank(admin);
        treasury.withdrawPUSD(MINT_AMOUNT);
        assertEq(treasury.pusdBalance(), 0);

        uint256 requested = 123 ether;

        // Expect full IOU and zero provided
        vm.expectEmit(false, false, false, true);
        emit ITreasury.BackstopIOUCreated(address(lendingVault), requested, 0, requested);
        vm.expectEmit(false, false, false, false);
        emit ITreasury.BackstopFundsUsed(address(pusd), requested, 0, address(lendingVault));

        vm.prank(address(lendingVault));
        uint256 provided = treasury.provideBackstopFunds(requested);

        assertEq(provided, 0);
        assertEq(treasury.backstopIouPusd(), requested);
        assertEq(treasury.totalBackstopUsed(), 0);
        assertEq(pusd.balanceOf(address(lendingVault)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                                NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ProvideBackstopFundsRevertWhenNotAuthorized() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__UnauthorizedCaller.selector));
        vm.prank(user1);
        treasury.provideBackstopFunds(MINT_AMOUNT);
    }

    function test_ProvideBackstopFundsRevertWhenCalledByAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__UnauthorizedCaller.selector));
        vm.prank(admin);
        treasury.provideBackstopFunds(1);
    }

    function test_ProvideBackstopFundsRevertWhenInvalidAmount() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAmount.selector));
        vm.prank(address(lendingVault));
        treasury.provideBackstopFunds(0);
    }
}