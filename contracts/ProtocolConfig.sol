// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IProtocolConfig} from "./interfaces/IProtocolConfig.sol";
import {IPUSD} from "./interfaces/IPUSD.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";

/**
 * @title ProtocolConfig
 * @notice Stores protocol-level configuration parameters for the lending protocol
 * @dev This contract manages critical protocol parameters including Oracles, Liquidation Thresholds, Fees etc
 */
contract ProtocolConfig is
    AccessControlEnumerableUpgradeable,
    UUPSUpgradeable,
    IProtocolConfig 
{
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_BPS = 10_000;
    uint256 public constant MAX_LIQUIDATION_THRESHOLD = 50_000;
    uint256 public constant MANDATORY_BUFFER_BPS = 3_000; // 30% mandatory buffer between ratios
    uint256 public constant MIN_CLOSE_FACTOR_BPS = 500; // 5% minimum close factor
    uint256 public constant MIN_LIQUIDATION_BONUS_BPS = 100; // 1% minimum liquidation bonus
    uint256 public constant MAX_LIQUIDATION_BONUS_BPS = 3_000; // 30% maximum liquidation bonus

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    IPriceOracle public oracle;
    ISwapRouter public swapRouter;
    IQuoterV2 public quoter;

    address public collateralToken;
    address public treasuryWallet;
    
    uint256 public liquidationThreshold;
    uint256 public minCollateralRatio;
    uint256 public debtCeiling;
    uint256 public minDebt;
    uint256 public closeFactorBps;
    uint256 public liquidationBonusBps;
    uint256 public uniswapFee;
    uint256 public maxStaleness;

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier checkZeroAddress(address _address) {
        if (_address == address(0)) revert ProtocolConfig__InvalidAddress();
        _;
    }

    modifier validateAmount(uint256 _amount) {
        if (_amount <= 0) revert ProtocolConfig__InvalidAmount();
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
        address _oracleAddress,
        address _swapRouterAddress,
        address _quoterAddress,
        address _collateralTokenAddress
    ) public override initializer {
        if (_oracleAddress == address(0) || 
            _swapRouterAddress == address(0) || _quoterAddress == address(0) ||
            _collateralTokenAddress == address(0)) revert ProtocolConfig__InvalidAddress();

        __AccessControlEnumerable_init();
        __UUPSUpgradeable_init();

        oracle = IPriceOracle(_oracleAddress);
        swapRouter = ISwapRouter(_swapRouterAddress);
        quoter = IQuoterV2(_quoterAddress);
        collateralToken = _collateralTokenAddress;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);

        // Set default values with validation
        liquidationThreshold = 12_000; // Default 120%
        minCollateralRatio = 12_000; // Default 120%
        debtCeiling = 100_000_000 ether; // Default 100M debt ceiling
        minDebt = 500 ether; // Default 500 PUSD minimum debt
        closeFactorBps = 5_000; // Default 50%
        liquidationBonusBps = 1_000; // Default +10%
        uniswapFee = 3_000; // Default Uniswap V3 0.3%
        maxStaleness = 3600; // Default 1 hour staleness tolerance

        emit ProtocolConfigInitialized(
            _oracleAddress, 
            _swapRouterAddress, 
            _quoterAddress, 
            liquidationThreshold, 
            minCollateralRatio, 
            debtCeiling, 
            minDebt, 
            closeFactorBps, 
            liquidationBonusBps, 
            uniswapFee
        );
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setTreasuryWallet(address _treasuryWallet) external onlyRole(ADMIN_ROLE) checkZeroAddress(_treasuryWallet) {
        address oldWallet = treasuryWallet;
        treasuryWallet = _treasuryWallet;
        
        emit TreasuryWalletUpdated(oldWallet, _treasuryWallet);
    }

    function setOracle(address _oracleAddress) external override onlyRole(ADMIN_ROLE) checkZeroAddress(_oracleAddress) {
        address oldOracle = address(oracle);
        oracle = IPriceOracle(_oracleAddress);
        
        emit OracleUpdated(oldOracle, _oracleAddress);
    }

    function setSwapRouter(address _swapRouter) external onlyRole(ADMIN_ROLE) checkZeroAddress(_swapRouter) {
        address oldSwapRouter = address(swapRouter);
        swapRouter = ISwapRouter(_swapRouter);

        emit SwapRouterUpdated(oldSwapRouter, _swapRouter);
    }

    function setQuoter(address _quoter) external onlyRole(ADMIN_ROLE) checkZeroAddress(_quoter) {
        address oldQuoter = address(quoter);
        quoter = IQuoterV2(_quoter);

        emit QuoterUpdated(oldQuoter, _quoter);
    }

    function setCollateralToken(address _collateralToken) external override onlyRole(ADMIN_ROLE) checkZeroAddress(_collateralToken) {
        address oldToken = collateralToken;
        collateralToken = _collateralToken;
        
        emit CollateralTokenUpdated(oldToken, _collateralToken);
    }

    function setLiquidationThreshold(uint256 _liquidationThreshold) external override onlyRole(ADMIN_ROLE) {
        // Allow thresholds above 100% (e.g., 12000 = 120%)
        if (_liquidationThreshold == 0 || _liquidationThreshold > MAX_LIQUIDATION_THRESHOLD) revert ProtocolConfig__InvalidPercentage();

        // Prevent scenarios where positions become immediately liquidatable after creation
        if (_liquidationThreshold >= minCollateralRatio) revert ProtocolConfig__InvalidRatio();
        
        // Ensure mandatory 30% buffer between liquidation threshold and min collateral ratio
        if (minCollateralRatio > 0 && minCollateralRatio - _liquidationThreshold < MANDATORY_BUFFER_BPS)
            revert ProtocolConfig__InvalidRatio();

        uint256 oldThreshold = liquidationThreshold;
        liquidationThreshold = _liquidationThreshold;

        emit LiquidationThresholdUpdated(oldThreshold, _liquidationThreshold);
    }

    function setMinCollateralRatio(uint256 _minCollateralRatio) external override onlyRole(ADMIN_ROLE) {
        if (_minCollateralRatio < MAX_BPS) revert ProtocolConfig__InvalidRatio(); // Must be at least 100%

        // Ensure new ratio maintains proper relationship with liquidation threshold
        if (liquidationThreshold > 0 && _minCollateralRatio <= liquidationThreshold) 
            revert ProtocolConfig__InvalidRatio();
        
        // Ensure mandatory 30% buffer between min collateral ratio and liquidation threshold
        if (liquidationThreshold > 0 && _minCollateralRatio - liquidationThreshold < MANDATORY_BUFFER_BPS)
            revert ProtocolConfig__InvalidRatio();

        uint256 oldRatio = minCollateralRatio;
        minCollateralRatio = _minCollateralRatio;

        emit MinCollateralRatioUpdated(oldRatio, _minCollateralRatio);
    }

    function setDebtCeiling(uint256 _debtCeiling) external override onlyRole(ADMIN_ROLE) validateAmount(_debtCeiling) {
        uint256 oldCeiling = debtCeiling;
        debtCeiling = _debtCeiling;
        
        emit DebtCeilingUpdated(oldCeiling, _debtCeiling);
    }

    function setMinDebt(uint256 _minDebt) external override onlyRole(ADMIN_ROLE) validateAmount(_minDebt) {
        uint256 old = minDebt;
        minDebt = _minDebt;

        emit MinDebtUpdated(old, _minDebt);
    }

    function setCloseFactorBps(uint256 _closeFactorBps) external override onlyRole(ADMIN_ROLE) {
        if (_closeFactorBps == 0 || _closeFactorBps > MAX_BPS) revert ProtocolConfig__InvalidPercentage();
        
        // Ensure minimum close factor to prevent forced full liquidations
        if (_closeFactorBps < MIN_CLOSE_FACTOR_BPS) revert ProtocolConfig__InvalidPercentage(); // Min 5%

        uint256 old = closeFactorBps;
        closeFactorBps = _closeFactorBps;

        emit CloseFactorUpdated(old, _closeFactorBps);
    }

    function setLiquidationBonusBps(uint256 _liquidationBonusBps) external override onlyRole(ADMIN_ROLE) validateAmount(_liquidationBonusBps) {
        if (_liquidationBonusBps > MAX_LIQUIDATION_BONUS_BPS) revert ProtocolConfig__InvalidPercentage(); // Max 20% bonus
        if (_liquidationBonusBps < MIN_LIQUIDATION_BONUS_BPS) revert ProtocolConfig__InvalidPercentage();  // Min 1% bonus

        uint256 old = liquidationBonusBps;
        liquidationBonusBps = _liquidationBonusBps;

        emit LiquidationBonusUpdated(old, _liquidationBonusBps);
    }

    function setUniswapFee(uint256 _fee) external onlyRole(ADMIN_ROLE) validateAmount(_fee) {
        // Accept common tiers: 100, 500, 3000, 10000; do not enforce strictly here
        uint256 old = uniswapFee;
        uniswapFee = _fee;

        emit UniswapFeeUpdated(old, _fee);
    }

    function setMaxStaleness(uint256 _maxStaleness) external onlyRole(ADMIN_ROLE) validateAmount(_maxStaleness) {
        uint256 old = maxStaleness;
        maxStaleness = _maxStaleness;

        emit MaxStalenessUpdated(old, _maxStaleness);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}