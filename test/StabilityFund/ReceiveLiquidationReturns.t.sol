// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {IStabilityFund} from "../../contracts/interfaces/IStabilityFund.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract ReceiveLiquidationReturnsTest is TestSetup {

    function setUp() public override {
        super.setUp();

        _mintPUSD(address(user1), LIQUIDATION_AMOUNT);

        // Make sure that the totalPusdLocked is non-zero and that there is a wPUSD supply
        vm.startPrank(user1);
        pusd.approve(address(stabilityFund), LIQUIDATION_AMOUNT);
        stabilityFund.depositPUSD(LIQUIDATION_AMOUNT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    function test_ReceiveLiquidationReturns_UpdatesState() public {
        _sendLiquidationFundsAndSwapCollateral(LIQUIDATION_AMOUNT, YIELD_AMOUNT);

        assertEq(stabilityFund.totalPusdLocked(), LIQUIDATION_AMOUNT);
        assertEq(wpusd.totalSupply(), LIQUIDATION_AMOUNT);

        // the stability fund should have no PUSD as it should be "in-transit"
        assertEq(pusd.balanceOf(address(stabilityFund)), 0);

        // Have the LiquidationEngine send the returns to the StabilityFund
        vm.startPrank(address(liquidationEngine));
        pusd.approve(address(stabilityFund), LIQUIDATION_AMOUNT + YIELD_AMOUNT);
        uint256 amountReceived = stabilityFund.receiveLiquidationReturns(LIQUIDATION_AMOUNT, YIELD_AMOUNT, 0);
        vm.stopPrank(); 

        // Verify the return value is correct
        assertEq(amountReceived, LIQUIDATION_AMOUNT + YIELD_AMOUNT, "Should return total amount received");

        assertEq(stabilityFund.totalPusdLocked(), LIQUIDATION_AMOUNT + YIELD_AMOUNT);
        assertEq(wpusd.totalSupply(), LIQUIDATION_AMOUNT);

        assertEq(pusd.balanceOf(address(stabilityFund)), LIQUIDATION_AMOUNT + YIELD_AMOUNT);
        assertEq(pusd.balanceOf(address(liquidationEngine)), 0);
        assertEq(pusd.balanceOf(address(stabilityFund)), stabilityFund.totalPusdLocked());
    }

    function test_ReceiveLiquidationReturns_UpdatesExchangeRate() public {
        _sendLiquidationFundsAndSwapCollateral(LIQUIDATION_AMOUNT, YIELD_AMOUNT);

        assertEq(stabilityFund.exchangeRate(), 1e18);

        assertEq(stabilityFund.totalPusdLocked(), LIQUIDATION_AMOUNT);
        assertEq(wpusd.totalSupply(), LIQUIDATION_AMOUNT);

        // Have the LiquidationEngine send the returns to the StabilityFund
        vm.startPrank(address(liquidationEngine));
        pusd.approve(address(stabilityFund), LIQUIDATION_AMOUNT + YIELD_AMOUNT);
        uint256 amountReceived =  stabilityFund.receiveLiquidationReturns(LIQUIDATION_AMOUNT, YIELD_AMOUNT, 0);
        vm.stopPrank(); 

        // Verify the return value is correct
        assertEq(amountReceived, LIQUIDATION_AMOUNT + YIELD_AMOUNT, "Should return total amount received");
        
        assertEq(stabilityFund.totalPusdLocked(), LIQUIDATION_AMOUNT + YIELD_AMOUNT);
        assertEq(wpusd.totalSupply(), LIQUIDATION_AMOUNT);

        uint256 expectedExchangeRate = stabilityFund.totalPusdLocked() * stabilityFund.getPrecision() / wpusd.totalSupply();
        assertEq(stabilityFund.exchangeRate(), expectedExchangeRate);
    }

    function test_ReceiveLiquidationReturns_DoesNotUpdateState_WhenNoYield() public {
        _sendLiquidationFundsAndSwapCollateral(LIQUIDATION_AMOUNT, 0);

        uint256 currentExchangeRate = stabilityFund.exchangeRate();
        assertEq(currentExchangeRate, 1e18);

        assertEq(stabilityFund.totalPusdLocked(), LIQUIDATION_AMOUNT);
        assertEq(wpusd.totalSupply(), LIQUIDATION_AMOUNT);

        // Have the LiquidationEngine send the returns to the StabilityFund
        vm.startPrank(address(liquidationEngine));
        pusd.approve(address(stabilityFund), LIQUIDATION_AMOUNT);
        uint256 amountReceived = stabilityFund.receiveLiquidationReturns(LIQUIDATION_AMOUNT, 0, 0);
        vm.stopPrank();

        // Verify the return value is correct
        assertEq(amountReceived, LIQUIDATION_AMOUNT, "Should return principal amount");

        assertEq(stabilityFund.totalPusdLocked(), LIQUIDATION_AMOUNT);
        assertEq(wpusd.totalSupply(), LIQUIDATION_AMOUNT);

        assertEq(stabilityFund.exchangeRate(), currentExchangeRate);

        assertEq(pusd.balanceOf(address(stabilityFund)), LIQUIDATION_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                            EVENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ReceiveLiquidationReturns_EmitsEvent() public {
        _sendLiquidationFundsAndSwapCollateral(LIQUIDATION_AMOUNT, YIELD_AMOUNT);

        vm.startPrank(address(liquidationEngine));
        pusd.approve(address(stabilityFund), LIQUIDATION_AMOUNT + YIELD_AMOUNT);

        vm.expectEmit(false, true, true, true);
        emit IStabilityFund.LiquidationReturnsReceived(
            address(liquidationEngine), LIQUIDATION_AMOUNT, YIELD_AMOUNT, LIQUIDATION_AMOUNT + YIELD_AMOUNT
        );
        stabilityFund.receiveLiquidationReturns(LIQUIDATION_AMOUNT, YIELD_AMOUNT, 0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ReceiveLiquidationReturns_RevertsIfBothAmountsAreZero() public {
        _sendLiquidationFundsAndSwapCollateral(LIQUIDATION_AMOUNT, YIELD_AMOUNT);

        vm.startPrank(address(liquidationEngine));
        vm.expectRevert(abi.encodeWithSelector(IStabilityFund.StabilityFund__InvalidAmount.selector, 0));
        stabilityFund.receiveLiquidationReturns(0, 0, 0);
        vm.stopPrank();
    }

    function test_ReceiveLiquidationReturns_AllowsPUSDAmountZero_WhenExcessAmountGreaterThanZero() public {
        _sendLiquidationFundsAndSwapCollateral(LIQUIDATION_AMOUNT, YIELD_AMOUNT);

        // Capture initial state
        uint256 initialTotalLocked = stabilityFund.totalPusdLocked();
        uint256 initialContractBalance = pusd.balanceOf(address(stabilityFund));

        // Send only excess (profits) with _pusdAmount = 0
        vm.startPrank(address(liquidationEngine));
        pusd.approve(address(stabilityFund), YIELD_AMOUNT);
        uint256 amountReceived = stabilityFund.receiveLiquidationReturns(0, YIELD_AMOUNT, 0);
        vm.stopPrank();

        // Verify the call succeeded
        assertEq(amountReceived, YIELD_AMOUNT, "Should return excess amount");

        // Verify state updates
        assertEq(stabilityFund.totalPusdLocked(), initialTotalLocked + YIELD_AMOUNT);

        // Verify state updates
        assertEq(pusd.balanceOf(address(stabilityFund)), initialContractBalance + YIELD_AMOUNT);

        // Verify exchange rate was updated
        uint256 expectedExchangeRate = (initialTotalLocked + YIELD_AMOUNT) * stabilityFund.getPrecision() / wpusd.totalSupply();
        assertEq(stabilityFund.exchangeRate(), expectedExchangeRate);
    }

    function test_ReceiveLiquidationReturns_AllowsExcessAmountZero_WhenPUSDAmountGreaterThanZero() public {
        _sendLiquidationFundsAndSwapCollateral(LIQUIDATION_AMOUNT, 0);

        // Capture initial state
        uint256 initialTotalLocked = stabilityFund.totalPusdLocked();
        uint256 initialContractBalance = pusd.balanceOf(address(stabilityFund));

        // Send only principal with _excessAmount = 0
        vm.startPrank(address(liquidationEngine));
        pusd.approve(address(stabilityFund), LIQUIDATION_AMOUNT);
        uint256 amountReceived = stabilityFund.receiveLiquidationReturns(LIQUIDATION_AMOUNT, 0, 0);
        vm.stopPrank();

        // Verify the call succeeded
        assertEq(amountReceived, LIQUIDATION_AMOUNT, "Should return principal amount");
        assertEq(stabilityFund.totalPusdLocked(), initialTotalLocked); // Should remain unchanged
        assertEq(pusd.balanceOf(address(stabilityFund)), initialContractBalance + LIQUIDATION_AMOUNT);

        // Verify exchange rate was NOT updated (no yield)
        assertEq(stabilityFund.exchangeRate(), 1e18);
    }

    function test_ReceiveLiquidationReturns_AllowsBothAmountsGreaterThanZero() public {
        _sendLiquidationFundsAndSwapCollateral(LIQUIDATION_AMOUNT, YIELD_AMOUNT);

        // Capture initial state
        uint256 initialTotalLocked = stabilityFund.totalPusdLocked();
        uint256 initialContractBalance = pusd.balanceOf(address(stabilityFund));

        // Send both principal and excess
        vm.startPrank(address(liquidationEngine));
        pusd.approve(address(stabilityFund), LIQUIDATION_AMOUNT + YIELD_AMOUNT);
        uint256 amountReceived = stabilityFund.receiveLiquidationReturns(LIQUIDATION_AMOUNT, YIELD_AMOUNT, 0);
        vm.stopPrank();

        // Verify the call succeeded
        assertEq(amountReceived, LIQUIDATION_AMOUNT + YIELD_AMOUNT, "Should return total amount");
        assertEq(stabilityFund.totalPusdLocked(), initialTotalLocked + YIELD_AMOUNT);

        // Verify state updates
        assertEq(pusd.balanceOf(address(stabilityFund)), initialContractBalance + LIQUIDATION_AMOUNT + YIELD_AMOUNT);

        // Verify exchange rate was updated
        uint256 expectedExchangeRate = (initialTotalLocked + YIELD_AMOUNT) * stabilityFund.getPrecision() / wpusd.totalSupply();
        assertEq(stabilityFund.exchangeRate(), expectedExchangeRate);
    }

    function test_ReceiveLiquidationReturns_RevertsOnUnauthorizedCaller() public {
        _sendLiquidationFundsAndSwapCollateral(LIQUIDATION_AMOUNT, YIELD_AMOUNT);

        vm.startPrank(address(user1));
        vm.expectRevert(abi.encodeWithSelector(IStabilityFund.StabilityFund__UnauthorizedCaller.selector, address(user1)));
        stabilityFund.receiveLiquidationReturns(LIQUIDATION_AMOUNT, YIELD_AMOUNT, 0);
        vm.stopPrank();
    }

    function test_ReceiveLiquidationReturns_RevertsWhenPaused() public {
        _sendLiquidationFundsAndSwapCollateral(LIQUIDATION_AMOUNT, YIELD_AMOUNT);

        vm.prank(admin);
        stabilityFund.pause();

        vm.startPrank(address(liquidationEngine));
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        stabilityFund.receiveLiquidationReturns(LIQUIDATION_AMOUNT, YIELD_AMOUNT, 0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_ReceiveLiquidationReturns(uint256 _liquidationAmount, uint256 _yieldAmount) public {
        _liquidationAmount = bound(_liquidationAmount, 1, LIQUIDATION_AMOUNT);
        _yieldAmount = bound(_yieldAmount, 0, YIELD_AMOUNT);

        // Capture initial state
        uint256 initialTotalLocked = stabilityFund.totalPusdLocked();
        uint256 initialContractBalance = pusd.balanceOf(address(stabilityFund));

        // Send liquidation funds
        vm.prank(address(lendingVault));
        uint256 actualSentAmount = stabilityFund.sendLiquidationFunds(_liquidationAmount);

        // Verify state after sending funds
        assertEq(stabilityFund.totalPusdLocked(), initialTotalLocked); // Should remain unchanged (in-transit)
        assertEq(pusd.balanceOf(address(stabilityFund)), initialContractBalance - actualSentAmount);

        // Mock the Liquidation engine swapping the users seized collateral for more PUSD than was requested
        // The returned base amount should match what was actually sent
        _mintPUSD(address(liquidationEngine), actualSentAmount + _yieldAmount);

        // Return liquidation funds with yield
        vm.startPrank(address(liquidationEngine));
        pusd.approve(address(stabilityFund), actualSentAmount + _yieldAmount);
        uint256 amountReceived = stabilityFund.receiveLiquidationReturns(actualSentAmount, _yieldAmount, 0);
        vm.stopPrank();

        // Verify the return value is correct
        assertEq(amountReceived, actualSentAmount + _yieldAmount, "Should return total amount received");

        // Verify final state
        uint256 finalTotalLocked = stabilityFund.totalPusdLocked();
        uint256 finalContractBalance = pusd.balanceOf(address(stabilityFund));

        // totalPusdLocked should equal: initial + yield (contract only adds yield since base amount was never subtracted)
        uint256 expectedTotalLocked = initialTotalLocked + _yieldAmount;
        assertEq(finalTotalLocked, expectedTotalLocked);

        // Contract balance should equal: initial - sentAmount + (actualSentAmount + yield) = initial + yield
        uint256 expectedContractBalance = initialContractBalance - actualSentAmount + (actualSentAmount + _yieldAmount);
        assertEq(finalContractBalance, expectedContractBalance);

        // Both should be equal: initial + yield (this verifies the accounting invariant)
        assertEq(finalTotalLocked, finalContractBalance);

        // Verify exchange rate calculation
        uint256 expectedExchangeRate = finalTotalLocked * stabilityFund.getPrecision() / wpusd.totalSupply();
        assertEq(stabilityFund.exchangeRate(), expectedExchangeRate);

        // After a complete liquidation cycle, totalPusdLocked should ALWAYS equal contract balance
        assertEq(finalContractBalance, finalTotalLocked);
    }
}