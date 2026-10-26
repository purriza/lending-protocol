// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";

import {ITreasury} from "./interfaces/ITreasury.sol";
import {IProtocolConfig} from "./interfaces/IProtocolConfig.sol";
import {IStabilityFund} from "./interfaces/IStabilityFund.sol";

/**
 * @title Treasury
 * @notice Protocol treasury that manages fees and provides backstop liquidity
 * @dev Handles fee collection, backstop activation, and emergency functions
 */
contract Treasury is 
    ITreasury,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                            STATE VARS
    //////////////////////////////////////////////////////////////*/

    IProtocolConfig public protocolConfig;

    address public lendingVault;
    address public liquidationEngine;
    address public stabilityFund;
    address public pusd;
    address public wstETH;
    
    uint256 public totalBackstopUsed;
    uint256 public pusdBalance;
    uint256 public wstETHBalance;
    uint256 public swapSlippageBps;
    uint256 public oracleStaleAfter;
    uint256 public swapDeadlineSeconds;

    uint256 private constant BPS_DENOMINATOR = 10_000;

    /// @notice PUSD-denominated outstanding IOU
    uint256 public backstopIouPusd;

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyAuthorized() {
        if (msg.sender != lendingVault && msg.sender != liquidationEngine) {
            revert Treasury__UnauthorizedCaller();
        }
        _;
    }
    
    modifier onlyAuthorizedOrAdmin() {
        if (msg.sender != lendingVault && msg.sender != liquidationEngine && !hasRole(protocolConfig.ADMIN_ROLE(), msg.sender)) {
            revert Treasury__UnauthorizedCaller();
        }
        _;
    }
    
    modifier checkZeroAddress(address _address) {
        if (_address == address(0)) revert Treasury__InvalidAddress();
        _;
    }

    modifier validateAmount(uint256 _amount) {
        if (_amount == 0) revert Treasury__InvalidAmount();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZERS
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _protocolConfig,
        address _pusd,
        address _wstETH
    ) public initializer checkZeroAddress(_protocolConfig) checkZeroAddress(_pusd) checkZeroAddress(_wstETH) {
        __AccessControlEnumerable_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        protocolConfig = IProtocolConfig(_protocolConfig);
        pusd = _pusd;
        wstETH = _wstETH;

        swapSlippageBps = 500; // default 5%
        oracleStaleAfter = 1 hours;
        swapDeadlineSeconds = 60;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(protocolConfig.ADMIN_ROLE(), msg.sender);
        _grantRole(protocolConfig.UPGRADER_ROLE(), msg.sender);

        emit TreasuryInitialized(_protocolConfig, _pusd, _wstETH);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setPUSD(address _pusd) external checkZeroAddress(_pusd) onlyRole(protocolConfig.ADMIN_ROLE()) {
        pusd = _pusd;
        emit PUSDUpdated(pusd);
    }

    function setWstETH(address _wstETH) external checkZeroAddress(_wstETH) onlyRole(protocolConfig.ADMIN_ROLE()) {
        wstETH = _wstETH;
        emit WstETHUpdated(wstETH);
    }

    function setProtocolConfig(address _protocolConfig) external checkZeroAddress(_protocolConfig) onlyRole(protocolConfig.ADMIN_ROLE()) {
        address oldConfig = address(protocolConfig);
        protocolConfig = IProtocolConfig(_protocolConfig);
        emit ProtocolConfigUpdated(oldConfig, _protocolConfig);
    }

    function setLendingVault(address _lendingVault) external checkZeroAddress(_lendingVault) onlyRole(protocolConfig.ADMIN_ROLE()) {
        address oldVault = lendingVault;
        lendingVault = _lendingVault;
        
        emit LendingVaultUpdated(oldVault, _lendingVault);
    }

    function setLiquidationEngine(address _liquidationEngine) external checkZeroAddress(_liquidationEngine) onlyRole(protocolConfig.ADMIN_ROLE()) {
        address oldEngine = liquidationEngine;
        liquidationEngine = _liquidationEngine;
        
        emit LiquidationEngineUpdated(oldEngine, _liquidationEngine);
    }

    function setStabilityFund(address _stabilityFund) external checkZeroAddress(_stabilityFund) onlyRole(protocolConfig.ADMIN_ROLE()) {
        address oldFund = stabilityFund;
        stabilityFund = _stabilityFund;
        emit StabilityFundUpdated(oldFund, _stabilityFund);
    }

    function setSwapSlippageBps(uint256 _bps) external onlyRole(protocolConfig.ADMIN_ROLE()) {
        if (_bps > 2000) revert Treasury__InvalidAmount();
        uint256 old = swapSlippageBps;
        swapSlippageBps = _bps;
        emit SwapSlippageUpdated(old, _bps);
    }

    function setOracleStaleAfter(uint256 _seconds) external onlyRole(protocolConfig.ADMIN_ROLE()) validateAmount(_seconds) {
        uint256 old = oracleStaleAfter;
        oracleStaleAfter = _seconds;
        emit OracleStaleAfterUpdated(old, _seconds);
    }

    function setSwapDeadlineSeconds(uint256 _seconds) external onlyRole(protocolConfig.ADMIN_ROLE()) validateAmount(_seconds) {
        uint256 old = swapDeadlineSeconds;
        swapDeadlineSeconds = _seconds;
        emit SwapDeadlineSecondsUpdated(old, _seconds);
    }

    function withdrawPUSD(uint256 _amount) external onlyRole(protocolConfig.ADMIN_ROLE()) validateAmount(_amount) {
        if (pusdBalance < _amount) revert Treasury__InsufficientPusdBalance(_amount, pusdBalance);

        pusdBalance -= _amount;
        IERC20(pusd).safeTransfer(msg.sender, _amount);

        emit PusdWithdrawn(pusd, _amount);
    }

    function withdrawWstETH(uint256 _amount) external onlyRole(protocolConfig.ADMIN_ROLE()) validateAmount(_amount) {
        if (wstETHBalance < _amount) revert Treasury__InsufficientWstETHBalance(_amount, wstETHBalance);

        wstETHBalance -= _amount;
        IERC20(wstETH).safeTransfer(msg.sender, _amount);

        emit WstETHWithdrawn(wstETH, _amount);
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

    function receivePUSD(
        uint256 _pusdAmount
    ) external onlyAuthorizedOrAdmin whenNotPaused validateAmount(_pusdAmount) {
        pusdBalance += _pusdAmount;
        
        IERC20(pusd).safeTransferFrom(msg.sender, address(this), _pusdAmount);
        
        emit PusdReceived(pusd, _pusdAmount);
    }

    function receiveWstETH(
        uint256 _wstETHAmount
    ) external onlyAuthorizedOrAdmin whenNotPaused validateAmount(_wstETHAmount) {
        wstETHBalance += _wstETHAmount;

        IERC20(wstETH).safeTransferFrom(msg.sender, address(this), _wstETHAmount);
        
        emit WstETHReceived(wstETH, _wstETHAmount);
    }

    function swapPusdForWstETH(uint256 _amountIn)
        external
        onlyRole(protocolConfig.ADMIN_ROLE())
        nonReentrant
        whenNotPaused
        validateAmount(_amountIn)
        checkZeroAddress(pusd)
        checkZeroAddress(wstETH)
        returns (uint256 amountOut)
    {
        if (pusdBalance < _amountIn) revert Treasury__InsufficientPusdBalance(_amountIn, pusdBalance);

        amountOut = _swap(pusd, wstETH, _amountIn);

        pusdBalance -= _amountIn;
        wstETHBalance += amountOut;

        emit PusdSwapped(pusd, wstETH, _amountIn, amountOut);
    }

    function swapWstETHForPusd(uint256 _amountIn)
        external
        onlyRole(protocolConfig.ADMIN_ROLE())
        nonReentrant
        whenNotPaused
        validateAmount(_amountIn)
        checkZeroAddress(wstETH)
        checkZeroAddress(pusd)
        returns (uint256 amountOut)
    {
        if (wstETHBalance < _amountIn) revert Treasury__InsufficientWstETHBalance(_amountIn, wstETHBalance);

        amountOut = _swap(wstETH, pusd, _amountIn);

        wstETHBalance -= _amountIn;
        pusdBalance += amountOut;

        emit WstETHSwapped(wstETH, pusd, _amountIn, amountOut);
    }

    function provideBackstopFunds(
        uint256 _amount
    ) external onlyAuthorized nonReentrant whenNotPaused validateAmount(_amount) returns (uint256 providedAmount) {

        // Use actual ERC20 balance to allow donated PUSD to be used for protocol health
        uint256 actualBalance = IERC20(pusd).balanceOf(address(this));
        providedAmount = actualBalance < _amount ? actualBalance : _amount;

        uint256 shortfall = _amount - providedAmount;
        if (shortfall > 0) {
            backstopIouPusd += shortfall;
            emit BackstopIOUCreated(msg.sender, _amount, providedAmount, shortfall);
        }

        if (providedAmount > 0) {
            totalBackstopUsed += providedAmount;
            // Only reduce pusdBalance if we have tracked balance, otherwise leave it as is
            if (pusdBalance >= providedAmount) {
                pusdBalance -= providedAmount;
            } else {
                // If provided amount exceeds tracked balance, we're using donated funds
                // Set tracked balance to 0 and the difference is from donations
                pusdBalance = 0;
            }
            IERC20(pusd).safeTransfer(msg.sender, providedAmount);
        }
        
        emit BackstopFundsUsed(pusd, _amount, providedAmount, msg.sender);
    }

    function repayBackstopIou(uint256 _pusdAmount, uint256 _wstETHAmount)
        external
        onlyRole(protocolConfig.ADMIN_ROLE())
        nonReentrant
        whenNotPaused
        returns (uint256 pusdValueUsed, uint256 remainingIOU)
    {
        _validateRepaymentInputs(_pusdAmount, _wstETHAmount);
        
        _receiveRepaymentFunds(_pusdAmount, _wstETHAmount);
        
        uint256 totalRepaymentValue = _processRepaymentTokens(_pusdAmount, _wstETHAmount);
        
        pusdValueUsed = _applyRepaymentToIOU(totalRepaymentValue);
        remainingIOU = backstopIouPusd;

        emit BackstopIouRepaid(msg.sender, _pusdAmount, _wstETHAmount, pusdValueUsed, remainingIOU);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Executes a Uniswap V3 exactInputSingle swap using ProtocolConfig's router.
     *      - Computes a conservative minAmountOut via oracle price and slippage configuration.
     *      - Temporarily approves the router for the exact input amount and resets to zero after swap.
     * @param _tokenIn  Address of the input token (PUSD or wstETH)
     * @param _tokenOut Address of the output token (wstETH or PUSD)
     * @param _amountIn Amount of input tokens to swap
     * @return amountOut Amount of output tokens received
     */
    function _swap(address _tokenIn, address _tokenOut, uint256 _amountIn) internal returns (uint256 amountOut) {
        ISwapRouter swapRouter = protocolConfig.swapRouter();
        uint256 minAmountOut = _computeMinAmountOut(_tokenIn, _tokenOut, _amountIn);
        if (minAmountOut == 0) revert Treasury__InvalidAmount();

        // Approve router for the exact amount, then reset to 0 after swap
        address routerAddr = address(swapRouter);
        IERC20(_tokenIn).approve(routerAddr, 0);
        IERC20(_tokenIn).approve(routerAddr, _amountIn);

        amountOut = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: uint24(protocolConfig.uniswapFee()),
                recipient: address(this),
                deadline: block.timestamp + swapDeadlineSeconds,
                amountIn: _amountIn,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );

        // Reset allowance back to zero to avoid lingering approvals
        IERC20(_tokenIn).approve(routerAddr, 0);

        if (amountOut < minAmountOut) revert Treasury__InvalidAmount();
    }

    /**
     * @dev Computes minimum acceptable output for a swap based on oracle price and configured slippage.
     *      If a Quoter minimum is available and lower (more conservative), it replaces the oracle-based min.
     * @param _tokenIn  Address of the input token
     * @param _tokenOut Address of the output token
     * @param _amountIn Amount of input token
     * @return minAmountOut Minimum acceptable output amount
     */
    function _computeMinAmountOut(address _tokenIn, address _tokenOut, uint256 _amountIn) internal returns (uint256 minAmountOut) {
        (uint256 price, uint8 oracleDecimals) = _getOraclePrice();

        uint256 oracleQuote;
        if (_tokenIn == pusd && _tokenOut == wstETH) {
            // wstETH out = PUSD in * 10^decimals / price
            oracleQuote = Math.mulDiv(_amountIn, 10 ** oracleDecimals, price);
        } else if (_tokenIn == wstETH && _tokenOut == pusd) {
            // PUSD out = wstETH in * price / 10^decimals
            oracleQuote = Math.mulDiv(_amountIn, price, 10 ** oracleDecimals);
        }

        minAmountOut = Math.mulDiv(oracleQuote, (BPS_DENOMINATOR - swapSlippageBps), BPS_DENOMINATOR);

        (bool hasQuoterMin, uint256 quoterMinOut) = _getQuoterMinAmountOut(_tokenIn, _tokenOut, _amountIn);
        if (hasQuoterMin && quoterMinOut < minAmountOut) {
            minAmountOut = quoterMinOut;
        }
    }

    /**
     * @dev Reads and validates oracle price. Ensures answer > 0, not stale, and valid round linkage.
     * @return price Oracle price as uint256
     * @return oracleDecimals Number of decimals of the oracle feed
     */
    function _getOraclePrice() internal view returns (uint256 price, uint8 oracleDecimals) {
        (uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredInRound) = protocolConfig.oracle().latestRoundData();
        if (answer <= 0) revert Treasury__InvalidAmount();
        if (updatedAt == 0 || block.timestamp - updatedAt > oracleStaleAfter) revert Treasury__StaleOraclePrice();
        if (answeredInRound < roundId) revert Treasury__InvalidOracleRound();
        oracleDecimals = protocolConfig.oracle().decimals();
        price = uint256(answer);
    }

    /**
     * @dev Queries Uniswap V3 QuoterV2 for a simulated output and converts it to a conservative minimum
     *      using the configured slippage. Swallows failures and returns (false,0) if quoter reverts.
     * @param _tokenIn Address of the input token
     * @param _tokenOut Address of the output token
     * @param _amountIn Amount of input token
     * @return hasMin True if quoter returned a value
     * @return quoterMinOut Conservative minimum out from quoter
     */
    function _getQuoterMinAmountOut(address _tokenIn, address _tokenOut, uint256 _amountIn) internal returns (bool hasMin, uint256 quoterMinOut) {
        try IQuoterV2(address(protocolConfig.quoter())).quoteExactInputSingle(IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: _tokenIn,
            tokenOut: _tokenOut,
            amountIn: _amountIn,
            fee: uint24(protocolConfig.uniswapFee()),
            sqrtPriceLimitX96: 0
        })) returns (uint256 out, uint160 /*sp*/, uint32 /*ticks*/, uint256 /*gasEst*/) {
            quoterMinOut = (out * (BPS_DENOMINATOR - swapSlippageBps)) / BPS_DENOMINATOR;
            hasMin = true;
        } catch {}
    }

    /**
     * @dev Validates repayment inputs and that an IOU is currently open.
     * @param _pusdAmount Amount of PUSD to repay
     * @param _wstETHAmount Amount of wstETH to swap
     */
    function _validateRepaymentInputs(uint256 _pusdAmount, uint256 _wstETHAmount) internal view {
        if (backstopIouPusd == 0) revert Treasury__NoIOUOpen();
        if (_pusdAmount == 0 && _wstETHAmount == 0) revert Treasury__InvalidAmount();
    }

    /**
     * @dev Pulls repayment tokens from caller and updates internal balances accordingly.
     * @param _pusdAmount Amount of PUSD to repay
     * @param _wstETHAmount Amount of wstETH to swap
     */
    function _receiveRepaymentFunds(uint256 _pusdAmount, uint256 _wstETHAmount) internal {
        if (_pusdAmount > 0) {
            pusdBalance += _pusdAmount;
            IERC20(pusd).safeTransferFrom(msg.sender, address(this), _pusdAmount);
        }
        if (_wstETHAmount > 0) {
            wstETHBalance += _wstETHAmount;
            IERC20(wstETH).safeTransferFrom(msg.sender, address(this), _wstETHAmount);
        }
    }

    /**
     * @dev Processes provided repayment tokens; swaps wstETH to PUSD when needed and returns total PUSD available.
     * @param _pusdAmount Amount of PUSD to repay
     * @param _wstETHAmount Amount of wstETH to swap
     * @return totalPusdRepayment Total PUSD available for IOU repayment
     */
    function _processRepaymentTokens(uint256 _pusdAmount, uint256 _wstETHAmount) internal returns (uint256) {
        uint256 totalPusdRepayment = _pusdAmount;
        
        if (_wstETHAmount > 0) {
            uint256 pusdFromSwap = _swapWstETHToPusd(_wstETHAmount);
            totalPusdRepayment += pusdFromSwap;
        }
        
        return totalPusdRepayment;
    }


    /**
     * @dev Swaps wstETH to PUSD via internal _swap and updates tracked balances.
     * @param _wstETHAmount Amount of wstETH to swap
     * @return pusdReceived Amount of PUSD received
     */
    function _swapWstETHToPusd(uint256 _wstETHAmount) internal returns (uint256 pusdReceived) {
        pusdReceived = _swap(wstETH, pusd, _wstETHAmount);
        
        wstETHBalance -= _wstETHAmount;
        pusdBalance += pusdReceived;
    }

    /**
     * @dev Applies repayment value to outstanding IOU, capped at remaining backstop IOU amount.
     * @return appliedValue Actual PUSD value applied to IOU
     */
    function _applyRepaymentToIOU(uint256 _totalRepaymentValue) internal returns (uint256 appliedValue) {
        appliedValue = _totalRepaymentValue;
        if (appliedValue > backstopIouPusd) {
            appliedValue = backstopIouPusd;
        }
        
        backstopIouPusd -= appliedValue;

        if (appliedValue > 0) {
            _forwardRepaymentToStabilityFund(appliedValue);
        }
    }

    /**
    * @dev Forwards repaid PUSD to StabilityFund to fulfill original backstop request
    * @dev Calls StabilityFund's receiveBackstopRepayment to properly track IOU reduction
    */
    function _forwardRepaymentToStabilityFund(uint256 _pusdAmount) internal {
        pusdBalance -= _pusdAmount;
        
        // Approve StabilityFund to pull the repayment
        IERC20(pusd).approve(stabilityFund, _pusdAmount);
        
        // Call StabilityFund's receiveBackstopRepayment to handle IOU tracking and exchange rate adjustment
        IStabilityFund(stabilityFund).receiveBackstopRepayment(_pusdAmount);
        
        emit BackstopRepaymentForwarded(stabilityFund, _pusdAmount);
    }

    /**
     * @notice Required override for UUPS upgrades
     */
    function _authorizeUpgrade(address _newImplementation) internal override onlyRole(protocolConfig.UPGRADER_ROLE()) {}
}