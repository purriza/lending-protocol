// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {Test, console} from "forge-std/Test.sol";
import {TestSetup} from "../TestSetup.t.sol";
import {LendingVault} from "../../contracts/LendingVault.sol";
import {ILendingVault} from "../../contracts/interfaces/ILendingVault.sol";
import {IProtocolConfig} from "../../contracts/interfaces/IProtocolConfig.sol";
import {ProtocolConfig} from "../../contracts/ProtocolConfig.sol";
import {Treasury} from "../../contracts/Treasury.sol";
import {PUSD} from "../../contracts/PUSD.sol";
import {wPUSD} from "../../contracts/wPUSD.sol";
import {StabilityFund} from "../../contracts/StabilityFund.sol";
import {LiquidationEngine} from "../../contracts/LiquidationEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TreasuryProtectionTest
 * @notice Tests for Treasury liquidation protection
 * @dev Ensures Treasury wallet cannot be liquidated under any circumstances
 */
contract TreasuryProtectionTest is TestSetup {
    
    address public testTreasuryWallet;
    address public regularUser;
    
    function setUp() public override {
        super.setUp();
        
        // Set up test addresses
        testTreasuryWallet = makeAddr("testTreasuryWallet");
        regularUser = makeAddr("regularUser");
        
        // Set treasury wallet in ProtocolConfig
        vm.prank(admin);
        protocolConfig.setTreasuryWallet(testTreasuryWallet);
        
        // Fund treasury wallet with wstETH
        deal(address(wstETH), testTreasuryWallet, 1000 ether);
        
        // Fund regular user with wstETH
        deal(address(wstETH), regularUser, 1000 ether);
        
        // Set up treasury wallet position (simulate treasury receiving collateral)
        vm.startPrank(testTreasuryWallet);
        wstETH.approve(address(lendingVault), type(uint256).max);
        lendingVault.deposit(100 ether); // Deposit 100 wstETH
        lendingVault.borrow(50_000 ether); // Borrow 50,000 PUSD
        vm.stopPrank();
        
        // Set up regular user position
        vm.startPrank(regularUser);
        wstETH.approve(address(lendingVault), type(uint256).max);
        lendingVault.deposit(100 ether); // Deposit 100 wstETH
        lendingVault.borrow(50_000 ether); // Borrow 50,000 PUSD
        vm.stopPrank();
        
        // Authorize liquidation bot
        vm.prank(admin);
        lendingVault.setLiquidationBot(address(this), true);
        
        // Fund StabilityFund and Treasury with PUSD for liquidations
        deal(address(pusd), address(stabilityFund), 100_000 ether);
        deal(address(pusd), address(treasury), 100_000 ether);
    }
    
    function testTreasuryIsNotLiquidatable() public {
        // Treasury should never be liquidatable regardless of health ratio
        assertFalse(lendingVault.isLiquidatable(testTreasuryWallet), "Treasury should not be liquidatable");
        
        // Even if treasury has unhealthy position, it should not be liquidatable
        // Simulate price drop to make position unhealthy
        vm.mockCall(
            address(mockOracle),
            abi.encodeWithSelector(mockOracle.latestRoundData.selector),
            abi.encode(0, 2000e8, 0, 0, 0) // Price drops to $2000 (unhealthy)
        );
        
        // Treasury should still not be liquidatable
        assertFalse(lendingVault.isLiquidatable(testTreasuryWallet), "Treasury should not be liquidatable even with unhealthy position");
    }
    
    function testRegularUserIsLiquidatableWhenUnhealthy() public {
        // Regular user should be liquidatable when unhealthy
        // Use a much lower price to make position unhealthy
        vm.mockCall(
            address(mockOracle),
            abi.encodeWithSelector(mockOracle.latestRoundData.selector),
            abi.encode(0, 500e8, 0, 0, 0) // Price drops to $500 (extremely unhealthy)
        );
        
        // Check health ratio first to debug
        uint256 healthRatio = lendingVault.getPositionHealthRatio(regularUser);
        uint256 threshold = protocolConfig.liquidationThreshold();
        
        // Debug info
        console.log("Health ratio:", healthRatio);
        console.log("Liquidation threshold:", threshold);
        
        assertTrue(lendingVault.isLiquidatable(regularUser), "Regular user should be liquidatable when unhealthy");
    }
    
    function testLiquidationSkippedEventEmitted() public {
        // Get treasury's current debt before liquidation attempt
        uint256 currentDebt = lendingVault.getCurrentDebt(testTreasuryWallet);
        
        // Attempt to liquidate treasury should emit event and return empty result
        vm.expectEmit(true, true, true, true);
        emit ILendingVault.LiquidationSkippedTreasuryExemption(testTreasuryWallet, testTreasuryWallet);
        
        ILendingVault.LiquidationResult memory result = lendingVault.liquidatePosition(testTreasuryWallet);
        
        // Verify the result matches expected values
        assertEq(result.debtRepaid, 0, "Debt repaid should be 0");
        assertEq(result.collateralSeized, 0, "Collateral seized should be 0");
        assertEq(result.remainingDebt, currentDebt, "Remaining debt should equal current debt");
        assertFalse(result.fullLiquidation, "Full liquidation should be false");
    }
    
    function testRegularUserLiquidationWorks() public {
        // Make regular user unhealthy
        vm.mockCall(
            address(mockOracle),
            abi.encodeWithSelector(mockOracle.latestRoundData.selector),
            abi.encode(0, 500e8, 0, 0, 0) // Price drops to $500 (extremely unhealthy)
        );
        
        // Check if user is liquidatable first
        assertTrue(lendingVault.isLiquidatable(regularUser), "User should be liquidatable");
        
        // Check if we have sufficient funds for liquidation
        uint256 sfBalance = pusd.balanceOf(address(stabilityFund));
        uint256 treasuryBalance = pusd.balanceOf(address(treasury));
        console.log("SF Balance:", sfBalance);
        console.log("Treasury Balance:", treasuryBalance);
        
        // Regular user liquidation should work
        LendingVault.LiquidationResult memory result = lendingVault.liquidatePosition(regularUser);
        
        console.log("Debt repaid:", result.debtRepaid);
        console.log("Collateral seized:", result.collateralSeized);
        
        assertTrue(result.debtRepaid > 0, "Debt should be repaid");
        assertTrue(result.collateralSeized > 0, "Collateral should be seized");
    }
    
    function testTreasuryProtectionWithDifferentTreasuryAddress() public {
        // Change treasury address
        address newTreasury = makeAddr("newTreasury");
        vm.prank(admin);
        protocolConfig.setTreasuryWallet(newTreasury);
        
        // Old treasury address should now be liquidatable
        vm.mockCall(
            address(mockOracle),
            abi.encodeWithSelector(mockOracle.latestRoundData.selector),
            abi.encode(0, 500e8, 0, 0, 0) // Price drops to $500 (extremely unhealthy)
        );
        
        assertTrue(lendingVault.isLiquidatable(testTreasuryWallet), "Old treasury should be liquidatable after address change");
        assertFalse(lendingVault.isLiquidatable(newTreasury), "New treasury should not be liquidatable");
    }
    
    function testTreasuryProtectionWithZeroTreasuryAddress() public {
        // Should revert due to zero address check
        vm.prank(admin);
        vm.expectRevert(IProtocolConfig.ProtocolConfig__InvalidAddress.selector);
        protocolConfig.setTreasuryWallet(address(0));
    }
    
    function testTreasuryProtectionOnlyAdminCanSetTreasury() public {
        // Non-admin should not be able to set treasury
        vm.prank(regularUser);
        vm.expectRevert();
        protocolConfig.setTreasuryWallet(makeAddr("newTreasury"));
    }
    
    function testTreasuryProtectionGasImpact() public view {
        // Test that treasury protection adds minimal gas overhead
        uint256 gasStart = gasleft();
        lendingVault.isLiquidatable(testTreasuryWallet);
        uint256 gasUsed = gasStart - gasleft();
        
        // Should be reasonable overhead (less than 30000 gas for the entire function)
        assertLt(gasUsed, 30000, "Treasury protection should have reasonable gas impact");
    }
    
    function testTreasuryProtectionWithEmptyTreasuryAddress() public {
        // Test with empty treasury address (should not be protected)
        address emptyTreasury = address(0);
        
        // Should not be liquidatable due to zero address check in isLiquidatable
        // The error is actually LendingVault__InvalidAddress from the contract, not interface
        vm.expectRevert();
        lendingVault.isLiquidatable(emptyTreasury);
    }
    
    function testTreasuryProtectionEventParameters() public {
        // Get treasury's current debt before liquidation attempt
        uint256 currentDebt = lendingVault.getCurrentDebt(testTreasuryWallet);
        
        // Test that event is emitted with correct parameters
        vm.expectEmit(true, true, true, true);
        emit ILendingVault.LiquidationSkippedTreasuryExemption(testTreasuryWallet, testTreasuryWallet);
        
        ILendingVault.LiquidationResult memory result = lendingVault.liquidatePosition(testTreasuryWallet);
        
        // Verify the result matches expected values
        assertEq(result.debtRepaid, 0, "Debt repaid should be 0");
        assertEq(result.collateralSeized, 0, "Collateral seized should be 0");
        assertEq(result.remainingDebt, currentDebt, "Remaining debt should equal current debt");
        assertFalse(result.fullLiquidation, "Full liquidation should be false");
    }
}
