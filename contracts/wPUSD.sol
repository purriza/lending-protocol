// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {ERC20Upgradeable, ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IwPUSD} from "./interfaces/IwPUSD.sol";
import {IProtocolConfig} from "./interfaces/IProtocolConfig.sol";

/**
 * @title wPUSD
 * @notice Yield bearing wrapped PUSD token minted by the Stability Fund
 */
contract wPUSD is 
    IwPUSD,
    ERC20BurnableUpgradeable,
    AccessControlEnumerableUpgradeable, 
    UUPSUpgradeable 
{
    IProtocolConfig public protocolConfig;

    address public stabilityFund;

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyStabilityFund() {
        if (msg.sender != stabilityFund) revert wPUSD__UnauthorizedCaller(msg.sender);
        _;
    }

    modifier checkZeroAddress(address _address) {
        if (_address == address(0)) revert wPUSD__InvalidAddress();
        _;
    }

    modifier validateAmount(uint256 _amount) {
        if (_amount == 0) revert wPUSD__InvalidAmount();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _protocolConfig) public initializer checkZeroAddress(_protocolConfig) {
        __ERC20_init("Wrapped Protocol USD", "wPUSD");
        __ERC20Burnable_init();
        __AccessControlEnumerable_init();
        __UUPSUpgradeable_init();

        protocolConfig = IProtocolConfig(_protocolConfig);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(protocolConfig.ADMIN_ROLE(), msg.sender);
        _grantRole(protocolConfig.UPGRADER_ROLE(), msg.sender);

        emit wPUSDInitialized(_protocolConfig);
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setStabilityFund(address _stabilityFund) external onlyRole(protocolConfig.ADMIN_ROLE()) checkZeroAddress(_stabilityFund) {
        address oldFund = stabilityFund;
        stabilityFund = _stabilityFund;
        
        emit StabilityFundUpdated(oldFund, _stabilityFund);
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function mint(address _to, uint256 _amount) external onlyStabilityFund checkZeroAddress(_to) validateAmount(_amount) {
        _mint(_to, _amount);
        emit WPUSDMinted(_to, _amount);
    }

    function burn(uint256 _amount) public override(ERC20BurnableUpgradeable, IwPUSD) onlyStabilityFund validateAmount(_amount) {
        super.burn(_amount);
        emit WPUSDBurned(_amount);
    }

    function burnFrom(address /* _account */, uint256 /* _value */) public view override onlyStabilityFund {
        // Explicitly disable burnFrom - only StabilityFund should burn wPUSD through burn()
        revert wPUSD__UnauthorizedCaller(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function decimals() public pure override(ERC20Upgradeable, IwPUSD) returns (uint8) {
        return 18;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address _newImplementation) internal override onlyRole(protocolConfig.UPGRADER_ROLE()) {}
}