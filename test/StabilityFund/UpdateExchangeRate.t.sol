// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TestSetup, StabilityFundHarness} from "../TestSetup.t.sol";
import {StabilityFund} from "../../contracts/StabilityFund.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IStabilityFund} from "../../contracts/interfaces/IStabilityFund.sol";

contract UpdateExchangeRateTest is TestSetup {
    StabilityFundHarness public stabilityFundHarnessImpl;
    StabilityFundHarness public stabilityFundHarness;
    ERC1967Proxy public stabilityFundHarnessProxy;

    function setUp() public override {
        super.setUp();

        stabilityFundHarness = _deployHarness();

         _mintPUSD(address(user1), LIQUIDATION_AMOUNT);

        // Make sure that the totalPusdLocked is non-zero and that there is a wPUSD supply
        vm.startPrank(user1);
        pusd.approve(address(stabilityFund), LIQUIDATION_AMOUNT);
        stabilityFund.depositPUSD(LIQUIDATION_AMOUNT);
        vm.stopPrank();
    }

    function test_ReceiveLiquidationReturns_UpdatesExchangeRate() public {
        _sendLiquidationFundsAndSwapCollateral(LIQUIDATION_AMOUNT, YIELD_AMOUNT);

        assertEq(stabilityFund.exchangeRate(), 1e18);

         // Have the LiquidationEngine send the returns to the StabilityFund
        vm.startPrank(address(liquidationEngine));
        pusd.approve(address(stabilityFund), LIQUIDATION_AMOUNT + YIELD_AMOUNT);
        uint256 amountReceived = stabilityFund.receiveLiquidationReturns(LIQUIDATION_AMOUNT, YIELD_AMOUNT, 0);
        vm.stopPrank(); 

        // Verify the return value is correct
        assertEq(amountReceived, LIQUIDATION_AMOUNT + YIELD_AMOUNT, "Should return total amount received");

        uint256 expectedExchangeRate = stabilityFund.totalPusdLocked() * stabilityFund.getPrecision() / wpusd.totalSupply();
        assertEq(stabilityFund.exchangeRate(), expectedExchangeRate);
    }

    function test_updateExchangeRate_updatesExchangeRate() public {
        assertEq(stabilityFundHarness.exchangeRate(), 1e18);

        uint256 newExchangeRate = 2 ether;
        stabilityFundHarness.updateExchangeRate(newExchangeRate);

        assertEq(stabilityFundHarness.exchangeRate(), newExchangeRate);
    }

    /*//////////////////////////////////////////////////////////////
                            EVENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_updateExchangeRate_emitsEvent() public {
        _sendLiquidationFundsAndSwapCollateral(LIQUIDATION_AMOUNT, YIELD_AMOUNT);

        uint256 initialExchangeRate = stabilityFund.exchangeRate();
        uint256 expectedExchangeRate = (LIQUIDATION_AMOUNT + YIELD_AMOUNT) * stabilityFund.getPrecision() / wpusd.totalSupply();

        vm.startPrank(address(liquidationEngine));
        pusd.approve(address(stabilityFund), LIQUIDATION_AMOUNT + YIELD_AMOUNT);
        vm.expectEmit(true, true, true, true);
        emit IStabilityFund.ExchangeRateUpdated(initialExchangeRate, expectedExchangeRate, block.timestamp);
        stabilityFund.receiveLiquidationReturns(LIQUIDATION_AMOUNT, YIELD_AMOUNT, 0);
        vm.stopPrank(); 
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _deployHarness() internal returns (StabilityFundHarness) {
        stabilityFundHarnessImpl = new StabilityFundHarness();
        bytes memory stabilityFundHarnessData = abi.encodeWithSelector(
            StabilityFund.initialize.selector,
            address(protocolConfig),
            address(pusd),
            address(wpusd)
        );
        stabilityFundHarnessProxy = new ERC1967Proxy(
            address(stabilityFundHarnessImpl),
            stabilityFundHarnessData
        );
        return StabilityFundHarness(address(stabilityFundHarnessProxy));
    }
}