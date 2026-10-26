// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IwPUSD} from "../../contracts/interfaces/IwPUSD.sol";

contract SettersAndGettersTest is TestSetup {

    error AccessControlUnauthorizedAccount(address account, bytes32 role);

    address public newStabilityFund = makeAddr("newStabilityFund");

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            SETTERS
    //////////////////////////////////////////////////////////////*/

    function test_SetStabilityFund() public {
        assertEq(wpusd.stabilityFund(), address(stabilityFund));

        vm.prank(admin);
        wpusd.setStabilityFund(newStabilityFund);

        assertEq(wpusd.stabilityFund(), newStabilityFund);
    }

    function test_SetStabilityFundRevertWhenNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, wpusd.protocolConfig().ADMIN_ROLE()));
        vm.prank(user1);
        wpusd.setStabilityFund(newStabilityFund);
    }

    function test_SetStabilityFundRevertWhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IwPUSD.wPUSD__InvalidAddress.selector));
        vm.prank(admin);
        wpusd.setStabilityFund(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            GETTERS
    //////////////////////////////////////////////////////////////*/

    function test_StabilityFundReturnsCorrectAddress() public view {
        assertEq(wpusd.stabilityFund(), address(stabilityFund));
    }

    function test_DecimalsReturnsCorrectValue() public view {
        assertEq(wpusd.decimals(), 18);
    }

}