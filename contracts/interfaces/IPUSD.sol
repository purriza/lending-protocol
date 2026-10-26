// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IPUSD
 * @notice Interface for the PUSD contract
 */
interface IPUSD is IERC20 {

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event LendingVaultUpdated(address indexed oldVault, address indexed newVault);
    event StabilityFundUpdated(address indexed oldFund, address indexed newFund);
    event PUSDMinted(address indexed to, uint256 amount);
    event PUSDBurned(address indexed from, uint256 amount);
    event PUSDInitialized(address indexed protocolConfig);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error PUSD__UnauthorizedMinter();
    error PUSD__UnauthorizedBurner();
    error PUSD__InvalidAddress();

    /*//////////////////////////////////////////////////////////////
                            FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the LendingVault contract address
     * @param _lendingVault The new LendingVault contract address
     */
    function setLendingVault(address _lendingVault) external;

    /**
     * @notice Sets the StabilityFund contract address
     * @param _stabilityFund The new StabilityFund contract address
     */
    function setStabilityFund(address _stabilityFund) external;

    /**
     * @notice Mints PUSD tokens to a specified address
     * @param to The address to mint tokens to
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burns PUSD tokens from the caller's account
     * @param amount The amount of tokens to burn
     */
    function burn(uint256 amount) external;

    /**
     * @notice Returns the number of decimals
     * @return The number of decimals
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Returns the address of the LendingVault contract
     * @return The address of the LendingVault contract
     */
    function lendingVault() external view returns (address);

    /**
     * @notice Returns the address of the StabilityFund contract
     * @return The address of the StabilityFund contract
     */
    function stabilityFund() external view returns (address);
}
