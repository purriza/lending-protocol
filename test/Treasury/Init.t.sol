// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {ITreasury} from "../../contracts/interfaces/ITreasury.sol";
import {Treasury} from "../../contracts/Treasury.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TreasuryInitTest is TestSetup {
    error InvalidInitialization();

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            STATE CHECKS
    //////////////////////////////////////////////////////////////*/

    function test_InitializesCorrectly() public view {
        assertEq(treasury.hasRole(treasury.protocolConfig().ADMIN_ROLE(), admin), true);
        assertEq(treasury.hasRole(treasury.protocolConfig().UPGRADER_ROLE(), upgrader), true);
        assertEq(address(treasury.protocolConfig()), address(protocolConfig));
        assertEq(treasury.pusd(), address(pusd));
        assertEq(treasury.wstETH(), address(wstETH));

        assertEq(treasury.totalBackstopUsed(), 0);
        assertEq(treasury.pusdBalance(), 0);
        assertEq(treasury.wstETHBalance(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            EVENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_init_EmitsTreasuryInitializedEvent() public {
        Treasury newTreasury = _deployNewTreasury();

        vm.expectEmit(true, true, true, true);
        emit ITreasury.TreasuryInitialized(address(protocolConfig), address(pusd), address(wstETH));
        newTreasury.initialize(address(protocolConfig), address(pusd), address(wstETH));
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initialize_revertsZeroAddress() public {
        
        Treasury newTreasury = _deployNewTreasury();

        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAddress.selector));
        newTreasury.initialize(address(0), address(pusd), address(wstETH));

        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAddress.selector));
        newTreasury.initialize(address(protocolConfig), address(0), address(wstETH));

        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAddress.selector));
        newTreasury.initialize(address(protocolConfig), address(pusd), address(0));
    }

    function test_initializeRevertsIfAlreadyInitialized() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(InvalidInitialization.selector));
        treasury.initialize(address(protocolConfig), address(pusd), address(wstETH));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _deployNewTreasury() internal returns (Treasury) {
        Treasury newTreasuryImpl = new Treasury();
        ERC1967Proxy newTreasuryProxy = new ERC1967Proxy(
            address(newTreasuryImpl),
            ""
        );
        return Treasury(address(newTreasuryProxy));
    }
}