// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {wPUSD} from "../../contracts/wPUSD.sol";
import {IwPUSD} from "../../contracts/interfaces/IwPUSD.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract wPUSDInitTest is TestSetup {
    error InvalidInitialization();

    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            STATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_init_SetsContractStateCorrectly() public view {
        assertEq(wpusd.hasRole(wpusd.protocolConfig().ADMIN_ROLE(), admin), true);
        assertEq(wpusd.hasRole(wpusd.protocolConfig().UPGRADER_ROLE(), upgrader), true);
        assertEq(address(wpusd.protocolConfig()), address(protocolConfig));
        assertEq(wpusd.decimals(), 18);
        assertEq(wpusd.stabilityFund(), address(stabilityFund));
        assertEq(wpusd.name(), "Wrapped Protocol USD");
        assertEq(wpusd.symbol(), "wPUSD");
    }

    /*//////////////////////////////////////////////////////////////
                            EVENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_init_EmitswPUSDInitializedEvent() public {
        
        wPUSD newWPUSDImpl = new wPUSD();
        
        ERC1967Proxy newWPUSDProxy = new ERC1967Proxy(
            address(newWPUSDImpl),
            ""
        );

        wPUSD newWPUSD = wPUSD(address(newWPUSDProxy));

        vm.expectEmit(true, true, true, true);
        emit IwPUSD.wPUSDInitialized(address(protocolConfig));
        newWPUSD.initialize(
            address(protocolConfig)
        );
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initialize_revertsZeroAddress() public {
        bytes memory initData = "";
        address implementation = address(new wPUSD());
        address proxy = address(new ERC1967Proxy(implementation, initData));
        wPUSD newWPUSD = wPUSD(proxy);

        vm.expectRevert(abi.encodeWithSelector(IwPUSD.wPUSD__InvalidAddress.selector));
        newWPUSD.initialize(
            address(0)
        );
    }

    function test_initializeRevertsIfAlreadyInitialized() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(InvalidInitialization.selector));
        wpusd.initialize(
            address(protocolConfig)
        );
        vm.stopPrank();
    }
}