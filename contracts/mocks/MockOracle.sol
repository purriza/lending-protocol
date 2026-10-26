// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../interfaces/IPriceOracle.sol";

contract MockOracle is IPriceOracle {
    uint8 private _decimals;
    int256 private _answer;
    uint256 private _updatedAt;
    bool public simulateFailure;
    bool public simulateGetPriceFailure;
    bool public simulateLatestRoundDataFailure;
    uint80 private _roundId;
    uint80 private _answeredInRound;

    constructor(uint8 decimals_, int256 answer_, uint256 updatedAt_) {
        _decimals = decimals_;
        _answer = answer_;
        _updatedAt = updatedAt_;
        simulateFailure = false;
        simulateGetPriceFailure = false;
        simulateLatestRoundDataFailure = false;
        _roundId = 1;
        _answeredInRound = 1;
    }

    function setDecimals(uint8 decimals_) external { _decimals = decimals_; }
    function setAnswer(int256 answer_) external { _answer = answer_; }
    function setUpdatedAt(uint256 updatedAt_) external { _updatedAt = updatedAt_; }
    function setSimulateFailure(bool _simulateFailure) external { simulateFailure = _simulateFailure; }
    function setSimulateGetPriceFailure(bool _simulateGetPriceFailure) external { simulateGetPriceFailure = _simulateGetPriceFailure; }
    function setSimulateLatestRoundDataFailure(bool _simulateLatestRoundDataFailure) external { simulateLatestRoundDataFailure = _simulateLatestRoundDataFailure; }
    function setRoundId(uint80 roundId_) external { _roundId = roundId_; }
    function setAnsweredInRound(uint80 answeredInRound_) external { _answeredInRound = answeredInRound_; }

    function decimals() external view override returns (uint8) { 
        return _decimals; 
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        if (simulateLatestRoundDataFailure || simulateFailure) {
            revert("MockOracle: Simulated latestRoundData failure");
        }
        return (_roundId, _answer, _updatedAt, _updatedAt, _answeredInRound);
    }

    // Implement other IPriceOracle functions with basic implementations
    function getPrice() external view override returns (uint256 price, uint256 timestamp) {
        if (simulateGetPriceFailure || simulateFailure) {
            revert("MockOracle: Simulated getPrice failure");
        }
        return (uint256(_answer), _updatedAt);
    }

    function getPriceWithStalenessCheck(uint256 /* maxStalenessPeriod */) 
        external 
        view 
        override 
        returns (uint256 price, uint256 timestamp) 
    {
        return (uint256(_answer), _updatedAt);
    }

    function getTWAP(uint256 /* twapPeriod */) external view override returns (uint256 twapPrice) {
        return uint256(_answer);
    }

    function getHistoricalPrice(uint256 /* targetTimestamp */) 
        external 
        view 
        override 
        returns (uint256 price, uint256 actualTimestamp) 
    {
        return (uint256(_answer), _updatedAt);
    }

    function description() external pure override returns (string memory) {
        return "Mock Oracle";
    }

    function stalenessPeriod() external pure override returns (uint256) {
        return 3600; // 1 hour
    }

    function isPaused() external pure override returns (bool) {
        return false;
    }

    function updateStalenessPeriod(uint256 /* newStalenessPeriod */) external pure override {
        // Mock implementation
    }

    function setEmergencyPause(bool /* paused */) external pure override {
        // Mock implementation
    }

    function updatePriceManually(uint256 newPrice) external override {
        _answer = int256(newPrice);
        _updatedAt = block.timestamp;
    }
}


