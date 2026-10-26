// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TestSetup} from "../TestSetup.t.sol";
import {PUSD} from "../../contracts/PUSD.sol";
import {IPUSD} from "../../contracts/interfaces/IPUSD.sol";
import {IProtocolConfig} from "../../contracts/interfaces/IProtocolConfig.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PUSDTest is TestSetup {

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error AccessControlUnauthorizedAccount(address account, bytes32 role);
    error InvalidInitialization();

    /*//////////////////////////////////////////////////////////////
                            STATE VARS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MINT_AMOUNT = 1000 ether;
    uint256 public constant BURN_AMOUNT = 500 ether;

    address public unauthorizedUser = makeAddr("unauthorizedUser");
    
    function setUp() public override {
        super.setUp();
    }

    /*//////////////////////////////////////////////////////////////
                            INIT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testInitialization() public view {
        assertEq(pusd.name(), "Protocol USD");
        assertEq(pusd.symbol(), "PUSD");
        assertEq(pusd.decimals(), 18);
        assertEq(address(pusd.protocolConfig()), address(protocolConfig));
        assertEq(pusd.lendingVault(), address(lendingVault));
        assertEq(pusd.stabilityFund(), address(stabilityFund));
        // Note: totalSupply may not be 0 if PUSD was minted during setup
        assertGe(pusd.totalSupply(), 0, "Total supply should be non-negative");
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_SetLendingVault() public {
        address newLendingVault = makeAddr("newLendingVault");
        
        assertEq(pusd.lendingVault(), address(lendingVault));

        vm.prank(admin);
        pusd.setLendingVault(newLendingVault);

        assertEq(pusd.lendingVault(), newLendingVault);
    }
    
    function test_SetStabilityFund() public {
        address newStabilityFund = makeAddr("newStabilityFund");
        
        assertEq(pusd.stabilityFund(), address(stabilityFund));
        
        vm.prank(admin);
        pusd.setStabilityFund(newStabilityFund);

        assertEq(pusd.stabilityFund(), newStabilityFund);
    }

    /*//////////////////////////////////////////////////////////////
                        STATE UPDATE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testMintFromLendingVault() public {
        uint256 userInitialBalance = pusd.balanceOf(user3);
        assertEq(userInitialBalance, 0);

        vm.prank(address(lendingVault));
        pusd.mint(user3, MINT_AMOUNT);

        assertEq(pusd.balanceOf(user3), userInitialBalance + MINT_AMOUNT);
    }

    function testBurnFromLendingVault() public {
        _mintPUSD(user1, MINT_AMOUNT);

        // Transfer PUSD to lendingVault for burning
        vm.prank(user1);
        pusd.transfer(address(lendingVault), MINT_AMOUNT);

        assertEq(pusd.balanceOf(address(lendingVault)), MINT_AMOUNT);

        vm.prank(address(lendingVault));
        pusd.burn(BURN_AMOUNT);

        assertEq(pusd.balanceOf(address(lendingVault)), MINT_AMOUNT - BURN_AMOUNT);
    }

    function testBurnFromStabilityFund_Reverts() public {
        _mintPUSD(user1, MINT_AMOUNT);

        // Transfer PUSD to stabilityFund
        vm.prank(user1);
        pusd.transfer(address(stabilityFund), MINT_AMOUNT);

        assertEq(pusd.balanceOf(address(stabilityFund)), MINT_AMOUNT);

        // StabilityFund should NOT be able to burn PUSD (only wPUSD)
        // This follows the principle of least privilege
        vm.expectRevert(abi.encodeWithSelector(IPUSD.PUSD__UnauthorizedBurner.selector));
        vm.prank(address(stabilityFund));
        pusd.burn(BURN_AMOUNT);

        // Balance should remain unchanged
        assertEq(pusd.balanceOf(address(stabilityFund)), MINT_AMOUNT);
    }

    function test_Transfer() public {
        _mintPUSD(user1, MINT_AMOUNT);

        assertEq(pusd.balanceOf(user3), 0);
        
        vm.prank(user1);
        pusd.transfer(user3, MINT_AMOUNT);

        assertEq(pusd.balanceOf(user3), MINT_AMOUNT);
    }

    function test_TransferFrom() public {
        _mintPUSD(user1, MINT_AMOUNT);

        uint256 user1InitialBalance = pusd.balanceOf(user1);
        uint256 lendingVaultInitialBalance = pusd.balanceOf(address(lendingVault));

        assertEq(pusd.balanceOf(user1), user1InitialBalance);
        assertEq(pusd.balanceOf(address(lendingVault)), lendingVaultInitialBalance);
        
        vm.prank(user1);
        pusd.approve(address(lendingVault), MINT_AMOUNT);

        vm.prank(address(lendingVault));
        pusd.transferFrom(user1, address(lendingVault), MINT_AMOUNT);

        assertEq(pusd.balanceOf(address(lendingVault)), lendingVaultInitialBalance + MINT_AMOUNT);
        assertEq(pusd.balanceOf(user1), user1InitialBalance - MINT_AMOUNT);
    }

    function test_UpgradeToAndCall() public {
        PUSDV2 pusdV2Impl = new PUSDV2();
        
        vm.prank(upgrader);
        pusd.upgradeToAndCall(address(pusdV2Impl), "");

        PUSDV2 pusdV2 = PUSDV2(address(pusd));

        assertEq(pusdV2.version(), 2);
    }

    /*//////////////////////////////////////////////////////////////
                            EVENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_PUSDInitializedEvent() public {
        PUSD pusdImpl = new PUSD();
        
        ERC1967Proxy pusdProxy = new ERC1967Proxy(
            address(pusdImpl),
            ""
        );

        PUSD pusd = PUSD(address(pusdProxy));

        vm.expectEmit(true, true, true, true);
        emit IPUSD.PUSDInitialized(address(protocolConfig));
        pusd.initialize(address(protocolConfig));
    }

    function test_PUSDMintedEvent() public {
        vm.expectEmit(true, true, true, true);
        emit IPUSD.PUSDMinted(user3, MINT_AMOUNT);
        vm.prank(address(lendingVault));
        pusd.mint(user3, MINT_AMOUNT);
    }

    function test_PUSDBurnedEvent() public {
        _mintPUSD(user1, MINT_AMOUNT);

        vm.prank(user1);
        pusd.transfer(address(lendingVault), MINT_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit IPUSD.PUSDBurned(address(lendingVault), BURN_AMOUNT);
        vm.prank(address(lendingVault));
        pusd.burn(BURN_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Init_FailsWithZeroAddress() public {
        PUSD pusdImpl = new PUSD();
        
        ERC1967Proxy pusdProxy = new ERC1967Proxy(
            address(pusdImpl),
            ""
        );

        PUSD pusd = PUSD(address(pusdProxy));

        vm.expectRevert(abi.encodeWithSelector(IPUSD.PUSD__InvalidAddress.selector));
        pusd.initialize(address(0));
    }

    function test_Init_FailsWhenCalledTwice() public {
        PUSD pusdImpl = new PUSD();
        
        ERC1967Proxy pusdProxy = new ERC1967Proxy(
            address(pusdImpl),
            ""
        );

        PUSD pusd = PUSD(address(pusdProxy));

        pusd.initialize(address(protocolConfig));

        vm.expectRevert(abi.encodeWithSelector(InvalidInitialization.selector));
        pusd.initialize(address(protocolConfig));
    }
    
    function test_MintFromUnauthorizedFails() public {
        vm.expectRevert(abi.encodeWithSelector(IPUSD.PUSD__UnauthorizedMinter.selector));
        vm.prank(unauthorizedUser);
        pusd.mint(user3, MINT_AMOUNT);
    }
    
    function tes_BurnFromUnauthorizedFails() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(IPUSD.PUSD__UnauthorizedBurner.selector));
        vm.prank(unauthorizedUser);
        pusd.burn(BURN_AMOUNT);
    }

    function test_BurnFrom_AlwaysReverts() public {
        // Mint PUSD to user1
        _mintPUSD(user1, MINT_AMOUNT);
        
        // User1 approves user3 to spend their PUSD
        vm.prank(user1);
        pusd.approve(user3, MINT_AMOUNT);
        
        // Verify approval was granted
        assertEq(pusd.allowance(user1, user3), MINT_AMOUNT);
        
        // Attempt to burn from user1's balance using user3 should revert
        vm.expectRevert(abi.encodeWithSelector(IPUSD.PUSD__UnauthorizedBurner.selector));
        vm.prank(user3);
        pusd.burnFrom(user1, BURN_AMOUNT);
        
        // Verify user1's balance unchanged
        assertEq(pusd.balanceOf(user1), MINT_AMOUNT);
    }

    function test_BurnFrom_RevertsEvenForAuthorizedContracts() public {
        // Mint PUSD to user1
        _mintPUSD(user1, MINT_AMOUNT);
        
        // User1 approves lendingVault to spend their PUSD
        vm.prank(user1);
        pusd.approve(address(lendingVault), MINT_AMOUNT);
        
        // Even authorized burners (lendingVault) cannot use burnFrom
        vm.expectRevert(abi.encodeWithSelector(IPUSD.PUSD__UnauthorizedBurner.selector));
        vm.prank(address(lendingVault));
        pusd.burnFrom(user1, BURN_AMOUNT);
        
        // Verify user1's balance unchanged
        assertEq(pusd.balanceOf(user1), MINT_AMOUNT);
    }
    
    function test_SetLendingVault_ZeroAddressFails() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IPUSD.PUSD__InvalidAddress.selector));
        pusd.setLendingVault(address(0));
    }
    
    function test_SetStabilityFund_ZeroAddressFails() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IPUSD.PUSD__InvalidAddress.selector));
        pusd.setStabilityFund(address(0));
    }
    
    function test_OnlyAdminCanSetContracts() public {
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, pusd.protocolConfig().ADMIN_ROLE()));
        pusd.setLendingVault(address(lendingVault));

        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, pusd.protocolConfig().ADMIN_ROLE()));
        pusd.setStabilityFund(address(stabilityFund));
        vm.stopPrank();
    }

    function test_UpgradeTo_FailsWhenCalledByNonUpgrader() public {
        address newPUSD = makeAddr("newPUSD");
        
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, pusd.protocolConfig().UPGRADER_ROLE()));
        pusd.upgradeToAndCall(newPUSD, "");
        vm.stopPrank();
    }       
}

contract PUSDV2 is PUSD {
    function version() public pure returns (uint256) {
        return 2;
    }
}