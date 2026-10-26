// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {ITreasury} from "../../contracts/interfaces/ITreasury.sol";

contract TreasuryReceiveFeesTest is TestSetup {

    uint256 public constant FEE_AMOUNT = 100 ether;

    function setUp() public override {
        super.setUp();

        vm.prank(address(lendingVault));
        pusd.mint(address(liquidationEngine), FEE_AMOUNT);
        wstETH.mint(address(liquidationEngine), FEE_AMOUNT);

        vm.startPrank(address(liquidationEngine));
        pusd.approve(address(treasury), FEE_AMOUNT);
        wstETH.approve(address(treasury), FEE_AMOUNT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    function test_receivePUSD() public {

        assertEq(pusd.balanceOf(address(treasury)), 0);
        assertEq(treasury.pusdBalance(), 0);

        assertEq(pusd.balanceOf(address(liquidationEngine)), FEE_AMOUNT);

        vm.prank(address(liquidationEngine));
        treasury.receivePUSD(FEE_AMOUNT);

        assertEq(pusd.balanceOf(address(treasury)), FEE_AMOUNT);
        assertEq(treasury.pusdBalance(), FEE_AMOUNT);

        assertEq(pusd.balanceOf(address(liquidationEngine)), 0);
    }

    function test_receiveWstETH() public {
        assertEq(wstETH.balanceOf(address(treasury)), 0);
        assertEq(treasury.wstETHBalance(), 0);

        vm.startPrank(address(liquidationEngine));
        treasury.receiveWstETH(FEE_AMOUNT);
        vm.stopPrank();

        assertEq(wstETH.balanceOf(address(treasury)), FEE_AMOUNT);
        assertEq(treasury.wstETHBalance(), FEE_AMOUNT);

        assertEq(wstETH.balanceOf(address(liquidationEngine)), 0);
    }

    function test_LendingVaultCanSendPusdToTreasury() public {
        vm.prank(address(lendingVault));
        pusd.mint(address(lendingVault), FEE_AMOUNT);

        assertEq(pusd.balanceOf(address(lendingVault)), FEE_AMOUNT);
        assertEq(treasury.pusdBalance(), 0);

        vm.startPrank(address(lendingVault));
        pusd.approve(address(treasury), FEE_AMOUNT);
        treasury.receivePUSD(FEE_AMOUNT);
        vm.stopPrank();

        assertEq(pusd.balanceOf(address(treasury)), FEE_AMOUNT);
        assertEq(treasury.pusdBalance(), FEE_AMOUNT);
        assertEq(pusd.balanceOf(address(lendingVault)), 0);
    }

    function test_LendingVaultCanSendWstETHToTreasury() public {
        wstETH.mint(address(lendingVault), FEE_AMOUNT);

        assertEq(wstETH.balanceOf(address(lendingVault)), FEE_AMOUNT);
        assertEq(treasury.wstETHBalance(), 0);

        vm.startPrank(address(lendingVault));
        wstETH.approve(address(treasury), FEE_AMOUNT);
        treasury.receiveWstETH(FEE_AMOUNT);
        vm.stopPrank();

        assertEq(wstETH.balanceOf(address(treasury)), FEE_AMOUNT);
        assertEq(treasury.wstETHBalance(), FEE_AMOUNT);
        assertEq(wstETH.balanceOf(address(lendingVault)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            EVENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_emitPUSDReceivedEvent() public {
        vm.expectEmit(true, true, false, false);
        emit ITreasury.PusdReceived(address(pusd), FEE_AMOUNT);
        vm.prank(address(liquidationEngine));
        treasury.receivePUSD(FEE_AMOUNT);
    }

    function test_emitWstETHReceivedEvent() public {
        vm.expectEmit(true, true, false, false);
        emit ITreasury.WstETHReceived(address(wstETH), FEE_AMOUNT);
        vm.prank(address(liquidationEngine));
        treasury.receiveWstETH(FEE_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_receivePUSDRevertsWithZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAmount.selector));
        vm.prank(address(liquidationEngine));
        treasury.receivePUSD(0);
    }

    function test_receiveWstETHRevertsWithZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAmount.selector));
        vm.prank(address(liquidationEngine));
        treasury.receiveWstETH(0);
    }

    function test_receivePUSDRevertsWithInvalidSender() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__UnauthorizedCaller.selector));
        vm.prank(user1);
        treasury.receivePUSD(FEE_AMOUNT);
    }

    function test_receiveWstETHRevertsWithInvalidSender() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__UnauthorizedCaller.selector));
        vm.prank(user1);
        treasury.receiveWstETH(FEE_AMOUNT);
    }
}