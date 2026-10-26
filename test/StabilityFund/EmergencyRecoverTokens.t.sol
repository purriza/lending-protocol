// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {StabilityFund} from "../../contracts/StabilityFund.sol";
import {IStabilityFund} from "../../contracts/interfaces/IStabilityFund.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

contract EmergencyRecoverTokens is TestSetup {

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error AccessControlUnauthorizedAccount(address account, bytes32 role);

    /*//////////////////////////////////////////////////////////////
                               STATE VARS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant PUSD_AMOUNT = 100 ether;

    MockERC20 public stuckToken;

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        stuckToken = new MockERC20("StuckToken", "STK");

        // Transfer invalid tokens to the stability fund
        stuckToken.transfer(address(stabilityFund), 1_000_000 ether);
        assertEq(stuckToken.balanceOf(address(stabilityFund)), 1_000_000 ether);
        vm.stopPrank();
        
        // Deposit Valid PUSD into the Stability Fund
        _mintPUSD(user1, PUSD_AMOUNT);
        vm.startPrank(user1);
        pusd.approve(address(stabilityFund), PUSD_AMOUNT);
        stabilityFund.depositPUSD(PUSD_AMOUNT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    function test_EmergencyRecoverTokens_TransfersStuckTokenBalanceToAdmin() public {
        uint256 initialStuckTokenStabilityFundBalance = stuckToken.balanceOf(address(stabilityFund));
        uint256 initialAdminStuckTokenBalance = stuckToken.balanceOf(admin);

        assertEq(initialStuckTokenStabilityFundBalance, 1_000_000 ether);
        assertEq(initialAdminStuckTokenBalance, 0);

        vm.prank(admin);
        stabilityFund.recoverStuckTokens(address(stuckToken));

        uint256 finalStuckTokenStabilityFundBalance = stuckToken.balanceOf(address(stabilityFund));
        uint256 finalAdminStuckTokenBalance = stuckToken.balanceOf(admin);

        assertEq(finalStuckTokenStabilityFundBalance, 0);
        assertEq(finalAdminStuckTokenBalance, 1_000_000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                            EVENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_EmergencyRecoverTokens_EmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit IStabilityFund.TokensRecovered(address(stuckToken), admin, 1_000_000 ether);

        vm.prank(admin);
        stabilityFund.recoverStuckTokens(address(stuckToken));
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_EmergencyRecoverTokens_RevertsIfTokenIsPUSD() public {
        vm.expectRevert(abi.encodeWithSelector(IStabilityFund.StabilityFund__CannotRecoverPUSD.selector));
        vm.prank(admin);
        stabilityFund.recoverStuckTokens(address(pusd));
    }

    function test_EmergencyRecoverTokens_RevertsIfNotAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, stabilityFund.protocolConfig().ADMIN_ROLE()));
        stabilityFund.recoverStuckTokens(address(stuckToken));
        vm.stopPrank();
    }

    function test_EmergencyRecoverTokens_RevertsIfContractBalanceIsZero() public {
        vm.startPrank(admin);
        stabilityFund.recoverStuckTokens(address(stuckToken));

        vm.expectRevert(abi.encodeWithSelector(IStabilityFund.StabilityFund__InvalidAmount.selector, 0));
        stabilityFund.recoverStuckTokens(address(stuckToken));
        vm.stopPrank();
    }
}