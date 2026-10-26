// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {TestSetup, TreasuryHarness} from "../TestSetup.t.sol";
import {IPriceOracle} from "../../contracts/interfaces/IPriceOracle.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {ITreasury} from "../../contracts/interfaces/ITreasury.sol";
import {Treasury} from "../../contracts/Treasury.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {console} from "forge-std/console.sol";

contract NonCompliantRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
        require(params.amountOutMinimum > 0, "min=0");
        return params.amountOutMinimum - 1;
    }

    function exactInput(bytes calldata) external payable returns (uint256) {
        revert("not-implemented");
    }
}

contract ProtocolConfigStub {
    address private _admin;
    address private _upgrader;
    address private _oracle;
    address private _router;
    address private _quoter;
    uint256 private _fee;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    constructor(address oracle_, address router_, address quoter_, uint256 fee_, address admin_, address upgrader_) {
        _admin = admin_;
        _upgrader = upgrader_;
        _oracle = oracle_;
        _router = router_;
        _quoter = quoter_;
        _fee = fee_;
    }

    function admin() external view returns (address) { return _admin; }
    function upgrader() external view returns (address) { return _upgrader; }
    function oracle() external view returns (IPriceOracle) { return IPriceOracle(_oracle); }
    function swapRouter() external view returns (ISwapRouter) { return ISwapRouter(_router); }
    function quoter() external view returns (IQuoterV2) { return IQuoterV2(_quoter); }
    function uniswapFee() external view returns (uint256) { return _fee; }
}

