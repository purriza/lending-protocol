// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {ERC20BurnableUpgradeable, ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IPUSD} from "./interfaces/IPUSD.sol";
import {IProtocolConfig} from "./interfaces/IProtocolConfig.sol";

/**
 * @title PUSD
 * @notice The protocol's stablecoin token
 * @dev ERC20 token with mint/burn functionality restricted to authorized contracts
 */
contract PUSD is 
    IPUSD,
    ERC20BurnableUpgradeable,
    AccessControlEnumerableUpgradeable,
    UUPSUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                            STATE VARS
    //////////////////////////////////////////////////////////////*/

    IProtocolConfig public protocolConfig;

    address public lendingVault;
    address public stabilityFund;

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier onlyLendingVault() {
        if (msg.sender != lendingVault) revert PUSD__UnauthorizedMinter();
        _;
    }

    modifier onlyAuthorizedBurner() {
        if (msg.sender != lendingVault) revert PUSD__UnauthorizedBurner();
        _;
    }

    modifier checkZeroAddress(address _address) {
        if (_address == address(0)) revert PUSD__InvalidAddress();
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
        address _protocolConfig
    ) public initializer checkZeroAddress(_protocolConfig) {
        __ERC20_init("Protocol USD", "PUSD");
        __ERC20Burnable_init();
        __AccessControlEnumerable_init();
        __UUPSUpgradeable_init();

        protocolConfig = IProtocolConfig(_protocolConfig);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(protocolConfig.ADMIN_ROLE(), msg.sender);
        _grantRole(protocolConfig.UPGRADER_ROLE(), msg.sender);

        emit PUSDInitialized(_protocolConfig);
    }
    
    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setLendingVault(address _lendingVault) external onlyRole(protocolConfig.ADMIN_ROLE()) checkZeroAddress(_lendingVault) {
        address oldVault = lendingVault;
        lendingVault = _lendingVault;
        
        emit LendingVaultUpdated(oldVault, _lendingVault);
    }

    function setStabilityFund(address _stabilityFund) external onlyRole(protocolConfig.ADMIN_ROLE()) checkZeroAddress(_stabilityFund) {
        address oldFund = stabilityFund;
        stabilityFund = _stabilityFund;
        
        emit StabilityFundUpdated(oldFund, _stabilityFund);
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function mint(address to, uint256 amount) external onlyLendingVault {
        _mint(to, amount);
        emit PUSDMinted(to, amount);
    }

    function burn(uint256 amount) public override(ERC20BurnableUpgradeable, IPUSD) onlyAuthorizedBurner {
        super.burn(amount);
        emit PUSDBurned(msg.sender, amount);
    }

    function burnFrom(address /* account */, uint256 /* value */) public pure override {
        // Explicitly disable burnFrom - only authorized burners should burn PUSD through burn()
        // This prevents bypassing the onlyAuthorizedBurner modifier and maintains protocol invariants
        revert PUSD__UnauthorizedBurner();
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function decimals() public pure override(ERC20Upgradeable, IPUSD) returns (uint8) {
        return 18;
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Required override for UUPS upgrades
     */
    function _authorizeUpgrade(address _newImplementation) internal override onlyRole(protocolConfig.UPGRADER_ROLE()) {}
}