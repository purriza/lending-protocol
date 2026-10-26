// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStabilityFund} from "./interfaces/IStabilityFund.sol";
import {IProtocolConfig} from "./interfaces/IProtocolConfig.sol";
import {PUSD} from "./PUSD.sol";
import {wPUSD} from "./wPUSD.sol";

/**
 * @title StabilityFund
 * @notice Manages PUSD deposits and mints wPUSD, provides liquidity for liquidations
 * @dev This contract accepts PUSD deposits, mints wPUSD, and manages exchange rates
 */
contract StabilityFund is 
    IStabilityFund,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    IProtocolConfig public protocolConfig;

    uint256 private constant PRECISION = 1e18;
    uint256 private constant ABSOLUTE_MIN_DEPOSIT_AMOUNT = 1e12;

    uint256 private _minDepositAmount;

    uint256 public exchangeRate;
    uint256 public totalPusdLocked;
    
    /// @notice Outstanding PUSD-denominated IOU from Treasury backstop
    uint256 public backstopIouAmount;
    
    PUSD public pusd;
    wPUSD public wpusd;
    
    address public lendingVault;
    address public liquidationEngine;
    address public treasury;
    
    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyLendingVault() {
        if (msg.sender != lendingVault) revert StabilityFund__UnauthorizedCaller(msg.sender);
        _;
    }

    modifier onlyLiquidationEngine() {
        if (msg.sender != liquidationEngine) revert StabilityFund__UnauthorizedCaller(msg.sender);
        _;
    }

    modifier checkZeroAddress(address _address) {
        if (_address == address(0)) revert StabilityFund__InvalidAddress();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _protocolConfig,
        address _pusd,
        address _wpusd
    ) public initializer {
        if (_protocolConfig == address(0) || _pusd == address(0) || _wpusd == address(0) ) {
            revert StabilityFund__InvalidAddress();
        }

        __AccessControlEnumerable_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        pusd = PUSD(_pusd);
        wpusd = wPUSD(_wpusd);
        protocolConfig = IProtocolConfig(_protocolConfig);

        // Initialize exchange rate at 1:1 (18 decimals)
        exchangeRate = 1e18;

        _minDepositAmount = 0.001 ether;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(protocolConfig.ADMIN_ROLE(), msg.sender);
        _grantRole(protocolConfig.UPGRADER_ROLE(), msg.sender);

        emit StabilityFundInitialized(_protocolConfig, _pusd, _wpusd, exchangeRate, _minDepositAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setLendingVault(address _lendingVault) external onlyRole(protocolConfig.ADMIN_ROLE()) checkZeroAddress(_lendingVault) {
        address oldVault = lendingVault;
        lendingVault = _lendingVault;
        
        emit LendingVaultUpdated(oldVault, _lendingVault);
    }

    function setLiquidationEngine(address _liquidationEngine) external onlyRole(protocolConfig.ADMIN_ROLE()) checkZeroAddress(_liquidationEngine) {
        address oldEngine = liquidationEngine;
        liquidationEngine = _liquidationEngine;
        
        emit LiquidationEngineUpdated(oldEngine, _liquidationEngine);
    }

    function setTreasury(address _treasury) external onlyRole(protocolConfig.ADMIN_ROLE()) checkZeroAddress(_treasury) {
        address oldTreasury = treasury;
        treasury = _treasury;
        
        emit TreasuryUpdated(oldTreasury, _treasury);
    }

    function setMinDepositAmount(uint256 _newMinDepositAmount) external onlyRole(protocolConfig.ADMIN_ROLE()) {
        if (_newMinDepositAmount < ABSOLUTE_MIN_DEPOSIT_AMOUNT) revert StabilityFund__InvalidAmount(_newMinDepositAmount);
        uint256 oldMinDepositAmount = _minDepositAmount;
        _minDepositAmount = _newMinDepositAmount;

        emit MinDepositAmountUpdated(oldMinDepositAmount, _newMinDepositAmount);
    }

    function recoverStuckTokens(address _token) external onlyRole(protocolConfig.ADMIN_ROLE()) {
        if (_token == address(pusd)) revert StabilityFund__CannotRecoverPUSD();

        uint256 balance = IERC20(_token).balanceOf(address(this));

        _validateAmount(balance);

        IERC20(_token).safeTransfer(msg.sender, balance);
        emit TokensRecovered(_token, msg.sender, balance);
    }

    function pause() external onlyRole(protocolConfig.ADMIN_ROLE()) {
        _pause();
    }

    function unpause() external onlyRole(protocolConfig.ADMIN_ROLE()) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function depositPUSD(uint256 _pusdAmount) external nonReentrant whenNotPaused returns (uint256 wpusdToMint){
        if (_pusdAmount < _minDepositAmount) revert StabilityFund__InvalidAmount(_pusdAmount);

        totalPusdLocked += _pusdAmount;
        wpusdToMint = (_pusdAmount * PRECISION) / exchangeRate;
        
        _validateAmount(wpusdToMint);
        
        pusd.transferFrom(msg.sender, address(this), _pusdAmount);
        wpusd.mint(msg.sender, wpusdToMint);
        
        emit PUSDDeposited(msg.sender, _pusdAmount, wpusdToMint);
    }

    function redeemWPUSD(uint256 wpusdAmount) external nonReentrant whenNotPaused returns (uint256 pusdToReturn) {
        _validateAmount(wpusdAmount);

        pusdToReturn = (wpusdAmount * exchangeRate) / PRECISION;
        uint256 contractPUSDBalance = pusd.balanceOf(address(this));
        
        if (contractPUSDBalance < pusdToReturn) {
            revert StabilityFund__InsufficientBalance(contractPUSDBalance, pusdToReturn);
        }

        totalPusdLocked -= pusdToReturn;

        IERC20(address(wpusd)).safeTransferFrom(msg.sender, address(this), wpusdAmount);
        wpusd.burn(wpusdAmount);
        
        IERC20(address(pusd)).safeTransfer(msg.sender, pusdToReturn);
        
        emit WPUSDRedeemed(msg.sender, wpusdAmount, pusdToReturn);
    }

    function sendLiquidationFunds(uint256 _requestedAmount) external onlyLendingVault returns (uint256) {
        _validateAmount(_requestedAmount);

        IERC20 pusdToken = IERC20(address(pusd));
        uint256 pusdBalance = pusdToken.balanceOf(address(this));

        uint256 transferAmount = pusdBalance < _requestedAmount ? pusdBalance : _requestedAmount;

        // This should not reduce the totalPusdLocked amount as that can be treated as in-transit funds
        pusdToken.safeTransfer(lendingVault, transferAmount);

        emit LiquidationFundsSent(lendingVault, transferAmount);

        return transferAmount;
    }

    function receiveLiquidationReturns(
        uint256 _pusdAmount, 
        uint256 _excessAmount,
        uint256 _iouAmount
    ) external onlyLiquidationEngine nonReentrant whenNotPaused returns (uint256 amountReceived) {
        // Allow _pusdAmount = 0 when only sending excess (profits)
        if (_pusdAmount == 0 && _excessAmount == 0 && _iouAmount == 0) {
            revert StabilityFund__InvalidAmount(0);
        }

        uint256 totalAmount = _pusdAmount + _excessAmount;

        if (totalAmount > 0) {
            IERC20(address(pusd)).safeTransferFrom(msg.sender, address(this), totalAmount);
        }

        // Track IOU if backstop was needed
        if (_iouAmount > 0) {
            backstopIouAmount += _iouAmount;
            emit BackstopIOURecorded(_iouAmount, backstopIouAmount);
        }

        if (_excessAmount > 0) {
            uint256 wpusdSupply = wpusd.totalSupply();
            if (wpusdSupply > 0) {
                // Increase totalPusdLocked by the yield amount received
                totalPusdLocked += _excessAmount;
                
                // Calculate exchange rate accounting for IOUs
                uint256 newRate = _calculateExchangeRate();
                if (newRate > exchangeRate) {
                    _updateExchangeRate(newRate);
                }
            } 
        } else if (_iouAmount > 0) {
            // If IOU created but no excess, still update exchange rate to reflect shortfall
            uint256 newRate = _calculateExchangeRate();
            if (newRate != exchangeRate) {
                _updateExchangeRate(newRate);
            }
        }

        amountReceived = totalAmount;

        emit LiquidationReturnsReceived(msg.sender, _pusdAmount, _excessAmount, amountReceived);
    }

    function receiveBackstopRepayment(uint256 _repaymentAmount) 
        external 
        nonReentrant 
        whenNotPaused 
        returns (uint256 iouReduction) 
    {
        if (msg.sender != treasury) revert StabilityFund__UnauthorizedCaller(msg.sender);
        _validateAmount(_repaymentAmount);
        
        if (backstopIouAmount == 0) revert StabilityFund__NoOutstandingIOU();
        
        // Calculate how much IOU can be reduced (capped at outstanding amount)
        iouReduction = _repaymentAmount > backstopIouAmount ? backstopIouAmount : _repaymentAmount;
        
        // Receive PUSD from Treasury
        IERC20(address(pusd)).safeTransferFrom(msg.sender, address(this), _repaymentAmount);
        
        // Reduce IOU tracking
        backstopIouAmount -= iouReduction;
        
        // Recalculate and update exchange rate to reflect improved solvency
        uint256 wpusdSupply = wpusd.totalSupply();
        if (wpusdSupply > 0) {
            uint256 newRate = _calculateExchangeRate();
            if (newRate != exchangeRate) {
                _updateExchangeRate(newRate);
            }
        }
        
        emit BackstopIOURepaid(iouReduction, backstopIouAmount, _repaymentAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getPusdAddress() external view returns (address) {
        return address(pusd);
    }

    function getWpusdAddress() external view returns (address) {
        return address(wpusd);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function getAbsoluteMinDepositAmount() external pure returns (uint256) {
        return ABSOLUTE_MIN_DEPOSIT_AMOUNT;
    }

    function getMinDepositAmount() external view returns (uint256) {
        return _minDepositAmount;
    }


    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates exchange rate accounting for outstanding IOUs
     * @dev Exchange rate = (totalPusdLocked - backstopIouAmount) / wpusdSupply
     * @dev IOUs reduce the effective PUSD value, lowering the exchange rate
     * @return rate The calculated exchange rate
     */
    function _calculateExchangeRate() internal view returns (uint256 rate) {
        uint256 wpusdSupply = wpusd.totalSupply();
        if (wpusdSupply == 0) return PRECISION; // Default 1:1 if no supply
        
        // Effective PUSD is total locked minus outstanding IOUs
        // IOUs represent PUSD we're owed but don't have yet
        uint256 effectivePusd = totalPusdLocked > backstopIouAmount 
            ? totalPusdLocked - backstopIouAmount 
            : 0;
        
        rate = (effectivePusd * PRECISION) / wpusdSupply;
    }

    function _updateExchangeRate(uint256 _exchangeRate) internal {
        uint256 oldRate = exchangeRate;
        exchangeRate = _exchangeRate;

        uint256 lastUpdated = block.timestamp;
     
        emit ExchangeRateUpdated(oldRate, exchangeRate, lastUpdated);
    }

    function _validateAmount(uint256 _amount) internal pure {
        if (_amount == 0) revert StabilityFund__InvalidAmount(_amount);
    }

    function _authorizeUpgrade(address _newImplementation) internal override onlyRole(protocolConfig.UPGRADER_ROLE()) {}
}