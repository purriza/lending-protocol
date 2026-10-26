// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {IwPUSD} from "../../contracts/interfaces/IwPUSD.sol";

contract wPUSDMintTest is TestSetup {
    uint256 public constant MINT_AMOUNT = 100 ether;

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    function test_MintSuccess() public {
        uint256 user1InitialWPUSDBalance = wpusd.balanceOf(user1);
        uint256 initialWPUSDSupply  = wpusd.totalSupply();

        assertEq(user1InitialWPUSDBalance, 0);
        assertEq(initialWPUSDSupply, 0);

        vm.prank(address(stabilityFund));
        wpusd.mint(user1, MINT_AMOUNT);

        uint256 user1FinalWPUSDBalance = wpusd.balanceOf(user1);
        uint256 finalWPUSDSupply  = wpusd.totalSupply();

        assertEq(user1FinalWPUSDBalance, MINT_AMOUNT);
        assertEq(finalWPUSDSupply, MINT_AMOUNT); 
    }

    function test_MintEmitEvent() public {
        vm.expectEmit(true, true, false, false);
        emit IwPUSD.WPUSDMinted(user1, MINT_AMOUNT);

        vm.prank(address(stabilityFund));
        wpusd.mint(user1, MINT_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MintRevertWhenNotStabilityFund() public {
        vm.expectRevert(abi.encodeWithSelector(IwPUSD.wPUSD__UnauthorizedCaller.selector, user1));
        vm.prank(user1);
        wpusd.mint(user1, MINT_AMOUNT);
    }

    function test_MintRevertWhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IwPUSD.wPUSD__InvalidAddress.selector));
        vm.prank(address(stabilityFund));
        wpusd.mint(address(0), MINT_AMOUNT);
    }

    function test_MintRevertWhenZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IwPUSD.wPUSD__InvalidAmount.selector));
        vm.prank(address(stabilityFund));
        wpusd.mint(user1, 0);
    }
}