contract TreasurySwapTest is TestSetup {

    error AccessControlUnauthorizedAccount(address account, bytes32 role);
    
    uint256 public PUSD_LIQUIDITY_AMOUNT = 10_000_000 ether;
    uint256 public WSTETH_LIQUIDITY_AMOUNT = 100_000 ether;

    uint256 public SWAP_AMOUNT = 1_000 ether;

    TreasuryHarness public treasuryHarnessImpl;
    TreasuryHarness public treasuryHarness;
    ERC1967Proxy public treasuryHarnessProxy;

    function setUp() public override {
        super.setUp();

        vm.prank(address(lendingVault));
        pusd.mint(admin, SWAP_AMOUNT + PUSD_LIQUIDITY_AMOUNT);

        wstETH.mint(admin, WSTETH_LIQUIDITY_AMOUNT + SWAP_AMOUNT);

        vm.startPrank(admin);
        pusd.approve(address(mockSwapRouter), PUSD_LIQUIDITY_AMOUNT);
        wstETH.approve(address(mockSwapRouter), WSTETH_LIQUIDITY_AMOUNT);

        mockSwapRouter.addToken(address(pusd), PUSD_LIQUIDITY_AMOUNT);
        mockSwapRouter.addToken(address(wstETH), WSTETH_LIQUIDITY_AMOUNT);

        wstETH.approve(address(treasury), SWAP_AMOUNT);
        pusd.approve(address(treasury), SWAP_AMOUNT);
        treasury.receivePUSD(SWAP_AMOUNT);
        treasury.receiveWstETH(SWAP_AMOUNT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            HARNESS HELPERS
    //////////////////////////////////////////////////////////////*/

    function _deployTreasuryHarness() internal returns (TreasuryHarness) {
        treasuryHarnessImpl = new TreasuryHarness();
        bytes memory data = abi.encodeWithSelector(
            Treasury.initialize.selector,
            address(protocolConfig),
            address(pusd),
            address(wstETH)
        );
        treasuryHarnessProxy = new ERC1967Proxy(address(treasuryHarnessImpl), data);
        return TreasuryHarness(address(treasuryHarnessProxy));
    }

    function _deployAndConfigureTreasuryHarness() internal returns (TreasuryHarness h) {
        vm.startPrank(admin);
        h = _deployTreasuryHarness();
        vm.stopPrank();

        vm.prank(address(lendingVault));
        pusd.mint(admin, SWAP_AMOUNT);
        wstETH.mint(admin, SWAP_AMOUNT);

        vm.startPrank(admin);
        h.grantRole(protocolConfig.ADMIN_ROLE(), admin);
        h.grantRole(protocolConfig.UPGRADER_ROLE(), upgrader);
        h.setLiquidationEngine(address(liquidationEngine));
        h.setLendingVault(address(lendingVault));
        h.setProtocolConfig(address(protocolConfig));

        wstETH.approve(address(h), SWAP_AMOUNT);
        pusd.approve(address(h), SWAP_AMOUNT);
        h.receivePUSD(SWAP_AMOUNT);
        h.receiveWstETH(SWAP_AMOUNT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            STATE UPDATES
    //////////////////////////////////////////////////////////////*/

    function test_SwapPusdWstETHSuccess_NoSlippage() public {
        uint256 initialPusdBalance = pusd.balanceOf(address(treasury));
        uint256 initialWstETHBalance = wstETH.balanceOf(address(treasury));

        assertEq(treasury.pusdBalance(), SWAP_AMOUNT);
        assertEq(treasury.wstETHBalance(), SWAP_AMOUNT);

        assertEq(initialPusdBalance, SWAP_AMOUNT);
        assertEq(initialWstETHBalance, SWAP_AMOUNT);

        uint256 expectedOut = mockSwapRouter.quote(address(pusd), address(wstETH), SWAP_AMOUNT);

        vm.prank(admin);
        uint256 amountOut = treasury.swapPusdForWstETH(SWAP_AMOUNT);

        uint256 finalPusdBalance = pusd.balanceOf(address(treasury));
        assertEq(finalPusdBalance, initialPusdBalance - SWAP_AMOUNT);

        uint256 finalWstETHBalance = wstETH.balanceOf(address(treasury));
        assertEq(finalWstETHBalance, initialWstETHBalance + expectedOut);
        assertEq(amountOut, expectedOut);

        assertEq(treasury.pusdBalance(), initialPusdBalance - SWAP_AMOUNT);
        assertEq(treasury.wstETHBalance(), initialWstETHBalance + expectedOut);
    }

    function test_SwapPusdWstETHSuccess_WithSlippage() public {
        vm.prank(admin);
        mockSwapRouter.setSlippageRate(address(pusd), address(wstETH), 500);

        uint256 initialPusdBalance = pusd.balanceOf(address(treasury));
        uint256 initialWstETHBalance = wstETH.balanceOf(address(treasury));

        assertEq(treasury.pusdBalance(), SWAP_AMOUNT);
        assertEq(treasury.wstETHBalance(), SWAP_AMOUNT);

        assertEq(initialPusdBalance, SWAP_AMOUNT);
        assertEq(initialWstETHBalance, SWAP_AMOUNT);

        uint256 expectedOut = mockSwapRouter.quote(address(pusd), address(wstETH), SWAP_AMOUNT);

        vm.prank(admin);
        uint256 amountOut = treasury.swapPusdForWstETH(SWAP_AMOUNT);

        uint256 finalPusdBalance = pusd.balanceOf(address(treasury));
        assertEq(finalPusdBalance, initialPusdBalance - SWAP_AMOUNT);
        
        uint256 finalWstETHBalance = wstETH.balanceOf(address(treasury));
        assertEq(finalWstETHBalance, initialWstETHBalance + expectedOut);

        assertEq(treasury.pusdBalance(), initialPusdBalance - SWAP_AMOUNT);
        assertEq(treasury.wstETHBalance(), initialWstETHBalance + expectedOut);
        assertEq(amountOut, expectedOut);
    }

    function test_SwapWstETHPusdSuccess_NoSlippage() public {
        uint256 initialPusdBalance = pusd.balanceOf(address(treasury));
        uint256 initialWstETHBalance = wstETH.balanceOf(address(treasury));

        assertEq(treasury.pusdBalance(), SWAP_AMOUNT);
        assertEq(treasury.wstETHBalance(), SWAP_AMOUNT);

        assertEq(initialPusdBalance, SWAP_AMOUNT);
        assertEq(initialWstETHBalance, SWAP_AMOUNT);

        uint256 expectedOut = mockSwapRouter.quote(address(wstETH), address(pusd), SWAP_AMOUNT);

        vm.prank(admin);
        uint256 amountOut = treasury.swapWstETHForPusd(SWAP_AMOUNT);

        uint256 finalWstETHBalance = wstETH.balanceOf(address(treasury));
        assertEq(finalWstETHBalance, initialWstETHBalance - SWAP_AMOUNT);

        uint256 finalPusdBalance = pusd.balanceOf(address(treasury));
        assertEq(finalPusdBalance, initialPusdBalance + expectedOut);

        assertEq(treasury.pusdBalance(), initialPusdBalance + expectedOut);
        assertEq(treasury.wstETHBalance(), initialWstETHBalance - SWAP_AMOUNT);
        assertEq(amountOut, expectedOut);
    }

    function test_SwapWstETHPusdSuccess_WithSlippage() public {
        vm.prank(admin);
        mockSwapRouter.setSlippageRate(address(wstETH), address(pusd), 500);

        uint256 initialPusdBalance = pusd.balanceOf(address(treasury));
        uint256 initialWstETHBalance = wstETH.balanceOf(address(treasury));

        assertEq(treasury.pusdBalance(), SWAP_AMOUNT);
        assertEq(treasury.wstETHBalance(), SWAP_AMOUNT);

        assertEq(initialPusdBalance, SWAP_AMOUNT);
        assertEq(initialWstETHBalance, SWAP_AMOUNT);

        uint256 expectedOut = mockSwapRouter.quote(address(wstETH), address(pusd), SWAP_AMOUNT);

        vm.prank(admin);
        uint256 amountOut = treasury.swapWstETHForPusd(SWAP_AMOUNT);
        
        uint256 finalWstETHBalance = wstETH.balanceOf(address(treasury));
        assertEq(finalWstETHBalance, initialWstETHBalance - SWAP_AMOUNT);

        uint256 finalPusdBalance = pusd.balanceOf(address(treasury));
        assertEq(finalPusdBalance, initialPusdBalance + expectedOut);

        assertEq(treasury.pusdBalance(), initialPusdBalance + expectedOut);
        assertEq(treasury.wstETHBalance(), initialWstETHBalance - SWAP_AMOUNT);
        assertEq(amountOut, expectedOut);
    }

    function test_Swap_ResetsAllowances() public {
        uint256 initialPusdAllowance = pusd.allowance(address(treasury), address(mockSwapRouter));
        
        assertEq(initialPusdAllowance, 0);

        vm.prank(admin);
        treasury.swapPusdForWstETH(SWAP_AMOUNT);

        uint256 finalPusdAllowance = pusd.allowance(address(treasury), address(mockSwapRouter));

        assertEq(finalPusdAllowance, 0);
    }

    function test_Swap_ResetsAllowances_WstETHPath() public {
        uint256 initialWstETHAllowance = wstETH.allowance(address(treasury), address(mockSwapRouter));

        assertEq(initialWstETHAllowance, 0);

        vm.prank(admin);
        treasury.swapWstETHForPusd(SWAP_AMOUNT);

        uint256 finalWstETHAllowance = wstETH.allowance(address(treasury), address(mockSwapRouter));

        assertEq(finalWstETHAllowance, 0);
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    function test_Swap_EmitsTokensSwappedEvent() public {
        uint256 expectedAmountOut = mockSwapRouter.quote(address(pusd), address(wstETH), SWAP_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit ITreasury.PusdSwapped(address(pusd), address(wstETH), SWAP_AMOUNT, expectedAmountOut);

        vm.prank(admin);
        treasury.swapPusdForWstETH(SWAP_AMOUNT);
    }

    function test_Swap_EmitsTokensSwappedEvent_WstETHToPUSD() public {
        uint256 expectedAmountOut = mockSwapRouter.quote(address(wstETH), address(pusd), SWAP_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit ITreasury.WstETHSwapped(address(wstETH), address(pusd), SWAP_AMOUNT, expectedAmountOut);

        vm.prank(admin);
        treasury.swapWstETHForPusd(SWAP_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                            NEGATIVE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SwapPusdForWstETH_RevertsIfWstETHAddressZero() public {
        // Deploy a fresh treasury implementation and proxy
        Treasury treasuryImpl = new Treasury();
        ERC1967Proxy treasuryProxy = new ERC1967Proxy(address(treasuryImpl), "");
        Treasury unconfiguredTreasury = Treasury(address(treasuryProxy));

        // Initialize with zero address for wstETH to test the revert
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAddress.selector));
        unconfiguredTreasury.initialize(address(protocolConfig), address(pusd), address(0));
        vm.stopPrank();
    }

    function test_SwapWstETHForPusd_RevertsIfPusdAddressZero() public {
        // Deploy a fresh treasury implementation and proxy
        Treasury treasuryImpl = new Treasury();
        ERC1967Proxy treasuryProxy = new ERC1967Proxy(address(treasuryImpl), "");
        Treasury unconfiguredTreasury = Treasury(address(treasuryProxy));

        // Initialize with zero address for PUSD to test the revert
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAddress.selector));
        unconfiguredTreasury.initialize(address(protocolConfig), address(0), address(wstETH));
        vm.stopPrank();
    }

    function test_SwapPusdForWstETH_RevertsIfNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, treasury.protocolConfig().ADMIN_ROLE()));
        vm.prank(user1);
        treasury.swapPusdForWstETH(SWAP_AMOUNT);
    }

    function test_SwapWstETHForPusd_RevertsIfNotAdmin() public {
        vm.expectRevert(abi.encodeWithSelector(AccessControlUnauthorizedAccount.selector, user1, treasury.protocolConfig().ADMIN_ROLE()));
        vm.prank(user1);
        treasury.swapWstETHForPusd(SWAP_AMOUNT);
    }

    function test_SwapPusdForWstETH_RevertsIfPaused() public {
        vm.prank(admin);
        treasury.pause();

        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vm.prank(admin);
        treasury.swapPusdForWstETH(SWAP_AMOUNT);
    }

    function test_SwapWstETHForPusd_RevertsIfPaused() public {
        vm.prank(admin);
        treasury.pause();

        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        vm.prank(admin);
        treasury.swapWstETHForPusd(SWAP_AMOUNT);
    }

    function test_SwapPusdForWstETH_RevertsIfAmountInIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAmount.selector));
        vm.prank(admin);
        treasury.swapPusdForWstETH(0);
    }

    function test_SwapWstETHForPusd_RevertsIfAmountInIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAmount.selector));
        vm.prank(admin);
        treasury.swapWstETHForPusd(0);
    }

    function test_SwapPusdForWstETH_RevertsIfInsufficientPusdBalance() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InsufficientPusdBalance.selector, SWAP_AMOUNT + 1, SWAP_AMOUNT));
        vm.prank(admin);
        treasury.swapPusdForWstETH(SWAP_AMOUNT + 1);
    }
    
    function test_SwapWstETHForPusd_RevertsIfInsufficientWstETHBalance() public {
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InsufficientWstETHBalance.selector, SWAP_AMOUNT + 1, SWAP_AMOUNT));
        vm.prank(admin);
        treasury.swapWstETHForPusd(SWAP_AMOUNT + 1);
    }
    
    function test_SwapPusdForWstETH_RevertsIfOracleStalePrice() public {
        mockOracle.setUpdatedAt(block.timestamp);
        vm.prank(admin);
        treasury.setOracleStaleAfter(1 hours);

        vm.warp(block.timestamp + 1 hours + 1);

        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__StaleOraclePrice.selector));
        vm.prank(admin);
        treasury.swapPusdForWstETH(SWAP_AMOUNT);
    }

    function test_SwapPusdForWstETH_RevertsIfOracleAnswerNonPositive() public {
        mockOracle.setAnswer(0);
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAmount.selector));
        vm.prank(admin);
        treasury.swapPusdForWstETH(SWAP_AMOUNT);
    }

    function test_SwapPusdForWstETH_RevertsIfOracleUpdatedAtZero() public {
        mockOracle.setUpdatedAt(0);
        vm.prank(admin);
        treasury.setOracleStaleAfter(1 hours);

        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__StaleOraclePrice.selector));
        vm.prank(admin);
        treasury.swapPusdForWstETH(SWAP_AMOUNT);
    }

    function test_SwapPusdForWstETH_RevertsIfAnsweredInRoundLessThanRoundId() public {
        mockOracle.setRoundId(2);
        mockOracle.setAnsweredInRound(1);
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidOracleRound.selector));
        vm.prank(admin);
        treasury.swapPusdForWstETH(SWAP_AMOUNT);
    }
    
    /*//////////////////////////////////////////////////////////////
                        INTERNAL _swap (HARNESS) TESTS
    //////////////////////////////////////////////////////////////*/

    function test_InternalSwap_PusdToWstETH_Success() public {
        TreasuryHarness h = _deployAndConfigureTreasuryHarness();

        uint256 initialPusdBalance = pusd.balanceOf(address(h));
        uint256 initialWstETHBalance = wstETH.balanceOf(address(h));

        assertEq(initialPusdBalance, SWAP_AMOUNT);
        assertEq(initialWstETHBalance, SWAP_AMOUNT);

        uint256 expectedOut = mockSwapRouter.quote(address(pusd), address(wstETH), SWAP_AMOUNT);

        uint256 amountOut = h.swap(address(pusd), address(wstETH), SWAP_AMOUNT);

        console.log(amountOut);

        assertEq(pusd.balanceOf(address(h)), initialPusdBalance - SWAP_AMOUNT);
        assertEq(wstETH.balanceOf(address(h)), initialWstETHBalance + expectedOut);
        assertEq(amountOut, expectedOut);

        uint256 finalAllowance = pusd.allowance(address(h), address(mockSwapRouter));
        assertEq(finalAllowance, 0);
    }

    function test_InternalSwap_WstETHToPusd_Success() public {
        TreasuryHarness h = _deployAndConfigureTreasuryHarness();

        uint256 initialWstETHBalance = wstETH.balanceOf(address(h));
        uint256 initialPusdBalance = pusd.balanceOf(address(h));

        assertEq(initialWstETHBalance, SWAP_AMOUNT);
        assertEq(initialPusdBalance, SWAP_AMOUNT);

        uint256 expectedOut = mockSwapRouter.quote(address(wstETH), address(pusd), SWAP_AMOUNT);

        uint256 amountOut = h.swap(address(wstETH), address(pusd), SWAP_AMOUNT);

        assertEq(wstETH.balanceOf(address(h)), initialWstETHBalance - SWAP_AMOUNT);
        assertEq(pusd.balanceOf(address(h)), initialPusdBalance + expectedOut);

        uint256 finalAllowance = wstETH.allowance(address(h), address(mockSwapRouter));
        assertEq(finalAllowance, 0);
        assertEq(amountOut, expectedOut);
    }

    function test_InternalSwap_RevertsIfOracleStale() public {
        TreasuryHarness h = _deployAndConfigureTreasuryHarness();

        _mintPUSD(address(h), SWAP_AMOUNT);

        mockOracle.setUpdatedAt(block.timestamp);
        vm.prank(admin);
        h.setOracleStaleAfter(1 hours);

        vm.warp(block.timestamp + 1 hours + 1);

        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__StaleOraclePrice.selector));
        h.swap(address(pusd), address(wstETH), SWAP_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE COVERAGE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Swap_RevertsWhenMinAmountOutIsZero() public {
        // Setup treasury with liquidity
        _setupTreasuryForLiquidation();
        
        // Set oracle answer to 0 to make minAmountOut calculation return 0
        mockOracle.setAnswer(0);
        
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAmount.selector));
        treasury.swapPusdForWstETH(1000 ether);
        vm.stopPrank();
    }

    function test_Swap_Reverts_WhenMinAmountOutZero() public {
        // High price so oracleQuote rounds to 0 ⇒ minAmountOut == 0
        mockOracle.setAnswer(1e27); // with 8 decimals, this is safely high

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAmount.selector));
        treasury.swapPusdForWstETH(1 ether);
    }

    function test_Swap_Reverts_WhenRouterAmountOutLessThanMin() public {
        mockOracle.setAnswer(3000e8); // sane price so minAmountOut > 0

        // Replace ProtocolConfig referenced by Treasury with a stub that uses a non-compliant router
        NonCompliantRouter nonCompliant = new NonCompliantRouter();
        ProtocolConfigStub stub = new ProtocolConfigStub(address(mockOracle), address(nonCompliant), address(mockQuoter), 3000, admin, upgrader);

        vm.startPrank(admin);
        treasury.setProtocolConfig(address(stub));
        vm.stopPrank();

        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSelector(ITreasury.Treasury__InvalidAmount.selector));
        treasury.swapPusdForWstETH(10 ether);
    }
    
}