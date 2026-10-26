// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {wPUSD} from "../../contracts/wPUSD.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract wPUSDV2 is wPUSD {
    function version() public pure returns (uint256) {
        return 2;
    }
}

contract wPUSDUpgradeTest is TestSetup {

    error AccessControlUnauthorizedAccount(address account, bytes32 role);

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    function test_UpgradeSuccess() public {
        wPUSDV2 newWPUSD = new wPUSDV2();

        vm.prank(upgrader);
        wpusd.upgradeToAndCall(address(newWPUSD), "");

        wPUSDV2 wpusdV2 = wPUSDV2(address(wpusd));

        assertEq(wpusdV2.version(), 2);
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_UpgradeRevertWhenNotOwner() public {
        wPUSDV2 newWPUSD = new wPUSDV2();

        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, wpusd.protocolConfig().UPGRADER_ROLE()));
        vm.prank(user1);
        wpusd.upgradeToAndCall(address(newWPUSD), "");
    }
}