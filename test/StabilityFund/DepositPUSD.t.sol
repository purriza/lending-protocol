// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {IStabilityFund} from "../../contracts/interfaces/IStabilityFund.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {console} from "forge-std/console.sol";

contract StabilityFundDepositTest is TestSetup {

    uint256 public lessThanMinDepositAmount = 0.0009 ether;
    uint256 public depositAmount = 1 ether;

    function setUp() public override {
        super.setUp();

        _mintPUSD(user1, INITIAL_PUSD_AMOUNT);
        _mintPUSD(user2, INITIAL_PUSD_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                        STATE UPDATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_depositPUSD_UpdatesTotalPusdLocked() public {
        assertEq(stabilityFund.totalPusdLocked(), 0);

        vm.startPrank(user1);
        pusd.approve(address(stabilityFund), depositAmount);
        stabilityFund.depositPUSD(depositAmount);
        vm.stopPrank();

        assertEq(stabilityFund.totalPusdLocked(), depositAmount);

        vm.startPrank(user2);
        pusd.approve(address(stabilityFund), depositAmount);
        stabilityFund.depositPUSD(depositAmount);
        vm.stopPrank();

        assertEq(stabilityFund.totalPusdLocked(), depositAmount * 2);
    }

    function test_depositPUSD_TransfersPUSDFromUser() public {
        uint256 user1InitialBalance = pusd.balanceOf(user1);
        uint256 initialStabilityFundBalance = pusd.balanceOf(address(stabilityFund));

        assertEq(user1InitialBalance, INITIAL_PUSD_AMOUNT);
        assertEq(initialStabilityFundBalance, 0);

        vm.startPrank(user1);
        pusd.approve(address(stabilityFund), depositAmount);
        stabilityFund.depositPUSD(depositAmount);
        vm.stopPrank();

        assertEq(pusd.balanceOf(user1), user1InitialBalance - depositAmount);
        assertEq(pusd.balanceOf(address(stabilityFund)), initialStabilityFundBalance + depositAmount);
    }

    function test_depositPUSD_MintsAtOneToOneRatioWhenRateIsOne() public {
        uint256 user1InitialWpusdBalance = wpusd.balanceOf(user1);
        assertEq(user1InitialWpusdBalance, 0);

        vm.startPrank(user1);
        pusd.approve(address(stabilityFund), depositAmount);
        uint256 wPUSDMinted = stabilityFund.depositPUSD(depositAmount);
        vm.stopPrank();

        assertEq(wPUSDMinted, depositAmount);
        assertEq(wpusd.balanceOf(user1), user1InitialWpusdBalance + depositAmount);
    }

    function test_depositPUSD_MintsAtCorrectRatioWhenRateIsGreaterThanOne() public {
        uint256 yeildAmount = 1 ether;
        
        uint256 user1InitialWpusdBalance = wpusd.balanceOf(user1);
        assertEq(user1InitialWpusdBalance, 0);

        /** 
            The only way to get the exchange rate to be greater than 1 is to have yield from 
            liquidations sent from the LiquidationEngine to the StabilityFund.
            This is done in the _sendLiquidationFundsAndSwapCollateral function.
        */

        _sendLiquidationFundsAndSwapCollateral(depositAmount, yeildAmount);

        vm.startPrank(address(liquidationEngine));
        pusd.approve(address(stabilityFund), depositAmount + yeildAmount);
        stabilityFund.receiveLiquidationReturns(depositAmount, yeildAmount, 0);
        vm.stopPrank();

        // Exchange rate is now 2:1
        // User 1 deposits 1 PUSD Should receive 0.5 wPUSD
        vm.startPrank(user1);
        pusd.approve(address(stabilityFund), depositAmount);
        uint256 wPUSDMinted = stabilityFund.depositPUSD(depositAmount);
        vm.stopPrank();

        uint256 expectedWPUSDMinted = (depositAmount * 1e18) / stabilityFund.exchangeRate();

        assertEq(wPUSDMinted, expectedWPUSDMinted);
        assertEq(wpusd.balanceOf(user1), user1InitialWpusdBalance + expectedWPUSDMinted);
    }

    function test_depositPUSD_emitsEvent() public {
        vm.startPrank(user1);
        pusd.approve(address(stabilityFund), depositAmount);

        vm.expectEmit(true, false, false, false);
        emit IStabilityFund.PUSDDeposited(user1, depositAmount, depositAmount);
        stabilityFund.depositPUSD(depositAmount);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_depositPUSD_RevertsOnInvalidAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IStabilityFund.StabilityFund__InvalidAmount.selector, lessThanMinDepositAmount));
        vm.prank(user1);
        stabilityFund.depositPUSD(lessThanMinDepositAmount);
    }

    function test_depositPUSD_RevertsWhenPaused() public {
        vm.prank(admin);
        stabilityFund.pause();

        assertTrue(stabilityFund.paused());

        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vm.prank(user1);
        stabilityFund.depositPUSD(1 ether);
    }

    function test_depositPUSD_RevertsWhenInsufficientAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(stabilityFund), 0, depositAmount));
        vm.prank(user1);
        stabilityFund.depositPUSD(depositAmount);
    }

    function test_depositPUSD_RevertsWhenInsufficientBalance() public {
        // User 3 has no balance of PUSD
        vm.startPrank(user3);
        pusd.approve(address(stabilityFund), depositAmount);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, user3, 0, depositAmount));
        stabilityFund.depositPUSD(depositAmount);
        vm.stopPrank();
    }

    function test_depositPUSD_RevertsWhenZeroTokensWouldBeMinted() public {
        // First, create initial wPUSD supply by making a deposit
        uint256 initialDeposit = 1 ether;
        vm.startPrank(user1);
        pusd.approve(address(stabilityFund), initialDeposit);
        stabilityFund.depositPUSD(initialDeposit);
        vm.stopPrank();

        // Now increase exchange rate significantly through liquidation returns
        // We need a yield large enough that even minDepositAmount results in 0 tokens
        uint256 liquidationAmount = initialDeposit;
        
        // Calculate the yield needed to make exchange rate high enough
        // We want: (minDepositAmount * 1e18) / exchangeRate < 1
        // So: exchangeRate > (minDepositAmount * 1e18)
        // minDepositAmount = 1e15, so we need exchangeRate > 1e15 * 1e18 = 1e33
        
        // Current totalPusdLocked = 1 ether = 1e18
        // Current wpusdSupply = 1 ether = 1e18
        // New exchange rate = (totalPusdLocked + yield) * 1e18 / wpusdSupply
        // We want: (1e18 + yield) * 1e18 / 1e18 > 1e33
        // So: 1e18 + yield > 1e33
        // Therefore: yield > 1e33 - 1e18 ≈ 1e33
        
        uint256 massiveYield = 1e33; // This creates an exchange rate > 1e33
        
        _sendLiquidationFundsAndSwapCollateral(liquidationAmount, massiveYield);
        
        vm.startPrank(address(liquidationEngine));
        pusd.approve(address(stabilityFund), liquidationAmount + massiveYield);
        stabilityFund.receiveLiquidationReturns(liquidationAmount, massiveYield, 0);
        vm.stopPrank();

        // Now try to deposit the minimum amount - this should result in 0 tokens
        uint256 minDeposit = stabilityFund.getMinDepositAmount(); // 0.001 ether = 1e15
        
        // User2 attempts to deposit minimum amount
        vm.startPrank(user2);
        pusd.approve(address(stabilityFund), minDeposit);
        
        // This should revert because wpusdToMint would be 0
        // Calculation: (1e15 * 1e18) / (very_large_exchange_rate) = 0 (due to integer division)
        vm.expectRevert(abi.encodeWithSelector(IStabilityFund.StabilityFund__InvalidAmount.selector, 0));
        stabilityFund.depositPUSD(minDeposit);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_depositPUSD_returnsCorrectAmountOfWPUSDMinted(uint256 _depositAmount) public {
        _depositAmount = bound(_depositAmount, stabilityFund.getMinDepositAmount(), INITIAL_PUSD_AMOUNT);

        vm.startPrank(user1);
        pusd.approve(address(stabilityFund), _depositAmount);
        uint256 wPUSDMinted = stabilityFund.depositPUSD(_depositAmount);
        vm.stopPrank();

        assertEq(wPUSDMinted, _depositAmount);
    }
}