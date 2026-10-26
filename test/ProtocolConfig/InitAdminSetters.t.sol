// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {TestSetup} from "../TestSetup.t.sol";

import {ProtocolConfig} from "../../contracts/ProtocolConfig.sol";
import {IProtocolConfig} from "../../contracts/interfaces/IProtocolConfig.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

interface IUUPS {
    function upgradeTo(address newImplementation) external;
    function upgradeToAndCall(address newImplementation, bytes memory data) external;
}

contract ProtocolConfigInitAdminSettersTest is TestSetup {

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    // Mirror OZ custom errors for precise revert matching
    error AccessControlUnauthorizedAccount(address account, bytes32 role);
    error InvalidInitialization();
    
    /*//////////////////////////////////////////////////////////////
                            INITIALIZER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Initialize_Success() public view {
        assertEq(protocolConfig.hasRole(protocolConfig.ADMIN_ROLE(), admin), true, "admin should have ADMIN_ROLE");
        assertEq(protocolConfig.hasRole(protocolConfig.UPGRADER_ROLE(), upgrader), true, "upgrader should have UPGRADER_ROLE");
        assertEq(address(protocolConfig.oracle()), address(mockOracle), "oracle should be set");
        assertEq(address(protocolConfig.swapRouter()), address(mockSwapRouter), "swapRouter should be set");
        assertEq(address(protocolConfig.quoter()), address(mockQuoter), "quoter should be set");
        assertEq(protocolConfig.liquidationThreshold(), 12_000, "liquidationThreshold should be default 120%");
        assertEq(protocolConfig.minCollateralRatio(), 12_000, "minCollateralRatio should be default 120%");
        assertEq(protocolConfig.debtCeiling(), 100_000_000 ether, "debtCeiling should be default 100M");
        assertEq(protocolConfig.minDebt(), 500 ether, "minDebt should be default 500");
        assertEq(protocolConfig.closeFactorBps(), 5000, "closeFactorBps should be default 50%");
        assertEq(protocolConfig.liquidationBonusBps(), 1000, "liquidationBonusBps should be default 10%");
    }

    function test_Initialize_RevertsOnZeroOracle() public {
        ProtocolConfig impl = new ProtocolConfig();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        ProtocolConfig pc = ProtocolConfig(address(proxy));

        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidAddress.selector));
        pc.initialize(address(0), address(mockSwapRouter), address(mockQuoter), address(wstETH));
    }

    function test_Initialize_RevertsOnZeroSwapRouter() public {
        ProtocolConfig impl = new ProtocolConfig();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        ProtocolConfig pc = ProtocolConfig(address(proxy));

        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidAddress.selector));
        pc.initialize(address(mockOracle), address(0), address(mockQuoter), address(wstETH));
    }

    function test_Initialize_RevertsOnZeroQuoter() public {
        ProtocolConfig impl = new ProtocolConfig();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        ProtocolConfig pc = ProtocolConfig(address(proxy));

        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidAddress.selector));
        pc.initialize(address(mockOracle), address(mockSwapRouter), address(0), address(wstETH));
    }

    function test_SetLiquidationThreshold_RevertWhenBufferInsufficient() public {
        // minCollateralRatio = 15000, liquidationThreshold = 13000 => buffer = 2000 < 3000
        vm.startPrank(admin);
        protocolConfig.setMinCollateralRatio(15_000);
        
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidRatio.selector));
        protocolConfig.setLiquidationThreshold(13_000);
        vm.stopPrank();
    }

    function test_Initialize_RevertsOnReinitialize() public {
        ProtocolConfig impl = new ProtocolConfig();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        ProtocolConfig pc = ProtocolConfig(address(proxy));

        pc.initialize(address(mockOracle), address(mockSwapRouter), address(mockQuoter), address(wstETH));

        vm.expectRevert(InvalidInitialization.selector);
        pc.initialize(address(mockOracle), address(mockSwapRouter), address(mockQuoter), address(wstETH));
    }

    function test_Initialize_EmitsProtocolConfigInitializedEvent() public {
        ProtocolConfig impl = new ProtocolConfig();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        ProtocolConfig pc = ProtocolConfig(address(proxy));

        vm.expectEmit(true, true, false, false);
        emit IProtocolConfig.ProtocolConfigInitialized(address(mockOracle), address(mockSwapRouter), address(mockQuoter), 12000, 12000, 100_000_000 ether, 500 ether, 5000, 1000, 3000);
        pc.initialize(address(mockOracle), address(mockSwapRouter), address(mockQuoter), address(wstETH));
    }

    /*//////////////////////////////////////////////////////////////
                            SET ORACLE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetOracle_Success() public {
        address newOracle = address(0x123);
        address oldOracle = address(protocolConfig.oracle());

        vm.expectEmit(true, true, false, false);
        emit IProtocolConfig.OracleUpdated(oldOracle, newOracle);

        vm.prank(admin);
        protocolConfig.setOracle(newOracle);

        assertEq(address(protocolConfig.oracle()), newOracle, "oracle should be updated");
    }

    function test_SetOracle_RevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidAddress.selector));
        vm.prank(admin);
        protocolConfig.setOracle(address(0));
    }

    function test_SetOracle_RevertsOnUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, protocolConfig.ADMIN_ROLE()));
        vm.prank(user1);
        protocolConfig.setOracle(address(0x123));
    }

    /*//////////////////////////////////////////////////////////////
                            SET SWAPROUTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetSwapRouter_Success() public {
        address newSwapRouter = address(0x123);
        address oldSwapRouter = address(protocolConfig.swapRouter());

        vm.expectEmit(true, true, false, false);
        emit IProtocolConfig.SwapRouterUpdated(oldSwapRouter, newSwapRouter);

        vm.prank(admin);
        protocolConfig.setSwapRouter(newSwapRouter);

        assertEq(address(protocolConfig.swapRouter()), newSwapRouter, "swapRouter should be updated");
    }

    function test_SetSwapRouter_RevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidAddress.selector));
        vm.startPrank(admin);
        protocolConfig.setSwapRouter(address(0));
        vm.stopPrank();
    }

    function test_SetSwapRouter_RevertsOnUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, protocolConfig.ADMIN_ROLE()));
        vm.startPrank(user1);
        protocolConfig.setSwapRouter(address(0x123));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            SET QUOTER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetQuoter_Success() public {
        address newQuoter = address(0x123);
        address oldQuoter = address(protocolConfig.quoter());

        vm.expectEmit(true, true, false, false);
        emit IProtocolConfig.QuoterUpdated(oldQuoter, newQuoter);

        vm.prank(admin);
        protocolConfig.setQuoter(newQuoter);

        assertEq(address(protocolConfig.quoter()), newQuoter, "quoter should be updated");
    }

    function test_SetQuoter_RevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidAddress.selector));
        vm.startPrank(admin);
        protocolConfig.setQuoter(address(0));
        vm.stopPrank();
    }

    function test_SetQuoter_RevertsOnUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, protocolConfig.ADMIN_ROLE()));
        vm.startPrank(user1);
        protocolConfig.setQuoter(address(0x123));
        vm.stopPrank();
    }


    /*//////////////////////////////////////////////////////////////
                        SET COLLATERAL TOKEN TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetCollateralToken_Success() public {
        address newToken = address(0x789);
        address oldToken = protocolConfig.collateralToken();

        vm.expectEmit(true, true, false, false);
        emit IProtocolConfig.CollateralTokenUpdated(oldToken, newToken);

        vm.prank(admin);
        protocolConfig.setCollateralToken(newToken);

        assertEq(protocolConfig.collateralToken(), newToken, "collateralToken should be updated");
    }

    function test_SetCollateralToken_RevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidAddress.selector));
        vm.startPrank(admin);
        protocolConfig.setCollateralToken(address(0));
        vm.stopPrank();
    }

    function test_SetCollateralToken_RevertsOnUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, protocolConfig.ADMIN_ROLE()));
        vm.startPrank(user1);
        protocolConfig.setCollateralToken(address(0x789));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        SET TREASURY WALLET TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetTreasuryWallet_Success() public {
        address newTreasuryWallet = address(0x789);
        address oldTreasuryWallet = protocolConfig.treasuryWallet();

        assertEq(protocolConfig.treasuryWallet(), oldTreasuryWallet, "treasuryWallet should be set");

        vm.expectEmit(true, false, false, true);
        emit IProtocolConfig.TreasuryWalletUpdated(oldTreasuryWallet, newTreasuryWallet);

        vm.prank(admin);
        protocolConfig.setTreasuryWallet(newTreasuryWallet);

        assertEq(protocolConfig.treasuryWallet(), newTreasuryWallet, "treasuryWallet should be updated");
    }

    function test_SetTreasuryWallet_RevertsOnZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidAddress.selector));
        vm.startPrank(admin);
        protocolConfig.setTreasuryWallet(address(0));
        vm.stopPrank();
    }

    function test_SetTreasuryWallet_RevertsOnUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, protocolConfig.ADMIN_ROLE()));
        vm.startPrank(user1);
        protocolConfig.setTreasuryWallet(address(0x789));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            SET MIN DEBT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetMinDebt_Success() public {
        uint256 newMinDebt = 1000 ether;
        uint256 oldMinDebt = protocolConfig.minDebt();

        vm.expectEmit(true, false, false, true);
        emit IProtocolConfig.MinDebtUpdated(oldMinDebt, newMinDebt);

        vm.startPrank(admin);
        protocolConfig.setMinDebt(newMinDebt);
        vm.stopPrank();

        assertEq(protocolConfig.minDebt(), newMinDebt, "minDebt should be updated");
    }

    function test_SetMinDebt_RevertsOnZero() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidAmount.selector));
        vm.startPrank(admin);
        protocolConfig.setMinDebt(0);
        vm.stopPrank();
    }

    function test_SetMinDebt_RevertsOnUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, protocolConfig.ADMIN_ROLE()));
        vm.startPrank(user1);
        protocolConfig.setMinDebt(1000 ether);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    SET LIQUIDATION THRESHOLD TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetLiquidationThreshold_Success() public {
        uint256 newThreshold = 9000; // 90%
        uint256 oldThreshold = protocolConfig.liquidationThreshold();

        vm.expectEmit(true, false, false, true);
        emit IProtocolConfig.LiquidationThresholdUpdated(oldThreshold, newThreshold);

        vm.startPrank(admin);
        protocolConfig.setLiquidationThreshold(newThreshold);
        vm.stopPrank();

        assertEq(protocolConfig.liquidationThreshold(), newThreshold, "liquidationThreshold should be updated");
    }

    function test_SetLiquidationThreshold_RevertsOnZero() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidPercentage.selector));
        vm.startPrank(admin);
        protocolConfig.setLiquidationThreshold(0);
        vm.stopPrank();
    }

    function test_SetLiquidationThreshold_RevertsOnTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidPercentage.selector));
        vm.startPrank(admin);
        protocolConfig.setLiquidationThreshold(50001); // > 500%
        vm.stopPrank();
    }

    function test_SetLiquidationThreshold_AllowsMaximum() public {
        vm.startPrank(admin);
        // Need to set minCollateralRatio to allow maximum liquidationThreshold with 30% buffer
        protocolConfig.setMinCollateralRatio(53000); // 530% - allows 50000 (500%) with 30% buffer
        protocolConfig.setLiquidationThreshold(50000); // 500%
        vm.stopPrank();

        assertEq(protocolConfig.liquidationThreshold(), 50000, "should allow maximum value");
    }

    function test_SetLiquidationThreshold_RevertsOnUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, protocolConfig.ADMIN_ROLE()));
        vm.startPrank(user1);
        protocolConfig.setLiquidationThreshold(9000);
        vm.stopPrank();
    }

    function test_SetLiquidationThreshold_RevertsOnInsufficientBuffer() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidRatio.selector));
        vm.startPrank(admin);
        protocolConfig.setLiquidationThreshold(14000); // Only 10% buffer from default 150%
        vm.stopPrank();
    }

    function test_SetLiquidationThreshold_RevertsOnExactlyMinCollateralRatio() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidRatio.selector));
        vm.startPrank(admin);
        protocolConfig.setLiquidationThreshold(15000); // Exactly equal to minCollateralRatio
        vm.stopPrank();
    }

    function test_SetLiquidationThreshold_RequiresMandatory30PercentBuffer() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidRatio.selector));
        vm.startPrank(admin);
        protocolConfig.setLiquidationThreshold(12500); // Only 25% buffer from default 150%
        vm.stopPrank();
    }

    function test_SetLiquidationThreshold_AllowsExactly30PercentBuffer() public {
        vm.startPrank(admin);
        // First set minCollateralRatio to 15000 (150%)
        protocolConfig.setMinCollateralRatio(15000);
        // Then set liquidationThreshold to 12000 (120%) - exactly 30% buffer
        protocolConfig.setLiquidationThreshold(12000);
        vm.stopPrank();
        
        assertEq(protocolConfig.liquidationThreshold(), 12000, "should allow exactly 30% buffer");
    }

    /*//////////////////////////////////////////////////////////////
                    SET MIN COLLATERAL RATIO TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetMinCollateralRatio_Success() public {
        uint256 newRatio = 15000; // 150%
        uint256 oldRatio = protocolConfig.minCollateralRatio();

        vm.expectEmit(true, false, false, true);
        emit IProtocolConfig.MinCollateralRatioUpdated(oldRatio, newRatio);

        vm.startPrank(admin);
        protocolConfig.setMinCollateralRatio(newRatio);
        vm.stopPrank();

        assertEq(protocolConfig.minCollateralRatio(), newRatio, "minCollateralRatio should be updated");
    }

    function test_SetMinCollateralRatio_RevertsOnTooLow() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidRatio.selector));
        vm.startPrank(admin);
        protocolConfig.setMinCollateralRatio(9999); // < 100%
        vm.stopPrank();
    }

    function test_SetMinCollateralRatio_AllowsMinimumWithCorrectLiquidationThreshold() public {
        vm.startPrank(admin);
        // First set liquidationThreshold to allow 100% minCollateralRatio with 30% buffer
        protocolConfig.setLiquidationThreshold(7000); // 70% - allows 10000 (100%) with 30% buffer
        protocolConfig.setMinCollateralRatio(10000); // 100%
        vm.stopPrank();

        assertEq(protocolConfig.minCollateralRatio(), 10000, "should allow minimum value with proper buffer");
    }

    function test_SetMinCollateralRatio_RevertsOnUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, protocolConfig.ADMIN_ROLE()));
        vm.startPrank(user1);
        protocolConfig.setMinCollateralRatio(15000);
        vm.stopPrank();
    }

    function test_SetMinCollateralRatio_RevertsOnInsufficientBuffer() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidRatio.selector));
        vm.prank(admin);
        protocolConfig.setMinCollateralRatio(13000); // Only 10% buffer from default 120%
    }

    function test_SetMinCollateralRatio_RevertsOnExactlyLiquidationThreshold() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidRatio.selector));
        vm.startPrank(admin);
        protocolConfig.setMinCollateralRatio(12000); // Exactly equal to liquidationThreshold
        vm.stopPrank();
    }

    function test_SetMinCollateralRatio_RequiresMandatory30PercentBuffer() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidRatio.selector));
        vm.prank(admin);
        protocolConfig.setMinCollateralRatio(14500); // Only 25% buffer from default 120%
    }

    function test_SetMinCollateralRatio_AllowsExactly30PercentBuffer() public {
        vm.prank(admin);
        protocolConfig.setMinCollateralRatio(15000); // Exactly 30% buffer from default 120%
        
        assertEq(protocolConfig.minCollateralRatio(), 15000, "should allow exactly 30% buffer");
    }

    /*//////////////////////////////////////////////////////////////
                        SET CLOSE FACTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetCloseFactorBps_Success() public {
        uint256 newFactor = 7500; // 75%
        uint256 oldFactor = protocolConfig.closeFactorBps();

        vm.expectEmit(true, false, false, true);
        emit IProtocolConfig.CloseFactorUpdated(oldFactor, newFactor);

        vm.prank(admin);
        protocolConfig.setCloseFactorBps(newFactor);

        assertEq(protocolConfig.closeFactorBps(), newFactor, "closeFactorBps should be updated");
    }

    function test_SetCloseFactorBps_RevertsOnZero() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidPercentage.selector));
        vm.prank(admin);
        protocolConfig.setCloseFactorBps(0);
    }

    function test_SetCloseFactorBps_RevertsOnBelowMinimum() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidPercentage.selector));
        vm.prank(admin);
        protocolConfig.setCloseFactorBps(499); // Below 5% minimum
    }

    function test_SetCloseFactorBps_AllowsMinimum() public {
        vm.prank(admin);
        protocolConfig.setCloseFactorBps(500); // 5% minimum

        assertEq(protocolConfig.closeFactorBps(), 500, "closeFactorBps should allow minimum");
    }

    function test_SetCloseFactorBps_AllowsMaximum() public {
        vm.prank(admin);
        protocolConfig.setCloseFactorBps(10000); // 100%

        assertEq(protocolConfig.closeFactorBps(), 10000, "should allow maximum value");
    }

    function test_SetCloseFactorBps_RevertsOnTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidPercentage.selector));
        vm.prank(admin);
        protocolConfig.setCloseFactorBps(10001); // > 100%
    }

    function test_SetCloseFactorBps_RevertsOnUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, protocolConfig.ADMIN_ROLE()));
        vm.startPrank(user1);
        protocolConfig.setCloseFactorBps(7500);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    SET LIQUIDATION BONUS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetLiquidationBonusBps_Success() public {
        uint256 newBonus = 1500; // 15%
        uint256 oldBonus = protocolConfig.liquidationBonusBps();

        vm.expectEmit(true, false, false, true);
        emit IProtocolConfig.LiquidationBonusUpdated(oldBonus, newBonus);

        vm.prank(admin);
        protocolConfig.setLiquidationBonusBps(newBonus);

        assertEq(protocolConfig.liquidationBonusBps(), newBonus, "liquidationBonusBps should be updated");
    }

    function test_SetLiquidationBonusBps_RevertsOnZero() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidAmount.selector));
        vm.prank(admin);
        protocolConfig.setLiquidationBonusBps(0);
    }

    function test_SetLiquidationBonusBps_AllowsMaximum() public {
        vm.prank(admin);
        protocolConfig.setLiquidationBonusBps(3000); // 30% max

        assertEq(protocolConfig.liquidationBonusBps(), 3000, "should allow maximum value");
    }

    function test_SetLiquidationBonusBps_RevertsOnTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidPercentage.selector));
        vm.prank(admin);
        protocolConfig.setLiquidationBonusBps(3001); // > 30%
    }

    function test_SetLiquidationBonusBps_RevertsOnBelowMinimum() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidPercentage.selector));
        vm.prank(admin);
        protocolConfig.setLiquidationBonusBps(99); // Below 1% minimum
    }

    function test_SetLiquidationBonusBps_AllowsMinimum() public {
        vm.prank(admin);
        protocolConfig.setLiquidationBonusBps(100); // 1% minimum

        assertEq(protocolConfig.liquidationBonusBps(), 100, "should allow minimum value");
    }

    function test_SetLiquidationBonusBps_RevertsOnUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, protocolConfig.ADMIN_ROLE()));
        vm.startPrank(user1);
        protocolConfig.setLiquidationBonusBps(1500);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        SET DEBT CEILING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetDebtCeiling_Success() public {
        uint256 newCeiling = 2000000 ether; // 2M
        uint256 oldCeiling = protocolConfig.debtCeiling();

        vm.expectEmit(true, false, false, true);
        emit IProtocolConfig.DebtCeilingUpdated(oldCeiling, newCeiling);

        vm.prank(admin);
        protocolConfig.setDebtCeiling(newCeiling);

        assertEq(protocolConfig.debtCeiling(), newCeiling, "debtCeiling should be updated");
    }

    function test_SetDebtCeiling_RevertsOnZero() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidAmount.selector));
        vm.prank(admin);
        protocolConfig.setDebtCeiling(0);
    }

    function test_SetDebtCeiling_RevertsOnUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, protocolConfig.ADMIN_ROLE()));
        vm.startPrank(user1);
        protocolConfig.setDebtCeiling(2000000 ether);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        SET UNISWAP FEE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetUniswapFee_Success() public {
        uint256 newUniswapFee = 1000; // 0.1
        uint256 oldUniswapFee = protocolConfig.uniswapFee();

        vm.expectEmit(true, false, false, true);
        emit IProtocolConfig.UniswapFeeUpdated(oldUniswapFee, newUniswapFee);

        vm.prank(admin);
        protocolConfig.setUniswapFee(newUniswapFee);

        assertEq(protocolConfig.uniswapFee(), newUniswapFee, "uniswapFee should be updated");
    }

    function test_SetUniswapFee_RevertsOnZero() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidAmount.selector));
        vm.prank(admin);
        protocolConfig.setUniswapFee(0);
    }

    function test_SetUniswapFee_RevertsOnUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, protocolConfig.ADMIN_ROLE()));
        vm.startPrank(user1);
        protocolConfig.setUniswapFee(1000);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        SET MAX STALENESS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SetMaxStaleness_Success() public {
        uint256 newMaxStaleness = 7200; // 2 hours
        uint256 oldMaxStaleness = protocolConfig.maxStaleness();

        vm.expectEmit(true, false, false, true);
        emit IProtocolConfig.MaxStalenessUpdated(oldMaxStaleness, newMaxStaleness);

        vm.prank(admin);
        protocolConfig.setMaxStaleness(newMaxStaleness);

        assertEq(protocolConfig.maxStaleness(), newMaxStaleness, "maxStaleness should be updated");
    }

    function test_SetMaxStaleness_RevertsOnZero() public {
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidAmount.selector));
        vm.prank(admin);
        protocolConfig.setMaxStaleness(0);
    }

    function test_SetMaxStaleness_RevertsOnUnauthorized() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, protocolConfig.ADMIN_ROLE()));
        vm.startPrank(user1);
        protocolConfig.setMaxStaleness(7200);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           UUPS UPGRADE COVERAGE
    //////////////////////////////////////////////////////////////*/

    function test_Upgrade_NonUpgraderReverts() public {
        ProtocolConfig newImpl = new ProtocolConfig();
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, protocolConfig.UPGRADER_ROLE()));
        IUUPS(address(protocolConfig)).upgradeToAndCall(address(newImpl), "");
        vm.stopPrank();
    }

    function test_Upgrade_UpgraderSucceeds() public {
        ProtocolConfig newImpl = new ProtocolConfig();
        vm.prank(upgrader);
        IUUPS(address(protocolConfig)).upgradeToAndCall(address(newImpl), "");
    }

    /*//////////////////////////////////////////////////////////////
                        SECURITY CONSTRAINTS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SecurityConstraints_ComprehensiveValidation() public {
        vm.startPrank(admin);
        
        // Test 1: Verify closeFactorBps constraints (5%-100%)
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidPercentage.selector));
        protocolConfig.setCloseFactorBps(0); // Below minimum
        
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidPercentage.selector));
        protocolConfig.setCloseFactorBps(499); // Below minimum
        
        protocolConfig.setCloseFactorBps(500); // Minimum allowed
        protocolConfig.setCloseFactorBps(10000); // Maximum allowed
        
        // Test 2: Verify liquidationBonusBps constraints (1%-30%)
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidPercentage.selector));
        protocolConfig.setLiquidationBonusBps(99); // Below minimum
        
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidPercentage.selector));
        protocolConfig.setLiquidationBonusBps(3001); // Above maximum
        
        protocolConfig.setLiquidationBonusBps(100); // Minimum allowed
        protocolConfig.setLiquidationBonusBps(3000); // Maximum allowed
        
        // Test 3: Verify 30% buffer requirement
        // Set up valid configuration first
        protocolConfig.setLiquidationThreshold(9000); // 90%
        protocolConfig.setMinCollateralRatio(12000); // 120% (exactly 30% buffer)
        
        // Try to violate buffer from liquidationThreshold side
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidRatio.selector));
        protocolConfig.setLiquidationThreshold(9500); // Would be only 25% buffer
        
        // Try to violate buffer from minCollateralRatio side
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidRatio.selector));
        protocolConfig.setMinCollateralRatio(11500); // Would be only 25% buffer
        
        // Verify valid configurations work
        protocolConfig.setLiquidationThreshold(8000); // 80%
        protocolConfig.setMinCollateralRatio(11000); // 110% (exactly 30% buffer)
        
        vm.stopPrank();
        
        // Verify final state
        assertEq(protocolConfig.liquidationThreshold(), 8000, "liquidationThreshold should be updated");
        assertEq(protocolConfig.minCollateralRatio(), 11000, "minCollateralRatio should be updated");
        assertEq(protocolConfig.closeFactorBps(), 10000, "closeFactorBps should be at maximum");
        assertEq(protocolConfig.liquidationBonusBps(), 3000, "liquidationBonusBps should be at maximum");
    }

    function test_SecurityConstraints_EdgeCasesAndCombinations() public {
        vm.startPrank(admin);
        
        // Test edge case: Minimum valid configuration
        protocolConfig.setLiquidationThreshold(7000); // 70%
        protocolConfig.setMinCollateralRatio(10000); // 100% (exactly 30% buffer)
        protocolConfig.setCloseFactorBps(500); // 5% minimum
        protocolConfig.setLiquidationBonusBps(100); // 1% minimum
        
        // Verify these values are set correctly
        assertEq(protocolConfig.liquidationThreshold(), 7000, "minimum liquidationThreshold");
        assertEq(protocolConfig.minCollateralRatio(), 10000, "minimum minCollateralRatio");
        assertEq(protocolConfig.closeFactorBps(), 500, "minimum closeFactorBps");
        assertEq(protocolConfig.liquidationBonusBps(), 100, "minimum liquidationBonusBps");
        
        // Test edge case: Maximum valid configuration
        protocolConfig.setMinCollateralRatio(53000); // 530%
        protocolConfig.setLiquidationThreshold(50000); // 500% (exactly 30% buffer)
        protocolConfig.setCloseFactorBps(10000); // 100% maximum
        protocolConfig.setLiquidationBonusBps(3000); // 30% maximum
        
        // Verify these values are set correctly
        assertEq(protocolConfig.liquidationThreshold(), 50000, "maximum liquidationThreshold");
        assertEq(protocolConfig.minCollateralRatio(), 53000, "maximum minCollateralRatio");
        assertEq(protocolConfig.closeFactorBps(), 10000, "maximum closeFactorBps");
        assertEq(protocolConfig.liquidationBonusBps(), 3000, "maximum liquidationBonusBps");
        
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    SECURITY CONSTRAINT CONSTANTS TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SecurityConstraintConstants_Values() public view {
        // Test all security constraint constants have correct values
        assertEq(protocolConfig.MAX_BPS(), 10_000, "MAX_BPS should be 10,000");
        assertEq(protocolConfig.MAX_LIQUIDATION_THRESHOLD(), 50_000, "MAX_LIQUIDATION_THRESHOLD should be 50,000");
        assertEq(protocolConfig.MANDATORY_BUFFER_BPS(), 3_000, "MANDATORY_BUFFER_BPS should be 3,000");
        assertEq(protocolConfig.MIN_CLOSE_FACTOR_BPS(), 500, "MIN_CLOSE_FACTOR_BPS should be 500");
        assertEq(protocolConfig.MIN_LIQUIDATION_BONUS_BPS(), 100, "MIN_LIQUIDATION_BONUS_BPS should be 100");
        assertEq(protocolConfig.MAX_LIQUIDATION_BONUS_BPS(), 3_000, "MAX_LIQUIDATION_BONUS_BPS should be 3,000");
    }

    function test_SecurityConstraintConstants_AreImmutable() public {
        // These constants should never change - they're part of the security model
        uint256 maxBps = protocolConfig.MAX_BPS();
        uint256 maxLiqThreshold = protocolConfig.MAX_LIQUIDATION_THRESHOLD();
        uint256 mandatoryBuffer = protocolConfig.MANDATORY_BUFFER_BPS();
        uint256 minCloseFactor = protocolConfig.MIN_CLOSE_FACTOR_BPS();
        uint256 minLiqBonus = protocolConfig.MIN_LIQUIDATION_BONUS_BPS();
        uint256 maxLiqBonus = protocolConfig.MAX_LIQUIDATION_BONUS_BPS();

        // Constants should remain the same even after other operations
        vm.startPrank(admin);
        protocolConfig.setLiquidationThreshold(8000);
        protocolConfig.setMinCollateralRatio(11000);
        protocolConfig.setCloseFactorBps(1000);
        protocolConfig.setLiquidationBonusBps(500);
        vm.stopPrank();

        // Verify constants haven't changed
        assertEq(protocolConfig.MAX_BPS(), maxBps, "MAX_BPS should remain constant");
        assertEq(protocolConfig.MAX_LIQUIDATION_THRESHOLD(), maxLiqThreshold, "MAX_LIQUIDATION_THRESHOLD should remain constant");
        assertEq(protocolConfig.MANDATORY_BUFFER_BPS(), mandatoryBuffer, "MANDATORY_BUFFER_BPS should remain constant");
        assertEq(protocolConfig.MIN_CLOSE_FACTOR_BPS(), minCloseFactor, "MIN_CLOSE_FACTOR_BPS should remain constant");
        assertEq(protocolConfig.MIN_LIQUIDATION_BONUS_BPS(), minLiqBonus, "MIN_LIQUIDATION_BONUS_BPS should remain constant");
        assertEq(protocolConfig.MAX_LIQUIDATION_BONUS_BPS(), maxLiqBonus, "MAX_LIQUIDATION_BONUS_BPS should remain constant");
    }

    function test_SecurityConstraintConstants_EnforceValidation() public {
        // Test that the constants are actually used in validation
        vm.startPrank(admin);

        // Test MIN_CLOSE_FACTOR_BPS enforcement (499 should fail, 500 should work)
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidPercentage.selector));
        protocolConfig.setCloseFactorBps(499);

        // Test MAX_LIQUIDATION_BONUS_BPS enforcement (3001 should fail, 3000 should work)
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidPercentage.selector));
        protocolConfig.setLiquidationBonusBps(3001);

        // Test MIN_LIQUIDATION_BONUS_BPS enforcement (99 should fail, 100 should work)
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidPercentage.selector));
        protocolConfig.setLiquidationBonusBps(99);

        // Test MAX_LIQUIDATION_THRESHOLD enforcement - need to set minCollateralRatio high enough first
        protocolConfig.setMinCollateralRatio(54000); // 540% to allow for 500% + 30% buffer + margin
        vm.expectRevert(abi.encodeWithSelector(IProtocolConfig.ProtocolConfig__InvalidPercentage.selector));
        protocolConfig.setLiquidationThreshold(50001); // Over maximum

        vm.stopPrank();
    }
}
