// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IStabilityFund {

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PUSDDeposited(address indexed user, uint256 pusdAmount, uint256 wpusdMinted);
    event WPUSDRedeemed(address indexed user, uint256 wpusdAmount, uint256 pusdReceived);
    event ExchangeRateUpdated(uint256 indexed oldRate, uint256 indexed newRate, uint256 indexed timestamp);
    event LiquidationFundsSent(address indexed to, uint256 amount);
    event LendingVaultUpdated(address indexed oldVault, address indexed newVault);
    event LiquidationEngineUpdated(address indexed oldEngine, address indexed newEngine);
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event StabilityFundInitialized(
        address protocolConfig, 
        address pusd, 
        address wpusd, 
        uint256 exchangeRate,
        uint256 minDepositAmount
    );
    event MinDepositAmountUpdated(uint256 indexed oldMinDepositAmount, uint256 indexed newMinDepositAmount);
    event TokensRecovered(address indexed token, address indexed to, uint256 amount);
    event LiquidationReturnsReceived(address from, uint256 indexed pusdAmount, uint256 indexed excessAmount, uint256 indexed amountReceived);
    event BackstopIOURecorded(uint256 iouAmount, uint256 totalOutstandingIOU);
    event BackstopIOURepaid(uint256 iouReduction, uint256 remainingIOU, uint256 repaymentAmount);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error StabilityFund__CannotRecoverPUSD();
    error StabilityFund__InvalidAddress();
    error StabilityFund__InvalidAmount(uint256 amount);
    error StabilityFund__InsufficientBalance(uint256 balance, uint256 amount);
    error StabilityFund__UnauthorizedCaller(address caller);
    error StabilityFund__NoOutstandingIOU();

    /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function initialize(
        address _protocolConfig, 
        address _pusd, 
        address _wpusd
    ) external;

    /**
     * @notice Allows the admin to unpause the contract
     */
    function unpause() external;

    /**
     * @notice Allows the admin to pause the contract
     */
    function pause() external;

    /**
     * @notice Allows the admin to set the LendingVault address
     * @param _lendingVault The address of the LendingVault
     */
    function setLendingVault(address _lendingVault) external;

    /**
     * @notice Allows the admin to set the LiquidationEngine address
     * @param _liquidationEngine The address of the LiquidationEngine
     */
    function setLiquidationEngine(address _liquidationEngine) external;

    /**
     * @notice Allows the admin to set the Treasury address
     * @param _treasury The address of the Treasury
     */
    function setTreasury(address _treasury) external;

    /**
     * @notice Allows the admin to set the minimum deposit amount
     * @param _minDepositAmount The minimum deposit amount
     */
    function setMinDepositAmount(uint256 _minDepositAmount) external;

    /**
     * @notice Allows the admin to recover any ERC20 tokens that is not PUSD sent to the fund in error
     * @param _token The address of the token to recover
     */
    function recoverStuckTokens(address _token) external;

    /**
     * @notice Allows users to deposit PUSD into the StabilityFund
     * @param _pusdAmount The amount of PUSD to deposit
     * @return wpusdToMint The amount of wPUSD minted
     */
    function depositPUSD(uint256 _pusdAmount) external returns (uint256 wpusdToMint);

    /**
     * @notice Allows users to redeem wPUSD for PUSD at the current exchange rate
     * @param wpusdAmount The amount of wPUSD to redeem
     * @return pusdToReturn The amount of PUSD received
     */
    function redeemWPUSD(uint256 wpusdAmount) external returns (uint256 pusdToReturn);

    /**
     * @notice Sends PUSD to the LendingVault to be burned when a liquidation occurs
     * @param _amount The amount of PUSD to send
     * @return amountSent The amount of PUSD sent
     */
    function sendLiquidationFunds(uint256 _amount) external returns (uint256);

    /**
     * @notice Receives PUSD from the LiquidationEngine after a liquidation has occured
     * @notice The LiquidationEngine will swap a user's collateral for PUSD. It will then repay the PUSD sent from the Fund
     * @notice Any excess is split 20% to the Treasury and 80% back to the StabilityFund as yield for wPUSD holders
     * @param _pusdAmount The amount of PUSD to receive
     * @param _excessAmount The amount of PUSD that was not used
     * @param _iouAmount The amount of PUSD that is owed as IOU from Treasury backstop
     * @return amountReceived The amount of PUSD received
     */
    function receiveLiquidationReturns(uint256 _pusdAmount, uint256 _excessAmount, uint256 _iouAmount) external returns (uint256 amountReceived);

    /**
     * @notice Receives backstop IOU repayment from Treasury
     * @dev This function is called by Treasury when admin repays backstop IOUs via repayBackstopIou
     * @dev It reduces the outstanding IOU and adjusts the exchange rate upward accordingly
     * @dev Only callable by the Treasury contract
     * @param _repaymentAmount The amount of PUSD being repaid
     * @return iouReduction The amount of IOU reduced (capped at outstanding backstopIouAmount)
     */
    function receiveBackstopRepayment(uint256 _repaymentAmount) external returns (uint256 iouReduction);

    /**
     * @notice Returns the address of the LendingVault
     * @return The address of the LendingVault
     */
    function lendingVault() external view returns (address);

    /**
     * @notice Returns the address of the LiquidationEngine
     * @return The address of the LiquidationEngine
     */
    function liquidationEngine() external view returns (address);

    /**
     * @notice Returns the address of the Treasury
     * @return The address of the Treasury
     */
    function treasury() external view returns (address);

    /**
     * @notice Returns the current exchange rate
     * @return The current exchange rate
     */
    function exchangeRate() external view returns (uint256);

    /**
     * @notice Returns the total amount of PUSD locked in the StabilityFund
     * @return The total amount of PUSD locked
     */
    function totalPusdLocked() external view returns (uint256);

    /**
     * @notice Returns the precision used in the contract
     * @return The precision amount
     */
    function getPrecision() external pure returns (uint256);

    /**
     * @notice Returns the absolute minimum deposit amount
     * @return The absolute minimum deposit amount
     */
    function getAbsoluteMinDepositAmount() external pure returns (uint256);

    /**
     * @notice Returns the currently set minimum deposit amount
     * @return The minimum deposit amount
     */
    function getMinDepositAmount() external view returns (uint256);

    /**
     * @notice Returns the address of the PUSD token
     * @return The address of the PUSD token
     */
    function getPusdAddress() external view returns (address);

    /**
     * @notice Returns the address of the wPUSD token
     * @return The address of the wPUSD token
     */
    function getWpusdAddress() external view returns (address);

    /**
     * @notice Returns the outstanding backstop IOU amount
     * @return The outstanding IOU amount in PUSD
     */
    function backstopIouAmount() external view returns (uint256);
}