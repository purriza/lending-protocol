// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TestSetup} from "../TestSetup.t.sol";

import {LiquidationEngine} from "../../contracts/LiquidationEngine.sol";
import {ILiquidationEngine} from "../../contracts/interfaces/ILiquidationEngine.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DataTypes} from "../../contracts/DataTypes.sol";

contract LiquidationEngineGettersTest is TestSetup {

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();
        
        // Check if Treasury already has an IOU open and close it if necessary
        uint256 existingIOU = treasury.backstopIouPusd();
        if (existingIOU > 0) {
            // Mint PUSD to repay the existing IOU
            _mintPUSD(admin, existingIOU);
            vm.startPrank(admin);
            pusd.approve(address(treasury), existingIOU);
            treasury.repayBackstopIou(existingIOU, 0);
            vm.stopPrank();
        }
        
        // Configure minimal necessary settings for liquidation engine
        vm.startPrank(admin);
        liquidationEngine.setStabilityFund(address(stabilityFund));
        vm.stopPrank();
        
        // Setup StabilityFund with sufficient PUSD for liquidations
        uint256 sfLiquidity = 50_000 ether; // 50k PUSD to cover liquidation debts
        _mintPUSD(admin, sfLiquidity);
        vm.startPrank(admin);
        pusd.approve(address(stabilityFund), sfLiquidity);
        stabilityFund.depositPUSD(sfLiquidity);
        vm.stopPrank();
        
        // Setup mock AMM with liquidity for swaps
        _setupMockAMM();
        
        // Mint PUSD to LiquidationEngine for distribution
        _mintPUSD(address(liquidationEngine), 1000e18);
        
        // Ensure Treasury has sufficient PUSD to avoid IOUs
        uint256 treasuryPUSD = 10_000_000 ether; // 10M PUSD should be more than enough
        _mintPUSD(address(treasury), treasuryPUSD);
        
        // Verify Treasury has sufficient PUSD before liquidations
        uint256 treasuryBalance = pusd.balanceOf(address(treasury));
        console.log("Treasury PUSD balance before liquidations:", treasuryBalance);
        console.log("Treasury address:", address(treasury));
        console.log("Treasury PUSD address:", address(treasury.pusd()));
        
        // Create basic liquidation records
        _createLiquidationRecords();
    }

    function _setupUserPositions() internal {
        // Ensure StabilityFund has PUSD liquidity for borrows
        uint256 sfLiquidity = 1_000_000 ether;
        _mintPUSD(admin, sfLiquidity);
        vm.startPrank(admin);
        pusd.approve(address(stabilityFund), sfLiquidity);
        stabilityFund.depositPUSD(sfLiquidity);
        lendingVault.setStabilityFund(address(stabilityFund));
        vm.stopPrank();
        
        // Setup user1 with a healthy position (high collateral ratio)
        vm.startPrank(user1);
        wstETH.mint(user1, 10 ether);
        wstETH.approve(address(lendingVault), 10 ether);
        lendingVault.deposit(5 ether);
        lendingVault.borrow(8000e18); // Health ratio ~187% (healthy but closer to threshold)
        vm.stopPrank();

        // Setup user2 with an undercollateralized position
        vm.startPrank(user2);
        wstETH.mint(user2, 5 ether);
        wstETH.approve(address(lendingVault), 5 ether);
        lendingVault.deposit(2 ether);
        lendingVault.borrow(4500e18); // Health ratio ~133% (liquidatable)
        vm.stopPrank();

        // Setup user3 with borderline position (close to liquidation threshold)
        vm.startPrank(user3);
        wstETH.mint(user3, 3 ether);
        wstETH.approve(address(lendingVault), 3 ether);
        lendingVault.deposit(1.5 ether);
        lendingVault.borrow(3375e18); // Health ratio ~133% (close to threshold)
        vm.stopPrank();
    }

    function _createLiquidationRecords() internal {
        // Create only one liquidation record to avoid IOU issues
        // Mock AMM returns: amount - (amount * 5% slippage) = amount * 0.95
        // So 1 ether (1e18) becomes 0.95e18 PUSD after slippage
        
        uint256 collateralAmount = INITIAL_COLLATERAL; // 5 wstETH
        uint256 debtAmount = BORROW_AMOUNT / 2; // 5,000 PUSD debt
        
        wstETH.mint(address(lendingVault), collateralAmount);
        
        vm.startPrank(address(lendingVault));
        wstETH.approve(address(liquidationEngine), collateralAmount);
        
        // Create LiquidationOrder for liquidation
        DataTypes.LiquidationOrder memory order;
        order.debtor = user1;
        order.debtPaidBySF = debtAmount;
        order.debtPaidByTreasury = 0;
        order.collateralToSell = collateralAmount;
        
        liquidationEngine.executeLiquidation(order);
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            GET LIQUIDATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetLiquidation_ReturnsCorrectRecord() public view {
        // Test liquidation record
        ILiquidationEngine.LiquidationRecord memory record = liquidationEngine.getLiquidation(1);
        
        assertEq(record.user, user1, "Record user should be user1");
        assertEq(record.collateralAmount, INITIAL_COLLATERAL, "Record collateral should be INITIAL_COLLATERAL");
        assertEq(record.debtAmount, BORROW_AMOUNT / 2, "Record debt should be BORROW_AMOUNT / 2");
        assertEq(record.timestamp, block.timestamp, "Record timestamp should be current");
        // Note: backstopUsed depends on whether there was remaining collateral that couldn't be sold
        // This is determined by the liquidation logic, not a fixed value
    }

    function test_GetLiquidation_RevertsOnZeroId() public {
        vm.expectRevert(abi.encodeWithSelector(ILiquidationEngine.LiquidationEngine__LiquidationNotFound.selector));
        liquidationEngine.getLiquidation(0);
    }

    function test_GetLiquidation_RevertsOnNonExistentId() public {
        // Current counter is 2 (after 1 liquidation), so ID 5 doesn't exist
        vm.expectRevert(abi.encodeWithSelector(ILiquidationEngine.LiquidationEngine__LiquidationNotFound.selector));
        liquidationEngine.getLiquidation(5);
    }

    function test_GetLiquidation_RevertsOnFutureId() public {
        uint256 currentCounter = liquidationEngine.liquidationCounter();
        
        vm.expectRevert(abi.encodeWithSelector(ILiquidationEngine.LiquidationEngine__LiquidationNotFound.selector));
        liquidationEngine.getLiquidation(currentCounter + 10);
    }

    function test_GetLiquidation_AllValidIds() public view {
        uint256 currentCounter = liquidationEngine.liquidationCounter();
        
        // Test all valid IDs (1 to currentCounter - 1)
        for (uint256 i = 1; i < currentCounter; i++) {
            ILiquidationEngine.LiquidationRecord memory record = liquidationEngine.getLiquidation(i);
            
            // Basic validation
            assertNotEq(record.user, address(0), "Record should have valid user");
            assertGt(record.collateralAmount, 0, "Record should have positive collateral");
            assertGt(record.debtAmount, 0, "Record should have positive debt");
            assertGt(record.timestamp, 0, "Record should have valid timestamp");
        }
    }

    /*//////////////////////////////////////////////////////////////
                        GET LIQUIDATION STATS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetLiquidationStats_ReturnsCorrectStats() public view {
        (uint256 totalLiquidations, uint256 totalCollateral, uint256 totalDebt) = liquidationEngine.getLiquidationStats();
        
        // We created 1 liquidation in setup
        assertEq(totalLiquidations, 1, "Total liquidations should be 1");
        assertEq(totalCollateral, INITIAL_COLLATERAL, "Total collateral should be INITIAL_COLLATERAL");
        // totalDebtCovered should now be updated with the debt amounts from liquidations
        assertEq(totalDebt, BORROW_AMOUNT / 2, "Total debt covered should match liquidation amounts");
    }

    function test_GetLiquidationStats_InitialState() public {
        // Deploy fresh liquidation engine with proxy to test initial state
        LiquidationEngine freshEngineImpl = new LiquidationEngine();
        bytes memory initData = abi.encodeWithSelector(
            LiquidationEngine.initialize.selector,
            address(protocolConfig),
            address(pusd)
            
        );
        ERC1967Proxy freshEngineProxy = new ERC1967Proxy(address(freshEngineImpl), initData);
        LiquidationEngine freshEngine = LiquidationEngine(address(freshEngineProxy));
        
        (uint256 totalLiquidations, uint256 totalCollateral, uint256 totalDebt) = freshEngine.getLiquidationStats();
        
        assertEq(totalLiquidations, 0, "Initial total liquidations should be 0");
        assertEq(totalCollateral, 0, "Initial total collateral should be 0");
        assertEq(totalDebt, 0, "Initial total debt should be 0");
    }

    function test_GetLiquidationStats_ConsistencyWithStateVariables() public view {
        (uint256 totalLiquidations, uint256 totalCollateral, uint256 totalDebt) = liquidationEngine.getLiquidationStats();
        
        // Check consistency with direct state variable access
        uint256 currentCounter = liquidationEngine.liquidationCounter();
        uint256 expectedLiquidations = currentCounter > 1 ? currentCounter - 1 : 0;
        
        assertEq(totalLiquidations, expectedLiquidations, "Stats should match counter - 1");
        assertEq(totalCollateral, liquidationEngine.totalCollateralLiquidated(), "Stats should match state variable");
        assertEq(totalDebt, liquidationEngine.totalDebtCovered(), "Stats should match state variable");
        
        // Verify that totalDebtCovered is now properly updated
        assertGt(totalDebt, 0, "Total debt covered should be greater than 0 after liquidations");
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZING TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_GetLiquidation_ValidIds(uint256 liquidationId) public view {
        uint256 currentCounter = liquidationEngine.liquidationCounter();
        
        if (currentCounter > 1) {
            // Bound to valid range
            liquidationId = bound(liquidationId, 1, currentCounter - 1);
            
            // Should not revert for valid IDs
            ILiquidationEngine.LiquidationRecord memory record = liquidationEngine.getLiquidation(liquidationId);
            
            // Basic sanity checks
            assertNotEq(record.user, address(0), "Record should have valid user");
            assertGt(record.timestamp, 0, "Record should have valid timestamp");
        }
    }

    function testFuzz_GetLiquidation_InvalidIds(uint256 liquidationId) public {
        uint256 currentCounter = liquidationEngine.liquidationCounter();
        
        // Test invalid IDs (0 or >= currentCounter)
        vm.assume(liquidationId == 0 || liquidationId >= currentCounter);
        
        vm.expectRevert(abi.encodeWithSelector(ILiquidationEngine.LiquidationEngine__LiquidationNotFound.selector));
        liquidationEngine.getLiquidation(liquidationId);
    }
}
