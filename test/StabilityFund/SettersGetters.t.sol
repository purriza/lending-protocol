// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {IStabilityFund} from "../../contracts/interfaces/IStabilityFund.sol";

contract StabilityFundSettersGettersTest is TestSetup {

    error AccessControlUnauthorizedAccount(address account, bytes32 role);

    uint256 initialMinDepositAmount = 0.001 ether;
    uint256 newMinDepositAmount = 0.00001 ether;

    address newLendingVault = makeAddr("newLendingVault");
    address newLiquidationEngine = makeAddr("newLiquidationEngine");
    address newTreasury = makeAddr("newTreasury");

    function setUp() public override {
        super.setUp();

        _mintPUSD(user1, INITIAL_PUSD_AMOUNT);
        _mintPUSD(user2, INITIAL_PUSD_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                            SETTERS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                            STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    function test_setMinDepositAmountSuccess() public {
        assertEq(stabilityFund.getMinDepositAmount(), initialMinDepositAmount);
        
        vm.prank(admin);
        stabilityFund.setMinDepositAmount(newMinDepositAmount);

        assertEq(stabilityFund.getMinDepositAmount(), newMinDepositAmount);
    }

    function test_setLendingVaultSuccess() public {
        assertEq(stabilityFund.lendingVault(), address(lendingVault));
        
        vm.prank(admin);
        stabilityFund.setLendingVault(newLendingVault);

        assertEq(stabilityFund.lendingVault(), newLendingVault);
    }

    function test_setLiquidationEngineSuccess() public {
        assertEq(stabilityFund.liquidationEngine(), address(liquidationEngine));
        
        vm.prank(admin);
        stabilityFund.setLiquidationEngine(newLiquidationEngine);

        assertEq(stabilityFund.liquidationEngine(), newLiquidationEngine);
    }

    function test_setTreasurySuccess() public {
        assertEq(stabilityFund.treasury(), address(treasury));
        
        vm.prank(admin);
        stabilityFund.setTreasury(newTreasury);

        assertEq(stabilityFund.treasury(), newTreasury);
    }

    /*//////////////////////////////////////////////////////////////
                            EVENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MinDepositAmountUpdatedEvent() public {
        vm.expectEmit(true, true, false, false);
        emit IStabilityFund.MinDepositAmountUpdated(initialMinDepositAmount, newMinDepositAmount);

        vm.prank(admin);
        stabilityFund.setMinDepositAmount(newMinDepositAmount);
    }

    function test_LendingVaultUpdatedEvent() public {
        vm.expectEmit(true, true, false, false);
        emit IStabilityFund.LendingVaultUpdated(address(lendingVault), newLendingVault);

        vm.prank(admin);
        stabilityFund.setLendingVault(newLendingVault);
    }

    function test_LiquidationEngineUpdatedEvent() public {
        vm.expectEmit(true, true, false, false);
        emit IStabilityFund.LiquidationEngineUpdated(address(liquidationEngine), newLiquidationEngine);

        vm.prank(admin);
        stabilityFund.setLiquidationEngine(newLiquidationEngine);
    }

    function test_TreasuryUpdatedEvent() public {
        vm.expectEmit(true, true, false, false);
        emit IStabilityFund.TreasuryUpdated(address(treasury), newTreasury);

        vm.prank(admin);
        stabilityFund.setTreasury(newTreasury);
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setMinDepositAmountReverts_AccessControlUnauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, stabilityFund.protocolConfig().ADMIN_ROLE()));

        vm.startPrank(user1);
        stabilityFund.setMinDepositAmount(newMinDepositAmount);
        vm.stopPrank();
    }

    function test_setMinDepositAmountReverts_InvalidAmount() public {
        uint256 invalidMinDepositAmount = stabilityFund.getAbsoluteMinDepositAmount() - 1;
        
        vm.expectRevert(abi.encodeWithSelector(IStabilityFund.StabilityFund__InvalidAmount.selector, invalidMinDepositAmount));
        vm.prank(admin);
        stabilityFund.setMinDepositAmount(invalidMinDepositAmount);
    }

    function test_setLendingVaultReverts_AccessControlUnauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, stabilityFund.protocolConfig().ADMIN_ROLE()));

        vm.startPrank(user1);
        stabilityFund.setLendingVault(newLendingVault);
        vm.stopPrank();
    }

    function test_setLiquidationEngineReverts_AccessControlUnauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, stabilityFund.protocolConfig().ADMIN_ROLE()));

        vm.startPrank(user1);
        stabilityFund.setLiquidationEngine(newLiquidationEngine);
        vm.stopPrank();
    }

    function test_setTreasuryReverts_AccessControlUnauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, stabilityFund.protocolConfig().ADMIN_ROLE()));

        vm.startPrank(user1);
        stabilityFund.setTreasury(newTreasury);
        vm.stopPrank();
    }

    function test_setLendingVaultReverts_InvalidAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IStabilityFund.StabilityFund__InvalidAddress.selector));

        vm.prank(admin);
        stabilityFund.setLendingVault(address(0));
    }

    function test_setLiquidationEngineReverts_InvalidAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IStabilityFund.StabilityFund__InvalidAddress.selector));

        vm.prank(admin);
        stabilityFund.setLiquidationEngine(address(0));
    }

    function test_setTreasuryReverts_InvalidAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IStabilityFund.StabilityFund__InvalidAddress.selector));

        vm.prank(admin);
        stabilityFund.setTreasury(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                            GETTERS
    //////////////////////////////////////////////////////////////*/

    function test_getAbsoluteMinDepositAmount() public view {
        assertEq(stabilityFund.getAbsoluteMinDepositAmount(), 1e12);
    }

    function test_getPrecision() public view {
        assertEq(stabilityFund.getPrecision(), 1e18);
    }

    function test_getMinDepositAmount() public {
        assertEq(stabilityFund.getMinDepositAmount(), initialMinDepositAmount);

        vm.prank(admin);
        stabilityFund.setMinDepositAmount(newMinDepositAmount);

        assertEq(stabilityFund.getMinDepositAmount(), newMinDepositAmount);
    }

    function test_getPusdAddress() public view {
        assertEq(stabilityFund.getPusdAddress(), address(pusd));
    }

    function test_getWpusdAddress() public view {
        assertEq(stabilityFund.getWpusdAddress(), address(wpusd));
    }

    function test_lendingVault() public {
        assertEq(stabilityFund.lendingVault(), address(lendingVault));

        vm.prank(admin);
        stabilityFund.setLendingVault(newLendingVault);

        assertEq(stabilityFund.lendingVault(), newLendingVault);
    }

    function test_liquidationEngine() public {
        assertEq(stabilityFund.liquidationEngine(), address(liquidationEngine));

        vm.prank(admin);
        stabilityFund.setLiquidationEngine(newLiquidationEngine);

        assertEq(stabilityFund.liquidationEngine(), newLiquidationEngine);
    }

    function test_treasury() public {
        assertEq(stabilityFund.treasury(), address(treasury));

        vm.prank(admin);
        stabilityFund.setTreasury(newTreasury);

        assertEq(stabilityFund.treasury(), newTreasury);
    }

    function test_exchangeRate() public view {
        assertEq(stabilityFund.exchangeRate(), 1e18);
    }

    function test_totalPusdLocked() public view {
        assertEq(stabilityFund.totalPusdLocked(), 0);
    }
}