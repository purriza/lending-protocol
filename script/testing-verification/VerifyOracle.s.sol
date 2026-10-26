// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {ProtocolConfig} from "../../contracts/ProtocolConfig.sol";
import {IPriceOracle} from "../../contracts/interfaces/IPriceOracle.sol";

contract VerifyOracle is Script {
    function run(address protocolConfigAddr) external view {
        check(protocolConfigAddr);
    }

    function check(address protocolConfigAddr) public view {
        ProtocolConfig config = ProtocolConfig(protocolConfigAddr);
        IPriceOracle oracle = config.oracle();

        console.log("=== ORACLE VERIFICATION ===");
        console.log("ProtocolConfig:", protocolConfigAddr);
        console.log("Oracle:", address(oracle));

        // Basic code existence check
        uint256 codeSize;
        address oracleAddr = address(oracle);
        assembly { codeSize := extcodesize(oracleAddr) }
        console.log("Oracle code size:", codeSize);
        if (codeSize == 0) {
            console.log("ERROR: No code at oracle address");
            return;
        }

        // Latest round data + decimals
        try oracle.decimals() returns (uint8 dec) {
            console.log("Decimals:", dec);
        } catch { console.log("ERROR: decimals() failed"); }

        try oracle.latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            console.log("Round ID:", roundId);
            console.log("Answer (scaled):", uint256(answer));
            console.log("StartedAt:", startedAt);
            console.log("UpdatedAt:", updatedAt);
            console.log("AnsweredInRound:", answeredInRound);
            if (updatedAt == 0) {
                console.log("WARNING: updatedAt == 0");
            }
        } catch {
            console.log("ERROR: latestRoundData() failed");
        }

        console.log("=== ORACLE VERIFICATION COMPLETE ===");
    }
}


