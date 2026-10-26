// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TestSetup} from "../TestSetup.t.sol";

import {LiquidationEngine} from "../../contracts/LiquidationEngine.sol";
import {ILiquidationEngine} from "../../contracts/interfaces/ILiquidationEngine.sol";
import {ILendingVault} from "../../contracts/interfaces/ILendingVault.sol";
import {DataTypes} from "../../contracts/DataTypes.sol";

contract LiquidationEngineOracleStalenessTest is TestSetup {

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();
        
        // Setup StabilityFund and Treasury with liquidity
        _setupStabilityFundForLiquidation();
        _setupTreasuryForLiquidation();
        
        // Setup user1 with a position
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL);
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();
        
        // Configure liquidation bot
        vm.prank(admin);
        lendingVault.setLiquidationBot(admin, true);
    }

    /*//////////////////////////////////////////////////////////////
                        ORACLE STALENESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LiquidationEngine_Staleness_RevertsOnExecuteLiquidation() public {
        // First make the position liquidatable by dropping price
        _makePositionLiquidatable();
        
        // Set oracle to a specific old timestamp
        uint256 oracleUpdateTime = 100;
        mockOracle.setUpdatedAt(oracleUpdateTime);
        
        // Warp to a time that makes the oracle stale
        uint256 maxStaleness = protocolConfig.maxStaleness();
        vm.warp(oracleUpdateTime + maxStaleness + 1);

        // Attempt to liquidate should revert with StaleOraclePrice (from LendingVault during initial checks)
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__StaleOraclePrice.selector));
        lendingVault.liquidatePosition(user1);
        vm.stopPrank();
    }

    function test_LiquidationEngine_Staleness_AllowsFreshPrice() public {
        // Make position liquidatable (oracle is fresh from setup)
        _makePositionLiquidatable();

        // Liquidation should succeed with fresh price
        vm.prank(admin);
        ILendingVault.LiquidationResult memory result = lendingVault.liquidatePosition(user1);

        // Verify liquidation was successful
        assertGt(result.debtRepaid, 0, "Debt should have been repaid with fresh oracle price");
        assertGt(result.collateralSeized, 0, "Collateral should have been seized with fresh oracle price");
    }

    function test_LiquidationEngine_Staleness_ExactlyAtThreshold() public {
        // Make position liquidatable
        _makePositionLiquidatable();
        
        // Warp to future time
        uint256 maxStaleness = protocolConfig.maxStaleness();
        uint256 futureTime = block.timestamp + 10000;
        vm.warp(futureTime);
        
        // Set oracle timestamp to exactly maxStaleness ago
        mockOracle.setUpdatedAt(futureTime - maxStaleness);

        // Should succeed at exactly the threshold
        vm.prank(admin);
        ILendingVault.LiquidationResult memory result = lendingVault.liquidatePosition(user1);

        assertGt(result.debtRepaid, 0, "Should succeed at exactly maxStaleness threshold");
    }

    function test_LiquidationEngine_Staleness_ConfigurableThreshold() public {
        // Change maxStaleness to a shorter period
        vm.prank(admin);
        protocolConfig.setMaxStaleness(60); // 1 minute

        // Make position liquidatable
        _makePositionLiquidatable();
        
        // Set oracle to a specific old timestamp
        uint256 oracleUpdateTime = 100;
        mockOracle.setUpdatedAt(oracleUpdateTime);
        
        // Warp to a time that makes the oracle stale with new threshold (61 seconds later)
        vm.warp(oracleUpdateTime + 61);

        // Should revert with new shorter staleness period (from LendingVault during initial checks)
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__StaleOraclePrice.selector));
        lendingVault.liquidatePosition(user1);
        vm.stopPrank();

        // Update oracle to current timestamp
        mockOracle.setUpdatedAt(block.timestamp);

        // Now should succeed
        vm.prank(admin);
        ILendingVault.LiquidationResult memory result = lendingVault.liquidatePosition(user1);

        assertGt(result.debtRepaid, 0, "Should succeed after oracle update");
    }

    function test_LiquidationEngine_Staleness_OnlyInOracleUsage() public {
        // Make position liquidatable with fresh oracle
        _makePositionLiquidatable();

        // Verify isLiquidatable works with fresh oracle
        bool liquidatable = lendingVault.isLiquidatable(user1);
        assertTrue(liquidatable, "Position should be liquidatable with fresh oracle");

        // Set oracle to a specific old timestamp
        uint256 oracleUpdateTime = 100;
        mockOracle.setUpdatedAt(oracleUpdateTime);
        
        // Warp to a time that makes the oracle stale
        uint256 maxStaleness = protocolConfig.maxStaleness();
        vm.warp(oracleUpdateTime + maxStaleness + 1);

        // isLiquidatable should revert with stale oracle (it calls getPositionHealthRatio which uses oracle)
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__StaleOraclePrice.selector));
        lendingVault.isLiquidatable(user1);
    }

    function test_LiquidationEngine_Staleness_MultipleLiquidationsWithStaleness() public {
        // Setup second user
        vm.startPrank(user2);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL);
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();

        // Make both positions liquidatable
        _makePositionLiquidatable();

        // Set oracle to a specific old timestamp
        uint256 oracleUpdateTime = 100;
        mockOracle.setUpdatedAt(oracleUpdateTime);
        
        // Warp to a time that makes the oracle stale
        uint256 maxStaleness = protocolConfig.maxStaleness();
        vm.warp(oracleUpdateTime + maxStaleness + 1);

        // Both liquidations should fail with stale oracle (from LendingVault during initial checks)
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__StaleOraclePrice.selector));
        lendingVault.liquidatePosition(user1);

        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__StaleOraclePrice.selector));
        lendingVault.liquidatePosition(user2);
        vm.stopPrank();

        // Update oracle to current timestamp
        mockOracle.setUpdatedAt(block.timestamp);

        // Now both should succeed
        vm.startPrank(admin);
        ILendingVault.LiquidationResult memory result1 = lendingVault.liquidatePosition(user1);
        ILendingVault.LiquidationResult memory result2 = lendingVault.liquidatePosition(user2);
        vm.stopPrank();

        assertGt(result1.debtRepaid, 0, "First liquidation should succeed");
        assertGt(result2.debtRepaid, 0, "Second liquidation should succeed");
    }

    function test_LiquidationEngine_Staleness_InExecuteLiquidation() public {
        // Make position liquidatable with fresh oracle
        _makePositionLiquidatable();
        mockOracle.setUpdatedAt(block.timestamp);
        
        // Set oracle to stale BEFORE liquidation attempt
        uint256 oracleUpdateTime = 100;
        mockOracle.setUpdatedAt(oracleUpdateTime);
        
        // Warp to a time that makes the oracle stale
        uint256 maxStaleness = protocolConfig.maxStaleness();
        vm.warp(oracleUpdateTime + maxStaleness + 1);

        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__StaleOraclePrice.selector));
        lendingVault.liquidatePosition(user1);
        vm.stopPrank();
        
        // Update oracle to fresh and try again - this will execute the full path
        mockOracle.setUpdatedAt(block.timestamp);
        
        vm.prank(admin);
        ILendingVault.LiquidationResult memory result = lendingVault.liquidatePosition(user1);
        assertGt(result.debtRepaid, 0, "Liquidation should succeed with fresh oracle");
    }

    function test_LiquidationEngine_Staleness_DirectCall() public {
        // Setup a valid liquidation order with minimal values
        DataTypes.LiquidationOrder memory order;
        order.debtor = user1;
        order.collateralToSell = 1 ether;
        order.debtPaidBySF = 500 ether;
        order.debtPaidByTreasury = 0;
        
        // Mint collateral to LendingVault
        wstETH.mint(address(lendingVault), order.collateralToSell);
        
        // Approve LiquidationEngine to take collateral
        vm.prank(address(lendingVault));
        wstETH.approve(address(liquidationEngine), order.collateralToSell);
        
        // Use helper to setup StabilityFund with PUSD
        _mintPUSD(address(stabilityFund), order.debtPaidBySF);
        
        // Set oracle to stale
        uint256 oracleUpdateTime = 100;
        mockOracle.setUpdatedAt(oracleUpdateTime);
        uint256 maxStaleness = protocolConfig.maxStaleness();
        vm.warp(oracleUpdateTime + maxStaleness + 1);
        
        // Execute liquidation with stale oracle - expect the staleness check to revert
        vm.prank(address(lendingVault));
        vm.expectRevert(abi.encodeWithSelector(ILiquidationEngine.LiquidationEngine__StaleOraclePrice.selector));
        liquidationEngine.executeLiquidation(order);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _makePositionLiquidatable() internal {
        // Get current position data
        (uint256 collateral, uint256 debt,,) = lendingVault.getPosition(user1);
        uint8 d = mockOracle.decimals();
        uint256 threshold = protocolConfig.liquidationThreshold();
        
        // Calculate target price to make position liquidatable
        // targetPrice = threshold * debt * 10^d / (10000 * collateral)
        uint256 numerator = threshold * debt * (10 ** d);
        uint256 denominator = 10000 * collateral;
        uint256 targetPrice = denominator == 0 ? 0 : numerator / denominator;
        uint256 newPrice = targetPrice > 1 ? (targetPrice - 1) : 1;
        
        mockOracle.setAnswer(int256(newPrice));
    }
}

