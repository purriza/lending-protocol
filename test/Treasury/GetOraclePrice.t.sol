// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {TestSetup, TreasuryHarness} from "../TestSetup.t.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ITreasury} from "../../contracts/interfaces/ITreasury.sol";
import {IProtocolConfig} from "../../contracts/interfaces/IProtocolConfig.sol";
import {Treasury} from "../../contracts/Treasury.sol";

contract TreasuryGetOraclePriceTest is TestSetup {
    TreasuryHarness public treasuryHarnessImpl;
    TreasuryHarness public treasuryHarness;
    ERC1967Proxy public treasuryHarnessProxy;

    function setUp() public override {
        super.setUp();
    }

    function _deployTreasuryHarness() internal returns (TreasuryHarness) {
        treasuryHarnessImpl = new TreasuryHarness();
        bytes memory data = abi.encodeWithSelector(
            Treasury.initialize.selector,
            address(protocolConfig),
            address(pusd),
            address(wstETH)
        );
        treasuryHarnessProxy = new ERC1967Proxy(address(treasuryHarnessImpl), data);
        return TreasuryHarness(address(treasuryHarnessProxy));
    }

    function _deployAndConfigureTreasuryHarness() internal returns (TreasuryHarness h) {
        vm.startPrank(admin);
        
        h = _deployTreasuryHarness();

        h.grantRole(protocolConfig.ADMIN_ROLE(), admin);
        h.grantRole(protocolConfig.UPGRADER_ROLE(), upgrader);
        h.setLiquidationEngine(address(liquidationEngine));
        h.setLendingVault(address(lendingVault));
        h.setProtocolConfig(address(protocolConfig));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        getOraclePrice TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getOraclePrice_ReturnsDefaultMockValues() public {
        TreasuryHarness h = _deployAndConfigureTreasuryHarness();

        (uint256 price, uint8 decimals_) = h.getOraclePrice();
        assertEq(price, 3000e8);
        assertEq(decimals_, 8);
    }

    function test_getOraclePrice_RevertsIfAnswerNonPositive() public {
        TreasuryHarness h = _deployAndConfigureTreasuryHarness();

        mockOracle.setAnswer(0);
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAmount.selector));
        h.getOraclePrice();
    }

    function test_getOraclePrice_RevertsIfUpdatedAtZero() public {
        TreasuryHarness h = _deployAndConfigureTreasuryHarness();

        mockOracle.setUpdatedAt(0);
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__StaleOraclePrice.selector));
        h.getOraclePrice();
    }

    function test_getOraclePrice_RevertsIfOracleStaleByTime() public {
        TreasuryHarness h = _deployAndConfigureTreasuryHarness();

        mockOracle.setUpdatedAt(block.timestamp);
        vm.prank(admin);
        h.setOracleStaleAfter(1 hours);
        vm.warp(block.timestamp + 1 hours + 1);

        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__StaleOraclePrice.selector));
        h.getOraclePrice();
    }

    function test_getOraclePrice_RevertsIfAnsweredInRoundLessThanRoundId() public {
        TreasuryHarness h = _deployAndConfigureTreasuryHarness();

        mockOracle.setRoundId(2);
        mockOracle.setAnsweredInRound(1);

        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidOracleRound.selector));
        h.getOraclePrice();
    }

    function test_getOraclePrice_RespectsOracleDecimals() public {
        TreasuryHarness h = _deployAndConfigureTreasuryHarness();

        mockOracle.setDecimals(10);
        (uint256 price, uint8 decimals_) = h.getOraclePrice();
        assertEq(price, 3000e8); // price value remains whatever oracle reports
        assertEq(decimals_, 10);
    }
}