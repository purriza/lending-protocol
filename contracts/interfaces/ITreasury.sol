// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;
import {IProtocolConfig} from "./IProtocolConfig.sol";

import "../interfaces/IProtocolConfig.sol";

/**
 * @title ITreasury
 * @notice Interface for the Treasury contract
 * @dev Defines all external functions, events, and custom errors for treasury operations
 */
interface ITreasury {
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event TreasuryInitialized(address indexed protocolConfig, address pusd, address wstETH);
    event PUSDUpdated(address indexed pusdAddress);
    event WstETHUpdated(address indexed wstETHAddress);
    event LendingVaultUpdated(address indexed oldAddress, address indexed newAddress);
    event LiquidationEngineUpdated(address indexed oldAddress, address indexed newAddress);
    event StabilityFundUpdated(address indexed oldAddress, address indexed newAddress);
    event ProtocolConfigUpdated(address indexed oldAddress, address indexed newAddress);
    event PusdReceived(address indexed pusdAddress, uint256 amount);
    event WstETHReceived(address indexed wstETHAddress, uint256 amount);
    event PusdWithdrawn(address indexed pusdAddress, uint256 amount);
    event WstETHWithdrawn(address indexed wstETHAddress, uint256 amount);
    event PusdSwapped(address indexed pusdAddress, address indexed wstETHAddress, uint256 amountIn, uint256 amountOut);
    event WstETHSwapped(address indexed wstETHAddress, address indexed pusdAddress, uint256 amountIn, uint256 amountOut);
    event BackstopFundsUsed(address indexed token, uint256 requestedAmount, uint256 providedAmount, address indexed requester);
    event BackstopIOUCreated(address indexed requester, uint256 requested, uint256 provided, uint256 shortfall);
    event BackstopIouRepaid(address indexed payer, uint256 repaidPusd, uint256 repaidWstETH, uint256 pusdValueUsed, uint256 remainingIOU);
    event BackstopRepaymentForwarded(address indexed stabilityFund, uint256 pusdAmount);
    event SwapSlippageUpdated(uint256 oldBps, uint256 newBps);
    event OracleStaleAfterUpdated(uint256 oldValue, uint256 newValue);
    event SwapDeadlineSecondsUpdated(uint256 oldValue, uint256 newValue);

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error Treasury__InvalidAddress();
    error Treasury__InvalidAmount();
    error Treasury__UnauthorizedCaller();
    error Treasury__InsufficientPusdBalance(uint256 requestedAmount, uint256 pusdbalance);
    error Treasury__InsufficientWstETHBalance(uint256 requestedAmount, uint256 wstETHBalance);
    error Treasury__StaleOraclePrice();
    error Treasury__InvalidOracleRound();
    error Treasury__NoIOUOpen();
    error Treasury__IOUAlreadyOpen();
    
    /*//////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    function initialize(
        address _protocolConfig,
        address _pusd,
        address _wstETH
    ) external;

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the PUSD contract address
     * @param _pusd The new PUSD contract address
     */
    function setPUSD(address _pusd) external;

    /**
     * @notice Sets the wstETH contract address
     * @param _wstETH The new wstETH contract address
     */
    function setWstETH(address _wstETH) external;

    /**
     * @notice Sets the LendingVault contract address
     * @param _lendingVault The new LendingVault contract address
     */
    function setLendingVault(address _lendingVault) external;

    /**
     * @notice Sets the ProtocolConfig contract address
     * @param _protocolConfig The new ProtocolConfig contract address
     */
    function setProtocolConfig(address _protocolConfig) external;

    /**
     * @notice Sets the StabilityFund contract address
     * @param _stabilityFund The new StabilityFund contract address
     */
    function setStabilityFund(address _stabilityFund) external;

    /**
     * @notice Sets the LiquidationEngine contract address
     * @param _liquidationEngine The new LiquidationEngine contract address
     */
    function setLiquidationEngine(address _liquidationEngine) external;

    /**
     * @notice Withdraws PUSD from the Treasury
     * @param _amount The amount of PUSD to withdraw
     */
    function withdrawPUSD(uint256 _amount) external;

    /**
     * @notice Withdraws wstETH from the Treasury
     * @param _amount The amount of wstETH to withdraw
     */
    function withdrawWstETH(uint256 _amount) external;

