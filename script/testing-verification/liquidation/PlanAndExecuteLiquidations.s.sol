// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {LendingVault} from "../../../contracts/LendingVault.sol";
import {ProtocolConfig} from "../../../contracts/ProtocolConfig.sol";
import {IStabilityFund} from "../../../contracts/interfaces/IStabilityFund.sol";
import {ITreasury} from "../../../contracts/interfaces/ITreasury.sol";
import {IPUSD} from "../../../contracts/interfaces/IPUSD.sol";
import "../../NetworkAddresses.sol";

contract PlanAndExecuteLiquidations is Script {
    // Addresses
    address private LENDING_VAULT;
    address private PROTOCOL_CONFIG;

    // Testing wallets
    uint256[] private testingWallets = [
        vm.envUint("LIQUIDATION_TESTING_1_PRIVATE_KEY"),
        vm.envUint("LIQUIDATION_TESTING_2_PRIVATE_KEY"),
        vm.envUint("LIQUIDATION_TESTING_3_PRIVATE_KEY"),
        vm.envUint("LIQUIDATION_TESTING_4_PRIVATE_KEY"),
        vm.envUint("LIQUIDATION_TESTING_5_PRIVATE_KEY")
    ];

    // Additional monitored wallets
    address constant TARGET_WALLET = address(0);

    // Liquidation bot key (must have LIQUIDATION_BOT role on LendingVault)
    uint256 private liquidationBotPk = vm.envUint("LIQUIDATION_BOT_PRIVATE_KEY");

    struct PlanItem {
        address wallet;
        uint256 currentDebt;        // 18 decimals
        uint256 debtToLiquidate;    // 18 decimals
        uint256 sfPays;             // 18 decimals
        uint256 treasuryPays;       // 18 decimals
        bool willProceed;
    }

    function run() external {
        LENDING_VAULT = NetworkAddresses.lendingVault();
        PROTOCOL_CONFIG = NetworkAddresses.protocolConfig();
        console.log("=== LIQUIDATION PLAN & EXECUTION ===");

        LendingVault vault = LendingVault(LENDING_VAULT);
        ProtocolConfig config = ProtocolConfig(PROTOCOL_CONFIG);

        address collateralToken = config.collateralToken();
        console.log("Collateral Token: %s", collateralToken);
        if (collateralToken == address(0)) {
            console.log("ERROR: ProtocolConfig.collateralToken() is address(0). Aborting execution.");
            console.log("Hint: set it to the collateral (e.g. wstETH) before running liquidations.");
            return;
        }

        address sfAddr = address(vault.stabilityFund());
        address treasuryAddr = address(vault.treasury());
        address pusdAddr = address(vault.pusd());

        console.log("LendingVault: %s", address(vault));
        console.log("StabilityFund: %s", sfAddr);
        console.log("Treasury: %s", treasuryAddr);
        console.log("PUSD: %s", pusdAddr);

        uint256 sfBalance = IERC20(pusdAddr).balanceOf(sfAddr);
        uint256 treasuryBalance = IERC20(pusdAddr).balanceOf(treasuryAddr);
        console.log("SF PUSD balance: %s", sfBalance / 1e18);
        console.log("Treasury PUSD balance: %s", treasuryBalance / 1e18);

        address[] memory candidates = _collectCandidates();
        (PlanItem[] memory plan, uint256 planSize, uint256 totalDebtToLiquidate, uint256 sfRemaining, uint256 treasuryRemaining) =
            _buildPlan(vault, config, candidates, sfBalance, treasuryBalance);

        console.log("\n=== PLANNED LIQUIDATIONS (PREVIEW) ===");
        for (uint256 i = 0; i < planSize; i++) {
            PlanItem memory it = plan[i];
            console.log("- Wallet: %s", it.wallet);
            console.log("  Current Debt: %s PUSD", it.currentDebt / 1e18);
            console.log("  Debt To Liquidate: %s PUSD", it.debtToLiquidate / 1e18);
            console.log("  SF Pays: %s PUSD", it.sfPays / 1e18);
            console.log("  Treasury Pays: %s PUSD", it.treasuryPays / 1e18);
            console.log("  Proceed: %s", it.willProceed ? "YES" : "NO (Insufficient funds)" );
        }
        console.log("Total Debt To Liquidate (all proceeding): %s PUSD", totalDebtToLiquidate / 1e18);
        console.log("Projected SF Remaining: %s PUSD", sfRemaining / 1e18);
        console.log("Projected Treasury Remaining: %s PUSD", treasuryRemaining / 1e18);

        console.log("\n=== EXECUTING LIQUIDATIONS ===");
        vm.startBroadcast(liquidationBotPk);
        for (uint256 i = 0; i < planSize; i++) {
            if (!plan[i].willProceed) continue;
            address user = plan[i].wallet;
            try vault.liquidatePosition(user) returns (LendingVault.LiquidationResult memory res) {
                console.log("Liquidated %s", user);
                console.log("  Debt repaid: %s PUSD", res.debtRepaid / 1e18);
                console.log("  Collateral seized: %s", res.collateralSeized);
                console.log("  Remaining debt: %s PUSD", res.remainingDebt / 1e18);
                console.log("  Full liquidation: %s", res.fullLiquidation ? "YES" : "NO");
            } catch {
                console.log("Liquidation failed for %s", user);
            }
        }
        vm.stopBroadcast();

        console.log("\n=== DONE ===");
    }

    function preview() external view {
        console.log("=== LIQUIDATION PLAN PREVIEW (NO EXECUTION) ===");
        LendingVault vault = LendingVault(NetworkAddresses.lendingVault());
        ProtocolConfig config = ProtocolConfig(NetworkAddresses.protocolConfig());

        address collateralToken = config.collateralToken();
        console.log("Collateral Token: %s", collateralToken);
        if (collateralToken == address(0)) {
            console.log("ERROR: ProtocolConfig.collateralToken() is address(0). Cannot preview meaningful execution.");
            console.log("Hint: set it to the collateral (e.g. wstETH) before running or previewing.");
            return;
        }

        address sfAddr = address(vault.stabilityFund());
        address treasuryAddr = address(vault.treasury());
        address pusdAddr = address(vault.pusd());

        uint256 sfBalance = IERC20(pusdAddr).balanceOf(sfAddr);
        uint256 treasuryBalance = IERC20(pusdAddr).balanceOf(treasuryAddr);
        console.log("SF PUSD balance: %s", sfBalance / 1e18);
        console.log("Treasury PUSD balance: %s", treasuryBalance / 1e18);

        address[] memory candidates = _collectCandidates();
        (PlanItem[] memory plan, uint256 planSize, uint256 totalDebtToLiquidate, uint256 sfRemaining, uint256 treasuryRemaining) =
            _buildPlan(vault, config, candidates, sfBalance, treasuryBalance);

        console.log("\n=== PLANNED LIQUIDATIONS (PREVIEW) ===");
        for (uint256 i = 0; i < planSize; i++) {
            PlanItem memory it = plan[i];
            console.log("- Wallet: %s", it.wallet);
            console.log("  Current Debt: %s PUSD", it.currentDebt / 1e18);
            console.log("  Debt To Liquidate: %s PUSD", it.debtToLiquidate / 1e18);
            console.log("  SF Pays: %s PUSD", it.sfPays / 1e18);
            console.log("  Treasury Pays: %s PUSD", it.treasuryPays / 1e18);
            console.log("  Proceed: %s", it.willProceed ? "YES" : "NO (Insufficient funds)");
        }
        console.log("Total Debt To Liquidate (all proceeding): %s PUSD", totalDebtToLiquidate / 1e18);
        console.log("Projected SF Remaining: %s PUSD", sfRemaining / 1e18);
        console.log("Projected Treasury Remaining: %s PUSD", treasuryRemaining / 1e18);

        console.log("\nNOTE: This is a preview. No transactions were broadcast.");
    }

    function _collectCandidates() internal view returns (address[] memory out) {
        uint256 n = testingWallets.length + 1;
        out = new address[](n);
        for (uint256 i = 0; i < testingWallets.length; i++) {
            out[i] = vm.addr(testingWallets[i]);
        }
        out[n - 1] = TARGET_WALLET;
    }

    function _computeDebtToRepaySim(ProtocolConfig config, uint256 currentDebt) internal view returns (uint256) {
        uint256 closeFactorBps = config.closeFactorBps();
        uint256 partialRepayAmount = (currentDebt * closeFactorBps) / 10_000;
        if (partialRepayAmount == 0) partialRepayAmount = currentDebt;
        uint256 minDebt = config.minDebt();
        if (currentDebt > partialRepayAmount && (currentDebt - partialRepayAmount) < minDebt) {
            return currentDebt;
        }
        return partialRepayAmount;
    }

    function _buildPlan(
        LendingVault vault,
        ProtocolConfig config,
        address[] memory candidates,
        uint256 sfBalance,
        uint256 treasuryBalance
    ) internal view returns (
        PlanItem[] memory plan,
        uint256 planSize,
        uint256 totalDebtToLiquidate,
        uint256 sfRemaining,
        uint256 treasuryRemaining
    ) {
        plan = new PlanItem[](candidates.length);
        planSize = 0;
        totalDebtToLiquidate = 0;
        sfRemaining = sfBalance;
        treasuryRemaining = treasuryBalance;

        for (uint256 i = 0; i < candidates.length; i++) {
            address user = candidates[i];
            if (user == address(0)) continue;
            if (!vault.isLiquidatable(user)) continue;

            uint256 currentDebt = vault.getCurrentDebt(user);
            if (currentDebt == 0) continue;

            uint256 debtToRepay = _computeDebtToRepaySim(config, currentDebt);
            uint256 sfPays = debtToRepay <= sfRemaining ? debtToRepay : sfRemaining;
            uint256 treasuryPays = debtToRepay - sfPays;
            bool canProceed = treasuryPays <= treasuryRemaining;

            plan[planSize] = PlanItem({
                wallet: user,
                currentDebt: currentDebt,
                debtToLiquidate: debtToRepay,
                sfPays: sfPays,
                treasuryPays: treasuryPays,
                willProceed: canProceed
            });
            planSize++;
            totalDebtToLiquidate += debtToRepay;
            if (canProceed) {
                sfRemaining -= sfPays;
                treasuryRemaining -= treasuryPays;
            }
        }
    }
}


