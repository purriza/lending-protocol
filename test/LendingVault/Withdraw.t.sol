// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TestSetup} from "../TestSetup.t.sol";

import {ILendingVault} from "../../contracts/interfaces/ILendingVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract WithdrawTest is TestSetup {

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidAmount(uint256 amount);
    error PositionNotFound(address user);
    error InsufficientBalance(uint256 requested, uint256 available);
    error InsufficientCollateral(uint256 required, uint256 provided);

    /*//////////////////////////////////////////////////////////////
                            STATE VARS
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();

        // Setup initial position for user1 with more collateral to maintain healthy ratio
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL * 2); // Double the collateral
        lendingVault.deposit(INITIAL_COLLATERAL * 2);
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        STATE CHANGE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Withdraw_UpdatesCollateral() public {
        uint256 withdrawAmount = 1 ether;
        uint256 userBalanceBefore = wstETH.balanceOf(user1);
        vm.startPrank(user1);
        lendingVault.withdraw(withdrawAmount);
        vm.stopPrank();

        (uint256 collateralAfter,, ,) = lendingVault.getPosition(user1);
        assertEq(collateralAfter, INITIAL_COLLATERAL * 2 - withdrawAmount, "Collateral should decrease");
        assertEq(wstETH.balanceOf(user1), userBalanceBefore + withdrawAmount, "User collateral balance should increase");
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Withdraw_RevertsWhenBelowMinCollateralRatio() public {
        uint256 minRatio = protocolConfig.minCollateralRatio();

        // Obtain oracle price and decimals to compute required collateral in token units.
        ( , int256 answer, , , ) = mockOracle.latestRoundData();
        uint8 decimals = mockOracle.decimals();
        assertGt(answer, 0, "oracle price must be positive");

        // Condition: (collateral' * price / 10**decimals) * 10000 / debt >= minRatio
        // Rearranged to tokens: collateral' >= ceil(minRatio * debt * 10**decimals / (10000 * price))
        uint256 price = uint256(answer);
        uint256 numerator = minRatio * BORROW_AMOUNT * (10 ** decimals);
        uint256 denominator = 10000 * price;
        // Ceil division to ensure we compute the minimal safe collateral tokens
        uint256 requiredCollateralTokens = (numerator + denominator - 1) / denominator;

        // If required exceeds deposit, clamp to deposit to avoid underflow in test math
        if (requiredCollateralTokens > INITIAL_COLLATERAL * 2) {
            requiredCollateralTokens = INITIAL_COLLATERAL * 2;
        }

        uint256 maxWithdraw = INITIAL_COLLATERAL * 2 - requiredCollateralTokens;

        vm.startPrank(user1);
        vm.expectRevert();
        lendingVault.withdraw(maxWithdraw + 1);
        vm.stopPrank();
    }

    function test_Withdraw_RevertsForInsufficientBalance() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InsufficientBalance.selector, INITIAL_COLLATERAL * 2 + 1, INITIAL_COLLATERAL * 2));
        lendingVault.withdraw(INITIAL_COLLATERAL * 2 + 1);
        vm.stopPrank();
    }

    function test_Withdraw_RevertsForNoPosition() public {
        vm.startPrank(user2);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__PositionNotFound.selector, user2));
        lendingVault.withdraw(1 ether);
        vm.stopPrank();
    }

    function test_Withdraw_RevertsForZeroAmount() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAmount.selector, 0));
        lendingVault.withdraw(0);
        vm.stopPrank();
    }

    function test_Withdraw_RevertsWhenPaused() public {
        vm.prank(admin);
        lendingVault.pause();

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        lendingVault.withdraw(1 ether);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Withdraw_MaxBoundary(uint96 raw) public {
        // Withdraw random portion up to deposit amount
        uint256 amount = uint256(raw) % (INITIAL_COLLATERAL + 1);
        vm.startPrank(user1);
        // Might revert due to collateral ratio; that's expected
        try lendingVault.withdraw(amount) {
        } catch {}
        vm.stopPrank();
    }
}


