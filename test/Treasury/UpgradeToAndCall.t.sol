// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {Treasury} from "../../contracts/Treasury.sol";

contract TreasuryV2 is Treasury {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract TreasuryUpgradeToAndCallTest is TestSetup {

    error AccessControlUnauthorizedAccount(address account, bytes32 role);

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    function test_UpgradeSuccess() public {
        TreasuryV2 newTreasury = new TreasuryV2();

        vm.prank(upgrader);
        treasury.upgradeToAndCall(address(newTreasury), "");

        TreasuryV2 treasuryV2 = TreasuryV2(address(treasury));

        assertEq(treasuryV2.version(), 2);
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_UpgradeRevertWhenNotUpgrader() public {
        TreasuryV2 newTreasury = new TreasuryV2();

        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, treasury.protocolConfig().UPGRADER_ROLE()));
        vm.prank(user1);
        treasury.upgradeToAndCall(address(newTreasury), "");
    }
}