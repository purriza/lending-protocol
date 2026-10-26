// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockCollateralToken
 * @notice Mock ERC20 token for testing collateral functionality (deployable on testnets)
 */
contract MockCollateralToken is ERC20, Ownable {
    event TokensMinted(address indexed to, uint256 amount);
    event TokensBurned(address indexed from, uint256 amount);

    error InvalidAddress();

    constructor(
        address _owner,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) Ownable(_owner) {
        if (_owner == address(0)) revert InvalidAddress();
    }

    function mint(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert InvalidAddress();
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    function burn(address from, uint256 amount) external onlyOwner {
        if (from == address(0)) revert InvalidAddress();
        _burn(from, amount);
        emit TokensBurned(from, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
        emit TokensBurned(msg.sender, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}


