// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {TestSetup} from "../TestSetup.t.sol";
import {ILendingVault} from "../../contracts/interfaces/ILendingVault.sol";

contract OracleTests is TestSetup {
    function setUp() public override {
        super.setUp();
        
        // Ensure oracle has fresh timestamp
        mockOracle.setUpdatedAt(block.timestamp);
        
        // Ensure user1 has deposited sufficient collateral for testing
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
        lendingVault.deposit(INITIAL_COLLATERAL);
        vm.stopPrank();
    }

    function test_Oracle_ZeroPrice_DisablesBorrowAndMaxBorrow() public {
        // Set oracle answer to 0
        mockOracle.setAnswer(0);
        mockOracle.setUpdatedAt(block.timestamp); // Ensure oracle is fresh to avoid staleness error

        // getMaxBorrow should revert with InvalidOraclePrice
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidOraclePrice.selector));
        lendingVault.getMaxBorrow(user1);

        // Attempt to borrow should revert with InvalidOraclePrice
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidOraclePrice.selector));
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();
    }

    function test_Oracle_NegativePrice_TreatedAsZero() public {
        // Set oracle answer to negative value
        mockOracle.setAnswer(-1);
        mockOracle.setUpdatedAt(block.timestamp); // Ensure oracle is fresh to avoid staleness error

        // getMaxBorrow should revert with InvalidOraclePrice
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidOraclePrice.selector));
        lendingVault.getMaxBorrow(user1);

        // Borrow reverts with InvalidOraclePrice
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidOraclePrice.selector));
        lendingVault.borrow(BORROW_AMOUNT); 
        vm.stopPrank();
    }

    function test_Oracle_DecimalsScaling_Works() public {
        // With 8 decimals and price 3000e8 (already set in TestSetup), compute a baseline maxBorrow
        uint256 maxBorrow8 = lendingVault.getMaxBorrow(user1);

        // Change to 6 decimals with consistent price scale (3000e6)
        mockOracle.setDecimals(6);
        mockOracle.setAnswer(3000e6);
        uint256 maxBorrow6 = lendingVault.getMaxBorrow(user1);

        // Change to 18 decimals with consistent price scale (3000e18)
        mockOracle.setDecimals(18);
        mockOracle.setAnswer(3000e18);
        uint256 maxBorrow18 = lendingVault.getMaxBorrow(user1);

        // All should be equal since internal scaling normalizes by oracle decimals
        assertEq(maxBorrow8, maxBorrow6, "Max borrow should be invariant to oracle decimals (8 vs 6)");
        assertEq(maxBorrow8, maxBorrow18, "Max borrow should be invariant to oracle decimals (8 vs 18)");
    }

    /*//////////////////////////////////////////////////////////////
                        ORACLE STALENESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Oracle_Staleness_RevertsOnBorrow() public {
        // Set oracle to a specific old timestamp
        uint256 oracleUpdateTime = 100;
        mockOracle.setUpdatedAt(oracleUpdateTime);
        
        // Warp to a time that makes the oracle stale
        uint256 maxStaleness = protocolConfig.maxStaleness();
        vm.warp(oracleUpdateTime + maxStaleness + 1);

        // Attempt to borrow should revert with StaleOraclePrice
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__StaleOraclePrice.selector));
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();
    }

    function test_Oracle_Staleness_RevertsOnGetMaxBorrow() public {
        // Set oracle to a specific old timestamp
        uint256 oracleUpdateTime = 100;
        mockOracle.setUpdatedAt(oracleUpdateTime);
        
        // Warp to a time that makes the oracle stale
        uint256 maxStaleness = protocolConfig.maxStaleness();
        vm.warp(oracleUpdateTime + maxStaleness + 1);

        // getMaxBorrow should revert with StaleOraclePrice
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__StaleOraclePrice.selector));
        lendingVault.getMaxBorrow(user1);
    }

    function test_Oracle_Staleness_RevertsOnGetPositionHealthRatio() public {
        // First borrow to establish position with debt
        vm.startPrank(user1);
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();

        // Set oracle to a specific old timestamp
        uint256 oracleUpdateTime = 100;
        mockOracle.setUpdatedAt(oracleUpdateTime);
        
        // Warp to a time that makes the oracle stale
        uint256 maxStaleness = protocolConfig.maxStaleness();
        vm.warp(oracleUpdateTime + maxStaleness + 1);

        // getPositionHealthRatio should revert with StaleOraclePrice
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__StaleOraclePrice.selector));
        lendingVault.getPositionHealthRatio(user1);
    }

    function test_Oracle_Staleness_RevertsOnWithdraw() public {
        // First borrow to establish position with debt
        vm.startPrank(user1);
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();

        // Set oracle to a specific old timestamp
        uint256 oracleUpdateTime = 100;
        mockOracle.setUpdatedAt(oracleUpdateTime);
        
        // Warp to a time that makes the oracle stale
        uint256 maxStaleness = protocolConfig.maxStaleness();
        vm.warp(oracleUpdateTime + maxStaleness + 1);

        // withdraw should revert with StaleOraclePrice when there's debt
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__StaleOraclePrice.selector));
        lendingVault.withdraw(0.1 ether);
        vm.stopPrank();
    }

    function test_Oracle_Staleness_AllowsFreshPrice() public {
        // Oracle is already fresh from setup
        // Borrow should succeed with fresh price
        vm.startPrank(user1);
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();

        // Verify borrow was successful
        uint256 debt = lendingVault.getCurrentDebt(user1);
        assertEq(debt, BORROW_AMOUNT, "Borrow should succeed with fresh oracle price");
    }

    function test_Oracle_Staleness_ExactlyAtThreshold() public {
        // Warp to future time
        uint256 maxStaleness = protocolConfig.maxStaleness();
        uint256 futureTime = block.timestamp + 10000;
        vm.warp(futureTime);
        
        // Set oracle timestamp to exactly maxStaleness ago
        mockOracle.setUpdatedAt(futureTime - maxStaleness);

        // Should succeed at exactly the threshold
        vm.startPrank(user1);
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();

        uint256 debt = lendingVault.getCurrentDebt(user1);
        assertEq(debt, BORROW_AMOUNT, "Should succeed at exactly maxStaleness threshold");
    }

    function test_Oracle_Staleness_ConfigurableThreshold() public {
        // Change maxStaleness to a shorter period
        vm.prank(admin);
        protocolConfig.setMaxStaleness(60); // 1 minute

        // Set oracle to a specific old timestamp
        uint256 oracleUpdateTime = 100;
        mockOracle.setUpdatedAt(oracleUpdateTime);
        
        // Warp to a time that makes the oracle stale with new threshold (61 seconds later)
        vm.warp(oracleUpdateTime + 61);

        // Should revert with new shorter staleness period
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__StaleOraclePrice.selector));
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();

        // Update oracle to current timestamp
        mockOracle.setUpdatedAt(block.timestamp);

        // Now should succeed
        vm.startPrank(user1);
        lendingVault.borrow(BORROW_AMOUNT);
        vm.stopPrank();

        uint256 debt = lendingVault.getCurrentDebt(user1);
        assertEq(debt, BORROW_AMOUNT, "Should succeed after oracle update");
    }
}


