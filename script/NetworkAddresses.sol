// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/// @dev Addresses of protocol-deployed contracts are intentionally left as
/// address(0). Populate them via the deployment scripts before running any
/// script that depends on this library against a live network.
library NetworkAddresses {
    error UnsupportedChain(uint256 chainId);

    function pusd() internal view returns (address) {
        if (block.chainid == 1) return address(0);
        if (block.chainid == 11155111) return address(0);

        revert UnsupportedChain(block.chainid);
    }

    function wpusd() internal view returns (address) {
        if (block.chainid == 1) return address(0);
        if (block.chainid == 11155111) return address(0);

        revert UnsupportedChain(block.chainid);
    }

     function protocolConfig() internal view returns (address) {
        if (block.chainid == 1) return address(0);
        if (block.chainid == 11155111) return address(0);

        revert UnsupportedChain(block.chainid);
    }

    function lendingVault() internal view returns (address) {
        if (block.chainid == 1) return address(0);
        if (block.chainid == 11155111) return address(0);

        revert UnsupportedChain(block.chainid);
    }

    function stabilityFund() internal view returns (address) {
        if (block.chainid == 1) return address(0);
        if (block.chainid == 11155111) return address(0);

        revert UnsupportedChain(block.chainid);
    }

    function treasury() internal view returns (address) {
        if (block.chainid == 1) return address(0);
        if (block.chainid == 11155111) return address(0);

        revert UnsupportedChain(block.chainid);
    }

    function liquidationEngine() internal view returns (address) {
        if (block.chainid == 1) return address(0);
        if (block.chainid == 11155111) return address(0);

        revert UnsupportedChain(block.chainid);
    }

    // Chainlink Lido STETH / USD
    function oracle() internal view returns (address) {
        if (block.chainid == 1) return 0xCfE54B5cD566aB89272946F602D76Ea879CAb4a8;
        if (block.chainid == 11155111) return 0x0d7Ed5946e191Fc448C1c240E6F409c292d599Ea;

        revert UnsupportedChain(block.chainid);
    }

    // Uniswap V3 Router
    function swapRouter() internal view returns (address) {
        if (block.chainid == 1) return 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        if (block.chainid == 11155111) return 0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E;

        revert UnsupportedChain(block.chainid);
    }

    // Uniswap V3 Quoter
    function quoter() internal view returns (address) {
        if (block.chainid == 1) return 0x61fFE014bA17989E743c5F6cB21bF9697530B21e;
        if (block.chainid == 11155111) return 0xEd1f6473345F45b75F8179591dd5bA1888cf2FB3;

        revert UnsupportedChain(block.chainid);
    }

    // wstETH
    function collateralToken() internal view returns (address) {
        if (block.chainid == 1) return 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        if (block.chainid == 11155111) return 0xB8f3258B88493174c8b7490Da9443ea22b698F63;

        revert UnsupportedChain(block.chainid);
    }

    function treasuryWallet() internal view returns (address) {
        if (block.chainid == 1) return address(0);
        if (block.chainid == 11155111) return address(0);

        revert UnsupportedChain(block.chainid);
    }
}