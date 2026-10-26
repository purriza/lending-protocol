// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {LendingVault} from "../../contracts/LendingVault.sol";

/**
 * @title UpdateConsolidatedDebtTest
 * @notice Tests for _updateConsolidatedDebt function to ensure both branches work correctly
 * @dev This test contract uses a helper contract to expose the internal _updateConsolidatedDebt function
 */
contract UpdateConsolidatedDebtTest is Test {
    LendingVaultHarness public lendingVaultHarness;

    address public admin = address(1);

    uint256 constant PRECISION = 1e12;

    function setUp() public {
        vm.startPrank(admin);
        
        // Deploy harness - no initialization needed for these isolated tests
        lendingVaultHarness = new LendingVaultHarness();
        
        vm.stopPrank();
    }

    /**
     * @notice Test that _updateConsolidatedDebt correctly increases totalConsolidatedDebt
     * @dev Simulates a scenario where new normalized principal is greater than old
     */
    function test_UpdateConsolidatedDebt_IncreaseBranch() public {
        vm.prank(admin);
        
        uint256 oldPrincipal = 1000e18;
        uint256 newPrincipal = 1500e18;
        uint256 oldUserIndex = PRECISION; // User index was 1.0
        uint256 currentIndex = PRECISION * 2; // Current index is 2.0 (double)
        
        // Calculate expected values
        uint256 oldPrincipalNormalized = (oldPrincipal * PRECISION) / oldUserIndex;
        uint256 newPrincipalNormalized = (newPrincipal * PRECISION) / currentIndex;
        
        // newPrincipalNormalized = 1500e18 * 1e12 / 2e12 = 750e18
        // oldPrincipalNormalized = 1000e18 * 1e12 / 1e12 = 1000e18
        // In this case: newPrincipalNormalized < oldPrincipalNormalized (decrease, not increase)
        
        // For increase branch, we need: newPrincipalNormalized > oldPrincipalNormalized
        // Let's adjust: oldPrincipal = 500e18, newPrincipal = 1500e18
        oldPrincipal = 500e18;
        newPrincipal = 1500e18;
        oldUserIndex = PRECISION * 2; // Old index was 2.0
        currentIndex = PRECISION; // Current index is 1.0
        
        // oldPrincipalNormalized = 500e18 * 1e12 / 2e12 = 250e18
        // newPrincipalNormalized = 1500e18 * 1e12 / 1e12 = 1500e18
        // newPrincipalNormalized > oldPrincipalNormalized ✓
        
        uint256 initialConsolidatedDebt = lendingVaultHarness.exposed_getTotalConsolidatedDebt();
        
        lendingVaultHarness.exposed_updateConsolidatedDebt(oldPrincipal, newPrincipal, oldUserIndex, currentIndex);
        
        uint256 finalConsolidatedDebt = lendingVaultHarness.exposed_getTotalConsolidatedDebt();
        
        oldPrincipalNormalized = (oldPrincipal * PRECISION) / oldUserIndex;
        newPrincipalNormalized = (newPrincipal * PRECISION) / currentIndex;
        uint256 expectedIncrease = newPrincipalNormalized - oldPrincipalNormalized;
        
        assertEq(
            finalConsolidatedDebt - initialConsolidatedDebt,
            expectedIncrease,
            "Increase branch should correctly increase totalConsolidatedDebt"
        );
    }

    /**
     * @notice Test that _updateConsolidatedDebt correctly decreases totalConsolidatedDebt
     * @dev This is the normal liquidation scenario
     */
    function test_UpdateConsolidatedDebt_DecreaseBranch() public {
        vm.startPrank(admin);
        
        // First, set some initial consolidated debt
        uint256 initialSetup = 1000e18;
        lendingVaultHarness.exposed_setTotalConsolidatedDebt(initialSetup);
        
        uint256 oldPrincipal = 1000e18;
        uint256 newPrincipal = 500e18; // Debt decreased (liquidation)
        uint256 oldUserIndex = PRECISION; // User index was 1.0
        uint256 currentIndex = PRECISION * 2; // Current index is 2.0
        
        // oldPrincipalNormalized = 1000e18 * 1e12 / 1e12 = 1000e18
        // newPrincipalNormalized = 500e18 * 1e12 / 2e12 = 250e18
        // oldPrincipalNormalized > newPrincipalNormalized ✓
        
        uint256 initialConsolidatedDebt = lendingVaultHarness.exposed_getTotalConsolidatedDebt();
        
        lendingVaultHarness.exposed_updateConsolidatedDebt(oldPrincipal, newPrincipal, oldUserIndex, currentIndex);
        
        uint256 finalConsolidatedDebt = lendingVaultHarness.exposed_getTotalConsolidatedDebt();
        
        uint256 oldPrincipalNormalized = (oldPrincipal * PRECISION) / oldUserIndex;
        uint256 newPrincipalNormalized = (newPrincipal * PRECISION) / currentIndex;
        uint256 expectedDecrease = oldPrincipalNormalized - newPrincipalNormalized;
        
        assertEq(
            initialConsolidatedDebt - finalConsolidatedDebt,
            expectedDecrease,
            "Decrease branch should correctly decrease totalConsolidatedDebt"
        );
        
        vm.stopPrank();
    }

    /**
     * @notice Test that _updateConsolidatedDebt handles equal principals correctly (no change)
     */
    function test_UpdateConsolidatedDebt_NoBranch_Equal() public {
        vm.startPrank(admin);
        
        lendingVaultHarness.exposed_setTotalConsolidatedDebt(1000e18);
        
        uint256 oldPrincipal = 1000e18;
        uint256 newPrincipal = 2000e18;
        uint256 oldUserIndex = PRECISION; // 1.0
        uint256 currentIndex = PRECISION * 2; // 2.0
        
        // oldPrincipalNormalized = 1000e18 * 1e12 / 1e12 = 1000e18
        // newPrincipalNormalized = 2000e18 * 1e12 / 2e12 = 1000e18
        // Equal!
        
        uint256 initialConsolidatedDebt = lendingVaultHarness.exposed_getTotalConsolidatedDebt();
        
        lendingVaultHarness.exposed_updateConsolidatedDebt(oldPrincipal, newPrincipal, oldUserIndex, currentIndex);
        
        uint256 finalConsolidatedDebt = lendingVaultHarness.exposed_getTotalConsolidatedDebt();
        
        assertEq(
            finalConsolidatedDebt,
            initialConsolidatedDebt,
            "Equal normalized principals should not change totalConsolidatedDebt"
        );
        
        vm.stopPrank();
    }

    /**
     * @notice Test that _updateConsolidatedDebt correctly handles oldUserIndex == 0
     */
    function test_UpdateConsolidatedDebt_ZeroOldUserIndex() public {
        vm.startPrank(admin);
        
        lendingVaultHarness.exposed_setTotalConsolidatedDebt(1000e18);
        
        uint256 oldPrincipal = 1000e18;
        uint256 newPrincipal = 500e18;
        uint256 oldUserIndex = 0; // Should use PRECISION instead
        uint256 currentIndex = PRECISION * 2; // 2.0
        
        // oldPrincipalNormalized = 1000e18 * 1e12 / 1e12 = 1000e18 (uses PRECISION when oldUserIndex == 0)
        // newPrincipalNormalized = 500e18 * 1e12 / 2e12 = 250e18
        
        uint256 initialConsolidatedDebt = lendingVaultHarness.exposed_getTotalConsolidatedDebt();
        
        lendingVaultHarness.exposed_updateConsolidatedDebt(oldPrincipal, newPrincipal, oldUserIndex, currentIndex);
        
        uint256 finalConsolidatedDebt = lendingVaultHarness.exposed_getTotalConsolidatedDebt();
        
        uint256 oldPrincipalNormalized = (oldPrincipal * PRECISION) / PRECISION; // Uses PRECISION
        uint256 newPrincipalNormalized = (newPrincipal * PRECISION) / currentIndex;
        uint256 expectedDecrease = oldPrincipalNormalized - newPrincipalNormalized;
        
        assertEq(
            initialConsolidatedDebt - finalConsolidatedDebt,
            expectedDecrease,
            "Should handle zero oldUserIndex by using PRECISION"
        );
        
        vm.stopPrank();
    }
}

/**
 * @title LendingVaultHarness
 * @notice Test harness to expose internal functions of LendingVault
 */
contract LendingVaultHarness is LendingVault {
    function exposed_updateConsolidatedDebt(
        uint256 _oldPrincipal,
        uint256 _newPrincipal,
        uint256 _oldUserIndex,
        uint256 _currentIndex
    ) external {
        _updateConsolidatedDebt(_oldPrincipal, _newPrincipal, _oldUserIndex, _currentIndex);
    }

    function exposed_getTotalConsolidatedDebt() external view returns (uint256 value) {
        // Storage slot 13 is where totalConsolidatedDebt is stored
        assembly {
            value := sload(13)
        }
    }

    function exposed_setTotalConsolidatedDebt(uint256 _amount) external {
        // Storage slot 13 is where totalConsolidatedDebt is stored
        assembly {
            sstore(13, _amount)
        }
    }
}

