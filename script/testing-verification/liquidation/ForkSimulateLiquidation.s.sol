// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";

import {ProtocolConfig} from "../../../contracts/ProtocolConfig.sol";
import {LendingVault} from "../../../contracts/LendingVault.sol";
import {ITreasury} from "../../../contracts/interfaces/ITreasury.sol";
import {IStabilityFund} from "../../../contracts/interfaces/IStabilityFund.sol";
import {LiquidationEngine} from "../../../contracts/LiquidationEngine.sol";
import {ILiquidationEngine} from "../../../contracts/interfaces/ILiquidationEngine.sol";
import {IPriceOracle} from "../../../contracts/interfaces/IPriceOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "../../NetworkAddresses.sol";

contract LiquidationExecutor {
    function execute(address lendingVault, address user) external {
        LendingVault(lendingVault).liquidatePosition(user);
    }
}

contract ForkSimulateLiquidation is Script {
    address LENDING_VAULT;
    address PROTOCOL_CONFIG;

    // Testing wallets
    uint256[] private testingWallets = [
        vm.envUint("LIQUIDATION_TESTING_1_PRIVATE_KEY"),
        vm.envUint("LIQUIDATION_TESTING_2_PRIVATE_KEY"),
        vm.envUint("LIQUIDATION_TESTING_3_PRIVATE_KEY"),
        vm.envUint("LIQUIDATION_TESTING_4_PRIVATE_KEY"),
        vm.envUint("LIQUIDATION_TESTING_5_PRIVATE_KEY")
    ];

    // Additional monitored wallets (by address)
    address[] private additionalWallets = [
        address(0) // target wallet
    ];

    function runFor(address user) external {
        LENDING_VAULT = NetworkAddresses.lendingVault();
        PROTOCOL_CONFIG = NetworkAddresses.protocolConfig();
        console.log("=== FORK LIQUIDATION SIMULATION ===");
        _setupFork();
        _simulateFor(user);
        console.log("=== SIMULATION COMPLETE ===");
    }

    function runForSF(address user) external {
        LENDING_VAULT = NetworkAddresses.lendingVault();
        PROTOCOL_CONFIG = NetworkAddresses.protocolConfig();
        console.log("=== FORK LIQUIDATION SIMULATION (SF-ONLY MODE) ===");
        _setupFork();
        (LendingVault vault, ITreasury treasury, IStabilityFund sf) = _resolveDeps();
        // Suppress unused variable warnings - these are used for setup
        vault;
        sf;
        address pusdToken = treasury.pusd();
        uint256 trBal = treasury.pusdBalance();
        if (trBal > 0) {
            vm.startPrank(address(treasury));
            IERC20(pusdToken).transfer(address(0x000000000000000000000000000000000000dEaD), trBal);
            vm.stopPrank();
        }
        _simulateFor(user);
        console.log("=== SIMULATION COMPLETE ===");
    }

    function runAll() external {
        LENDING_VAULT = NetworkAddresses.lendingVault();
        PROTOCOL_CONFIG = NetworkAddresses.protocolConfig();
        console.log("=== FORK LIQUIDATION SIMULATION ===");
        _setupFork();
        for (uint256 i = 0; i < testingWallets.length; i++) {
            address wallet = vm.addr(testingWallets[i]);
            if (LendingVault(LENDING_VAULT).isLiquidatable(wallet)) {
                _simulateFor(wallet);
            }
        }
        for (uint256 j = 0; j < additionalWallets.length; j++) {
            address wallet2 = additionalWallets[j];
            if (LendingVault(LENDING_VAULT).isLiquidatable(wallet2)) {
                _simulateFor(wallet2);
            }
        }
        console.log("=== SIMULATION COMPLETE ===");
    }

    function _simulateFor(address user) internal {
        (LendingVault vault, ITreasury treasury, IStabilityFund sf) = _resolveDeps();

        console.log("User:", user);

        (uint256 coll0, uint256 debtNow, uint256 sfPusd0, uint256 trPusd0, uint256 trWst0) =
            _getAndLogInitial(vault, treasury, sf, user);
        if (!vault.isLiquidatable(user)) return;

        vm.recordLogs();
        _authorizeAndExecute(vault, user);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _logSwapMetrics(address(vault.liquidationEngine()), logs);

        _getAndLogFinal(vault, treasury, sf, user, coll0, debtNow, sfPusd0, trPusd0, trWst0);
        _logPlan(coll0, debtNow);
    }

    function _setupFork() internal {
        vm.selectFork(vm.createFork(vm.envString("SEPOLIA_RPC_URL")));
    }

    function _logSwapMetrics(address engine, Vm.Log[] memory logs) internal pure {
        bytes32 sigSwap = keccak256("CollateralSwapped(uint256,uint256,uint256)");
        bytes32 sigSentSF = keccak256("FundsSentToStabilityFund(uint256)");
        bytes32 sigSentTr = keccak256("FundsSentToTreasury(uint256)");
        uint256 soldWst;
        uint256 pusdOut;
        uint256 sentSF;
        uint256 sentTr;
        for (uint256 i = 0; i < logs.length; i++) {
            Vm.Log memory L = logs[i];
            if (L.emitter != engine) continue;
            if (L.topics.length > 0 && L.topics[0] == sigSwap) {
                (, uint256 sellable, uint256 outJ) = abi.decode(L.data, (uint256,uint256,uint256));
                soldWst = sellable;
                pusdOut = outJ;
            } else if (L.topics.length > 0 && L.topics[0] == sigSentSF) {
                (uint256 amt) = abi.decode(L.data, (uint256));
                sentSF += amt;
            } else if (L.topics.length > 0 && L.topics[0] == sigSentTr) {
                (uint256 amt2) = abi.decode(L.data, (uint256));
                sentTr += amt2;
            }
        }
        console.log("");
        console.log("--- SWAP METRICS ---");
        console.log("  Collateral sold (wstETH, wei): %s", soldWst);
        console.log("  PUSD from swap (wei): %s", pusdOut);
        console.log("  PUSD sent to SF (wei): %s", sentSF);
        console.log("  PUSD sent to Treasury (wei): %s", sentTr);
    }

    function _resolveDeps() internal view returns (LendingVault vault, ITreasury treasury, IStabilityFund sf) {
        vault = LendingVault(LENDING_VAULT);
        LiquidationEngine eng = LiquidationEngine(address(vault.liquidationEngine()));
        treasury = ITreasury(address(eng.treasury()));
        sf = IStabilityFund(address(eng.stabilityFund()));
    }

    function _getAndLogInitial(LendingVault vault, ITreasury treasury, IStabilityFund sf, address user)
        internal
        view
        returns (uint256 coll0, uint256 debtNow, uint256 sfPusd0, uint256 trPusd0, uint256 trWst0)
    {
        (coll0, , ,) = vault.getPosition(user);
        debtNow = vault.getCurrentDebt(user);
        console.log("");
        console.log("--- INITIAL STATE ---");
        console.log("  User collateral (wstETH, wei): %s", coll0);
        console.log("  User debt (PUSD, wei): %s", debtNow);
        console.log("  Collateral Value (USD, wei): %s", _collateralValueUSD(ProtocolConfig(PROTOCOL_CONFIG), coll0));
        _logHealthRatio(vault, user);
        bool liq = vault.isLiquidatable(user);
        console.log("  Liquidatable:", liq);
        sfPusd0 = IERC20(treasury.pusd()).balanceOf(address(sf));
        trPusd0 = treasury.pusdBalance();
        trWst0 = treasury.wstETHBalance();
        console.log("  SF PUSD (PUSD, wei): %s", sfPusd0);
        console.log("  Treasury PUSD (PUSD, wei): %s", trPusd0);
        console.log("  Treasury wstETH (wstETH, wei): %s", trWst0);
    }

    function _authorizeAndExecute(LendingVault vault, address user) internal {
        LiquidationExecutor exec = new LiquidationExecutor();
        address admin = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));
        vm.startPrank(admin);
        vault.setLiquidationBot(address(exec), true);
        vm.stopPrank();
        exec.execute(address(vault), user);
    }

    function _getAndLogFinal(
        LendingVault vault,
        ITreasury treasury,
        IStabilityFund sf,
        address user,
        uint256 coll0,
        uint256 debt0,
        uint256 sfPusd0,
        uint256 trPusd0,
        uint256 trWst0
    ) internal view {
        (uint256 coll1, uint256 debt1, ,) = vault.getPosition(user);
        uint256 sfPusd1 = IERC20(treasury.pusd()).balanceOf(address(sf));
        uint256 trPusd1 = treasury.pusdBalance();
        uint256 trWst1 = treasury.wstETHBalance();
        uint256 collVal1 = _collateralValueUSD(ProtocolConfig(PROTOCOL_CONFIG), coll1);
        console.log("");
        console.log("--- FINAL STATE ---");
        console.log("  User collateral (wstETH, wei): %s", coll1);
        console.log("  User debt (PUSD, wei): %s", debt1);
        console.log("  Collateral Value (USD, wei): %s", collVal1);
        _logHealthRatio(vault, user);

        console.log("");
        console.log("--- DELTAS ---");
        console.log("  Collateral seized (wstETH, wei): %s", coll0 > coll1 ? (coll0 - coll1) : 0);
        console.log("  Debt repaid (PUSD, wei): %s", debt0 > debt1 ? (debt0 - debt1) : 0);
        console.log("  Stability Fund PUSD used (PUSD, wei): %s", sfPusd0 > sfPusd1 ? (sfPusd0 - sfPusd1) : 0);
        console.log("  Treasury PUSD used (PUSD, wei): %s", trPusd0 > trPusd1 ? (trPusd0 - trPusd1) : 0);
        uint256 wstDelta = trWst1 >= trWst0 ? (trWst1 - trWst0) : (trWst0 - trWst1);
        console.log("  Treasury wstETH Delta (wstETH, wei): %s", wstDelta);
    }

    function _logPlan(uint256 coll0, uint256 debtNow) internal view {
        uint256 cfBps = ProtocolConfig(PROTOCOL_CONFIG).closeFactorBps();
        uint256 partialRepay = (debtNow * cfBps) / 10_000;
        if (partialRepay == 0) partialRepay = debtNow;
        uint256 minDebt = ProtocolConfig(PROTOCOL_CONFIG).minDebt();
        uint256 debtToRepay = (debtNow - partialRepay) < minDebt ? debtNow : partialRepay;
        (, int256 ans,, , ) = ProtocolConfig(PROTOCOL_CONFIG).oracle().latestRoundData();
        uint8 dec = ProtocolConfig(PROTOCOL_CONFIG).oracle().decimals();
        uint256 price = uint256(ans);
        uint256 bonusBps = ProtocolConfig(PROTOCOL_CONFIG).liquidationBonusBps();
        uint256 expectedSeize = (debtToRepay * (10_000 + bonusBps) * (10 ** dec)) / (price * 10_000);
        if (expectedSeize > coll0) expectedSeize = coll0;
        console.log("");
        console.log("--- PLAN (from params) ---");
        console.log("  closeFactorBps:", cfBps);
        console.log("  debtToRepay (PUSD, wei): %s", debtToRepay);
        console.log("  expected collateral to seize (wstETH, wei): %s", expectedSeize);
        console.log("");
    }

    function _logHealthRatio(LendingVault vault, address user) internal view {
        console.log("  Health Ratio (bps): %s", vault.getPositionHealthRatio(user));
    }

    function _collateralValueUSD(ProtocolConfig cfg, uint256 collateralAmount) internal view returns (uint256) {
        if (collateralAmount == 0) return 0;
        IPriceOracle oracle = cfg.oracle();
        (, int256 answer,, , ) = oracle.latestRoundData();
        if (answer <= 0) return 0;
        uint256 price = uint256(answer);
        uint8 dec = oracle.decimals();
        return (collateralAmount * price) / (10 ** dec);
    }
}

// helpers
function _toDec18(uint256 amount, uint8 dp) pure returns (string memory) {
    if (dp > 18) dp = 18;
    uint256 whole = amount / 1e18;
    uint256 frac = dp == 0 ? 0 : (amount % 1e18) / (10 ** (18 - dp));
    string memory wholeStr = Strings.toString(whole);
    if (dp == 0) return wholeStr;
    string memory fracStr = Strings.toString(frac);
    // left-pad fraction with zeros to dp
    uint256 len = bytes(fracStr).length;
    if (len < dp) {
        bytes memory zeros = new bytes(dp - len);
        for (uint256 i = 0; i < dp - len; i++) zeros[i] = bytes1("0");
        fracStr = string(abi.encodePacked(string(zeros), fracStr));
    }
    return string(abi.encodePacked(wholeStr, ".", fracStr));
}


