// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPUSD} from "./IPUSD.sol";
import {IProtocolConfig} from "./IProtocolConfig.sol";
import {ILiquidationEngine} from "./ILiquidationEngine.sol";
import {IStabilityFund} from "./IStabilityFund.sol";
import {ITreasury} from "./ITreasury.sol";

/**
 * @title ILendingVault
 * @notice Interface for the LendingVault contract
 * @dev Defines all external functions, events, and custom errors for the lending protocol
 */
interface ILendingVault {

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    struct Position {
        uint256 collateralAmount;
        uint256 debtAmount;          // Includes consolidated interest (for normalized debt system)
        uint256 lastInterestUpdate;
        uint256 purePrincipal;       // Actual borrowed amount excluding consolidated interest
        bool exists;
    }

    struct LiquidationResult {
        uint256 debtRepaid;
        uint256 collateralSeized;
        uint256 remainingDebt;
        bool fullLiquidation;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event Deposited(address indexed user, uint256 amount, uint256 newCollateralRatio);
    event Borrowed(address indexed user, uint256 amount, uint256 newCollateralRatio);
    event Repaid(address indexed user, uint256 amount, uint256 newCollateralRatio);
    event InterestFeesCollected(address indexed user, uint256 interestAmount, uint256 totalFeesAccumulated);
    event Withdrawn(address indexed user, uint256 amount, uint256 newCollateralRatio);
    event Liquidated(address indexed user, address indexed liquidator, uint256 collateralAmount, uint256 debtAmount);
    event LiquidationSkippedTreasuryExemption(address indexed user, address indexed treasury);
    event PositionTransferredToTreasury(
        address indexed user, 
        address indexed treasuryWallet, 
        uint256 debtTransferred, 
        uint256 collateralTransferred
    );
    event InterestAccrued(uint256 totalInterest, uint256 newGlobalIndex, uint256 timeElapsed, uint256 aprBasisPoints);
    event ProtocolConfigUpdated(address indexed oldConfig, address indexed newConfig);
    event LiquidationEngineUpdated(address indexed oldEngine, address indexed newEngine);
    event StabilityFundUpdated(address indexed oldFund, address indexed newFund);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event CollateralTokenUpdated(address indexed oldToken, address indexed newToken);
    event InterestRateUpdated(uint256 oldRate, uint256 newRate);
    event MinDepositAmountUpdated(uint256 oldMinDepositAmount, uint256 newMinDepositAmount);
    event LiquidationBotUpdated(address indexed bot, bool authorized);
    event LendingVaultInitialized(
        address pusd, 
        address protocolConfig, 
        address collateralToken, 
        uint256 aprBasisPoints, 
        uint256 lastInterestUpdate, 
        uint256 globalInterestIndex, 
        uint256 minDepositAmount
    );

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    error LendingVault__InvalidAddress(address addr);
    error LendingVault__InvalidAPR(uint256 aprBasisPoints);
    error LendingVault__InvalidAmount(uint256 amount);
    error LendingVault__InsufficientCollateral(uint256 required, uint256 provided);
    error LendingVault__InsufficientBalance(uint256 requested, uint256 available);
    error LendingVault__PositionNotFound(address user);
    error LendingVault__PositionHealthy(uint256 healthRatio, uint256 threshold);
    error LendingVault__ExceedsDebtCeiling(uint256 requested, uint256 current, uint256 ceiling);
    error LendingVault__BelowMinCollateralRatio(uint256 current, uint256 minimum);
    error LendingVault__BelowMinimumDebt(uint256 remaining, uint256 minimum);
    error LendingVault__InvalidOraclePrice();
    error LendingVault__StaleOraclePrice();
    error LendingVault__InsufficientRemainingDebtToTransfer(uint256 currentDebt, uint256 debtToTransfer);
    error LendingVault__InsufficientRemainingCollateralToTransfer(uint256 currentCollateral, uint256 collateralToTransfer);


