// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {IProtocolConfig} from "../../contracts/interfaces/IProtocolConfig.sol";
import {ProtocolConfig} from "../../contracts/ProtocolConfig.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ProtocolConfigGettersTest is TestSetup {
    
    /*//////////////////////////////////////////////////////////////
                                 GETTERS
    //////////////////////////////////////////////////////////////*/

    function test_Getters_InitialValues() public view {
        assertEq(protocolConfig.hasRole(protocolConfig.ADMIN_ROLE(), admin), true, "admin should have ADMIN_ROLE");
        assertEq(protocolConfig.hasRole(protocolConfig.UPGRADER_ROLE(), upgrader), true, "upgrader should have UPGRADER_ROLE");
        assertEq(address(protocolConfig.oracle()), address(mockOracle), "oracle should match");
        assertEq(protocolConfig.liquidationThreshold(), 12_000, "liquidationThreshold should be 120%");
        assertEq(protocolConfig.minCollateralRatio(), 12_000, "minCollateralRatio should be 120%");
        assertEq(protocolConfig.debtCeiling(), 100_000_000 ether, "debtCeiling should be 100M");
        assertEq(protocolConfig.minDebt(), 500 ether, "minDebt should be 500 ether (default value)");
        assertEq(protocolConfig.closeFactorBps(), 5_000, "closeFactorBps should be 50%");
        assertEq(protocolConfig.liquidationBonusBps(), 1_000, "liquidationBonusBps should be 10%");
        assertEq(protocolConfig.uniswapFee(), 3_000, "uniswapFee should be 30%");
        assertEq(protocolConfig.MAX_BPS(), 10_000, "MAX_BPS should be 10_000");
    }

    function test_Getters_SecurityConstraintConstants() public view {
        // Test all security constraint constants
        assertEq(protocolConfig.MAX_BPS(), 10_000, "MAX_BPS should be 10,000 (100%)");
        assertEq(protocolConfig.MAX_LIQUIDATION_THRESHOLD(), 50_000, "MAX_LIQUIDATION_THRESHOLD should be 50,000 (500%)");
        assertEq(protocolConfig.MANDATORY_BUFFER_BPS(), 3_000, "MANDATORY_BUFFER_BPS should be 3,000 (30%)");
        assertEq(protocolConfig.MIN_CLOSE_FACTOR_BPS(), 500, "MIN_CLOSE_FACTOR_BPS should be 500 (5%)");
        assertEq(protocolConfig.MIN_LIQUIDATION_BONUS_BPS(), 100, "MIN_LIQUIDATION_BONUS_BPS should be 100 (1%)");
        assertEq(protocolConfig.MAX_LIQUIDATION_BONUS_BPS(), 3_000, "MAX_LIQUIDATION_BONUS_BPS should be 3,000 (30%)");
    }

    function test_Getters_AfterSetters() public {
        // Set new values
        address newOracle = address(0x123);
        address newCollateral = address(0x789);
        address newTreasuryWallet = address(0x321);
        uint256 newMinDebt = 1000 ether;
        uint256 newLiquidationThreshold = 9000; // 90%
        uint256 newMinCollateralRatio = 15000; // 150%
        uint256 newCloseFactorBps = 7500; // 75%
        uint256 newLiquidationBonusBps = 1500; // 15%
        uint256 newUniswapFee = 1000; // 0.1%
        uint256 newDebtCeiling = 2000000 ether; // 2M

        vm.startPrank(admin);
        protocolConfig.setOracle(newOracle);
        protocolConfig.setCollateralToken(newCollateral);
        protocolConfig.setTreasuryWallet(newTreasuryWallet);
        protocolConfig.setMinDebt(newMinDebt);
        protocolConfig.setLiquidationThreshold(newLiquidationThreshold);
        protocolConfig.setMinCollateralRatio(newMinCollateralRatio);
        protocolConfig.setCloseFactorBps(newCloseFactorBps);
        protocolConfig.setLiquidationBonusBps(newLiquidationBonusBps);
        protocolConfig.setUniswapFee(newUniswapFee);
        protocolConfig.setDebtCeiling(newDebtCeiling);
        vm.stopPrank();

        // Test updated values
        assertEq(address(protocolConfig.oracle()), newOracle, "oracle should be updated");
        assertEq(protocolConfig.collateralToken(), newCollateral, "collateralToken should be updated");
        assertEq(protocolConfig.treasuryWallet(), newTreasuryWallet, "treasuryWallet should be updated");
        assertEq(protocolConfig.minDebt(), newMinDebt, "minDebt should be updated");
        assertEq(protocolConfig.liquidationThreshold(), newLiquidationThreshold, "liquidationThreshold should be updated");
        assertEq(protocolConfig.minCollateralRatio(), newMinCollateralRatio, "minCollateralRatio should be updated");
        assertEq(protocolConfig.closeFactorBps(), newCloseFactorBps, "closeFactorBps should be updated");
        assertEq(protocolConfig.liquidationBonusBps(), newLiquidationBonusBps, "liquidationBonusBps should be updated");
        assertEq(protocolConfig.uniswapFee(), newUniswapFee, "uniswapFee should be updated");
        assertEq(protocolConfig.debtCeiling(), newDebtCeiling, "debtCeiling should be updated");
    }

    /*//////////////////////////////////////////////////////////////
                            BOUNDARY VALUES
    //////////////////////////////////////////////////////////////*/

    function test_Getters_BoundaryValues() public {
        vm.startPrank(admin);
        
        // Test minimum values with proper validation constraints
        protocolConfig.setLiquidationThreshold(7000); // 70% - allows minimum minCollateralRatio with 30% buffer
        protocolConfig.setMinCollateralRatio(10000); // Minimum 100%
        protocolConfig.setCloseFactorBps(500); // Minimum 5%
        protocolConfig.setLiquidationBonusBps(100); // Minimum 1%
        protocolConfig.setMinDebt(1); // Minimum 1
        protocolConfig.setDebtCeiling(1); // Minimum 1
        
        assertEq(protocolConfig.liquidationThreshold(), 7000, "should handle minimum liquidationThreshold with buffer");
        assertEq(protocolConfig.minCollateralRatio(), 10000, "should handle minimum minCollateralRatio");
        assertEq(protocolConfig.closeFactorBps(), 500, "should handle minimum closeFactorBps");
        assertEq(protocolConfig.liquidationBonusBps(), 100, "should handle minimum liquidationBonusBps");
        assertEq(protocolConfig.minDebt(), 1, "should handle minimum minDebt");
        assertEq(protocolConfig.debtCeiling(), 1, "should handle minimum debtCeiling");
        
        // Test maximum values with proper constraints
        protocolConfig.setMinCollateralRatio(53000); // 530% - allows maximum liquidationThreshold with 30% buffer
        protocolConfig.setLiquidationThreshold(50000); // Maximum 500%
        protocolConfig.setCloseFactorBps(10000); // Maximum 100%
        protocolConfig.setLiquidationBonusBps(3000); // Maximum 30%
        protocolConfig.setMinDebt(type(uint256).max); // Maximum uint256
        protocolConfig.setDebtCeiling(type(uint256).max); // Maximum uint256
        
        assertEq(protocolConfig.liquidationThreshold(), 50000, "should handle maximum liquidationThreshold");
        assertEq(protocolConfig.closeFactorBps(), 10000, "should handle maximum closeFactorBps");
        assertEq(protocolConfig.liquidationBonusBps(), 3000, "should handle maximum liquidationBonusBps");
        assertEq(protocolConfig.minDebt(), type(uint256).max, "should handle maximum minDebt");
        assertEq(protocolConfig.debtCeiling(), type(uint256).max, "should handle maximum debtCeiling");
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        SECURITY CONSTRAINT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Getters_SecurityConstraintRelationships() public view {
        // Test that constants maintain logical relationships
        assertTrue(protocolConfig.MIN_CLOSE_FACTOR_BPS() > 0, "MIN_CLOSE_FACTOR_BPS must be greater than 0");
        assertTrue(protocolConfig.MIN_CLOSE_FACTOR_BPS() <= protocolConfig.MAX_BPS(), "MIN_CLOSE_FACTOR_BPS must be <= MAX_BPS");
        
        assertTrue(protocolConfig.MIN_LIQUIDATION_BONUS_BPS() > 0, "MIN_LIQUIDATION_BONUS_BPS must be greater than 0");
        assertTrue(protocolConfig.MAX_LIQUIDATION_BONUS_BPS() <= protocolConfig.MAX_BPS(), "MAX_LIQUIDATION_BONUS_BPS must be <= MAX_BPS");
        assertTrue(protocolConfig.MIN_LIQUIDATION_BONUS_BPS() < protocolConfig.MAX_LIQUIDATION_BONUS_BPS(), "MIN must be < MAX for liquidation bonus");
        
        assertTrue(protocolConfig.MANDATORY_BUFFER_BPS() > 0, "MANDATORY_BUFFER_BPS must be greater than 0");
        assertTrue(protocolConfig.MANDATORY_BUFFER_BPS() < protocolConfig.MAX_BPS(), "MANDATORY_BUFFER_BPS must be < MAX_BPS");
        
        assertTrue(protocolConfig.MAX_LIQUIDATION_THRESHOLD() > protocolConfig.MAX_BPS(), "MAX_LIQUIDATION_THRESHOLD allows over 100%");
    }

    function test_Getters_SecurityConstraintBoundaries() public view {
        // Test specific boundary values match our security requirements
        assertEq(protocolConfig.MIN_CLOSE_FACTOR_BPS(), 500, "5% minimum close factor for partial liquidations");
        assertEq(protocolConfig.MIN_LIQUIDATION_BONUS_BPS(), 100, "1% minimum bonus to incentivize liquidators");
        assertEq(protocolConfig.MAX_LIQUIDATION_BONUS_BPS(), 3000, "30% maximum bonus to protect borrowers");
        assertEq(protocolConfig.MANDATORY_BUFFER_BPS(), 3000, "30% mandatory buffer between ratios");
        assertEq(protocolConfig.MAX_LIQUIDATION_THRESHOLD(), 50000, "500% maximum liquidation threshold");
    }
}
