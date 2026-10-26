// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {TestSetup} from "../TestSetup.t.sol";

import {LendingVault} from "../../contracts/LendingVault.sol";
import {ILendingVault} from "../../contracts/interfaces/ILendingVault.sol";
import {ProtocolConfig} from "../../contracts/ProtocolConfig.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

interface IUUPS {
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(address newImplementation, bytes memory data) external;
}

contract LendingVaultInitAdminSettersTest is TestSetup {

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    // Mirror OZ custom errors for precise revert matching
    error AccessControlUnauthorizedAccount(address account, bytes32 role);
    error InvalidInitialization();
    
    /*//////////////////////////////////////////////////////////////
                            INITIALIZER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Initialize_RevertsOnZeroPUSD() public {
        LendingVault impl = new LendingVault();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        LendingVault lv = LendingVault(address(proxy));

        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAddress.selector, address(0)));
        lv.initialize(address(0), address(protocolConfig), address(wstETH));
    }

    function test_Initialize_RevertsOnZeroProtocolConfig() public {
        LendingVault impl = new LendingVault();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        LendingVault lv = LendingVault(address(proxy));
        
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAddress.selector, address(0)));
        lv.initialize(address(pusd), address(0), address(wstETH));
    }

    function test_Initialize_RevertsOnZeroCollateral() public {
        LendingVault impl = new LendingVault();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        LendingVault lv = LendingVault(address(proxy));
        
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAddress.selector, address(0)));
        lv.initialize(address(pusd), address(protocolConfig), address(0));
    }

    function test_Initialize_DoubleCallReverts() public {
        // Calling initialize again on the proxy should revert due to Initializable guard
        vm.expectRevert(abi.encodeWithSelector(InvalidInitialization.selector));
        LendingVault(address(lendingVault)).initialize(address(pusd), address(protocolConfig), address(wstETH));
    }

    function test_Initialize_SetsInitialState() public view {
        // Admin set
        assertEq(lendingVault.hasRole(lendingVault.protocolConfig().ADMIN_ROLE(), admin), true, "admin should be initializer admin");
        assertEq(lendingVault.hasRole(lendingVault.protocolConfig().UPGRADER_ROLE(), upgrader), true, "upgrader should be initializer upgrader");
        // Core addresses set
        assertEq(address(lendingVault.pusd()), address(pusd), "pusd set by initializer");
        assertEq(address(lendingVault.protocolConfig()), address(protocolConfig), "protocolConfig set by initializer");
        assertEq(address(lendingVault.collateralToken()), address(wstETH), "collateral token set");
        // Defaults
        assertEq(lendingVault.aprBasisPoints(), 50, "default APR bps should be 50");
        assertEq(lendingVault.globalInterestIndex(), 1e12, "globalInterestIndex should start at PRECISION");
        assertEq(lendingVault.totalCollateral(), 0, "totalCollateral should start at 0");
        assertEq(lendingVault.totalDebt(), 0, "totalDebt should start at 0");
        assertFalse(lendingVault.paused(), "should start unpaused");
        // Timestamp set to current block
        assertEq(lendingVault.lastInterestUpdate(), block.timestamp, "lastInterestUpdate set to now");
        // Set during TestSetup connections
        assertEq(address(lendingVault.liquidationEngine()), address(liquidationEngine), "liquidation engine should be connected");
        assertEq(address(lendingVault.stabilityFund()), address(stabilityFund), "stability fund should be connected");
        assertEq(lendingVault.minDepositAmount(), 0.01 ether, "min deposit amount should be 0.01 ether");
    }

    function test_Initialize_EmitsEvent() public {
        LendingVault impl = new LendingVault();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        LendingVault lv = LendingVault(address(proxy));

        // Expect the LendingVaultInitialized event to be emitted with correct parameters
        vm.expectEmit(true, true, true, true, address(lv));
        emit ILendingVault.LendingVaultInitialized(
            address(pusd),           // pusd
            address(protocolConfig), // protocolConfig
            address(wstETH),         // collateralToken
            50,                      // aprBasisPoints (default 0.5%)
            block.timestamp,         // lastInterestUpdate
            1e12,                    // globalInterestIndex (PRECISION)
            0.01 ether              // minDepositAmount
        );

        lv.initialize(address(pusd), address(protocolConfig), address(wstETH));
    }

    /*//////////////////////////////////////////////////////////////
                               ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Admin_PauseUnpause_OnlyAdmin() public {
        vm.prank(admin);
        lendingVault.pause();
        assertTrue(lendingVault.paused(), "Vault should be paused");

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, lendingVault.protocolConfig().ADMIN_ROLE()));
        lendingVault.unpause();
        vm.stopPrank();

        vm.prank(admin);
        lendingVault.unpause();
        assertFalse(lendingVault.paused(), "Vault should be unpaused");
    }

    function test_Admin_SetProtocolConfig_SetAndGetter() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAddress.selector, address(0)));
        lendingVault.setProtocolConfig(address(0));

        vm.prank(admin);
        vm.expectEmit(true, true, false, true, address(lendingVault));
        emit ILendingVault.ProtocolConfigUpdated(address(protocolConfig), address(protocolConfig));
        lendingVault.setProtocolConfig(address(protocolConfig));
        assertEq(address(lendingVault.protocolConfig()), address(protocolConfig), "ProtocolConfig should match");
    }

    function test_Admin_SetLiquidationEngine_SetAndGetter() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAddress.selector, address(0)));
        lendingVault.setLiquidationEngine(address(0));

        address engine = address(0xE1);
        vm.prank(admin);
        vm.expectEmit(true, true, false, true, address(lendingVault));
        emit ILendingVault.LiquidationEngineUpdated(address(liquidationEngine), engine);
        lendingVault.setLiquidationEngine(engine);
        assertEq(address(lendingVault.liquidationEngine()), engine, "Liquidation engine should match");
    }

    function test_Admin_SetStabilityFund_SetAndGetter() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAddress.selector, address(0)));
        lendingVault.setStabilityFund(address(0));

        address fund = address(0xF1);
        vm.prank(admin);
        vm.expectEmit(true, true, false, true, address(lendingVault));
        emit ILendingVault.StabilityFundUpdated(address(stabilityFund), fund);
        lendingVault.setStabilityFund(fund);
        assertEq(address(lendingVault.stabilityFund()), fund, "Stability fund should match");
    }

    function test_Admin_SetTreasury_SetAndGetter() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAddress.selector, address(0)));
        lendingVault.setTreasury(address(0));

        address fund = address(0xF1);
        vm.prank(admin);
        vm.expectEmit(true, true, false, true, address(lendingVault));
        emit ILendingVault.TreasuryUpdated(address(treasury), fund);
        lendingVault.setTreasury(fund);
        assertEq(address(lendingVault.treasury()), fund, "Treasury should match");
    }

    function test_Admin_SetCollateralToken_SetAndGetter() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAddress.selector, address(0)));
        lendingVault.setCollateralToken(address(0));

        address newCollateral = address(0xC01);
        vm.prank(admin);
        vm.expectEmit(true, true, false, true, address(lendingVault));
        emit ILendingVault.CollateralTokenUpdated(address(wstETH), newCollateral);
        lendingVault.setCollateralToken(newCollateral);
        assertEq(address(lendingVault.collateralToken()), newCollateral, "Collateral token should match");
    }

    function test_Admin_SetProtocolConfig_RevertsForNonAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, lendingVault.protocolConfig().ADMIN_ROLE()));
        lendingVault.setProtocolConfig(address(protocolConfig));
        vm.stopPrank();
    }

    function test_Admin_SetLiquidationEngine_RevertsForNonAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, lendingVault.protocolConfig().ADMIN_ROLE()));
        lendingVault.setLiquidationEngine(address(0xE2));
        vm.stopPrank();
    }

    function test_Admin_SetStabilityFund_RevertsForNonAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, lendingVault.protocolConfig().ADMIN_ROLE()));
        lendingVault.setStabilityFund(address(0xF2));
        vm.stopPrank();
    }

    function test_Admin_SetTreasury_RevertsForNonAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, lendingVault.protocolConfig().ADMIN_ROLE()));
        lendingVault.setTreasury(address(0xF2));
        vm.stopPrank();
    }

    function test_Admin_SetCollateralToken_RevertsForNonAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, lendingVault.protocolConfig().ADMIN_ROLE()));
        lendingVault.setCollateralToken(address(0xC02));
        vm.stopPrank();
    }

    function test_Admin_SetMinDepositAmount_SetAndGetter() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAmount.selector, 0));
        lendingVault.setMinDepositAmount(0);

        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit ILendingVault.MinDepositAmountUpdated(0.01 ether, 1 ether);
        lendingVault.setMinDepositAmount(1 ether);
        assertEq(lendingVault.minDepositAmount(), 1 ether, "Min deposit amount should match");
    }

    function test_Admin_SetMinDepositAmount_RevertsForNonAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, lendingVault.protocolConfig().ADMIN_ROLE()));
        lendingVault.setMinDepositAmount(1 ether);
        vm.stopPrank();
    }

    function test_Admin_SetAPR_SetAndGetter() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAPR.selector, 10_001));
        lendingVault.setAPR(10_001); // Over 100%

        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit ILendingVault.InterestRateUpdated(50, 200); // 50 is initial APR, 200 is new
        lendingVault.setAPR(200);
        assertEq(lendingVault.getAPRbps(), 200, "APR should match");
    }

    function test_Admin_SetAPR_RevertsForNonAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, lendingVault.protocolConfig().ADMIN_ROLE()));
        lendingVault.setAPR(200);
        vm.stopPrank();
    }

    function test_Admin_SetLiquidationBot_SetAndGetter() public {
        address bot = address(0xB07);
        
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAddress.selector, address(0)));
        lendingVault.setLiquidationBot(address(0), true);

        // Test authorizing a bot
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit ILendingVault.LiquidationBotUpdated(bot, true);
        lendingVault.setLiquidationBot(bot, true);
        assertTrue(lendingVault.isLiquidationBot(bot), "Bot should be authorized");

        // Test unauthorizing a bot
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit ILendingVault.LiquidationBotUpdated(bot, false);
        lendingVault.setLiquidationBot(bot, false);
        assertFalse(lendingVault.isLiquidationBot(bot), "Bot should be unauthorized");
    }

    function test_Admin_SetLiquidationBot_RevertsForNonAdmin() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, lendingVault.protocolConfig().ADMIN_ROLE()));
        lendingVault.setLiquidationBot(address(0xB07), true);
        vm.stopPrank();
    }

    function test_SetLiquidationBot_Reverts_InvalidAddress() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ILendingVault.LendingVault__InvalidAddress.selector, address(0)));
        lendingVault.setLiquidationBot(address(0), true);
    }

    function test_Admin_CanGrantRole_RevokeRole() public {
        assertFalse(lendingVault.hasRole(lendingVault.protocolConfig().ADMIN_ROLE(), user1), "User1 should not be admin");
        vm.startPrank(admin);
        lendingVault.grantRole(lendingVault.protocolConfig().ADMIN_ROLE(), user1);
        assertTrue(lendingVault.hasRole(lendingVault.protocolConfig().ADMIN_ROLE(), user1), "User1 should be admin");

        lendingVault.revokeRole(lendingVault.protocolConfig().ADMIN_ROLE(), user1);
        assertFalse(lendingVault.hasRole(lendingVault.protocolConfig().ADMIN_ROLE(), user1), "User1 should not be admin");
        vm.stopPrank();
    }

    function test_GrantRole_RevertsForNonAdmin() public {
        bytes32 adminRole = lendingVault.protocolConfig().ADMIN_ROLE();
        bytes32 defaultAdminRole = lendingVault.DEFAULT_ADMIN_ROLE();
        
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, defaultAdminRole));
        lendingVault.grantRole(adminRole, user1);
        vm.stopPrank();
    }
    
    function test_RevokeRole_RevertsForNonAdmin() public {
        bytes32 adminRole = lendingVault.protocolConfig().ADMIN_ROLE();
        bytes32 defaultAdminRole = lendingVault.DEFAULT_ADMIN_ROLE();
        
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, defaultAdminRole));
        lendingVault.revokeRole(adminRole, user1);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           UUPS UPGRADE COVERAGE
    //////////////////////////////////////////////////////////////*/

    function test_Upgrade_NonUpgraderReverts() public {
        LendingVault newImpl = new LendingVault();
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, lendingVault.protocolConfig().UPGRADER_ROLE()));
        IUUPS(address(lendingVault)).upgradeToAndCall(address(newImpl), "");
        vm.stopPrank();
    }

    function test_Upgrade_UpgraderSucceeds() public {
        LendingVault newImpl = new LendingVault();
        vm.prank(upgrader);
        IUUPS(address(lendingVault)).upgradeToAndCall(address(newImpl), "");
    }
}


