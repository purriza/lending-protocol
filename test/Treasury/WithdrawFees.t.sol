// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {ITreasury} from "../../contracts/interfaces/ITreasury.sol";

contract TreasuryWithdrawFeesTest is TestSetup {

    error AccessControlUnauthorizedAccount(address account, bytes32 role);

    uint256 public constant FEE_AMOUNT = 100 ether;

    function setUp() public override {
        super.setUp();

        vm.prank(address(lendingVault));
        pusd.mint(address(lendingVault), FEE_AMOUNT);

        vm.prank(address(lendingVault));
        wstETH.mint(address(lendingVault), FEE_AMOUNT);

        vm.startPrank(address(lendingVault));
        pusd.approve(address(treasury), FEE_AMOUNT);
        wstETH.approve(address(treasury), FEE_AMOUNT);
        
        treasury.receivePUSD(FEE_AMOUNT);
        treasury.receiveWstETH(FEE_AMOUNT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    function test_AdminCanWithdrawPUSD() public {
        uint256 adminBalanceBefore = pusd.balanceOf(address(admin));

        assertEq(pusd.balanceOf(address(treasury)), FEE_AMOUNT);
        assertEq(treasury.pusdBalance(), FEE_AMOUNT);
        assertEq(pusd.balanceOf(address(admin)), adminBalanceBefore);

        vm.startPrank(admin);
        treasury.withdrawPUSD(FEE_AMOUNT);
        vm.stopPrank();

        assertEq(pusd.balanceOf(address(treasury)), 0);
        assertEq(treasury.pusdBalance(), 0);
        assertEq(pusd.balanceOf(address(admin)), adminBalanceBefore + FEE_AMOUNT);
    }

    function test_AdminCanWithdrawWstETH() public {
        uint256 adminBalanceBefore = wstETH.balanceOf(address(admin));

        assertEq(wstETH.balanceOf(address(treasury)), FEE_AMOUNT);
        assertEq(treasury.wstETHBalance(), FEE_AMOUNT);
        assertEq(wstETH.balanceOf(address(admin)), adminBalanceBefore);

        vm.startPrank(admin);
        treasury.withdrawWstETH(FEE_AMOUNT);
        vm.stopPrank();

        assertEq(wstETH.balanceOf(address(treasury)), 0);
        assertEq(treasury.wstETHBalance(), 0);
        assertEq(wstETH.balanceOf(address(admin)), adminBalanceBefore + FEE_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    function test_emitPusdWithdrawnEvent() public {
        vm.expectEmit(true, true, false, false);
        emit ITreasury.PusdWithdrawn(address(pusd), FEE_AMOUNT);
        vm.prank(admin);
        treasury.withdrawPUSD(FEE_AMOUNT);
    }

    function test_emitWstETHWithdrawnEvent() public {
        vm.expectEmit(true, true, false, false);
        emit ITreasury.WstETHWithdrawn(address(wstETH), FEE_AMOUNT);
        vm.prank(admin);
        treasury.withdrawWstETH(FEE_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_revertsIfNotAdminCallingWithdrawPUSD() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, treasury.protocolConfig().ADMIN_ROLE()));
        vm.startPrank(user1);
        treasury.withdrawPUSD(FEE_AMOUNT);
        vm.stopPrank();
    }

    function test_revertsIfNotAdminCallingWithdrawWstETH() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, treasury.protocolConfig().ADMIN_ROLE()));
        vm.startPrank(user1);
        treasury.withdrawWstETH(FEE_AMOUNT);
        vm.stopPrank();
    }

    function test_revertsIfZeroAmountCallingWithdrawPUSD() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAmount.selector));
        vm.prank(admin);
        treasury.withdrawPUSD(0);
    }

    function test_revertsIfZeroAmountCallingWithdrawWstETH() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAmount.selector));
        vm.prank(admin);
        treasury.withdrawWstETH(0);
    }

    function test_revertsIfInsufficientPusdBalanceCallingWithdrawPUSD() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InsufficientPusdBalance.selector, FEE_AMOUNT + 1, FEE_AMOUNT));
        vm.prank(admin);
        treasury.withdrawPUSD(FEE_AMOUNT + 1);
    }

    function test_revertsIfInsufficientWstETHBalanceCallingWithdrawWstETH() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InsufficientWstETHBalance.selector, FEE_AMOUNT + 1, FEE_AMOUNT));
        vm.prank(admin);
        treasury.withdrawWstETH(FEE_AMOUNT + 1);
    }
}