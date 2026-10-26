// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/**
 * @title IPriceOracle
 * @notice Interface for price oracle contracts
 * @dev Provides price feeds for wstETH/ETH and other asset pairs
 */
interface IPriceOracle {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PriceUpdated(uint256 indexed price, uint256 timestamp);
    event StalenessPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);
    event EmergencyPauseToggled(bool paused);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error StalePrice();
    error InvalidPrice();
    error PriceOraclePaused();

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the latest price from the oracle
     * @return price The latest price in 18 decimals (wstETH per PUSD)
     * @return timestamp The timestamp of the price update
     */
    function getPrice() external view returns (uint256 price, uint256 timestamp);

    /**
     * @notice Gets the latest price with staleness check
     * @param maxStalenessPeriod Maximum time since last update (in seconds)
     * @return price The latest price in 18 decimals
     * @return timestamp The timestamp of the price update
     */
    function getPriceWithStalenessCheck(uint256 maxStalenessPeriod) 
        external 
        view 
        returns (uint256 price, uint256 timestamp);

    /**
     * @notice Gets TWAP (Time-Weighted Average Price) over a specified period
     * @param twapPeriod The period over which to calculate TWAP (in seconds)
     * @return twapPrice The TWAP price in 18 decimals
     */
    function getTWAP(uint256 twapPeriod) external view returns (uint256 twapPrice);

    /**
     * @notice Gets historical price at a specific timestamp
     * @param targetTimestamp The timestamp to get price for
     * @return price The price at the specified timestamp
     * @return actualTimestamp The actual timestamp of the closest price data
     */
    function getHistoricalPrice(uint256 targetTimestamp) 
        external 
        view 
        returns (uint256 price, uint256 actualTimestamp);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the decimals used by the oracle
     * @return decimals Number of decimals (typically 18)
     */
    function decimals() external view returns (uint8 decimals);

    /**
     * @notice Returns the description of the price feed
     * @return description Human-readable description
     */
    function description() external view returns (string memory description);

    /**
     * @notice Returns the current staleness period
     * @return staleness Maximum allowed staleness in seconds
     */
    function stalenessPeriod() external view returns (uint256 staleness);

    /**
     * @notice Checks if the oracle is currently paused
     * @return paused True if oracle is paused
     */
    function isPaused() external view returns (bool paused);

    /**
     * @notice Gets the latest round data (Chainlink-compatible)
     * @return roundId The round ID
     * @return answer The price answer
     * @return startedAt Timestamp when round started
     * @return updatedAt Timestamp when round was updated
     * @return answeredInRound The round ID that the answer was computed in
     */
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Updates the staleness period (admin only)
     * @param newStalenessPeriod New staleness period in seconds
     */
    function updateStalenessPeriod(uint256 newStalenessPeriod) external;

    /**
     * @notice Emergency pause/unpause the oracle (admin only)
     * @param paused True to pause, false to unpause
     */
    function setEmergencyPause(bool paused) external;

    /**
     * @notice Updates the price manually (admin only, for emergency situations)
     * @param newPrice New price in 18 decimals
     */
    function updatePriceManually(uint256 newPrice) external;
}
