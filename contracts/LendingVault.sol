// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ILendingVault} from "./interfaces/ILendingVault.sol";
import {IPUSD} from "./interfaces/IPUSD.sol";
import {IProtocolConfig} from "./interfaces/IProtocolConfig.sol";
import {ILiquidationEngine} from "./interfaces/ILiquidationEngine.sol";
import {IStabilityFund} from "./interfaces/IStabilityFund.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";
import {DataTypes} from "./DataTypes.sol";

/**
 * @title LendingVault
 * @notice Core contract of the lending protocol
 * @dev Handles deposits, borrowing, repayments, withdrawals and liquidations
 */
contract LendingVault is 
    ILendingVault,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    // Linear interest math uses a fixed-point precision with 12 decimals.
    // All interest multipliers and indices are maintained in this scale.
    uint256 private constant PRECISION = 1e12;
    uint256 private constant SECONDS_PER_YEAR = 365 * 24 * 3600;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/    

    IPUSD public pusd;
    IProtocolConfig public protocolConfig;
    ILiquidationEngine public liquidationEngine;
    IStabilityFund public stabilityFund;
    ITreasury public treasury;
    
    IERC20 public collateralToken;

    uint256 public totalCollateral;
    uint256 public totalPurePrincipal; // Sum of pure principal amounts (no interest)
    uint256 public aprBasisPoints;
    uint256 public lastInterestUpdate;
    uint256 public globalInterestIndex;
    uint256 public minDepositAmount;
    uint256 public totalInterestFees;

    uint256 private totalConsolidatedDebt; // Internal: normalized consolidated debt for calculations

    mapping(address _user => Position _position) public positions;
    mapping(address _bot => bool _isLiquidatonBot) public isLiquidationBot;

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/   

    modifier onlyLiquidationBot() {
        if (!isLiquidationBot[msg.sender]) revert LendingVault__InvalidAddress(msg.sender);
        _;
    }

    modifier validateAmount(uint256 _amount) {
        if (_amount == 0) revert LendingVault__InvalidAmount(_amount);
        _;
    }

    modifier validateMinDepositAmount(uint256 _amount) {
        if (_amount < minDepositAmount) revert LendingVault__InvalidAmount(_amount);
        _;
    }

    modifier checkZeroAddress(address _address) {
        if (_address == address(0)) revert LendingVault__InvalidAddress(_address);
        _;
    }

    modifier requireValidPosition() {
        if (!positions[msg.sender].exists) revert LendingVault__PositionNotFound(msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZER
    //////////////////////////////////////////////////////////////*/

    function initialize(
        address _pusd,
        address _protocolConfig,
        address _collateralToken
    ) public override initializer {
        if (_pusd == address(0)) revert LendingVault__InvalidAddress(_pusd);
        if (_protocolConfig == address(0)) revert LendingVault__InvalidAddress(_protocolConfig);
        if (_collateralToken == address(0)) revert LendingVault__InvalidAddress(_collateralToken);

        __AccessControlEnumerable_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        pusd = IPUSD(_pusd);
        protocolConfig = IProtocolConfig(_protocolConfig);
        collateralToken = IERC20(_collateralToken);
        
        // Initialize interest tracking
        aprBasisPoints = 50; // 0.5% APR in basis points
        lastInterestUpdate = block.timestamp;
        // Index uses PRECISION scale
        globalInterestIndex = PRECISION;

        minDepositAmount = 0.01 ether;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(protocolConfig.ADMIN_ROLE(), msg.sender);
        _grantRole(protocolConfig.UPGRADER_ROLE(), msg.sender);

        emit LendingVaultInitialized(_pusd, _protocolConfig, _collateralToken, aprBasisPoints, lastInterestUpdate, globalInterestIndex, minDepositAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function pause() external override onlyRole(protocolConfig.ADMIN_ROLE()) {
        _pause();
    }

    function unpause() external override onlyRole(protocolConfig.ADMIN_ROLE()) {
        _unpause();
    }

    function setProtocolConfig(address _protocolConfig) external override onlyRole(protocolConfig.ADMIN_ROLE()) checkZeroAddress(_protocolConfig) {
        
        address oldConfig = address(protocolConfig);
        protocolConfig = IProtocolConfig(_protocolConfig);
        
        emit ProtocolConfigUpdated(oldConfig, _protocolConfig);
    }

    function setStabilityFund(address _stabilityFund) external override onlyRole(protocolConfig.ADMIN_ROLE()) checkZeroAddress(_stabilityFund) {
        
        address oldFund = address(stabilityFund);
        stabilityFund = IStabilityFund(_stabilityFund);
        
        emit StabilityFundUpdated(oldFund, _stabilityFund);
    }

    function setLiquidationEngine(address _liquidationEngine) external override onlyRole(protocolConfig.ADMIN_ROLE()) checkZeroAddress(_liquidationEngine) {
        
        address oldEngine = address(liquidationEngine);
        liquidationEngine = ILiquidationEngine(_liquidationEngine);
        
        emit LiquidationEngineUpdated(oldEngine, _liquidationEngine);
    }

    function setTreasury(address _treasury) external onlyRole(protocolConfig.ADMIN_ROLE()) checkZeroAddress(_treasury) {
        
        address oldTreasury = address(treasury);
        treasury = ITreasury(_treasury);
        
        emit TreasuryUpdated(oldTreasury, _treasury);
    }

    function setCollateralToken(address _collateralToken) external override onlyRole(protocolConfig.ADMIN_ROLE()) checkZeroAddress(_collateralToken) {
        
        address oldToken = address(collateralToken);
        collateralToken = IERC20(_collateralToken);
        
        emit CollateralTokenUpdated(oldToken, _collateralToken);
    }

    function setAPR(uint256 _aprBasisPoints) external override onlyRole(protocolConfig.ADMIN_ROLE()) {
        if (_aprBasisPoints > 10_000) revert LendingVault__InvalidAPR(_aprBasisPoints); // Max 100%
        
        _updateInterest();
        uint256 oldRate = aprBasisPoints;
        aprBasisPoints = _aprBasisPoints;
        
        emit InterestRateUpdated(oldRate, _aprBasisPoints);
    }

    function setLiquidationBot(address _bot, bool _authorized) external override onlyRole(protocolConfig.ADMIN_ROLE()) checkZeroAddress(_bot) {
        isLiquidationBot[_bot] = _authorized;

        emit LiquidationBotUpdated(_bot, _authorized);
    }

    function setMinDepositAmount(uint256 _minDepositAmount) external override onlyRole(protocolConfig.ADMIN_ROLE()) validateAmount(_minDepositAmount) {
        uint256 oldMinDepositAmount = minDepositAmount;
        minDepositAmount = _minDepositAmount;

        emit MinDepositAmountUpdated(oldMinDepositAmount, _minDepositAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function deposit(uint256 _amount, uint256 _minCollateralRatio) external override nonReentrant whenNotPaused validateAmount(_amount) validateMinDepositAmount(_amount) {
        _deposit(_amount, _minCollateralRatio);
    }

    function deposit(uint256 _amount) external override nonReentrant whenNotPaused validateAmount(_amount) validateMinDepositAmount(_amount) {
        uint256 protocolMinRatio = protocolConfig.minCollateralRatio();
        _deposit(_amount, protocolMinRatio);
    }

    function borrow(uint256 _amount) external override nonReentrant whenNotPaused validateAmount(_amount) requireValidPosition {
        Position storage position = positions[msg.sender];
        
        // Update interest and get current index for this transaction
        uint256 currentIndex = _updateInterestAndGetIndex();

        // Calculate current debt including accrued interest
        uint256 currentDebt = _currentDebtOf(position, currentIndex);
        
        // Track pure principal separately (actual borrowed amount)
        position.purePrincipal += _amount;
        
        // Consolidate accrued interest into debt amount
        // This is necessary for the normalized debt system to work correctly
        uint256 newPrincipal = currentDebt + _amount;
        
        // Enforce minimum outstanding debt at open/borrow to avoid dust debts
        uint256 minDebt = protocolConfig.minDebt();
        if (newPrincipal > 0 && newPrincipal < minDebt) {
            revert LendingVault__BelowMinimumDebt(newPrincipal, minDebt);
        }
        
        // Check debt ceiling using dynamic total debt view
        uint256 currentTotalDebt = totalDebt();
        if (currentTotalDebt + _amount > protocolConfig.debtCeiling()) {
            revert LendingVault__ExceedsDebtCeiling(_amount, currentTotalDebt, protocolConfig.debtCeiling());
        }

        // Update user position
        position.debtAmount = newPrincipal;
        position.lastInterestUpdate = currentIndex; // repurposed as userDebtIndex
        totalPurePrincipal += _amount;

        // Add exactly that _amount to normalized debt
        totalConsolidatedDebt += (_amount * PRECISION) / currentIndex;
        
        // Check collateral ratio
        uint256 healthRatio = getPositionHealthRatio(msg.sender);
        uint256 minRatio = protocolConfig.minCollateralRatio();
        if (healthRatio < minRatio) revert LendingVault__InsufficientCollateral(minRatio, healthRatio);
        
        // Mint PUSD to user
        pusd.mint(msg.sender, _amount);
        
        emit Borrowed(msg.sender, _amount, healthRatio);
    }

    function repay(uint256 _amount) external override nonReentrant whenNotPaused validateAmount(_amount) requireValidPosition {
        Position storage position = positions[msg.sender];
        
        // Update interest and get current index for this transaction
        uint256 currentIndex = _updateInterestAndGetIndex();
        uint256 debtNow = _currentDebtOf(position, currentIndex);
        
        // Calculate and validate actual repayment amount
        uint256 actualAmount = _calculateActualRepaymentAmount(_amount, debtNow);
        
        // Transfer PUSD from user
        IERC20(address(pusd)).safeTransferFrom(msg.sender, address(this), actualAmount);
        
        // Process payment split between principal and interest
        (uint256 principalPaid, ) = _processRepaymentSplit(position, debtNow, actualAmount);
        
        // Update position and global accounting
        _updatePositionAfterRepayment(position, debtNow, actualAmount, currentIndex);
        
        // Update totalPurePrincipal by only the principal amount paid (pure principal, no interest)
        totalPurePrincipal -= principalPaid;
        
        uint256 newRatio = getPositionHealthRatio(msg.sender);
        
        emit Repaid(msg.sender, actualAmount, newRatio);
    }

    function withdraw(uint256 _amount) external override nonReentrant whenNotPaused validateAmount(_amount) requireValidPosition {
        Position storage position = positions[msg.sender];
        if (position.collateralAmount < _amount) revert LendingVault__InsufficientBalance(_amount, position.collateralAmount);
        
        // Update interest and get current index for this transaction
        uint256 currentIndex = _updateInterestAndGetIndex();
        
        // Temporarily reduce collateral to check ratio
        position.collateralAmount -= _amount;
        totalCollateral -= _amount;
        
        uint256 healthRatio = getPositionHealthRatio(msg.sender);
        // Check collateral ratio if there's debt
        uint256 debtNow = _currentDebtOf(position, currentIndex);
        if (debtNow > 0) {
            uint256 minRatio = protocolConfig.minCollateralRatio();
            if (healthRatio < minRatio) revert LendingVault__InsufficientCollateral(minRatio, healthRatio);
        }
        
        // Transfer collateral to user
        collateralToken.safeTransfer(msg.sender, _amount);
        
        emit Withdrawn(msg.sender, _amount, healthRatio);
    }

    function liquidatePosition(address _user) 
        external 
        override 
        nonReentrant 
        whenNotPaused 
        onlyLiquidationBot 
        checkZeroAddress(_user)
        returns (LiquidationResult memory result) 
    {
        // Ensure interest is up to date before computing liquidation amounts
        _updateInterest();

        // 1. VALIDATION
        if (!isLiquidatable(_user)) {
            // Check if it's treasury exemption and emit event
            if (_user == protocolConfig.treasuryWallet()) {
                emit LiquidationSkippedTreasuryExemption(_user, protocolConfig.treasuryWallet());
            }
            // Return empty result instead of reverting
            return LiquidationResult(0, 0, getCurrentDebt(_user), false);
        }
        
        // 2. DEBT CALCULATION 
        uint256 currentIndex = globalInterestIndex;
        Position storage userPosition = positions[_user];
        uint256 currentDebt = _currentDebtOf(userPosition, currentIndex);
        uint256 debtToLiquidate = _computeDebtToRepay(currentDebt);
        
        // 3. CREATE LIQUIDATION ORDER
        DataTypes.LiquidationOrder memory order;
        order.debtor = _user;
        
        // 4. FUNDING LOGIC
        uint256 sfBalance = pusd.balanceOf(address(stabilityFund));
        if (sfBalance >= debtToLiquidate) {
            // --- CASE 1: StabilityFund covers 100% ---
            uint256 sfReceived = IStabilityFund(stabilityFund).sendLiquidationFunds(debtToLiquidate);
            order.debtPaidBySF = sfReceived;
            order.debtPaidByTreasury = 0;
        } else if (sfBalance + pusd.balanceOf(address(treasury)) < debtToLiquidate) {
            // --- CASE 1B: HYBRID APPROACH ---
            return _executeHybridLiquidation(_user, debtToLiquidate, sfBalance, order);
        } else {
            // --- CASE 2: Split payment ---
            uint256 treasuryContribution = debtToLiquidate - sfBalance;
            uint256 sfReceived = 0;
            if (sfBalance > 0) {
                sfReceived = IStabilityFund(stabilityFund).sendLiquidationFunds(sfBalance);
            }
            ITreasury(treasury).provideBackstopFunds(treasuryContribution);
            order.debtPaidBySF = sfReceived;
            order.debtPaidByTreasury = treasuryContribution;
        }
        
        // 5. SETTLE DEBT: Split between principal and interest, then burn/transfer accordingly
        (uint256 principalPortion, uint256 interestPortion) = _splitDebtPayment(
            userPosition.purePrincipal,
            currentDebt,
            debtToLiquidate
        );
        
        // Burn only the principal portion
        if (principalPortion > 0) {
            pusd.burn(principalPortion);
        }
        
        // Send interest fees to Treasury
        if (interestPortion > 0) {
            totalInterestFees += interestPortion;
            IERC20(address(pusd)).approve(address(treasury), interestPortion);
            ITreasury(treasury).receivePUSD(interestPortion);
            emit InterestFeesCollected(_user, interestPortion, totalInterestFees);
        }
        
        // Update position accounting
        _updatePositionAfterMainLiquidation(userPosition, currentDebt, debtToLiquidate, currentIndex);

        // Update user position snapshot
        userPosition.lastInterestUpdate = currentIndex;
        
        // 6. SEIZE AND APPROVE COLLATERAL
        uint256 collateralToSeize = _computeCollateralToSeize(debtToLiquidate);
        
        // Cap collateral seized to available collateral to prevent underflow
        uint256 availableCollateral = positions[_user].collateralAmount;
        if (collateralToSeize > availableCollateral) {
            collateralToSeize = availableCollateral;
        }
        
        order.collateralToSell = collateralToSeize;
        
        // Update user's position (seize collateral)
        positions[_user].collateralAmount -= collateralToSeize;
        totalCollateral -= collateralToSeize;
        
        // Approve collateral for LiquidationEngine to transfer
        collateralToken.approve(address(liquidationEngine), collateralToSeize);
        
        // 7. EXECUTE LIQUIDATION
        ILiquidationEngine(liquidationEngine).executeLiquidation(order);
        
        // 8. CALCULATE AND RETURN LIQUIDATION RESULT
        result.debtRepaid = debtToLiquidate;
        result.collateralSeized = collateralToSeize;
        result.remainingDebt = positions[_user].debtAmount;
        result.fullLiquidation = (result.remainingDebt == 0);
        
        // 9. EMIT LIQUIDATION EVENT
        emit Liquidated(_user, msg.sender, collateralToSeize, debtToLiquidate);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getCurrentDebt(address _user) public view override returns (uint256) {
        Position memory position = positions[_user];
        if (!position.exists || position.debtAmount == 0) {
            return 0;
        }
        uint256 currentIndex = _getCurrentIndex();
        
        return _currentDebtOf(position, currentIndex);
    }

    function getPositionHealthRatio(address _user) public view override checkZeroAddress(_user) returns (uint256) {
        Position memory position = positions[_user];
        
        if (position.collateralAmount == 0) return 0;
        if (position.debtAmount == 0) return type(uint256).max;
        
        // Get current debt with accrued interest
        uint256 currentDebt = getCurrentDebt(_user);
        
        // Get collateral value in USD using oracle
        uint256 collateralValue = _collateralValueUSD(position.collateralAmount);
        
        // Calculate health ratio: (collateral value / debt amount) * 100
        return (collateralValue * 10_000) / currentDebt;
    }

    function isLiquidatable(address _user) public view checkZeroAddress(_user) returns (bool) {
        // Treasury wallet is never liquidatable
        if (_user == protocolConfig.treasuryWallet()) {
            return false;
        }
        
        Position memory position = positions[_user];
        
        // If position doesn't exist or has no collateral, it's not liquidatable
        if (!position.exists || position.collateralAmount == 0) {
            return false;
        }
        
        // If position has no debt, it's not liquidatable
        if (position.debtAmount == 0) {
            return false;
        }
        
        uint256 healthRatio = getPositionHealthRatio(_user);
        uint256 threshold = protocolConfig.liquidationThreshold();
        return healthRatio < threshold;
    }

    function getRatePerSecond() public view override returns (uint256) {
        return (aprBasisPoints * PRECISION) / (10_000 * SECONDS_PER_YEAR);
    }

    function totalDebt() public view override returns (uint256) {
        uint256 idx = _getCurrentIndex();
        if (totalConsolidatedDebt == 0) return 0;
        return (totalConsolidatedDebt * idx) / PRECISION;
    }

    function getMaxBorrow(address _user) external view override checkZeroAddress(_user) returns (uint256) {
        Position memory position = positions[_user];
        
        if (!position.exists || position.collateralAmount == 0) {
            return 0;
        }
        
        // Get current debt with accrued interest
        uint256 currentDebt = getCurrentDebt(_user);
        
        // Calculate collateral value using oracle (USD, 18 decimals)
        // This converts collateral amount to USD value using oracle price
        uint256 collateralValue = _collateralValueUSD(position.collateralAmount);
        
        // Get minimum collateral ratio from protocol config (in basis points)
        // Example: 12000 = 120% = 1.2 ratio
        uint256 minRatio = protocolConfig.minCollateralRatio();
        
        // Calculate maximum debt based on collateral value and minimum ratio
        // Formula: maxDebt = collateralValue / (minRatio / 10000)
        // Since minRatio is in basis points, we use: maxDebt = (collateralValue * 10000) / minRatio
        uint256 maxDebt = (collateralValue * 10000) / minRatio;
        
        // Calculate available borrow amount
        // If current debt is already at or above maximum, no more borrowing allowed
        if (currentDebt >= maxDebt) {
            return 0;
        }
        
        // Available borrow = maximum debt - current debt
        uint256 availableBorrow = maxDebt - currentDebt;
        
        // Check debt ceiling
        uint256 remainingCeiling = protocolConfig.debtCeiling() - totalDebt();
        if (availableBorrow > remainingCeiling) {
            availableBorrow = remainingCeiling;
        }
        
        return availableBorrow;
    }

    function getPosition(address _user) external view override checkZeroAddress(_user) returns (
        uint256 collateral,
        uint256 debt,
        uint256 healthRatio,
        bool exists
    ) {
        Position memory position = positions[_user];
        
        // Get current debt with accrued interest
        uint256 currentDebt = getCurrentDebt(_user);
        
        healthRatio = 0;
        if (position.collateralAmount > 0) {
            if (currentDebt == 0) {
                healthRatio = type(uint256).max;
            } else {
                uint256 collateralValue = _collateralValueUSD(position.collateralAmount);
                healthRatio = (collateralValue * 10_000) / currentDebt;
            }
        }
        return (
            position.collateralAmount,
            currentDebt,
            healthRatio,
            position.exists
        );
    }

    function getCollateralAmountForValue(uint256 _value) external view returns (uint256) {
        (uint256 price, uint8 oracleDecimals) = _getValidatedOraclePrice();

        // Calculate collateral amount needed for a given USD value
        // Formula: collateralAmount = value * 10^oracleDecimals / price
        // Note: Multiplication is done first to maintain precision, then division
        return (_value * (10 ** oracleDecimals)) / price;
    }

    function getAPRbps() external view override returns (uint256) {
        return aprBasisPoints;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal deposit function
     * @param _amount Amount of collateral to deposit
     * @param _minCollateralRatio Minimum collateral ratio after deposit
     */
    function _deposit(uint256 _amount, uint256 _minCollateralRatio) internal {
        // Update interest before modifying position
        _updateInterest();
        
        // Transfer collateral from user
        collateralToken.safeTransferFrom(msg.sender, address(this), _amount);
        
        // Update position
        Position storage position = positions[msg.sender];
        if (!position.exists) {
            position.exists = true;
            // userDebtIndex is only meaningful when principal > 0; leave as 0 for new positions without debt
            position.lastInterestUpdate = 0;
        }
        
        position.collateralAmount += _amount;
        totalCollateral += _amount;
        
        uint256 newRatio = getPositionHealthRatio(msg.sender);
        if (newRatio < _minCollateralRatio) revert LendingVault__BelowMinCollateralRatio(newRatio, _minCollateralRatio);
        
        emit Deposited(msg.sender, _amount, newRatio);
    }

    /**
     * @notice Updates global interest and returns the current index for immediate use
     * @dev Convenience function that combines _updateInterest() and index snapshotting
     * @return currentIndex The global interest index after update
     */
    function _updateInterestAndGetIndex() internal returns (uint256 currentIndex) {
        _updateInterest();
        return globalInterestIndex;
    }

    /**
     * @notice Updates global interest and accrues interest using linear calculation
     * @dev Advances the global index using linear interest accrual:
     *      newIndex = globalInterestIndex * (1 + ratePerSecond * timeElapsed)
     *      All values are in PRECISION scale; no compounding beyond linear model.
     *      We DO NOT mutate principal or per-user debt here.
     */
    function _updateInterest() internal {
        uint256 timeElapsed = block.timestamp - lastInterestUpdate;
        if (timeElapsed == 0) return;

        // Calculate linear interest using basis points
        uint256 ratePerSecond = getRatePerSecond();

        // Interest factor and index in PRECISION scale
        uint256 interestFactor = PRECISION + (ratePerSecond * timeElapsed);
        uint256 newIndex = (globalInterestIndex * interestFactor) / PRECISION;

        // Theoretical interest accrued (view purpose only) derived from consolidated debt and index delta
        uint256 interestAccrued = totalConsolidatedDebt == 0 ? 0 : ((newIndex - globalInterestIndex) * totalConsolidatedDebt) / PRECISION;
        globalInterestIndex = newIndex;
        lastInterestUpdate = block.timestamp;

        emit InterestAccrued(interestAccrued, newIndex, timeElapsed, aprBasisPoints);
    }

    /**
     * @notice Returns the up-to-date global index without mutating state
     * @dev Formula: currentIndex = globalInterestIndex * (1 + ratePerSecond * dt)
     */
    function _getCurrentIndex() internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - lastInterestUpdate;
        if (timeElapsed == 0) return globalInterestIndex;

        uint256 ratePerSecond = getRatePerSecond();
        
        uint256 interestFactor = PRECISION + (ratePerSecond * timeElapsed);

        return (globalInterestIndex * interestFactor) / PRECISION;
    }

    /**
     * @notice Converts a user's principal to current debt using indices
     * @dev Formula: currentDebt = principal * currentIndex / userDebtIndex
     *      - `position.debtAmount` stores user principal (snapshot)
     *      - `position.lastInterestUpdate` stores userDebtIndex (snapshot)
     * @param _position The user position struct (principal and index snapshot)
     * @param _currentIndex The current global index in PRECISION scale
     * @return The user's current debt including accrued interest
     */
    function _currentDebtOf(Position memory _position, uint256 _currentIndex) internal pure returns (uint256) {
        if (_position.debtAmount == 0) return 0;
        uint256 userIndex = _position.lastInterestUpdate;

        return (_position.debtAmount * _currentIndex) / userIndex;
    }

    /**
     * @notice Gets validated oracle price and decimals (reverts on invalid price)
     * @dev Fetches latest price from protocol oracle and validates it's positive and not stale
     * @return price The current price from oracle as uint256
     * @return decimals The number of decimals used by the oracle
     */
    function _getValidatedOraclePrice() internal view returns (uint256 price, uint8 decimals) {
        IPriceOracle oracle = protocolConfig.oracle();
        
        // Get latest price data from oracle
        (, int256 latestAnswer, , uint256 updatedAt,) = oracle.latestRoundData();
        if (latestAnswer <= 0) revert LendingVault__InvalidOraclePrice();
        
        // Check for staleness
        if (block.timestamp - updatedAt > protocolConfig.maxStaleness()) {
            revert LendingVault__StaleOraclePrice();
        }
        
        price = uint256(latestAnswer);
        decimals = oracle.decimals();
    }

    /**
     * @notice Returns collateral value in USD (18 decimals) using oracle from protocol config
     * @param _collateralAmount Amount of collateral token (assumed 18 decimals) to value in USD
     */
    function _collateralValueUSD(uint256 _collateralAmount) internal view returns (uint256) {
        // Use validated oracle price which includes staleness check
        (uint256 price, uint8 oracleDecimals) = _getValidatedOraclePrice();

        // Calculate collateral value in USD
        // Formula: collateralValue = (collateralAmount * price) / 10^oracleDecimals
        // Note: Multiplication first, then division to maintain precision
        return (_collateralAmount * price) / (10 ** oracleDecimals);
    }

    /**
     * @notice Executes hybrid liquidation approach when insufficient funds are available
     * @param _user Address of the user being liquidated
     * @param _debtToLiquidate Total debt amount to liquidate
     * @param _sfBalance StabilityFund balance available
     * @param _order Liquidation order struct (passed by reference)
     * @return result Liquidation result
     */
    function _executeHybridLiquidation(
        address _user,
        uint256 _debtToLiquidate,
        uint256 _sfBalance,
        DataTypes.LiquidationOrder memory _order
    ) internal returns (LiquidationResult memory result) {
        uint256 availableFunds = _sfBalance + pusd.balanceOf(address(treasury));
        address treasuryWallet = protocolConfig.treasuryWallet();
        
        // Pre-calculate total collateral
        uint256 totalCollateralToSeize = _computeCollateralToSeize(_debtToLiquidate);
        
        uint256 currentIndex;
        uint256 totalFundsReceived = 0;
        uint256 liquidationCollateral = 0;
        
        // PART 1: Execute partial liquidation with available funds (if any)
        if (availableFunds > 0) {
            (totalFundsReceived, liquidationCollateral, currentIndex) = _executePartialLiquidation(
                _user, availableFunds, _sfBalance, totalCollateralToSeize, _debtToLiquidate, _order
            );
            
            // Set liquidation result for the funded portion only
            result.debtRepaid = totalFundsReceived;
            result.collateralSeized = liquidationCollateral;
            // Note: remainingDebt will be calculated after treasury transfer
            
            emit Liquidated(_user, msg.sender, liquidationCollateral, totalFundsReceived);
        } else {
            // Edge case: No available funds - initialize empty result for pure position transfer
            _updateInterest();
            currentIndex = globalInterestIndex;
            
            result.debtRepaid = 0;
            result.collateralSeized = 0;
            // Note: remainingDebt will be calculated after treasury transfer
        }
        
        // PART 2: Transfer remaining debt to Treasury Wallet (internal accounting)
        uint256 remainingDebt = _debtToLiquidate - totalFundsReceived;
        if (remainingDebt > 0) {
            // Calculate collateral with liquidation bonus to protect treasury from bad debt
            uint256 remainingCollateral = _computeCollateralToSeize(remainingDebt);
            
            // Cap remaining collateral to available collateral to prevent underflow
            uint256 availableCollateral = positions[_user].collateralAmount;
            if (remainingCollateral > availableCollateral) {
                remainingCollateral = availableCollateral;
            }
            
            _transferPositionToTreasury(_user, treasuryWallet, remainingDebt, remainingCollateral, currentIndex);
        }
        
        // PART 3: Calculate final remaining debt and liquidation status after all operations
        result.remainingDebt = getCurrentDebt(_user);
        result.fullLiquidation = (result.remainingDebt == 0);
        
        return result;
    }

    /**
     * @notice Executes partial liquidation with available funds
     * @param _user Address of the user being liquidated
     * @param _availableFunds Total funds available for liquidation
     * @param _sfBalance StabilityFund balance
     * @param _totalCollateralToSeize Total collateral to seize
     * @param _debtToLiquidate Total debt to liquidate
     * @param _order Liquidation order struct
     * @return totalFundsReceived Total funds actually received
     * @return liquidationCollateral Collateral seized for liquidation
     * @return currentIndex Current interest index
     */
    function _executePartialLiquidation(
        address _user,
        uint256 _availableFunds,
        uint256 _sfBalance,
        uint256 _totalCollateralToSeize,
        uint256 _debtToLiquidate,
        DataTypes.LiquidationOrder memory _order
    ) internal returns (uint256 totalFundsReceived, uint256 liquidationCollateral, uint256 currentIndex) {
        // Get funds from SF and Treasury
        uint256 sfReceived = 0;
        if (_sfBalance > 0) {
            sfReceived = IStabilityFund(stabilityFund).sendLiquidationFunds(_sfBalance);
        }
        
        // Calculate treasury contribution and receive funds (scope to reduce stack depth)
        {
            uint256 treasuryContribution = _availableFunds - _sfBalance;
            if (treasuryContribution > 0) {
                uint256 treasuryActualBalance = pusd.balanceOf(address(treasury));
                if (treasuryActualBalance > 0) {
                    uint256 treasuryReceived = ITreasury(treasury).provideBackstopFunds(treasuryActualBalance);
                    totalFundsReceived = sfReceived + treasuryReceived;
                    _order.debtPaidByTreasury = treasuryReceived;
                }
            } else {
                totalFundsReceived = sfReceived;
                _order.debtPaidByTreasury = 0;
            }
        }
        
        // Use index from liquidatePosition (already updated)
        currentIndex = globalInterestIndex;
        liquidationCollateral = (_totalCollateralToSeize * totalFundsReceived) / _debtToLiquidate;
        
        // Cap collateral seized to available collateral to prevent underflow
        uint256 availableCollateral = positions[_user].collateralAmount;
        if (liquidationCollateral > availableCollateral) {
            liquidationCollateral = availableCollateral;
        }
        
        _order.debtPaidBySF = sfReceived;
        _order.collateralToSell = liquidationCollateral;
        
        // Process fee split and burn/transfer (scope to reduce stack depth)
        {
            Position storage userPosition = positions[_user];
            uint256 currentUserDebt = _currentDebtOf(userPosition, currentIndex);
            (uint256 principalPortion, uint256 interestPortion) = _splitDebtPayment(
                userPosition.purePrincipal,
                currentUserDebt,
                totalFundsReceived
            );
            
            // Burn only the principal portion
            if (principalPortion > 0) {
                pusd.burn(principalPortion);
            }
            
            // Send interest fees to Treasury
            if (interestPortion > 0) {
                totalInterestFees += interestPortion;
                IERC20(address(pusd)).approve(address(treasury), interestPortion);
                ITreasury(treasury).receivePUSD(interestPortion);
                emit InterestFeesCollected(_user, interestPortion, totalInterestFees);
            }
        }
        
        // Update user position and global accounting
        _updateUserPositionAfterLiquidation(_user, totalFundsReceived, liquidationCollateral, currentIndex);
        
        // Approve and execute liquidation for this portion
        collateralToken.approve(address(liquidationEngine), liquidationCollateral);
        ILiquidationEngine(liquidationEngine).executeLiquidation(_order);
    }

    /**
     * @notice Updates user position after liquidation with proper interest accounting
     * @param _user Address of the user being liquidated
     * @param _debtRepaid Amount of debt repaid in liquidation
     * @param _collateralSeized Amount of collateral seized in liquidation
     * @param _currentIndex Current global interest index
     */
    function _updateUserPositionAfterLiquidation(
        address _user,
        uint256 _debtRepaid,
        uint256 _collateralSeized,
        uint256 _currentIndex
    ) internal {
        Position storage userPosition = positions[_user];
        uint256 oldUserPrincipal = userPosition.debtAmount;
        uint256 oldUserIndex = userPosition.lastInterestUpdate;
        uint256 oldPurePrincipal = userPosition.purePrincipal;
        uint256 currentUserDebtBeforeLiquidation = _currentDebtOf(userPosition, _currentIndex);
        uint256 newUserDebt = currentUserDebtBeforeLiquidation - _debtRepaid;
        
        // Calculate how much of _debtRepaid was principal vs interest (similar to _processRepaymentSplit)
        uint256 interestAccrued = currentUserDebtBeforeLiquidation - oldPurePrincipal;
        
        uint256 principalPortion;
        if (_debtRepaid <= interestAccrued) {
            // Repayment only covered interest
            principalPortion = 0;
        } else {
            // Repayment covered interest + part of principal
            principalPortion = _debtRepaid - interestAccrued;
        }
        
        // Update user's pure principal
        userPosition.purePrincipal = oldPurePrincipal - principalPortion;
        
        // Apply updates to user position
        userPosition.debtAmount = newUserDebt; // with index = currentIndex, principal equals current debt
        userPosition.lastInterestUpdate = _currentIndex;
        userPosition.collateralAmount -= _collateralSeized;
        
        // Update global accounting
        totalCollateral -= _collateralSeized;
        
        // Update totalConsolidatedDebt for totalDebt() calculation
        _updateConsolidatedDebt(oldUserPrincipal, newUserDebt, oldUserIndex, _currentIndex);
        
        // Update totalPurePrincipal
        if (principalPortion > 0) {
            totalPurePrincipal -= principalPortion;
        }
    }

    /**
     * @notice Updates position after main liquidation flow (non-hybrid)
     * @param _position User position storage reference
     * @param _currentDebt Current debt including accrued interest
     * @param _debtToLiquidate Amount of debt being liquidated
     * @param _currentIndex Current global interest index
     */
    function _updatePositionAfterMainLiquidation(
        Position storage _position,
        uint256 _currentDebt,
        uint256 _debtToLiquidate,
        uint256 _currentIndex
    ) internal {
        uint256 newDebt = _currentDebt - _debtToLiquidate;
        uint256 oldPrincipal = _position.debtAmount;
        uint256 oldUserIndex = _position.lastInterestUpdate;
        uint256 oldPurePrincipal = _position.purePrincipal;
        
        // Calculate how much of the liquidation payment goes to pure principal
        uint256 interestAccrued = _currentDebt - oldPurePrincipal;
        uint256 principalPaid;
        
        if (_debtToLiquidate <= interestAccrued) {
            principalPaid = 0;
        } else {
            principalPaid = _debtToLiquidate - interestAccrued;
        }
        
        // Update pure principal
        _position.purePrincipal = oldPurePrincipal - principalPaid;
        
        // Update total pure principal tracking - simply reduce by principal paid
        totalPurePrincipal -= principalPaid;
        
        // Update debt amount
        _position.debtAmount = newDebt;

        // Update totalConsolidatedDebt for totalDebt() calculation
        _updateConsolidatedDebt(oldPrincipal, newDebt, oldUserIndex, _currentIndex);
    }

    /**
     * @notice Transfers a portion of a user's position to the treasury wallet internally
     * @dev This function assumes interest has already been updated and user position may have been modified
     * @param _user Address of the user being liquidated
     * @param _treasuryWallet Address of the treasury wallet receiving the position
     * @param _debtToTransfer Amount of debt to transfer to treasury wallet
     * @param _collateralToTransfer Amount of collateral to transfer (pre-calculated to avoid redundant oracle calls)
     * @param _currentIndex Current global interest index (to avoid duplicate interest updates)
     */
    function _transferPositionToTreasury(
        address _user, 
        address _treasuryWallet, 
        uint256 _debtToTransfer,
        uint256 _collateralToTransfer,
        uint256 _currentIndex
    ) internal {
        // NOTE: Interest update already done in main liquidation flow - using provided currentIndex
        
        // Get user's current position (may already be modified by partial liquidation)
        Position storage userPosition = positions[_user];
        uint256 oldUserPurePrincipal = userPosition.purePrincipal;
        
        // Calculate current debt based on current position state
        uint256 currentDebt = _currentDebtOf(userPosition, _currentIndex);
        
        // Ensure user has sufficient remaining debt and collateral for transfer
        if (currentDebt < _debtToTransfer) {
            revert LendingVault__InsufficientRemainingDebtToTransfer(currentDebt, _debtToTransfer);
        }
        if (userPosition.collateralAmount < _collateralToTransfer) {
            revert LendingVault__InsufficientRemainingCollateralToTransfer(userPosition.collateralAmount, _collateralToTransfer);
        }
        
        // Calculate how much of the debt transfer is principal vs interest
        uint256 interestAccrued = currentDebt - oldUserPurePrincipal;
        uint256 principalPortion;
        
        if (_debtToTransfer <= interestAccrued) {
            // Transfer only covers interest
            principalPortion = 0;
        } else {
            // Transfer covers interest + part of principal
            principalPortion = _debtToTransfer - interestAccrued;
        }
        
        // Update user's pure principal
        uint256 newUserPurePrincipal = oldUserPurePrincipal - principalPortion;
        userPosition.purePrincipal = newUserPurePrincipal;
        
        // Calculate new principal for user after debt transfer
        uint256 newUserDebt = currentDebt - _debtToTransfer;
        uint256 newUserPrincipal = newUserDebt; // with index = currentIndex, principal equals current debt
        
        // Update user's position
        userPosition.debtAmount = newUserPrincipal;
        userPosition.lastInterestUpdate = _currentIndex;
        userPosition.collateralAmount -= _collateralToTransfer;
        
        // Update total collateral (subtract only the transfer amount, not double-counting liquidation)
        totalCollateral -= _collateralToTransfer;
        
        // Get or create treasury wallet position
        Position storage treasuryPosition = positions[_treasuryWallet];
        if (!treasuryPosition.exists) {
            // Create new treasury position with transferred amounts
            treasuryPosition.exists = true;
            treasuryPosition.lastInterestUpdate = _currentIndex;
            treasuryPosition.debtAmount = _debtToTransfer;
            treasuryPosition.collateralAmount = _collateralToTransfer;
            treasuryPosition.purePrincipal = principalPortion; // Transfer only the principal portion
        } else {
            // Update existing treasury position and add transferred amounts
            uint256 treasuryCurrentDebt = _currentDebtOf(treasuryPosition, _currentIndex);
            treasuryPosition.debtAmount = treasuryCurrentDebt + _debtToTransfer;
            treasuryPosition.lastInterestUpdate = _currentIndex;
            treasuryPosition.collateralAmount += _collateralToTransfer;
            treasuryPosition.purePrincipal += principalPortion; // Add only the principal portion
        }
        
        // Note: No change to totalPrincipal needed since we're transferring existing debt internally
        // User principal decreases by _debtToTransfer, treasury principal increases by _debtToTransfer (net zero)
        
        emit PositionTransferredToTreasury(_user, _treasuryWallet, _debtToTransfer, _collateralToTransfer);
    }

    /**
     * @notice Computes the debt amount to repay during liquidation using the configured close factor
     * @param _currentDebt Current user debt including accrued interest (in PUSD wei)
     * @return Debt amount to repay (in PUSD wei)
     */
    function _computeDebtToRepay(uint256 _currentDebt) internal view returns (uint256) {
        uint256 configuredCloseFactorBps = protocolConfig.closeFactorBps();

        // Base partial liquidation amount using close factor
        uint256 partialRepayAmount = (_currentDebt * configuredCloseFactorBps) / 10_000;
        if (partialRepayAmount == 0) {
            partialRepayAmount = _currentDebt;
        }

        // If the remaining debt would be below minDebt, liquidate fully
        uint256 minimumDebtAllowed = protocolConfig.minDebt();
        if ((_currentDebt - partialRepayAmount) < minimumDebtAllowed) {
            return _currentDebt;
        }

        return partialRepayAmount;
    }

    /**
     * @notice Computes the amount of collateral to seize applying the configured liquidation bonus
     * @param _debtToRepay Debt amount (in PUSD wei) being repaid by StabilityFund
     * @return Amount of collateral tokens to seize from the user
     */
    function _computeCollateralToSeize(uint256 _debtToRepay) internal view returns (uint256) {
        (uint256 price, uint8 oracleDecimals) = _getValidatedOraclePrice();
        uint256 configuredBonusBps = protocolConfig.liquidationBonusBps();

        // This keeps everything in the same decimal scale as the oracle (8 decimals)
        uint256 bonusFactor = 10_000 + configuredBonusBps;
        
        // collateralToSeize = (debtToRepay * (10000 + bonusBps)) / (price * 10000)
        return (_debtToRepay * bonusFactor * (10 ** oracleDecimals)) / (price * 10000);
    }

    /**
     * @notice Calculates and validates the actual repayment amount
     * @param _requestedAmount The amount the user wants to repay
     * @param _currentDebt The user's current debt including accrued interest
     * @return actualAmount The validated actual repayment amount
     */
    function _calculateActualRepaymentAmount(uint256 _requestedAmount, uint256 _currentDebt) internal view returns (uint256 actualAmount) {
        // Calculate actual repayment amount (can't exceed debt)
        actualAmount = _requestedAmount > _currentDebt ? _currentDebt : _requestedAmount;
        uint256 newDebt = _currentDebt - actualAmount;

        // Enforce minimum remaining debt requirement unless fully repaid
        if (_currentDebt > 0) {
            uint256 minDebt = protocolConfig.minDebt();
            if (newDebt > 0 && newDebt < minDebt) {
                revert LendingVault__BelowMinimumDebt(newDebt, minDebt);
            }
        }
    }

    /**
     * @notice Splits a debt payment into principal and interest portions
     * @param _purePrincipal The pure principal amount (actual borrowed amount)
     * @param _currentDebt The current debt including accrued interest
     * @param _paymentAmount The total payment amount
     * @return principalPortion Amount that goes to principal
     * @return interestPortion Amount that goes to interest
     */
    function _splitDebtPayment(
        uint256 _purePrincipal,
        uint256 _currentDebt,
        uint256 _paymentAmount
    ) internal pure returns (uint256 principalPortion, uint256 interestPortion) {
        uint256 interestAccrued = _currentDebt - _purePrincipal;
        
        if (_paymentAmount <= interestAccrued) {
            // Payment only covers interest
            principalPortion = 0;
            interestPortion = _paymentAmount;
        } else {
            // Payment covers interest + part of principal
            interestPortion = interestAccrued;
            principalPortion = _paymentAmount - interestAccrued;
        }
    }

    /**
     * @notice Processes the repayment split between principal and interest
     * @param _position The user's position storage reference
     * @param _currentDebt The user's current debt including accrued interest
     * @param _actualAmount The actual repayment amount
     * @return principalPaid Amount paid towards principal
     * @return interestPaid Amount paid towards interest
     */
    function _processRepaymentSplit(
        Position storage _position, 
        uint256 _currentDebt, 
        uint256 _actualAmount
    ) internal returns (uint256 principalPaid, uint256 interestPaid) {
        // Use the split function to separate principal from interest
        (principalPaid, interestPaid) = _splitDebtPayment(_position.purePrincipal, _currentDebt, _actualAmount);
        
        // Burn only the principal paid
        if (principalPaid > 0) {
            pusd.burn(principalPaid);
        }
        
        // Send interest fees to Treasury
        if (interestPaid > 0) {
            totalInterestFees += interestPaid;
            IERC20(address(pusd)).approve(address(treasury), interestPaid);
            ITreasury(treasury).receivePUSD(interestPaid);

            emit InterestFeesCollected(msg.sender, interestPaid, totalInterestFees);
        }
    }

    /**
     * @notice Updates the user's position after repayment
     * @param _position The user's position storage reference
     * @param _currentDebt The user's current debt before repayment
     * @param _actualAmount The actual repayment amount
     * @param _currentIndex The current global interest index
     */
    function _updatePositionAfterRepayment(
        Position storage _position,
        uint256 _currentDebt,
        uint256 _actualAmount,
        uint256 _currentIndex
    ) internal {
        // Calculate the correct new principal amount
        // Use pure principal (actual borrowed amount) not debtAmount (which includes consolidated interest)
        uint256 oldPurePrincipal = _position.purePrincipal;
        uint256 interestAccrued = _currentDebt - oldPurePrincipal;
        uint256 principalPaid;
        
        if (_actualAmount <= interestAccrued) {
            // Payment only covers interest
            principalPaid = 0;
        } else {
            // Payment covers interest + part of principal
            principalPaid = _actualAmount - interestAccrued;
        }
        
        // Update pure principal
        _position.purePrincipal = oldPurePrincipal - principalPaid;
        
        // Calculate new debt amount (for position tracking and normalized debt calculations)
        uint256 oldPrincipal = _position.debtAmount;
        uint256 newPrincipal = _currentDebt - _actualAmount;
        
        // Calculate normalized principal changes for totalConsolidatedDebt accounting
        // Convert both old and new principal to PRECISION base for consistent totalConsolidatedDebt tracking
        uint256 oldPrincipalNormalized = (oldPrincipal * PRECISION) / (_position.lastInterestUpdate == 0 ? PRECISION : _position.lastInterestUpdate);
        uint256 newPrincipalNormalized = (newPrincipal * PRECISION) / _currentIndex;
        
        // In normal operation, oldPrincipalNormalized should always be >= newPrincipalNormalized
        // since principal can only decrease during repayments and indices only increase over time
        if (oldPrincipalNormalized > newPrincipalNormalized) {
            totalConsolidatedDebt -= (oldPrincipalNormalized - newPrincipalNormalized);
        }
        
        // Note: totalPurePrincipal is updated separately in the repay function based on principalPaid

        _position.debtAmount = newPrincipal;
        _position.lastInterestUpdate = _currentIndex; // userDebtIndex snapshot
    }

    /**
     * @notice Updates totalConsolidatedDebt based on principal changes
     * @param _oldPrincipal Previous principal amount
     * @param _newPrincipal New principal amount
     * @param _oldUserIndex User's index at the time the old principal was recorded (lastInterestUpdate)
     * @param _currentIndex Current global interest index
     */
    function _updateConsolidatedDebt(uint256 _oldPrincipal, uint256 _newPrincipal, uint256 _oldUserIndex, uint256 _currentIndex) internal {
        uint256 oldPrincipalNormalized = (_oldPrincipal * PRECISION) / (_oldUserIndex == 0 ? PRECISION : _oldUserIndex);
        uint256 newPrincipalNormalized = (_newPrincipal * PRECISION) / _currentIndex;
        
        if (newPrincipalNormalized > oldPrincipalNormalized) {
            totalConsolidatedDebt += (newPrincipalNormalized - oldPrincipalNormalized);
        } else if (oldPrincipalNormalized > newPrincipalNormalized) {
            totalConsolidatedDebt -= (oldPrincipalNormalized - newPrincipalNormalized);
        }
    }

    /**
     * @notice Required override for UUPS upgrades
     */
    function _authorizeUpgrade(address _newImplementation) internal override onlyRole(protocolConfig.UPGRADER_ROLE()) {}
}