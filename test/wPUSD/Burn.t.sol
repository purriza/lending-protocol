// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {IwPUSD} from "../../contracts/interfaces/IwPUSD.sol";
import {console} from "forge-std/console.sol";

contract wPUSDBurnTest is TestSetup {
    uint256 public constant MINT_AMOUNT = 100 ether;
    uint256 public constant BURN_AMOUNT = 50 ether;

    function setUp() public override {
        super.setUp();

        vm.startPrank(address(stabilityFund));
        wpusd.mint(address(stabilityFund), MINT_AMOUNT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    function test_BurnSuccess() public {
        uint256 initialWPUSDBalance = wpusd.balanceOf(address(stabilityFund));
        uint256 initialWPUSDSupply  = wpusd.totalSupply();

        assertEq(initialWPUSDBalance, MINT_AMOUNT);
        assertEq(initialWPUSDSupply, MINT_AMOUNT);

        vm.startPrank(address(stabilityFund));
        wpusd.burn(BURN_AMOUNT);
        vm.stopPrank();

        uint256 finalWPUSDBalance = wpusd.balanceOf(address(stabilityFund));
        uint256 finalWPUSDSupply  = wpusd.totalSupply();

        assertEq(finalWPUSDBalance, MINT_AMOUNT - BURN_AMOUNT);
        assertEq(finalWPUSDSupply, MINT_AMOUNT - BURN_AMOUNT); 
    }

    function test_BurnEmitEvent() public {
        vm.startPrank(address(stabilityFund));

        vm.expectEmit(true, true, false, false);
        emit IwPUSD.WPUSDBurned(BURN_AMOUNT);
        wpusd.burn(BURN_AMOUNT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_BurnRevertWhenNotStabilityFund() public {
        vm.expectRevert(abi.encodeWithSelector(IwPUSD.wPUSD__UnauthorizedCaller.selector, user1));
        vm.prank(user1);
        wpusd.burn(BURN_AMOUNT);
    }

    function test_BurnRevertWhenZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IwPUSD.wPUSD__InvalidAmount.selector));
        vm.prank(address(stabilityFund));
        wpusd.burn(0);
    }

    function test_BurnFromAlwaysReverts() public {
        vm.startPrank(address(stabilityFund));
        wpusd.approve(address(stabilityFund), BURN_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(IwPUSD.wPUSD__UnauthorizedCaller.selector, address(stabilityFund)));
        wpusd.burnFrom(address(stabilityFund), BURN_AMOUNT);
        vm.stopPrank();

        vm.prank(user1);
        wpusd.approve(user2, BURN_AMOUNT);

        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(IwPUSD.wPUSD__UnauthorizedCaller.selector, user2));
        wpusd.burnFrom(user1, BURN_AMOUNT);
    }
}