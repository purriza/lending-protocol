// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import {IProtocolConfig} from "./interfaces/IProtocolConfig.sol";
import {ILendingVault} from "./interfaces/ILendingVault.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";
import {ILiquidationEngine} from "./interfaces/ILiquidationEngine.sol";
import {IStabilityFund} from "./interfaces/IStabilityFund.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IPUSD} from "./interfaces/IPUSD.sol";

import {DataTypes} from "./DataTypes.sol";

/**
 * @title LiquidationEngine
 * @notice Handles liquidation of undercollateralized positionsforge 
 * @dev Receives collateral from LendingVault, swaps via AMM and calls Treasury backstop if needed
 */
contract LiquidationEngine is
    ILiquidationEngine,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    uint256 private constant MAX_SLIPPAGE_BPS = 2_000; // Max 20%
    uint256 private constant MAX_TREASURY_REVENUE_FEE_BPS = 5_000; // Max 50%
    uint256 private constant BPS_DENOMINATOR = 10_000;

    IProtocolConfig public protocolConfig;
    IPUSD public pusd;
    ILendingVault public lendingVault;
    IStabilityFund public stabilityFund;
    ITreasury public treasury;

    uint256 public maxSlippage;
    uint256 public treasuryRevenueFee;
    uint256 public totalCollateralLiquidated;
    uint256 public totalDebtCovered;
    uint256 public liquidationCounter;

    mapping(uint256 _liquidationId => ILiquidationEngine.LiquidationRecord _record) public liquidations; 

    /*//////////////////////////////////////////////////////////////
                                MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Modifier to restrict calls to LendingVault
    modifier onlyLendingVault() {
        if (msg.sender != address(lendingVault)) revert LiquidationEngine__UnauthorizedCaller();
        _;
    }

    modifier checkZeroAddress(address _address) {
        if (_address == address(0)) revert LiquidationEngine__InvalidAddress(_address);
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
        address _protocolConfig,
        address _pusd
    ) external override initializer {
        if (_protocolConfig == address(0)) revert LiquidationEngine__InvalidAddress(_protocolConfig);
        if (_pusd == address(0)) revert LiquidationEngine__InvalidAddress(_pusd);

        __AccessControlEnumerable_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        
        protocolConfig = IProtocolConfig(_protocolConfig);
        pusd = IPUSD(_pusd);
        
        maxSlippage = 1_000; // 10% max slippage
        treasuryRevenueFee = 2_000; // 20% default treasury fee
        liquidationCounter = 1;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(protocolConfig.ADMIN_ROLE(), msg.sender);
        _grantRole(protocolConfig.UPGRADER_ROLE(), msg.sender);

        emit LiquidationEngineInitialized(_protocolConfig, _pusd, maxSlippage, treasuryRevenueFee);
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

    function setLendingVault(address _lendingVault) external override onlyRole(protocolConfig.ADMIN_ROLE()) checkZeroAddress(_lendingVault) {

        address oldVault = address(lendingVault);
        lendingVault = ILendingVault(_lendingVault);
        
        emit LendingVaultUpdated(oldVault, _lendingVault);
    }

    function setStabilityFund(address _stabilityFund) external override onlyRole(protocolConfig.ADMIN_ROLE()) checkZeroAddress(_stabilityFund) {

        address oldStabilityFund = address(stabilityFund);
        stabilityFund = IStabilityFund(_stabilityFund);
        
        emit StabilityFundUpdated(oldStabilityFund, _stabilityFund);
    }

    function setTreasury(address _treasury) external override onlyRole(protocolConfig.ADMIN_ROLE()) checkZeroAddress(_treasury) {

        address oldTreasury = address(treasury);
        treasury = ITreasury(_treasury);
        
        emit TreasuryUpdated(oldTreasury, _treasury);
    }

    function setMaxSlippage(uint256 _maxSlippage) external override onlyRole(protocolConfig.ADMIN_ROLE()) {
        if (_maxSlippage > MAX_SLIPPAGE_BPS) revert LiquidationEngine__InvalidPercentage();
        
        uint256 oldSlippage = maxSlippage;
        maxSlippage = _maxSlippage;
        
        emit MaxSlippageUpdated(oldSlippage, _maxSlippage);
    }

    function setTreasuryRevenueFee(uint256 _treasuryRevenueFee) external override onlyRole(protocolConfig.ADMIN_ROLE()) {
        if (_treasuryRevenueFee > MAX_TREASURY_REVENUE_FEE_BPS) revert LiquidationEngine__InvalidPercentage();
        
        uint256 oldFee = treasuryRevenueFee;
        treasuryRevenueFee = _treasuryRevenueFee;
        
        emit TreasuryRevenueFeeUpdated(oldFee, _treasuryRevenueFee);
    }

    /*//////////////////////////////////////////////////////////////
                                CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function executeLiquidation(DataTypes.LiquidationOrder calldata _order) 
        external 
        onlyLendingVault 
        nonReentrant 
        whenNotPaused 
        returns (uint256 liquidationId) 
    {
        liquidationId = liquidationCounter++;
        
        // 1. RECEIVE COLLATERAL (approved by LendingVault)
        IERC20 collateralToken = IERC20(protocolConfig.collateralToken());
        collateralToken.safeTransferFrom(address(lendingVault), address(this), _order.collateralToSell);
        
        totalCollateralLiquidated += _order.collateralToSell;
        emit CollateralReceived(_order.debtor, _order.collateralToSell, liquidationId);
        
        // 2. COMPUTE AND SWAP MAXIMUM COLLATERAL SELLABLE AMOUNT
        (uint256 sellableAmount, uint256 expectedPUSD, uint256 minAcceptablePUSD) = _calculateMaxSellableAmount(_order.collateralToSell);
        
        uint256 pusdReceived = 0;
        uint256 actuallySwapped = 0;
        if (sellableAmount > 0) {
            pusdReceived = _swapCollateral(address(collateralToken), sellableAmount, minAcceptablePUSD);

            // If swap succeeded, track the amount that was actually swapped
            if (pusdReceived > 0) {
                actuallySwapped = sellableAmount;
            }

            emit CollateralSwapped(liquidationId, sellableAmount, pusdReceived);
        }
        
        // 3. SEND REMAINING COLLATERAL TO TREASURY
        // If swap failed (pusdReceived == 0), include sellableAmount in remainingCollateral
        uint256 remainingCollateral = _order.collateralToSell - actuallySwapped;
        if (remainingCollateral > 0) {
            _transferCollateralToTreasury(remainingCollateral);
        }
        
        // 4. DISTRIBUTE FUNDS
        _distributeFunds(pusdReceived, _order);
        
        // 5. RECORD LIQUIDATION        
        liquidations[liquidationId] = LiquidationRecord({
            user: _order.debtor,
            collateralAmount: _order.collateralToSell,
            debtAmount: _order.debtPaidBySF + _order.debtPaidByTreasury,
            timestamp: block.timestamp,
            backstopUsed: pusdReceived < _order.debtPaidBySF
        });
        
        // Update total debt covered
        totalDebtCovered += _order.debtPaidBySF + _order.debtPaidByTreasury;
        
        // Emit final liquidation completion event
        emit LiquidationCompleted(
            liquidationId,
            _order.debtor,
            _order.debtPaidBySF + _order.debtPaidByTreasury,
            _order.collateralToSell,
            pusdReceived < _order.debtPaidBySF
        );
        
        return liquidationId;
    }

    /*//////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getLiquidation(uint256 _liquidationId) external view override returns (ILiquidationEngine.LiquidationRecord memory) {
        if (_liquidationId == 0 || _liquidationId >= liquidationCounter) revert LiquidationEngine__LiquidationNotFound();
        return liquidations[_liquidationId];
    }

    function getLiquidationStats() external view override returns (
        uint256 totalLiquidations,
        uint256 totalCollateral,
        uint256 totalDebt
    ) {
        return (liquidationCounter - 1, totalCollateralLiquidated, totalDebtCovered);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Calculate maximum sellable amount within slippage tolerance using binary search
     * @dev Binary search guarantees O(log n) iterations (max 20) vs linear search which could require 100+ iterations
     * @param _collateralAmount Total collateral amount to evaluate
     * @return sellableAmount Amount that can be sold within slippage tolerance
     * @return expectedPUSD Expected PUSD from selling the sellable amount
     * @return minAcceptablePUSD Minimum acceptable PUSD based on oracle floor price (oracle - maxSlippage)
     */
    function _calculateMaxSellableAmount(uint256 _collateralAmount) internal returns (uint256 sellableAmount, uint256 expectedPUSD, uint256 minAcceptablePUSD) {
        if (_collateralAmount == 0) return (0, 0, 0);
        
        // 1. Oracle sanity check
        uint256 oracleExpected = _getOracleExpectedAmount(_collateralAmount);
        if (oracleExpected == 0) return (0, _getQuoterPrice(_collateralAmount), 0);
        
        // Calculate minimum acceptable quote with configured slippage
        uint256 minQuote = Math.mulDiv(oracleExpected, (BPS_DENOMINATOR - maxSlippage), BPS_DENOMINATOR);
        
        // 2. Binary search for maximum sellable amount
        uint256 left = 0;
        uint256 right = _collateralAmount;
        
        // Binary search guarantees log2(n) 
        for (uint256 i = 0; i < 20; i++) {
            if (left > right) break;
            
            uint256 mid = (left + right) / 2;
            if (mid == 0) break;
            
            uint256 quoted = _getQuoterPrice(mid);
            
            if (quoted == 0) {
                // Quoter failed - try smaller amount
                right = mid - 1;
                continue;
            }
            
            // Check if quote meets slippage requirement (inline calculation to avoid stack too deep)
            if (quoted >= Math.mulDiv(minQuote, mid, _collateralAmount)) {
                // This amount works - save it and try larger
                sellableAmount = mid;
                expectedPUSD = quoted;
                left = mid + 1;
            } else {
                // This amount fails slippage check - try smaller
                right = mid - 1;
            }
        }
        
        // Calculate proportional minAcceptablePUSD based on final sellableAmount
        if (sellableAmount > 0) {
            minAcceptablePUSD = Math.mulDiv(minQuote, sellableAmount, _collateralAmount);
        }
        
        return (sellableAmount, expectedPUSD, minAcceptablePUSD);
    }

    /**
     * @notice Swaps collateral for PUSD via AMM
     * @param _collateralToken Address of collateral token
     * @param _amount Amount to swap
     * @param _minAmountOut Minimum acceptable PUSD based on oracle floor price (oracle - maxSlippage)
     * @return amountOut Amount of PUSD received
     */
    function _swapCollateral(
        address _collateralToken,
        uint256 _amount,
        uint256 _minAmountOut
    ) internal returns (uint256 amountOut) {
        address pusdToken = address(pusd);
        
        // Approve router to spend collateral
        IERC20(_collateralToken).approve(address(protocolConfig.swapRouter()), _amount);
        
        // Execute swap via AMM using ISwapRouter with deadline
        address routerAddr = address(protocolConfig.swapRouter());
        try ISwapRouter(routerAddr).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _collateralToken,
                tokenOut: pusdToken,
                fee: uint24(protocolConfig.uniswapFee()),
                recipient: address(this),
                deadline: block.timestamp + 300,
                amountIn: _amount,
                amountOutMinimum: _minAmountOut,
                sqrtPriceLimitX96: 0
            })
        ) returns (uint256 out0) {
            amountOut = out0;
        } catch {
            amountOut = 0;
        }
        
        return amountOut;
    }

    /**
     * @notice Distributes funds according to liquidation order details
     * @param _totalAmount Total PUSD obtained from the sale
     * @param _order The struct containing payment details
     */
    function _distributeFunds(uint256 _totalAmount, DataTypes.LiquidationOrder calldata _order) internal {
        uint256 totalDebtPaid = _order.debtPaidBySF + _order.debtPaidByTreasury;
        
        if (_totalAmount >= totalDebtPaid) {
            // Case 1: Sale covers debt - normal distribution
            _distributeNormalFunds(_totalAmount, _order);
        } else {
            // Case 2: Sale insufficient - activate Treasury backstop
            _handleInsufficientSale(_totalAmount, _order);
        }
    }

    /**
     * @notice Handles normal fund distribution when sale covers debt
     * @param _totalAmount Total PUSD obtained from the sale
     * @param _order The liquidation order
     */
    function _distributeNormalFunds(uint256 _totalAmount, DataTypes.LiquidationOrder calldata _order) internal {
        uint256 totalDebtPaid = _order.debtPaidBySF + _order.debtPaidByTreasury;

        // 1. REIMBURSE FUNDING SOURCES
        if (_order.debtPaidBySF > 0) {
            // _sendFundsToStabilityFund expects (principal, profit, iouAmount)
            // Here we only return the principal. Profit is calculated later. No IOU in this case.
            _sendFundsToStabilityFund(_order.debtPaidBySF, 0, 0); 
        }
        if (_order.debtPaidByTreasury > 0) {
            _sendFundsToTreasury(_order.debtPaidByTreasury);
        }

        // 2. DISTRIBUTE PROFIT
        uint256 profit = _totalAmount - totalDebtPaid;
        if (profit > 0) {
            uint256 treasuryShare = Math.mulDiv(profit, treasuryRevenueFee, BPS_DENOMINATOR);
            uint256 sfShare = profit - treasuryShare;
            
            // Send profit share to StabilityFund
            if (sfShare > 0) {
                _sendFundsToStabilityFund(0, sfShare, 0);
            }
            
            // Send profit share to Treasury
            if (treasuryShare > 0) {
                _sendFundsToTreasury(treasuryShare);
            }
        }
    }

    /**
     * @notice Handles case where sale is insufficient to cover debt
     * @param _totalAmount Total PUSD obtained from the sale
     * @param _order The liquidation order
     */
    function _handleInsufficientSale(uint256 _totalAmount, DataTypes.LiquidationOrder calldata _order) internal {
        uint256 totalDebtPaid = _order.debtPaidBySF + _order.debtPaidByTreasury;
        uint256 shortfall = totalDebtPaid - _totalAmount;
        
        uint256 iouAmount = 0;
        
        // 1. Request Treasury backstop for the shortfall if needed
        if (shortfall > 0) {
            uint256 backstopAmount = ITreasury(treasury).provideBackstopFunds(shortfall);
            
            // Calculate IOU amount (shortfall that Treasury couldn't provide)
            if (backstopAmount < shortfall) {
                iouAmount = shortfall - backstopAmount;
            }
            
            // Add backstop amount to total received
            _totalAmount += backstopAmount;
        }
        
        // 2. Send all PUSD received (from sale + backstop) to StabilityFund with IOU tracking
        if (_totalAmount > 0 || iouAmount > 0) {
            _sendFundsToStabilityFund(_totalAmount, 0, iouAmount);
        }
    }

    /**
     * @dev Transfer remaining collateral to Treasury using receiveWstETH
     * @param _collateralAmount Amount of collateral to transfer
     */
    function _transferCollateralToTreasury(uint256 _collateralAmount) internal {
        IERC20 collateralToken = IERC20(protocolConfig.collateralToken());
        
        // Approve Treasury to spend collateral
        collateralToken.approve(address(treasury), _collateralAmount);
        
        // Use Treasury's receiveWstETH function
        treasury.receiveWstETH(_collateralAmount);
        
        emit CollateralSentToTreasury(_collateralAmount);
    }

    /**
     * @dev Get price quote from Uniswap V3 Quoter
     * @param _collateralAmount Amount of collateral
     * @return quotedAmount Amount of PUSD expected from Uniswap quoter
     */
    function _getQuoterPrice(uint256 _collateralAmount) internal returns (uint256 quotedAmount) {
        address collateralToken = protocolConfig.collateralToken();
        address pusdToken = address(pusd);
        
        try IQuoterV2(address(protocolConfig.quoter())).quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: collateralToken,
                tokenOut: pusdToken,
                amountIn: _collateralAmount,
                fee: uint24(protocolConfig.uniswapFee()),
                sqrtPriceLimitX96: 0
            })
        ) returns (uint256 out, uint160 /*sp*/, uint32 /*ticks*/, uint256 /*gasEst*/) {
            quotedAmount = out;
        } catch {
            quotedAmount = 0;
        }
    }

    /**
     * @dev Get expected PUSD amount using oracle price
     * @param _collateralAmount Amount of collateral
     * @return expectedAmount Expected PUSD amount based on oracle price
     */
    function _getOracleExpectedAmount(uint256 _collateralAmount) internal view returns (uint256 expectedAmount) {
        IPriceOracle oracle = protocolConfig.oracle();

        try oracle.latestRoundData() returns (
            uint80 /* roundId */, int256 answer, uint256 /* startedAt */, uint256 updatedAt, uint80 /* answeredInRound */
        ) {
            if (answer > 0 && updatedAt != 0) {
                // Check for staleness
                if (block.timestamp - updatedAt > protocolConfig.maxStaleness()) {
                    revert LiquidationEngine__StaleOraclePrice();
                }
                
                uint8 oracleDecimals = oracle.decimals();
                uint256 price = uint256(answer);

                if (_collateralAmount > 0 && price > 0) {
                    // Use Math.mulDiv for overflow-safe calculation
                    expectedAmount = Math.mulDiv(_collateralAmount, price, (10 ** oracleDecimals));
                } else {
                    expectedAmount = 0;
                }
            } else {
                expectedAmount = 0;
            }
        } catch {
            expectedAmount = 0;
        }
    }

    /**
     * @notice Sends funds to StabilityFund using receiveLiquidationReturns
     * @param _debtAmount Original debt amount that StabilityFund covered
     * @param _excessAmount Excess amount (80% of surplus) going to StabilityFund
     * @param _iouAmount IOU amount created when Treasury backstop was insufficient
     */
    function _sendFundsToStabilityFund(uint256 _debtAmount, uint256 _excessAmount, uint256 _iouAmount) internal {
        if (_debtAmount == 0 && _excessAmount == 0 && _iouAmount == 0) return;
        
        uint256 totalAmount = _debtAmount + _excessAmount;
        IERC20 pusdToken = IERC20(address(pusd));
        
        // Approve StabilityFund to pull the funds (if any)
        if (totalAmount > 0) {
            pusdToken.approve(address(stabilityFund), totalAmount);
        }
        
        // Call receiveLiquidationReturns with IOU tracking
        stabilityFund.receiveLiquidationReturns(_debtAmount, _excessAmount, _iouAmount);
        
        emit FundsSentToStabilityFund(totalAmount);
    }

    /**
     * @notice Sends funds to Treasury using receivePUSD
     * @param _amount Amount to send
     */
    function _sendFundsToTreasury(uint256 _amount) internal {
        IERC20 pusdToken = IERC20(address(pusd));
        
        // Approve Treasury to spend PUSD
        pusdToken.approve(address(treasury), _amount);
        
        // Use Treasury's receivePUSD function
        treasury.receivePUSD(_amount);

        emit FundsSentToTreasury(_amount);
    }

    /**
     * @notice Required override for UUPS upgrades
     */
    function _authorizeUpgrade(address _newImplementation) internal override onlyRole(protocolConfig.UPGRADER_ROLE()) {}
}