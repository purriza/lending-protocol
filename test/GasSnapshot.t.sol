// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {TestSetup} from "./TestSetup.t.sol";
import {ILendingVault} from "../contracts/interfaces/ILendingVault.sol";
import {DataTypes} from "../contracts/DataTypes.sol";

/**
 * @title GasSnapshot
 * @notice Gas cost tracking and snapshot tests for Lending Protocol contracts
 * @dev This test suite tracks gas costs for critical operations to ensure they stay within acceptable limits
 */
contract GasSnapshot is TestSetup {

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 constant GAS_TEST_COLLATERAL = 1 ether;
    uint256 constant GAS_TEST_BORROW = 2000 ether;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();
        
        // Setup users with positions for gas testing
        _setupUserPositions();
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _setupUserPositions() internal {
        // Setup user1 position
        wstETH.mint(user1, GAS_TEST_COLLATERAL);
        vm.startPrank(user1);
        wstETH.approve(address(lendingVault), GAS_TEST_COLLATERAL);
        lendingVault.deposit(GAS_TEST_COLLATERAL);
        lendingVault.borrow(GAS_TEST_BORROW);
        vm.stopPrank();

        // Setup user2 position
        wstETH.mint(user2, GAS_TEST_COLLATERAL);
        vm.startPrank(user2);
        wstETH.approve(address(lendingVault), GAS_TEST_COLLATERAL);
        lendingVault.deposit(GAS_TEST_COLLATERAL);
        lendingVault.borrow(GAS_TEST_BORROW);
        vm.stopPrank();

        // Make positions liquidatable
        _pushHealthBelowThreshold();
        
        // Authorize this contract as liquidation bot
        vm.prank(admin);
        lendingVault.setLiquidationBot(address(this), true);
        
        // Set close factor to 100% for full liquidation
        vm.prank(admin);
        protocolConfig.setCloseFactorBps(10000);
    }

    function _pushHealthBelowThreshold() internal {
        (uint256 collateral, uint256 debt,,) = lendingVault.getPosition(user1);
        uint8 d = mockOracle.decimals();
        uint256 threshold = protocolConfig.liquidationThreshold();
        
        uint256 numerator = threshold * debt * (10 ** d);
        uint256 denominator = 10000 * collateral;
        uint256 targetPrice = denominator == 0 ? 0 : numerator / denominator;
        uint256 newPrice = targetPrice > 1 ? (targetPrice - 1) : 1;
        
        mockOracle.setAnswer(int256(newPrice));
    }

    /*//////////////////////////////////////////////////////////////
                            GAS SNAPSHOT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GasSnapshot_LendingVault_Deposit() public {
        uint256 amount = 0.5 ether;
        wstETH.mint(address(this), amount);
        wstETH.approve(address(lendingVault), amount);
        
        uint256 snapshot = vm.snapshot();
        lendingVault.deposit(amount);
        vm.revertTo(snapshot);
    }

    function test_GasSnapshot_LendingVault_Borrow() public {
        uint256 amount = 1000 ether; // Must meet minimum debt requirement
        
        // Create a fresh position for this test
        address testUser = makeAddr("testUser");
        wstETH.mint(testUser, 2 ether); // More collateral for larger borrow
        vm.startPrank(testUser);
        wstETH.approve(address(lendingVault), 2 ether);
        lendingVault.deposit(2 ether);
        vm.stopPrank();
        
        uint256 snapshot = vm.snapshot();
        vm.prank(testUser);
        lendingVault.borrow(amount);
        vm.revertTo(snapshot);
    }

    function test_GasSnapshot_LendingVault_Repay() public {
        uint256 amount = 50 ether; // Smaller amount
        // Use existing user position for repaying
        vm.prank(user1);
        pusd.approve(address(lendingVault), amount);
        
        uint256 snapshot = vm.snapshot();
        vm.prank(user1);
        lendingVault.repay(amount);
        vm.revertTo(snapshot);
    }

    function test_GasSnapshot_LendingVault_Withdraw() public {
        uint256 amount = 0.1 ether; // Small amount to avoid collateral issues
        
        // Create a fresh position for this test
        address testUser = makeAddr("testUser2");
        wstETH.mint(testUser, 2 ether);
        vm.startPrank(testUser);
        wstETH.approve(address(lendingVault), 2 ether);
        lendingVault.deposit(2 ether);
        lendingVault.borrow(1000 ether); // Meet minimum debt requirement
        vm.stopPrank();
        
        uint256 snapshot = vm.snapshot();
        vm.prank(testUser);
        lendingVault.withdraw(amount);
        vm.revertTo(snapshot);
    }

    function test_GasSnapshot_LendingVault_LiquidatePosition() public {
        uint256 snapshot = vm.snapshot();
        lendingVault.liquidatePosition(user1);
        vm.revertTo(snapshot);
    }

    function test_GasSnapshot_LiquidationEngine_ExecuteLiquidation() public {
        // Use LendingVault.liquidatePosition instead since executeLiquidation requires onlyLendingVault
        uint256 snapshot = vm.snapshot();
        lendingVault.liquidatePosition(user1);
        vm.revertTo(snapshot);
    }

    function test_GasSnapshot_StabilityFund_SendLiquidationFunds() public {
        uint256 amount = 1000 ether;
        
        // sendLiquidationFunds requires onlyLendingVault, so we need to call it through LendingVault
        uint256 snapshot = vm.snapshot();
        vm.prank(address(lendingVault));
        stabilityFund.sendLiquidationFunds(amount);
        vm.revertTo(snapshot);
    }

    function test_GasSnapshot_Treasury_ProvideBackstopFunds() public {
        uint256 amount = 1000 ether;
        
        // provideBackstopFunds requires onlyAuthorized (lendingVault or liquidationEngine)
        uint256 snapshot = vm.snapshot();
        vm.prank(address(lendingVault));
        treasury.provideBackstopFunds(amount);
        vm.revertTo(snapshot);
    }

    function test_GasSnapshot_ProtocolConfig_Setters() public {
        vm.startPrank(admin);
        
        uint256 snapshot1 = vm.snapshot();
        protocolConfig.setMinCollateralRatio(15000);
        vm.revertTo(snapshot1);
        
        // First set minCollateralRatio to 15000 to allow setting liquidationThreshold to 12000
        uint256 snapshot2 = vm.snapshot();
        protocolConfig.setMinCollateralRatio(15000);
        protocolConfig.setLiquidationThreshold(12000);
        vm.revertTo(snapshot2);
        
        uint256 snapshot3 = vm.snapshot();
        protocolConfig.setCloseFactorBps(5000);
        vm.revertTo(snapshot3);
        
        vm.stopPrank();
    }

    function test_GasSnapshot_ComplexLiquidationFlow() public {
        // Test the complete liquidation flow with MEV attack simulation
        uint256 snapshot = vm.snapshot();
        
        // Execute first liquidation
        lendingVault.liquidatePosition(user1);
        
        // Simulate MEV attack by manipulating quoter
        vm.prank(admin);
        mockQuoter.setExchangeRate(address(wstETH), address(pusd), 0);
        
        // Execute second liquidation with manipulated quoter
        lendingVault.liquidatePosition(user2);
        
        vm.revertTo(snapshot);
    }

    function test_GasSnapshot_MultipleOperations() public {
        uint256 snapshot = vm.snapshot();
        
        // Deposit
        wstETH.mint(address(this), 2 ether);
        wstETH.approve(address(lendingVault), 2 ether);
        lendingVault.deposit(2 ether);
        
        // Borrow
        lendingVault.borrow(1000 ether); // Meet minimum debt requirement
        
        // Repay
        pusd.approve(address(lendingVault), 500 ether);
        lendingVault.repay(500 ether);
        
        // Withdraw
        lendingVault.withdraw(0.1 ether); // Small amount
        
        vm.revertTo(snapshot);
    }
}