    /**
     * @notice Sets the swap slippage basis points
     * @param _bps The new swap slippage basis points
     * @dev Max Value is 2_000 (20%)
     */
    function setSwapSlippageBps(uint256 _bps) external;

    /**
     * @notice Sets the oracle stale after time
     * @param _seconds The new oracle stale after time
     */
    function setOracleStaleAfter(uint256 _seconds) external;

    /**
     * @notice Sets the swap deadline seconds
     * @param _seconds The new swap deadline seconds
     */
    function setSwapDeadlineSeconds(uint256 _seconds) external;

    /*//////////////////////////////////////////////////////////////
                                CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Receives PUSD from the LendingVault, LiquidationEngine, or Admin
     * @param _amount The amount of PUSD to receive
     */
    function receivePUSD(uint256 _amount) external;

    /**
     * @notice Receives wstETH from the LendingVault, LiquidationEngine, or Admin
     * @param _amount The amount of wstETH to receive
     */
    function receiveWstETH(uint256 _amount) external;

    /**
     * @notice Provides backstop funds in PUSD shoud the stability fund not have enough PUSD to cover a liquidation
     * @param _amount Amount of tokens to provide
     * @return providedAmount The amount of PUSD provided
     */
    function provideBackstopFunds(uint256 _amount) external returns (uint256 providedAmount);

    /**
     * @notice Repays the backstop IOU amount created when the Treasury does not have enough PUSD to cover a liquidation
     * @param _pusdAmount The amount of PUSD to repay
     * @param _wstETHAmount The amount of wstETH to swap to PUSD
     * @return pusdValueUsed The amount of PUSD used to repay the IOU
     * @return remainingIOU The remaining amount of IOU
     */
    function repayBackstopIou(uint256 _pusdAmount, uint256 _wstETHAmount) external returns (uint256 pusdValueUsed, uint256 remainingIOU);

    /**
     * @notice Swaps PUSD for wstETH
     * @param _amountIn The amount of PUSD to swap
     * @return amountOut The amount of wstETH received
     */
    function swapPusdForWstETH(uint256 _amountIn) external returns (uint256 amountOut);

    /**
     * @notice Swaps wstETH for PUSD
     * @param _amountIn The amount of wstETH to swap
     * @return amountOut The amount of PUSD received
     */
    function swapWstETHForPusd(uint256 _amountIn) external returns (uint256 amountOut);

    /*//////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the address of the PUSD contract
     * @return The address of the PUSD contract
     */
    function pusd() external view returns (address);

    /**
     * @notice Returns the address of the wstETH contract
     * @return The address of the wstETH contract
     */
    function wstETH() external view returns (address);

    /**
     * @notice Returns the address of the LendingVault contract
     * @return The address of the LendingVault contract
     */
    function lendingVault() external view returns (address);

    /**
     * @notice Returns the address of the LiquidationEngine contract
     * @return The address of the LiquidationEngine contract
     */
    function liquidationEngine() external view returns (address);

    /**
     * @notice Returns the address of the StabilityFund contract
     * @return The address of the StabilityFund contract
     */
    function stabilityFund() external view returns (address);

    /**
     * @notice Returns the balance of PUSD in the Treasury
     * @return The balance of PUSD in the Treasury
     */
    function pusdBalance() external view returns (uint256);

    /**
     * @notice Returns the balance of wstETH in the Treasury
     * @return The balance of wstETH in the Treasury
     */
    function wstETHBalance() external view returns (uint256);

    /**
     * @notice Returns the total amount of backstop funds used
     * @return The total amount of backstop funds used
     */
    function totalBackstopUsed() external view returns (uint256);

    /**
     * @notice Returns the amount of PUSD-denominated outstanding IOU
     * @return The amount of PUSD-denominated outstanding IOU
     */
    function backstopIouPusd() external view returns (uint256);

    /**
     * @notice Returns the address of the ProtocolConfig contract
     * @return The address of the ProtocolConfig contract
     */
    function protocolConfig() external view returns (IProtocolConfig);

    /**
     * @notice Returns the swap slippage basis points
     * @return The swap slippage basis points
     */
    function swapSlippageBps() external view returns (uint256);

    /**
     * @notice Returns the oracle stale after time
     * @return The oracle stale after time
     */
    function oracleStaleAfter() external view returns (uint256);

    /**
     * @notice Returns the swap deadline seconds
     * @return The swap deadline seconds
     */
    function swapDeadlineSeconds() external view returns (uint256);
}
