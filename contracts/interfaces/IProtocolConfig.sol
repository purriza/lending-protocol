// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./IPUSD.sol";

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {IPriceOracle} from "./IPriceOracle.sol";

/**
 * @title IProtocolConfig
 * @notice Interface for the ProtocolConfig contract
 * @dev Defines all external functions, events, and custom errors for protocol configuration
 */
interface IProtocolConfig {
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event TreasuryWalletUpdated(address indexed oldWallet, address indexed newWallet);
    event OracleUpdated(address indexed oldOracle, address indexed newOracle);
    event SwapRouterUpdated(address indexed oldSwapRouter, address indexed newSwapRouter);
    event QuoterUpdated(address indexed oldQuoter, address indexed newQuoter);
    event CollateralTokenUpdated(address indexed oldToken, address indexed newToken);
    event LiquidationThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event MinCollateralRatioUpdated(uint256 oldRatio, uint256 newRatio);
    event DebtCeilingUpdated(uint256 oldCeiling, uint256 newCeiling);
    event MinDebtUpdated(uint256 oldMinDebt, uint256 newMinDebt);
    event CloseFactorUpdated(uint256 oldCloseFactorBps, uint256 newCloseFactorBps);
    event LiquidationBonusUpdated(uint256 oldBonusBps, uint256 newBonusBps);
    event UniswapFeeUpdated(uint256 oldFee, uint256 newFee);
    event MaxStalenessUpdated(uint256 oldMaxStaleness, uint256 newMaxStaleness);
    event ProtocolConfigInitialized(
        address oracle, 
        address swapRouter, 
        address quoter, 
        uint256 liquidationThreshold, 
        uint256 minCollateralRatio, 
        uint256 debtCeiling, 
        uint256 minDebt, 
        uint256 closeFactorBps, 
        uint256 liquidationBonusBps, 
        uint256 uniswapFee
    );

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error ProtocolConfig__InvalidAddress();
    error ProtocolConfig__InvalidPercentage();
    error ProtocolConfig__InvalidRatio();
    error ProtocolConfig__InvalidAmount();

    /*//////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the ProtocolConfig contract
     * @param _oracleAddress The oracle address for price feeds
     * @param _swapRouterAddress The Uniswap V3 swap router address
     * @param _quoterAddress The Uniswap V3 quoter address
     * @param _collateralTokenAddress The collateral token address
     */
    function initialize(
        address _oracleAddress,
        address _swapRouterAddress,
        address _quoterAddress,
        address _collateralTokenAddress
    ) external;

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the treasury wallet address
     * @param _treasuryWallet New treasury wallet address
     */
    function setTreasuryWallet(address _treasuryWallet) external;

    /**
     * @notice Updates the oracle address
     * @param _oracleAddress New oracle address
     */
    function setOracle(address _oracleAddress) external;

    /**
     * @notice Updates the swap router address
     * @param _swapRouter New swap router address
     */ 
    function setSwapRouter(address _swapRouter) external;

    /**
     * @notice Updates the Uniswap V3 quoter address
     * @param _quoter New quoter address
     */
    function setQuoter(address _quoter) external;

    /**
     * @notice Updates the collateral token address (wstETH)
     * @param _collateralToken New collateral token address
     */
    function setCollateralToken(address _collateralToken) external;

    /**
     * @notice Updates the liquidation threshold (basis points, e.g., 8000 = 80%)
     * @param _liquidationThreshold New liquidation threshold in basis points
     * @dev 🔐 SECURITY CONSTRAINT: Must maintain mandatory 30% buffer below minCollateralRatio
     *      - Prevents immediate liquidation after position creation
     *      - Example: if minCollateralRatio = 15000 (150%), liquidationThreshold ≤ 12000 (120%)
     *      - Violation causes ProtocolConfig__InvalidRatio() revert
     *      - Range: 1 to 50000 bps (0.01% to 500%) but limited by buffer requirement
     */
    function setLiquidationThreshold(uint256 _liquidationThreshold) external;

    /**
     * @notice Updates the minimum collateral ratio (basis points, e.g., 12000 = 120%)
     * @param _minCollateralRatio New minimum collateral ratio in basis points
     * @dev 🔐 SECURITY CONSTRAINT: Must maintain mandatory 30% buffer above liquidationThreshold
     *      - Ensures borrowers have safety margin before liquidation risk
     *      - Example: if liquidationThreshold = 12000 (120%), minCollateralRatio ≥ 15000 (150%)
     *      - Violation causes ProtocolConfig__InvalidRatio() revert
     *      - Minimum: 10000 bps (100% - fully collateralized)
     */
    function setMinCollateralRatio(uint256 _minCollateralRatio) external;

    /**
     * @notice Updates the debt ceiling (in PUSD wei)
     * @param _debtCeiling New debt ceiling amount
     */
    function setDebtCeiling(uint256 _debtCeiling) external;

    /**
     * @notice Updates the minimum allowed outstanding debt for positions (in PUSD wei)
     * @param _minDebt New minimum debt amount
     */
    function setMinDebt(uint256 _minDebt) external;

