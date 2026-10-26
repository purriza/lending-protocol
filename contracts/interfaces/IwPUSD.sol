// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IwPUSD
 * @notice Interface for the wPUSD wrapped token contract
 * @dev Defines all external functions, events, and custom errors for the wPUSD wrapped token
 */
interface IwPUSD {
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event StabilityFundUpdated(address indexed oldFund, address indexed newFund);
    event WPUSDMinted(address indexed to, uint256 indexed amount);
    event WPUSDBurned(uint256 indexed amount);
    event wPUSDInitialized(address indexed protocolConfig);
    

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    error wPUSD__UnauthorizedCaller(address caller);
    error wPUSD__InvalidAddress();
    error wPUSD__InvalidAmount();

    /*//////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the wPUSD contract
     * @param _protocolConfig The initial protocol config of the contract
     */
    function initialize(address _protocolConfig) external;

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the stability fund address
     * @param _stabilityFund The new stability fund address
     */
    function setStabilityFund(address _stabilityFund) external;

    /*//////////////////////////////////////////////////////////////
                                CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mints wPUSD to an address
     * @param _to The address to mint wPUSD to
     * @param _amount The amount of wPUSD to mint
     */
    function mint(address _to, uint256 _amount) external;

    /**
     * @notice Burns wPUSD from an address
     * @param _amount The amount of wPUSD to burn
     */
    function burn(uint256 _amount) external;

    /*//////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the number of token decimals
     * @return The number of token decimals
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Returns the address of the stability fund
     * @return The address of the stability fund
     */
    function stabilityFund() external view returns (address);

}
