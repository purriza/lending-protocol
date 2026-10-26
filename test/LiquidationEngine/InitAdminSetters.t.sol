// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TestSetup} from "../TestSetup.t.sol";

import {LiquidationEngine} from "../../contracts/LiquidationEngine.sol";
import {ILiquidationEngine} from "../../contracts/interfaces/ILiquidationEngine.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

interface IUUPS {
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(address newImplementation, bytes memory data) external;
}

contract LiquidationEngineInitAdminSettersTest is TestSetup {

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    // Mirror OZ custom errors for precise revert matching
    error AccessControlUnauthorizedAccount(address account, bytes32 role);
    error InvalidInitialization();
    
    /*//////////////////////////////////////////////////////////////
                            INITIALIZER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Initialize_RevertsOnZeroProtocolConfig() public {
        LiquidationEngine impl = new LiquidationEngine();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        LiquidationEngine le = LiquidationEngine(address(proxy));

        vm.expectRevert(abi.encodeWithSelector(ILiquidationEngine.LiquidationEngine__InvalidAddress.selector, address(0)));
        le.initialize(address(0), address(pusd));
    }

    function test_Initialize_RevertsOnZeroPUSD() public {
        LiquidationEngine impl = new LiquidationEngine();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        LiquidationEngine le = LiquidationEngine(address(proxy));

        vm.expectRevert(abi.encodeWithSelector(ILiquidationEngine.LiquidationEngine__InvalidAddress.selector, address(0)));
        le.initialize(address(protocolConfig), address(0));
    }

    function test_Initialize_RevertsOnDoubleInitialization() public {
        LiquidationEngine impl = new LiquidationEngine();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        LiquidationEngine le = LiquidationEngine(address(proxy));

        le.initialize(address(protocolConfig), address(pusd));

        vm.expectRevert(abi.encodeWithSelector(InvalidInitialization.selector));
        le.initialize(address(protocolConfig), address(pusd));
    }

    function test_Initialize_SetsInitialState() public view{
        // Admin set
        assertEq(liquidationEngine.hasRole(liquidationEngine.protocolConfig().ADMIN_ROLE(), admin), true, "admin should be initializer admin");
        // Upgrader set
        assertEq(liquidationEngine.hasRole(liquidationEngine.protocolConfig().UPGRADER_ROLE(), upgrader), true, "upgrader should be initializer upgrader");
        // Core addresses set
        assertEq(address(liquidationEngine.protocolConfig()), address(protocolConfig), "protocolConfig set by initializer");
        // Defaults
        assertEq(liquidationEngine.maxSlippage(), 1000, "default max slippage should be 1000 (10%)");
        assertEq(liquidationEngine.liquidationCounter(), 1, "liquidation counter should start at 1");
        assertEq(liquidationEngine.totalCollateralLiquidated(), 0, "total collateral liquidated should start at 0");
        assertEq(liquidationEngine.totalDebtCovered(), 0, "total debt covered should start at 0");
        assertFalse(liquidationEngine.paused(), "should start unpaused");
    }

    function test_Initialize_EmitsLiquidationEngineInitializedEvent() public {
        LiquidationEngine impl = new LiquidationEngine();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        LiquidationEngine le = LiquidationEngine(address(proxy));

        // Expect the LiquidationEngineInitialized event to be emitted
        vm.expectEmit(true, true, true, true);
        emit ILiquidationEngine.LiquidationEngineInitialized(
            address(protocolConfig),
            address(pusd),
            1000, // default maxSlippage
            2000  // default treasuryRevenueFee
        );

        le.initialize(address(protocolConfig), address(pusd));
    }

    /*//////////////////////////////////////////////////////////////
                               ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Admin_Pause_SetAndGetter() public {
        assertFalse(liquidationEngine.paused(), "Should start unpaused");

        vm.prank(admin);
        liquidationEngine.pause();
        assertTrue(liquidationEngine.paused(), "Should be paused after pause()");
    }

    function test_Admin_Unpause_SetAndGetter() public {
        vm.prank(admin);
        liquidationEngine.pause();
        assertTrue(liquidationEngine.paused(), "Should be paused");

        vm.prank(admin);
        liquidationEngine.unpause();
        assertFalse(liquidationEngine.paused(), "Should be unpaused after unpause()");
    }
    
    function test_Admin_SetProtocolConfig_SetAndGetter() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILiquidationEngine.LiquidationEngine__InvalidAddress.selector, address(0)));
        liquidationEngine.setProtocolConfig(address(0));

        address newConfig = address(0xC0);
        vm.prank(admin);
        vm.expectEmit(true, true, false, true, address(liquidationEngine));
        emit ILiquidationEngine.ProtocolConfigUpdated(address(protocolConfig), newConfig);
        liquidationEngine.setProtocolConfig(newConfig);
        assertEq(address(liquidationEngine.protocolConfig()), newConfig, "Protocol config should match");
    }

    function test_Admin_SetLendingVault_SetAndGetter() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILiquidationEngine.LiquidationEngine__InvalidAddress.selector, address(0)));
        liquidationEngine.setLendingVault(address(0));

        address newVault = address(0xBA);
        vm.prank(admin);
        vm.expectEmit(true, true, false, true, address(liquidationEngine));
        emit ILiquidationEngine.LendingVaultUpdated(address(lendingVault), newVault);
        liquidationEngine.setLendingVault(newVault);
        assertEq(address(liquidationEngine.lendingVault()), newVault, "Lending vault should match");
    }

    function test_Admin_SetStabilityFund_SetAndGetter() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILiquidationEngine.LiquidationEngine__InvalidAddress.selector, address(0)));
        liquidationEngine.setStabilityFund(address(0));

        address newStabilityFund = address(0x5F);
        vm.prank(admin);
        vm.expectEmit(true, true, false, true, address(liquidationEngine));
        emit ILiquidationEngine.StabilityFundUpdated(address(stabilityFund), newStabilityFund);
        liquidationEngine.setStabilityFund(newStabilityFund);
        assertEq(address(liquidationEngine.stabilityFund()), newStabilityFund, "StabilityFund should match");
    }

    function test_Admin_SetTreasury_SetAndGetter() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILiquidationEngine.LiquidationEngine__InvalidAddress.selector, address(0)));
        liquidationEngine.setTreasury(address(0));

        address newTreasury = address(0xFEE);
        vm.prank(admin);
        vm.expectEmit(true, true, false, true, address(liquidationEngine));
        emit ILiquidationEngine.TreasuryUpdated(address(treasury), newTreasury);
        liquidationEngine.setTreasury(newTreasury);
        assertEq(address(liquidationEngine.treasury()), newTreasury, "Treasury should match");
    }





    function test_Admin_SetMaxSlippage_SetAndGetter() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILiquidationEngine.LiquidationEngine__InvalidPercentage.selector));
        liquidationEngine.setMaxSlippage(2001); // > 20%

        uint256 newSlippage = 1000; // 10%
        vm.prank(admin);
        vm.expectEmit(true, true, false, true, address(liquidationEngine));
        emit ILiquidationEngine.MaxSlippageUpdated(1000, newSlippage); // Default is 1000 (10%)
        liquidationEngine.setMaxSlippage(newSlippage);
        assertEq(liquidationEngine.maxSlippage(), newSlippage, "Max slippage should match");
    }

    function test_Admin_SetTreasuryRevenueFee_SetAndGetter() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILiquidationEngine.LiquidationEngine__InvalidPercentage.selector));
        liquidationEngine.setTreasuryRevenueFee(5001); // > 50%

        uint256 newFee = 3000; // 30%
        vm.prank(admin);
        vm.expectEmit(true, true, false, true, address(liquidationEngine));
        emit ILiquidationEngine.TreasuryRevenueFeeUpdated(2000, newFee);
        liquidationEngine.setTreasuryRevenueFee(newFee);
        assertEq(liquidationEngine.treasuryRevenueFee(), newFee, "Treasury revenue fee should match");
    }

    /*//////////////////////////////////////////////////////////////
                        ONLY ADMIN MODIFIER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Admin_OnlyAdmin_SetMaxSlippage_RevertsForNonAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, liquidationEngine.protocolConfig().ADMIN_ROLE()));
        liquidationEngine.setMaxSlippage(1000);
        vm.stopPrank();
    }

    function test_Admin_OnlyAdmin_SetLendingVault_RevertsForNonAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, liquidationEngine.protocolConfig().ADMIN_ROLE()));
        liquidationEngine.setLendingVault(address(0xBA));
        vm.stopPrank();
    }

    function test_Admin_OnlyAdmin_SetProtocolConfig_RevertsForNonAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, liquidationEngine.protocolConfig().ADMIN_ROLE()));
        liquidationEngine.setProtocolConfig(address(0xC0));
        vm.stopPrank();
    }

    function test_Admin_OnlyAdmin_SetTreasury_RevertsForNonAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, liquidationEngine.protocolConfig().ADMIN_ROLE()));
        liquidationEngine.setTreasury(address(0xFEE));
        vm.stopPrank();
    }

    function test_Admin_OnlyAdmin_SetStabilityFund_RevertsForNonAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, liquidationEngine.protocolConfig().ADMIN_ROLE()));
        liquidationEngine.setStabilityFund(address(0x5F));
        vm.stopPrank();
    }

    function test_Admin_OnlyAdmin_SetTreasuryRevenueFee_RevertsForNonAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, liquidationEngine.protocolConfig().ADMIN_ROLE()));
        liquidationEngine.setTreasuryRevenueFee(3000);
        vm.stopPrank();
    }

    function test_Admin_OnlyAdmin_Pause_RevertsForNonAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, liquidationEngine.protocolConfig().ADMIN_ROLE()));
        liquidationEngine.pause();
        vm.stopPrank();
    }

    function test_Admin_OnlyAdmin_Unpause_RevertsForNonAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, liquidationEngine.protocolConfig().ADMIN_ROLE()));
        liquidationEngine.unpause();
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           UUPS UPGRADE COVERAGE
    //////////////////////////////////////////////////////////////*/

    function test_Upgrade_NonUpgraderReverts() public {
        LiquidationEngine newImpl = new LiquidationEngine();
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, liquidationEngine.protocolConfig().UPGRADER_ROLE()));
        IUUPS(address(liquidationEngine)).upgradeToAndCall(address(newImpl), "");
        vm.stopPrank();
    }

    function test_Upgrade_UpgraderSucceeds() public {
        LiquidationEngine newImpl = new LiquidationEngine();
        vm.prank(upgrader);
        IUUPS(address(liquidationEngine)).upgradeToAndCall(address(newImpl), "");
    }
}
