// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {IStabilityFund} from "../../contracts/interfaces/IStabilityFund.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {console} from "forge-std/console.sol";

contract RedeemWPUSDTest is TestSetup {

    uint256 public constant PUSD_DEPOSIT_AMOUNT = 1000 ether;
    uint256 public constant AMOUNT_TO_REDEEM = 100 ether;

    function setUp() public override {
        super.setUp();

        _mintPUSD(user1, PUSD_DEPOSIT_AMOUNT);

        vm.startPrank(user1);
        pusd.approve(address(stabilityFund), PUSD_DEPOSIT_AMOUNT);
        stabilityFund.depositPUSD(PUSD_DEPOSIT_AMOUNT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    function test_RedeemWPUSD_Success_WhenExchangeRateIs1() public {
        uint256 initialWPUSDBalance = wpusd.balanceOf(user1);
        uint256 initialPUSDBalance = pusd.balanceOf(user1);
        uint256 initialPUSDStabilityFundBalance = pusd.balanceOf(address(stabilityFund));

        assertEq(initialWPUSDBalance, PUSD_DEPOSIT_AMOUNT);
        assertEq(initialPUSDBalance, 0);
        assertEq(initialPUSDStabilityFundBalance, PUSD_DEPOSIT_AMOUNT);
        assertEq(wpusd.totalSupply(), PUSD_DEPOSIT_AMOUNT);

        vm.startPrank(user1);
        wpusd.approve(address(stabilityFund), AMOUNT_TO_REDEEM);
        uint256 returnedPUSD = stabilityFund.redeemWPUSD(AMOUNT_TO_REDEEM);
        vm.stopPrank();

        assertEq(returnedPUSD, AMOUNT_TO_REDEEM);
        assertEq(wpusd.balanceOf(user1), PUSD_DEPOSIT_AMOUNT - AMOUNT_TO_REDEEM);
        assertEq(pusd.balanceOf(user1), AMOUNT_TO_REDEEM);
        assertEq(pusd.balanceOf(address(stabilityFund)), initialPUSDStabilityFundBalance - AMOUNT_TO_REDEEM);
        assertEq(stabilityFund.totalPusdLocked(), PUSD_DEPOSIT_AMOUNT - AMOUNT_TO_REDEEM);
        assertEq(wpusd.totalSupply(), PUSD_DEPOSIT_AMOUNT - AMOUNT_TO_REDEEM);
    }

    function test_RedeemWPUSD_Success_WhenExchangeRateIsGreaterThan1() public {
        uint256 yeildAmount = 1 ether;

        uint256 initialWPUSDBalance = wpusd.balanceOf(user1);
        uint256 initialPUSDBalance = pusd.balanceOf(user1);

        uint256 initialPUSDStabilityFundBalance = pusd.balanceOf(address(stabilityFund));

        assertEq(initialWPUSDBalance, PUSD_DEPOSIT_AMOUNT);
        assertEq(initialPUSDBalance, 0);
        assertEq(initialPUSDStabilityFundBalance, PUSD_DEPOSIT_AMOUNT);
        assertEq(wpusd.totalSupply(), PUSD_DEPOSIT_AMOUNT);

        _sendLiquidationFundsAndSwapCollateral(PUSD_DEPOSIT_AMOUNT, yeildAmount);

        vm.startPrank(address(liquidationEngine));
        pusd.approve(address(stabilityFund), PUSD_DEPOSIT_AMOUNT + yeildAmount);
        stabilityFund.receiveLiquidationReturns(PUSD_DEPOSIT_AMOUNT, yeildAmount, 0);
        vm.stopPrank();

        uint256 newExchangeRate = stabilityFund.totalPusdLocked() * stabilityFund.getPrecision() / wpusd.totalSupply();

        assertEq(stabilityFund.exchangeRate(), newExchangeRate);

        uint256 expectedReturnedPUSD = _calculateExpectedReturnedPUSD(AMOUNT_TO_REDEEM, newExchangeRate);

        vm.startPrank(user1);
        wpusd.approve(address(stabilityFund), AMOUNT_TO_REDEEM);
        uint256 returnedPUSD = stabilityFund.redeemWPUSD(AMOUNT_TO_REDEEM);
        vm.stopPrank();

        assertEq(returnedPUSD, expectedReturnedPUSD);
        assertEq(wpusd.balanceOf(user1), PUSD_DEPOSIT_AMOUNT - AMOUNT_TO_REDEEM);
        assertEq(pusd.balanceOf(user1), expectedReturnedPUSD);
        assertEq(pusd.balanceOf(address(stabilityFund)), initialPUSDStabilityFundBalance - expectedReturnedPUSD + yeildAmount);
        assertEq(stabilityFund.totalPusdLocked(), PUSD_DEPOSIT_AMOUNT - expectedReturnedPUSD + yeildAmount);
        assertEq(wpusd.totalSupply(), PUSD_DEPOSIT_AMOUNT - AMOUNT_TO_REDEEM);
    }

    /*//////////////////////////////////////////////////////////////
                            EVENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RedeemWPUSD_EmitsCorrectEvent_WhenExchangeRateIs1() public {
        vm.startPrank(user1);
        wpusd.approve(address(stabilityFund), AMOUNT_TO_REDEEM);

        vm.expectEmit(true, true, true, true);
        emit IStabilityFund.WPUSDRedeemed(user1, AMOUNT_TO_REDEEM, AMOUNT_TO_REDEEM);
        stabilityFund.redeemWPUSD(AMOUNT_TO_REDEEM);
        vm.stopPrank();
    }

    function test_RedeemWPUSD_EmitsCorrectEvent_WhenExchangeRateIsGreaterThan1() public {
        uint256 yeildAmount = 1 ether;

        _sendLiquidationFundsAndSwapCollateral(PUSD_DEPOSIT_AMOUNT, yeildAmount);

        vm.startPrank(address(liquidationEngine));
        pusd.approve(address(stabilityFund), PUSD_DEPOSIT_AMOUNT + yeildAmount);
        stabilityFund.receiveLiquidationReturns(PUSD_DEPOSIT_AMOUNT, yeildAmount, 0);
        vm.stopPrank();
        
        uint256 newExchangeRate = stabilityFund.exchangeRate();

        uint256 expectedReturnedPUSD = _calculateExpectedReturnedPUSD(AMOUNT_TO_REDEEM, newExchangeRate);

        vm.startPrank(user1);
        wpusd.approve(address(stabilityFund), AMOUNT_TO_REDEEM);

        vm.expectEmit(true, true, true, false);
        emit IStabilityFund.WPUSDRedeemed(user1, AMOUNT_TO_REDEEM, expectedReturnedPUSD);
        stabilityFund.redeemWPUSD(AMOUNT_TO_REDEEM);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RedeemWPUSD_Reverts_WhenAmountIs0() public {
        vm.startPrank(user1);
        wpusd.approve(address(stabilityFund), AMOUNT_TO_REDEEM);

        vm.expectRevert(abi.encodeWithSelector(IStabilityFund.StabilityFund__InvalidAmount.selector, 0));
        stabilityFund.redeemWPUSD(0);
        vm.stopPrank();
    }

    function test_RedeemWPUSD_Reverts_WhenAmountIsGreaterThanStabilityFundBalance() public {
        uint256 amountToRedeem = PUSD_DEPOSIT_AMOUNT + 1;

        vm.startPrank(user1);
        wpusd.approve(address(stabilityFund), amountToRedeem);

        vm.expectRevert(abi.encodeWithSelector(IStabilityFund.StabilityFund__InsufficientBalance.selector, PUSD_DEPOSIT_AMOUNT, amountToRedeem));
        stabilityFund.redeemWPUSD(amountToRedeem);
        vm.stopPrank();
    }

    function test_RedeemWPUSD_Reverts_WhenInsufficientUserBalance() public {
        // User 3 has no balance of wPUSD
        vm.startPrank(user3);
        wpusd.approve(address(stabilityFund), AMOUNT_TO_REDEEM);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user3, 0, AMOUNT_TO_REDEEM));
        stabilityFund.redeemWPUSD(AMOUNT_TO_REDEEM);
        vm.stopPrank();
    }

    function test_RedeemWPUSD_Reverts_WhenPaused() public {
        vm.prank(admin);
        stabilityFund.pause();
        assertTrue(stabilityFund.paused());

        vm.startPrank(user1);
        wpusd.approve(address(stabilityFund), AMOUNT_TO_REDEEM);

        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        stabilityFund.redeemWPUSD(AMOUNT_TO_REDEEM);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_RedeemWPUSD_WhenExchangeRateIs1(uint256 _amountToRedeem) public {
        _amountToRedeem = bound(_amountToRedeem, 1, AMOUNT_TO_REDEEM);

        uint256 initialWPUSDBalance = wpusd.balanceOf(user1);
        uint256 initialPUSDBalance = pusd.balanceOf(user1);
        uint256 initialPUSDStabilityFundBalance = pusd.balanceOf(address(stabilityFund));

        vm.startPrank(user1);
        wpusd.approve(address(stabilityFund), _amountToRedeem);
        uint256 returnedPUSD = stabilityFund.redeemWPUSD(_amountToRedeem);
        vm.stopPrank();

        assertEq(returnedPUSD, _amountToRedeem);
        assertEq(wpusd.balanceOf(user1), initialWPUSDBalance - _amountToRedeem);
        assertEq(pusd.balanceOf(user1), initialPUSDBalance + _amountToRedeem, "User PUSD balance should increase");
        assertEq(pusd.balanceOf(address(stabilityFund)), initialPUSDStabilityFundBalance - _amountToRedeem);
        assertEq(stabilityFund.totalPusdLocked(), initialPUSDStabilityFundBalance - _amountToRedeem);
    }

    function testFuzz_RedeemWPUSD_WhenExchangeRateIsGreaterThan1(uint256 _amountToRedeem, uint256 _yeildAmount) public {
        _amountToRedeem = bound(_amountToRedeem, 1, AMOUNT_TO_REDEEM);
        _yeildAmount = bound(_yeildAmount, 1 ether, 2 ether);

        uint256 initialPUSDBalance = pusd.balanceOf(user1);

        uint256 initialWPUSDBalance = wpusd.balanceOf(user1);
        uint256 initialPUSDStabilityFundBalance = pusd.balanceOf(address(stabilityFund));

        _sendLiquidationFundsAndSwapCollateral(PUSD_DEPOSIT_AMOUNT, _yeildAmount);

        vm.startPrank(address(liquidationEngine));
        pusd.approve(address(stabilityFund), PUSD_DEPOSIT_AMOUNT + _yeildAmount);
        stabilityFund.receiveLiquidationReturns(PUSD_DEPOSIT_AMOUNT, _yeildAmount, 0);
        vm.stopPrank();

        vm.startPrank(user1);
        wpusd.approve(address(stabilityFund), _amountToRedeem);
        uint256 returnedPUSD = stabilityFund.redeemWPUSD(_amountToRedeem);
        vm.stopPrank();

        uint256 newExchangeRate = stabilityFund.exchangeRate();
        uint256 expectedReturnedPUSD = _calculateExpectedReturnedPUSD(_amountToRedeem, newExchangeRate);

        assertEq(returnedPUSD, expectedReturnedPUSD);
        assertEq(wpusd.balanceOf(user1), initialWPUSDBalance - _amountToRedeem);
        assertEq(pusd.balanceOf(user1), expectedReturnedPUSD);
        
        // Verify that user's PUSD balance actually increased
        assertGt(pusd.balanceOf(user1), initialPUSDBalance, "User PUSD balance should increase after redeem");
        
        assertEq(pusd.balanceOf(address(stabilityFund)), initialPUSDStabilityFundBalance - expectedReturnedPUSD + _yeildAmount);
        assertEq(stabilityFund.totalPusdLocked(), initialPUSDStabilityFundBalance - expectedReturnedPUSD + _yeildAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _calculateExpectedReturnedPUSD(uint256 _wpusdAmount, uint256 _exchangeRate) internal view returns (uint256) {
        return (_wpusdAmount * _exchangeRate) / stabilityFund.getPrecision();
    }
}