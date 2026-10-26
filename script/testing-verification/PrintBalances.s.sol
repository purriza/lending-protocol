// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IProtocolConfig} from "../../contracts/interfaces/IProtocolConfig.sol";
import {ITreasury} from "../../contracts/interfaces/ITreasury.sol";
import {ILendingVault} from "../../contracts/interfaces/ILendingVault.sol";
import {IPriceOracle} from "../../contracts/interfaces/IPriceOracle.sol";
import "../NetworkAddresses.sol";

contract PrintBalances is Script {
    function run() external view {
        address protocolConfig = NetworkAddresses.protocolConfig();
        address lendingVault = NetworkAddresses.lendingVault();
        address treasury = NetworkAddresses.treasury();
        address stabilityFund = NetworkAddresses.stabilityFund();
        address pusd = NetworkAddresses.pusd();

        // Resolve testing wallets from private keys (fallback to USER1..USER5 if present)
        address[5] memory users;
        address u1 = _envAddressOrZero("USER1");
        if (u1 != address(0)) {
            users = [
                u1,
                _envAddressOrZero("USER2"),
                _envAddressOrZero("USER3"),
                _envAddressOrZero("USER4"),
                _envAddressOrZero("USER5")
            ];
        } else {
            users = [
                vm.addr(vm.envUint("LIQUIDATION_TESTING_1_PRIVATE_KEY")),
                vm.addr(vm.envUint("LIQUIDATION_TESTING_2_PRIVATE_KEY")),
                vm.addr(vm.envUint("LIQUIDATION_TESTING_3_PRIVATE_KEY")),
                vm.addr(vm.envUint("LIQUIDATION_TESTING_4_PRIVATE_KEY")),
                vm.addr(vm.envUint("LIQUIDATION_TESTING_5_PRIVATE_KEY"))
            ];
        }

        console.log("=== Protocol Diagnostics: Balances & Positions ===");
        console.log("ProtocolConfig:", protocolConfig);
        console.log("LendingVault:  ", lendingVault);
        console.log("StabilityFund: ", stabilityFund);
        console.log("Treasury:      ", treasury);
        console.log("");

        console.log("SF PUSD token balance:", IERC20(pusd).balanceOf(stabilityFund));
        console.log("Treasury.pusdBalance(): ", ITreasury(treasury).pusdBalance());
        console.log("Treasury.wstETHBalance():", ITreasury(treasury).wstETHBalance());

        console.log("");
        console.log("--- User Positions ---");
        IPriceOracle oracle = IProtocolConfig(protocolConfig).oracle();
        (, int256 answer, , ,) = oracle.latestRoundData();
        uint256 priceScaled = uint256(answer);
        ILendingVault vault = ILendingVault(lendingVault);
        for (uint256 i = 0; i < users.length; i++) {
            address u = users[i];
            if (u == address(0)) continue;
            _printUser(vault, u, priceScaled, i);
        }
    }

    function _printUser(ILendingVault vault, address user, uint256 priceScaled, uint256 idx) internal view {
        (uint256 col, uint256 debt, uint256 hr, bool exists) = vault.getPosition(user);
        console.log("User", idx + 1, user);
        console.log("  Collateral:", col);
        console.log("  Debt:      ", debt);
        console.log("  Health:    ", hr);
        uint256 colValue = (col * priceScaled) / 1e8;
        uint256 ltv = colValue > 0 ? (debt * 10000) / colValue : 0;
        bool liquid = vault.isLiquidatable(user);
        console.log("  LTV(bps):  ", ltv);
        console.log("  Liquidable:", liquid);
        console.log("  Exists:    ", exists);
    }

    function _envAddressOrZero(string memory key) private view returns (address) {
        try vm.envAddress(key) returns (address a) {
            return a;
        } catch {
            return address(0);
        }
    }
}


