// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {StabilityFund} from "../../contracts/StabilityFund.sol";
import {IStabilityFund} from "../../contracts/interfaces/IStabilityFund.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

interface IUUPS {
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(address newImplementation, bytes memory data) external;
}

contract StabilityFundInitAdminTest is TestSetup {
    error InvalidInitialization();
    error AccessControlUnauthorizedAccount(address account, bytes32 role);

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            STATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_init_SetsContractStateCorrectly() public view {
        assertEq(address(stabilityFund.protocolConfig()), address(protocolConfig));
        assertEq(stabilityFund.paused(), false);

        assertEq(stabilityFund.hasRole(stabilityFund.protocolConfig().ADMIN_ROLE(), admin), true);
        assertEq(stabilityFund.hasRole(stabilityFund.protocolConfig().UPGRADER_ROLE(), upgrader), true);

        assertEq(address(stabilityFund.pusd()), address(pusd));
        assertEq(address(stabilityFund.wpusd()), address(wpusd));
        assertEq(stabilityFund.lendingVault(), address(lendingVault));
        assertEq(stabilityFund.liquidationEngine(), address(liquidationEngine));
        assertEq(stabilityFund.treasury(), address(treasury));

        assertEq(stabilityFund.exchangeRate(), 1e18);
        assertEq(stabilityFund.getMinDepositAmount(), 0.001 ether);
        assertEq(stabilityFund.totalPusdLocked(), 0);
        assertEq(stabilityFund.getPrecision(), 1e18);
        assertEq(stabilityFund.getAbsoluteMinDepositAmount(), 1e12);
    }

    /*//////////////////////////////////////////////////////////////
                            EVENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_init_EmitsStabilityFundInitializedEvent() public {
        uint256 exchangeRate = 1e18;
        uint256 minDepositAmount = 0.001 ether;
        
        StabilityFund stabilityFundImpl = new StabilityFund();
        
        ERC1967Proxy stabilityFundProxy = new ERC1967Proxy(
            address(stabilityFundImpl),
            ""
        );

        StabilityFund stabilityFund = StabilityFund(address(stabilityFundProxy));

        vm.expectEmit(true, true, true, true);
        emit IStabilityFund.StabilityFundInitialized(address(protocolConfig), address(pusd), address(wpusd), exchangeRate, minDepositAmount);
        stabilityFund.initialize(
            address(protocolConfig),
            address(pusd), 
            address(wpusd)
        );
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initialize_revertsZeroAddress() public {
        bytes memory initData = "";
        address implementation = address(new StabilityFund());
        address proxy = address(new ERC1967Proxy(implementation, initData));
        StabilityFund newStabilityFund = StabilityFund(proxy);

        vm.startPrank(admin);

        vm.expectRevert(abi.encodeWithSelector(IStabilityFund.StabilityFund__InvalidAddress.selector));
        newStabilityFund.initialize(
            address(0),
            address(pusd),
            address(wpusd)
        );

        vm.expectRevert(abi.encodeWithSelector(IStabilityFund.StabilityFund__InvalidAddress.selector));
        newStabilityFund.initialize(
            address(protocolConfig),
            address(0), 
            address(wpusd)
        );

        vm.expectRevert(abi.encodeWithSelector(IStabilityFund.StabilityFund__InvalidAddress.selector));
        newStabilityFund.initialize(
            address(protocolConfig),
            address(pusd), 
            address(0)
        );
        vm.stopPrank();
    }

    function test_initializeRevertsIfAlreadyInitialized() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(InvalidInitialization.selector));
        stabilityFund.initialize(
            address(protocolConfig),
            address(pusd), 
            address(wpusd)
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                               ADMIN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Admin_PauseUnpause_OnlyAdmin() public {
        vm.prank(admin);
        stabilityFund.pause();
        assertTrue(stabilityFund.paused(), "StabilityFund should be paused");

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, stabilityFund.protocolConfig().ADMIN_ROLE()));
        stabilityFund.unpause();
        vm.stopPrank();

        vm.prank(admin);
        stabilityFund.unpause();
        assertFalse(stabilityFund.paused(), "StabilityFund should be unpaused");
    }

    /*//////////////////////////////////////////////////////////////
                           UUPS UPGRADE COVERAGE
    //////////////////////////////////////////////////////////////*/

    function test_Upgrade_NonUpgraderReverts() public {
        StabilityFund newImpl = new StabilityFund();
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, stabilityFund.protocolConfig().UPGRADER_ROLE()));
        IUUPS(address(stabilityFund)).upgradeToAndCall(address(newImpl), "");
        vm.stopPrank();
    }

    function test_Upgrade_UpgraderSucceeds() public {
        StabilityFund newImpl = new StabilityFund();
        vm.prank(upgrader);
        IUUPS(address(stabilityFund)).upgradeToAndCall(address(newImpl), "");
    }
}