    /**
     * @notice Updates the close factor in basis points
     * @param _closeFactorBps New close factor in basis points (e.g., 5000 = 50%)
     * @dev 🔐 SECURITY CONSTRAINT: Must be between 5%-100% (500-10000 bps)
     *      - CANNOT BE ZERO: Prevents forced full liquidations that could harm users
     *      - Minimum 5%: Ensures partial liquidations are always viable for large positions
     *      - Maximum 100%: Allows full liquidation when economically necessary
     *      - Violation causes ProtocolConfig__InvalidPercentage() revert
     *      - Controls liquidation granularity and capital requirements
     */
    function setCloseFactorBps(uint256 _closeFactorBps) external;

    /**
     * @notice Updates the liquidation bonus in basis points
     * @param _liquidationBonusBps New bonus in basis points (e.g., 1000 = 10%)
     * @dev 🔐 SECURITY CONSTRAINT: Must be between 1%-30% (100-3000 bps)
     *      - Minimum 1%: Ensures liquidator incentive exists to maintain protocol health
     *      - Maximum 30%: Prevents excessive penalties that could harm borrowers
     *      - Balances liquidator rewards with borrower protection
     *      - Violation causes ProtocolConfig__InvalidPercentage() revert
     *      - Too low = no liquidation incentive, too high = unfair to borrowers
     */
    function setLiquidationBonusBps(uint256 _liquidationBonusBps) external;

    /**
     * @notice Updates the Uniswap V3 fee tier
     * @param _fee New Uniswap V3 fee tier (in basis points)
     */
    function setUniswapFee(uint256 _fee) external;

    /**
     * @notice Updates the maximum staleness allowed for oracle prices
     * @param _maxStaleness New maximum staleness in seconds
     */
    function setMaxStaleness(uint256 _maxStaleness) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Returns the oracle address for price feeds
     */
    function oracle() external view returns (IPriceOracle);

    /**
     * @notice Returns the uniswap v3swap router address
     */
    function swapRouter() external view returns (ISwapRouter);

    /**
     * @notice Returns the uniswap v3 quoter address
     */
    function quoter() external view returns (IQuoterV2);

    /**
     * @notice Returns the collateral token address
     */
    function collateralToken() external view returns (address);

    /**
     * @notice Returns the treasury wallet address
     */
    function treasuryWallet() external view returns (address);

    /**
     * @notice Returns the liquidation threshold (12_000 = 120%)
     * @dev Always maintains 30% buffer below minCollateralRatio for security
     */
    function liquidationThreshold() external view returns (uint256);

    /**
     * @notice Returns the minimum collateral ratio (15_000 = 150%)
     * @dev Always maintains 30% buffer above liquidationThreshold for security
     */
    function minCollateralRatio() external view returns (uint256);

    /**
     * @notice Maximum debt ceiling for the protocol
     */
    function debtCeiling() external view returns (uint256);

    /**
     * @notice Minimum allowed outstanding debt (in PUSD wei) when a position is not fully repaid
     */
    function minDebt() external view returns (uint256);

    /**
     * @notice Close factor in basis points for partial liquidations (5_000 = 50%)
     * @dev Range: 5%-100% (500-10000 bps) - never zero for security
     */
    function closeFactorBps() external view returns (uint256);

    /**
     * @notice Liquidation bonus applied to seized collateral in basis points (1_000 = +10%)
     * @dev Range: 1%-30% (100-3000 bps) - balanced incentive structure
     */
    function liquidationBonusBps() external view returns (uint256);

    /**
     * @notice Uniswap V3 fee tier (3_000 = 0.3%)
     */
    function uniswapFee() external view returns (uint256);

    /**
     * @notice Maximum staleness allowed for oracle prices (in seconds)
     */
    function maxStaleness() external view returns (uint256);

    /**
     * @notice Maximum basis points (10_000)
     */
    function MAX_BPS() external view returns (uint256);

    /**
     * @notice Maximum liquidation threshold (50_000 bps = 500%)
     */
    function MAX_LIQUIDATION_THRESHOLD() external view returns (uint256);

    /**
     * @notice Mandatory buffer between liquidation threshold and min collateral ratio (3_000 bps = 30%)
     * @dev This ensures borrowers have sufficient safety margin before liquidation risk
     */
    function MANDATORY_BUFFER_BPS() external view returns (uint256);

    /**
     * @notice Minimum close factor for partial liquidations (500 bps = 5%)
     * @dev Prevents forced full liquidations that could harm users
     */
    function MIN_CLOSE_FACTOR_BPS() external view returns (uint256);

    /**
     * @notice Minimum liquidation bonus to incentivize liquidators (100 bps = 1%)
     * @dev Ensures liquidator incentive exists to maintain protocol health
     */
    function MIN_LIQUIDATION_BONUS_BPS() external view returns (uint256);

    /**
     * @notice Maximum liquidation bonus to protect borrowers (3_000 bps = 30%)
     * @dev Prevents excessive penalties that could harm borrowers
     */
    function MAX_LIQUIDATION_BONUS_BPS() external view returns (uint256);

    function ADMIN_ROLE() external view returns (bytes32);

    function UPGRADER_ROLE() external view returns (bytes32);
}
