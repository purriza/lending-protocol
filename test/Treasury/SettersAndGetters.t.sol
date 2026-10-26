// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {Treasury} from "../../contracts/Treasury.sol";
import {ITreasury} from "../../contracts/interfaces/ITreasury.sol";

contract TreasurySettersAndGettersTest is TestSetup {

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error AccessControlUnauthorizedAccount(address account, bytes32 role);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    address public newPUSD = makeAddr("newPUSD");
    address public newWstETH = makeAddr("newWstETH");
    address public newLendingVault = makeAddr("newLendingVault");
    address public newLiquidationEngine = makeAddr("newLiquidationEngine");
    address public newProtocolConfig = makeAddr("newProtocolConfig");
    address public newStabilityFund = makeAddr("newStabilityFund");

    uint256 public newSwapSlippageBps = 1000;
    uint256 public newOracleStaleAfter = 2 hours;
    uint256 public newSwapDeadlineSeconds = 120;

    uint256 public constant MINT_AMOUNT = 1_000_000 ether; 

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    function test_SetWstETH() public {
        assertEq(address(treasury.wstETH()), address(wstETH));
        vm.prank(admin);
        treasury.setWstETH(newWstETH);
        assertEq(address(treasury.wstETH()), newWstETH);
    }

    function test_SetPUSD() public {
        assertEq(address(treasury.pusd()), address(pusd));
        vm.prank(admin);
        treasury.setPUSD(newPUSD);
        assertEq(address(treasury.pusd()), newPUSD);
    }

    function test_SetLendingVault() public {
        assertEq(address(treasury.lendingVault()), address(lendingVault));
        vm.prank(admin);
        treasury.setLendingVault(newLendingVault);
        assertEq(address(treasury.lendingVault()), newLendingVault);
    }
    
    function test_SetLiquidationEngine() public {
        assertEq(address(treasury.liquidationEngine()), address(liquidationEngine));
        vm.prank(admin);
        treasury.setLiquidationEngine(newLiquidationEngine);
        assertEq(address(treasury.liquidationEngine()), newLiquidationEngine);
    }

    function test_SetProtocolConfig() public {
        assertEq(address(treasury.protocolConfig()), address(protocolConfig));
        vm.prank(admin);
        treasury.setProtocolConfig(newProtocolConfig);
        assertEq(address(treasury.protocolConfig()), newProtocolConfig);
    }

    function test_SetStabilityFund() public {
        assertEq(address(treasury.stabilityFund()), address(stabilityFund));
        vm.prank(admin);
        treasury.setStabilityFund(newStabilityFund);
        assertEq(address(treasury.stabilityFund()), newStabilityFund);
    }

    function test_SetSwapSlippageBps() public {
        assertEq(treasury.swapSlippageBps(), 500);
        vm.prank(admin);
        treasury.setSwapSlippageBps(newSwapSlippageBps);
        assertEq(treasury.swapSlippageBps(), newSwapSlippageBps);
    }

    function test_SetOracleStaleAfter() public {
        assertEq(treasury.oracleStaleAfter(), 1 hours);
        vm.prank(admin);
        treasury.setOracleStaleAfter(newOracleStaleAfter);
        assertEq(treasury.oracleStaleAfter(), newOracleStaleAfter);
    }

    function test_SetSwapDeadlineSeconds() public {
        assertEq(treasury.swapDeadlineSeconds(), 60);
        vm.prank(admin);
        treasury.setSwapDeadlineSeconds(newSwapDeadlineSeconds);
        assertEq(treasury.swapDeadlineSeconds(), newSwapDeadlineSeconds);
    }

    /*//////////////////////////////////////////////////////////////
                            EVENT TESTS
    //////////////////////////////////////////////////////////////*/


    function test_SetWstETHEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ITreasury.WstETHUpdated(newWstETH);
        vm.prank(admin);
        treasury.setWstETH(newWstETH);
    }

    function test_SetPUSDEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ITreasury.PUSDUpdated(newPUSD);
        vm.prank(admin);
        treasury.setPUSD(newPUSD);
    }
    
    function test_SetLendingVaultEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ITreasury.LendingVaultUpdated(address(lendingVault), newLendingVault);
        vm.prank(admin);
        treasury.setLendingVault(newLendingVault);
    }
    
    function test_SetLiquidationEngineEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ITreasury.LiquidationEngineUpdated(address(liquidationEngine), newLiquidationEngine);
        vm.prank(admin);
        treasury.setLiquidationEngine(newLiquidationEngine);
    }

    function test_SetProtocolConfigEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ITreasury.ProtocolConfigUpdated(address(protocolConfig), newProtocolConfig);
        vm.prank(admin);
        treasury.setProtocolConfig(newProtocolConfig);
    }

    function test_SetStabilityFundEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ITreasury.StabilityFundUpdated(address(stabilityFund), newStabilityFund);
        vm.prank(admin);
        treasury.setStabilityFund(newStabilityFund);
    }

    function test_SetSwapSlippageBpsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ITreasury.SwapSlippageUpdated(500, newSwapSlippageBps);
        vm.prank(admin);
        treasury.setSwapSlippageBps(newSwapSlippageBps);
    }

    function test_SetOracleStaleAfterEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ITreasury.OracleStaleAfterUpdated(1 hours, newOracleStaleAfter);
        vm.prank(admin);
        treasury.setOracleStaleAfter(newOracleStaleAfter);
    }
    
    function test_SetSwapDeadlineSecondsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit ITreasury.SwapDeadlineSecondsUpdated(60, newSwapDeadlineSeconds);
        vm.prank(admin);
        treasury.setSwapDeadlineSeconds(newSwapDeadlineSeconds);
    }
    
    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/


    function test_SetWstETHRevertWhenNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, treasury.protocolConfig().ADMIN_ROLE()));
        vm.prank(user1);
        treasury.setWstETH(newWstETH);
    }

    function test_SetPUSDRevertWhenNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, treasury.protocolConfig().ADMIN_ROLE()));
        vm.prank(user1);
        treasury.setPUSD(newPUSD);
    }
    
    function test_SetLendingVaultRevertWhenNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, treasury.protocolConfig().ADMIN_ROLE()));
        vm.prank(user1);
        treasury.setLendingVault(newLendingVault);
    }
    
    function test_SetLiquidationEngineRevertWhenNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, treasury.protocolConfig().ADMIN_ROLE()));
        vm.prank(user1);
        treasury.setLiquidationEngine(newLiquidationEngine);
    }

    function test_SetProtocolConfigRevertWhenNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, treasury.protocolConfig().ADMIN_ROLE()));
        vm.prank(user1);
        treasury.setProtocolConfig(newProtocolConfig);
    }

    function test_SetStabilityFundRevertWhenNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, treasury.protocolConfig().ADMIN_ROLE()));
        vm.prank(user1);
        treasury.setStabilityFund(newStabilityFund);
    }

    function test_SetSwapSlippageBpsRevertWhenNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, treasury.protocolConfig().ADMIN_ROLE()));
        vm.prank(user1);
        treasury.setSwapSlippageBps(newSwapSlippageBps);
    }

    function test_SetOracleStaleAfterRevertWhenNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, treasury.protocolConfig().ADMIN_ROLE()));
        vm.prank(user1);
        treasury.setOracleStaleAfter(newOracleStaleAfter);
    }

    function test_SetSwapDeadlineSecondsRevertWhenNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, treasury.protocolConfig().ADMIN_ROLE()));
        vm.prank(user1);
        treasury.setSwapDeadlineSeconds(newSwapDeadlineSeconds);
    }

    function test_SetWstETHRevertWhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAddress.selector));
        vm.prank(admin);
        treasury.setWstETH(address(0));
    }

    function test_SetPUSDRevertWhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAddress.selector));
        vm.prank(admin);
        treasury.setPUSD(address(0));
    }
    
    function test_SetLendingVaultRevertWhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAddress.selector));
        vm.prank(admin);
        treasury.setLendingVault(address(0));
    }
    
    function test_SetLiquidationEngineRevertWhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAddress.selector));
        vm.prank(admin);
        treasury.setLiquidationEngine(address(0));
    }  

    function test_SetProtocolConfigRevertWhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAddress.selector));
        vm.prank(admin);
        treasury.setProtocolConfig(address(0));
    }

    function test_SetStabilityFundRevertWhenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAddress.selector));
        vm.prank(admin);
        treasury.setStabilityFund(address(0));
    }

    function test_SetSwapSlippageBpsRevertWhenAboveMax() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAmount.selector));
        vm.prank(admin);
        treasury.setSwapSlippageBps(2001);
    }

    function test_SetOracleStaleAfterRevertWhenZero() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAmount.selector));
        vm.prank(admin);
        treasury.setOracleStaleAfter(0);
    }

    function test_SetSwapDeadlineSecondsRevertWhenZero() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAmount.selector));
        vm.prank(admin);
        treasury.setSwapDeadlineSeconds(0);
    }

    /*//////////////////////////////////////////////////////////////
                            GETTERS
    //////////////////////////////////////////////////////////////*/

    function test_Pusd() public view {
        assertEq(address(treasury.pusd()), address(pusd));
    }

    function test_WstETH() public view {
        assertEq(address(treasury.wstETH()), address(wstETH));
    }

    function test_LendingVault() public view {
        assertEq(address(treasury.lendingVault()), address(lendingVault));
    }

    function test_LiquidationEngine() public view {
        assertEq(address(treasury.liquidationEngine()), address(liquidationEngine));
    }

    function test_ProtocolConfig() public view {
        assertEq(address(treasury.protocolConfig()), address(protocolConfig));
    }

    function test_StabilityFund() public view {
        assertEq(address(treasury.stabilityFund()), address(stabilityFund));
    }

    function test_SwapSlippageBps() public view {
        assertEq(treasury.swapSlippageBps(), 500);
    }

    function test_OracleStaleAfter() public view {
        assertEq(treasury.oracleStaleAfter(), 1 hours);
    }

    function test_SwapDeadlineSeconds() public view {
        assertEq(treasury.swapDeadlineSeconds(), 60);
    }

    function test_PusdBalance() public {
        // Setup Treasury with liquidity
        _setupTreasuryForLiquidation();
        
        assertEq(treasury.pusdBalance(), MINT_AMOUNT);
    }

    function test_WstETHBalance() public {
        assertEq(treasury.wstETHBalance(), 0);

        vm.startPrank(admin);
        wstETH.mint(admin, MINT_AMOUNT);
        wstETH.approve(address(treasury), MINT_AMOUNT);
        treasury.receiveWstETH(MINT_AMOUNT);
        vm.stopPrank();

        assertEq(treasury.wstETHBalance(), MINT_AMOUNT);
    }

    function test_TotalBackstopUsed() public {
        // Setup Treasury with liquidity
        _setupTreasuryForLiquidation();
        
        assertEq(treasury.totalBackstopUsed(), 0);

        vm.startPrank(address(lendingVault));
        treasury.provideBackstopFunds(MINT_AMOUNT);
        vm.stopPrank();

        assertEq(treasury.totalBackstopUsed(), MINT_AMOUNT);
    }

    function test_BackstopIouPusd() public {
        // Initially should be 0
        assertEq(treasury.backstopIouPusd(), 0);
        
        // Setup Treasury with some liquidity but not enough to cover full request
        vm.prank(address(lendingVault));
        pusd.mint(admin, MINT_AMOUNT);

        vm.startPrank(admin);
        pusd.approve(address(treasury), MINT_AMOUNT);
        treasury.receivePUSD(MINT_AMOUNT);
        vm.stopPrank();
        
        // Request more than available, should create IOU for shortfall
        vm.startPrank(address(lendingVault));
        uint256 providedAmount = treasury.provideBackstopFunds(MINT_AMOUNT + 10 ether);
        vm.stopPrank();
        
        // Should have IOU equal to the shortfall (MINT_AMOUNT - MINT_AMOUNT/2)
        assertEq(treasury.backstopIouPusd(), 10 ether);
        assertEq(providedAmount, MINT_AMOUNT);
    }   
}