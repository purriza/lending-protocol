// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IProtocolConfig} from "./IProtocolConfig.sol";
import {ILendingVault} from "./ILendingVault.sol";
import {ITreasury} from "./ITreasury.sol";
import {IStabilityFund} from "./IStabilityFund.sol";
import {IPUSD} from "./IPUSD.sol";
import {DataTypes} from "../DataTypes.sol";

/**
 * @title ILiquidationEngine
 * @notice Interface for the LiquidationEngine contract
 * @dev Defines all external functions, events, and custom errors for liquidation operations
 */
interface ILiquidationEngine {
    
    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/
    
    struct LiquidationRecord {
        address user;
        uint256 collateralAmount;
        uint256 debtAmount;
        uint256 timestamp;
        bool backstopUsed;
    }
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event ProtocolConfigUpdated(address indexed oldConfig, address indexed newConfig);
    event LendingVaultUpdated(address indexed oldVault, address indexed newVault);
    event StabilityFundUpdated(address indexed oldStabilityFund, address indexed newStabilityFund);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event MaxSlippageUpdated(uint256 oldSlippage, uint256 newSlippage);
    event TreasuryRevenueFeeUpdated(uint256 oldFee, uint256 newFee);
    event CollateralReceived(address indexed user, uint256 amount, uint256 liquidationId);
    event CollateralSwapped(uint256 liquidationId, uint256 collateralIn, uint256 stablecoinOut);
    event CollateralSentToTreasury(uint256 amount);
    event TreasuryBackstopReceived(uint256 amount);
    event FundsSentToStabilityFund(uint256 amount);
    event FundsSentToTreasury(uint256 amount);
    event LiquidationCompleted(
        uint256 indexed liquidationId, 
        address indexed user, 
        uint256 totalDebtPaid, 
        uint256 collateralLiquidated, 
        bool backstopUsed
    );
    event LiquidationEngineInitialized( 
        address indexed protocolConfig, 
        address pusd, 
        uint256 maxSlippage, 
        uint256 treasuryRevenueFee
    );

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error LiquidationEngine__UnauthorizedCaller();
    error LiquidationEngine__InvalidAddress(address addr);
    error LiquidationEngine__InvalidPercentage();
    error LiquidationEngine__InvalidAmount(uint256 amount);
    error LiquidationEngine__LiquidationNotFound();
    error LiquidationEngine__LiquidationResultedInLoss();
    error LiquidationEngine__StaleOraclePrice();

    /*//////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the LiquidationEngine contract
     * @param _protocolConfig Protocol configuration contract address
     * @param _pusd PUSD token contract address
     */
    function initialize(
        address _protocolConfig,
        address _pusd
    ) external;

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emergency pause function
     */
    function pause() external;

    /**
     * @notice Emergency unpause function
     */
    function unpause() external;

    /**
     * @notice Sets the protocol configuration contract
     * @param _protocolConfig New protocol config address
     */
    function setProtocolConfig(address _protocolConfig) external;

    /**
     * @notice Sets the lending vault contract
     * @param _lendingVault New lending vault address
     */
    function setLendingVault(address _lendingVault) external;

    /**
     * @notice Sets the StabilityFund contract address
     * @param _stabilityFund New StabilityFund contract address
     */
    function setStabilityFund(address _stabilityFund) external;

    /**
     * @notice Sets the Treasury contract address
     * @param _treasury New Treasury contract address
     */
    function setTreasury(address _treasury) external;


    /**
     * @notice Sets the maximum allowed slippage
     * @param _maxSlippage New max slippage in basis points
     */
    function setMaxSlippage(uint256 _maxSlippage) external;

    /**
     * @notice Sets the treasury revenue fee percentage
     * @param _treasuryRevenueFee New treasury revenue fee in basis points
     */
    function setTreasuryRevenueFee(uint256 _treasuryRevenueFee) external;


    /*//////////////////////////////////////////////////////////////
                                CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Executes collateral sale and distributes funds according to the liquidation order
     * @param _order The struct containing liquidation details including debtor and funding breakdown
     * @return liquidationId The unique identifier for this liquidation
     * @dev Performs maximum effort sale within slippage limits, sends remaining collateral to Treasury.
     *      Uses oracle price for initial sanity check, then iterates with quoter for efficiency.
     *      Distributes funds based on two cases:
     *      - Case 1: Sale covers debt - normal distribution with profit sharing
     *      - Case 2: Sale insufficient - activates Treasury backstop for shortfall
     */
    function executeLiquidation(DataTypes.LiquidationOrder calldata _order) external returns (uint256 liquidationId);

    /*//////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the protocol configuration contract address
     * @return The protocol configuration contract address
     */
    function protocolConfig() external view returns (IProtocolConfig);

    /**
     * @notice Gets the PUSD token contract address
     * @return The PUSD token contract address
     */
    function pusd() external view returns (IPUSD);

    /**
     * @notice Gets the lending vault contract address
     * @return The lending vault contract address
     */
    function lendingVault() external view returns (ILendingVault);

    /**
     * @notice Gets the stability fund contract address
     * @return The stability fund contract address
     */
    function stabilityFund() external view returns (IStabilityFund);

    /**
     * @notice Gets the treasury contract address
     * @return The treasury contract address
     */
    function treasury() external view returns (ITreasury);


    /**
     * @notice Gets the maximum slippage allowed for swaps
     * @return The maximum slippage in basis points
     */
    function maxSlippage() external view returns (uint256);

    /**
     * @notice Gets the treasury revenue fee percentage
     * @return The treasury revenue fee in basis points
     */
    function treasuryRevenueFee() external view returns (uint256);

    /**
     * @notice Gets the total collateral liquidated
     * @return The total amount of collateral liquidated
     */
    function totalCollateralLiquidated() external view returns (uint256);

    /**
     * @notice Gets the total debt covered through liquidations
     * @return The total amount of debt covered
     */
    function totalDebtCovered() external view returns (uint256);

    /**
     * @notice Gets the current liquidation ID counter
     * @return The current liquidation counter value
     */
    function liquidationCounter() external view returns (uint256);

    /**
     * @notice Gets liquidation record by ID
     * @param _liquidationId ID of the liquidation
     * @return user The user that was liquidated
     * @return collateralAmount The amount of collateral liquidated
     * @return debtAmount The amount of debt paid
     * @return timestamp The timestamp of the liquidation
     * @return backstopUsed Whether the Treasury backstop was used
     */
    function liquidations(uint256 _liquidationId) external view returns (
        address user,
        uint256 collateralAmount,
        uint256 debtAmount,
        uint256 timestamp,
        bool backstopUsed
    );

    /**
     * @notice Gets liquidation details by ID
     * @param _liquidationId ID of the liquidation
     */
    function getLiquidation(uint256 _liquidationId) external view returns (
        LiquidationRecord memory record
    );

    /**
     * @notice Gets liquidation statistics
     * @return totalLiquidations Total number of liquidations
     * @return totalCollateral Total collateral liquidated
     * @return totalDebt Total debt covered
     */
    function getLiquidationStats() external view returns (
        uint256 totalLiquidations,
        uint256 totalCollateral,
        uint256 totalDebt
    );
}
