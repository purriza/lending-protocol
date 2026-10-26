// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {Treasury} from "../../contracts/Treasury.sol";

contract TreasuryPauseableTest is TestSetup {

    error AccessControlUnauthorizedAccount(address account, bytes32 role);

    event Paused(address account);
    event Unpaused(address account);

    error EnforcedPause();
    error ExpectedPause();

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    function test_pause() public {
        assertFalse(treasury.paused());
        vm.prank(admin);
        treasury.pause();
        assertTrue(treasury.paused());
    }

    function test_unpause() public {
        vm.prank(admin);
        treasury.pause();
        assertTrue(treasury.paused());

        vm.prank(admin);
        treasury.unpause();
        assertFalse(treasury.paused());
    }

    function test_ReceivePusdRevertsWhenPaused() public {
        vm.prank(admin);
        treasury.pause();

        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        vm.prank(admin);
        treasury.receivePUSD(1 ether);
    }

    function test_ReceiveWstETHRevertsWhenPaused() public {
        vm.prank(admin);
        treasury.pause();

        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        vm.prank(admin);
        treasury.receiveWstETH(1 ether);
    }

    function test_SwapRevertsWhenPaused() public {
        vm.prank(admin);
        treasury.pause();

        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        vm.prank(admin);
        treasury.swapWstETHForPusd(1 ether);
    }

    function test_ProvideBackstopFundsRevertsWhenPaused() public {
        vm.prank(admin);
        treasury.pause();
        
        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        vm.prank(address(lendingVault));
        treasury.provideBackstopFunds(1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    function test_PauseEvent() public {
        vm.expectEmit(true, true, false, false);
        emit Paused(admin);
        vm.prank(admin);
        treasury.pause();
    }
    
    function test_UnpauseEvent() public {
        vm.prank(admin);
        treasury.pause();

        vm.expectEmit(true, true, false, false);
        emit Unpaused(admin);
        vm.prank(admin);
        treasury.unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_pauseRevertsIfNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, treasury.protocolConfig().ADMIN_ROLE()));
        vm.startPrank(user1);
        treasury.pause();
        vm.stopPrank();
    }

    function test_unpauseRevertsIfNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, treasury.protocolConfig().ADMIN_ROLE()));
        vm.startPrank(user1);
        treasury.unpause();
        vm.stopPrank();
    }
}