    /*//////////////////////////////////////////////////////////////
                                INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the LendingVault contract
     * @param _pusd PUSD token contract address
     * @param _protocolConfig Protocol configuration contract address
     * @param _collateralToken Collateral token address
     */
    function initialize(
        address _pusd,
        address _protocolConfig,
        address _collateralToken
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
     * @notice Sets the stability fund contract
     * @param _stabilityFund New stability fund address
     */
    function setStabilityFund(address _stabilityFund) external;

    /**
     * @notice Sets the liquidation engine contract
     * @param _liquidationEngine New liquidation engine address
     */
    function setLiquidationEngine(address _liquidationEngine) external;

    /**
     * @notice Sets the treasury contract
     * @param _treasury New treasury address  
     */
    function setTreasury(address _treasury) external;

    /**
     * @notice Sets the collateral token
     * @param _collateralToken New collateral token address
     */
    function setCollateralToken(address _collateralToken) external;

    /**
     * @notice Updates the APR in basis points
     * @param _aprBasisPoints New APR in basis points (e.g., 500 = 5%)
     */
    function setAPR(uint256 _aprBasisPoints) external;

    /**
     * @notice Sets or unsets an authorized liquidation bot address
     * @param bot Bot address to authorize/deauthorize
     * @param authorized True to authorize, false to revoke
     */
    function setLiquidationBot(address bot, bool authorized) external;

    /**
     * @notice Sets the minimum deposit amount for wstETH collateral
     * @param _minDepositAmount New minimum deposit amount
     */
    function setMinDepositAmount(uint256 _minDepositAmount) external;

    /*//////////////////////////////////////////////////////////////
                                CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits collateral into the vault with custom minimum collateral ratio
     * @param amount Amount of collateral to deposit
     * @param minCollateralRatio Minimum collateral ratio after deposit
     */
    function deposit(uint256 amount, uint256 minCollateralRatio) external;

    /**
     * @notice Deposits collateral into the vault using protocol's minimum collateral ratio
     * @param amount Amount of collateral to deposit
     */
    function deposit(uint256 amount) external;

    /**
     * @notice Borrows PUSD against collateral
     * @param amount Amount of PUSD to borrow
     */
    function borrow(uint256 amount) external;

    /**
     * @notice Repays PUSD debt
     * @param amount Amount of PUSD to repay
     */
    function repay(uint256 amount) external;

    /**
     * @notice Withdraws collateral from the vault
     * @param amount Amount of collateral to withdraw
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice Initiates and orchestrates the liquidation of a user's position using dual funding mechanism
     * @param user The address of the user to liquidate
     * @return result The result of the liquidation operation
     * @dev Liquidates 50% of the user's debt using a combination of StabilityFund and Treasury funds
     */
    function liquidatePosition(address user) external returns (LiquidationResult memory result);

    /*//////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice PUSD stablecoin contract
     */
    function pusd() external view returns (IPUSD);
    
    /**
     * @notice Protocol configuration contract
     */
    function protocolConfig() external view returns (IProtocolConfig);
    
    /**
     * @notice Liquidation engine contract
     */
    function liquidationEngine() external view returns (ILiquidationEngine);
    
    /**
     * @notice Stability fund contract
     */
    function stabilityFund() external view returns (IStabilityFund);
    
    /**
     * @notice Treasury contract
     */
    function treasury() external view returns (ITreasury);
    
    /**
     * @notice Collateral token
     */
    function collateralToken() external view returns (IERC20);
    
    /**
     * @notice Total collateral deposited in the vault
     */
    function totalCollateral() external view returns (uint256);
    
    /**
     * @notice Sum of all pure principals across positions (no interest)
     */
    function totalPurePrincipal() external view returns (uint256);
    
    /**
     * @notice Interest rate in basis points per year (e.g., 50 = 0.5% APR)
     */
    function aprBasisPoints() external view returns (uint256);
    
    /**
     * @notice Last global interest index checkpoint timestamp
     */
    function lastInterestUpdate() external view returns (uint256);
    
    /**
     * @notice Global interest index (PRECISION scale)
     */
    function globalInterestIndex() external view returns (uint256);

    /**
     * @notice Minimum deposit amount of collateral token
     */
    function minDepositAmount() external view returns (uint256);
    
    /**
     * @notice Total interest fees collected from repayments
     */
    function totalInterestFees() external view returns (uint256);
    
    /**
     * @notice Gets user position information
     * @param user Address of the user
     * @return collateralAmount Amount of collateral in the position
     * @return debtAmount Amount of debt in the position (includes consolidated interest)
     * @return lastInterestUpdate Last interest update timestamp (used as user debt index)
     * @return purePrincipal Actual borrowed amount excluding consolidated interest
     * @return exists Whether the position exists
     */
    function positions(address user) external view returns (uint256 collateralAmount, uint256 debtAmount, uint256 lastInterestUpdate, uint256 purePrincipal, bool exists);
    
    /**
     * @notice Checks if an address is an authorized liquidation bot
     * @param bot Address to check
     * @return authorized True if the address is an authorized liquidation bot
     */
    function isLiquidationBot(address bot) external view returns (bool authorized);

    /**
     * @notice Calculates current debt with accrued interest for a position
     * @param user Address of the user
     * @return Current debt amount including accrued interest
     */
    function getCurrentDebt(address user) external view returns (uint256);

    /**
     * @notice Gets the health ratio of a position
     * @param user Address of the user
     * @return Health ratio (18 decimals), 0 if no collateral
     */
    function getPositionHealthRatio(address user) external view returns (uint256);

    /**
     * @notice Checks if a user's position is liquidatable
     * @param user Address of the user to check
     * @return True if position can be liquidated
     */
    function isLiquidatable(address user) external view returns (bool);

    /**
     * @notice Returns the interest rate per second in PRECISION scale (1e12)
     * @dev Linear model: ratePerSecond = aprBps * PRECISION / (10000 * SECONDS_PER_YEAR)
     * @return Interest rate per second for linear interest calculations
     */
    function getRatePerSecond() external view returns (uint256);

    /**
     * @notice Returns the current total protocol debt using the up-to-date global index
     * @dev Computed as: totalDebt = totalPrincipal * currentIndex / PRECISION
     * @return Current total debt including accrued interest
     */
    function totalDebt() external view returns (uint256);

    /**
     * @notice Calculates the maximum amount a user can borrow based on their collateral
     * @param user Address of the user
     * @return maxBorrow Maximum borrow amount in PUSD
     */
    function getMaxBorrow(address user) external view returns (uint256);

    /**
     * @notice Gets position details for a user
     * @param user Address of the user
     * @return collateral Collateral amount
     * @return debt Current debt amount (including accrued interest)
     * @return healthRatio Current health ratio
     * @return exists Whether position exists
     */
    function getPosition(address user) external view returns (
        uint256 collateral,
        uint256 debt,
        uint256 healthRatio,
        bool exists
    );

    /**
     * @notice Calculates the amount of collateral tokens equivalent to a given USD value
     * @param value USD value in wei (18 decimals)
     * @return Amount of collateral equivalent to the value
     */
    function getCollateralAmountForValue(uint256 value) external view returns (uint256);

    /**
     * @notice Returns the current annual percentage rate in basis points (APR)
     * @return APR in basis points (e.g., 500 = 5%)
     */
    function getAPRbps() external view returns (uint256);
}
