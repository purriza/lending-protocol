// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {TestSetup} from "../../TestSetup.t.sol";

import {LendingVault} from "../../../contracts/LendingVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";

/*//////////////////////////////////////////////////////////////
                    DEPOSIT INVARIANT TEST
//////////////////////////////////////////////////////////////*/

contract DepositInvariantTest is StdInvariant, TestSetup {
    
    DepositHandler public handler;
    
    function setUp() public override {
        super.setUp();
        
        // Create handler for invariant testing
        handler = new DepositHandler(lendingVault, wstETH, user1, user2, user3, INITIAL_COLLATERAL);
        
        // Set handler as target for invariant testing
        targetContract(address(handler));
    }
    
    /// @dev The core invariant: total collateral should always equal sum of user positions
    function invariant_TotalCollateralEqualsSumOfPositions() public view {
        uint256 totalCollateral = lendingVault.totalCollateral();
        uint256 sumOfUserCollateral = 0;
        
        // Sum up all user positions
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        
        for (uint256 i = 0; i < users.length; i++) {
            (uint256 collateral, , , bool exists) = lendingVault.getPosition(users[i]);
            if (exists) {
                sumOfUserCollateral += collateral;
            }
        }
        
        assertEq(totalCollateral, sumOfUserCollateral, "Total collateral should equal sum of user positions");
    }
    
    /// @dev Invariant: vault token balance should equal total collateral
    function invariant_VaultBalanceEqualsTotalCollateral() public view {
        uint256 vaultBalance = wstETH.balanceOf(address(lendingVault));
        uint256 totalCollateral = lendingVault.totalCollateral();
        
        assertEq(vaultBalance, totalCollateral, "Vault balance should equal total collateral");
    }
    
    /// @dev Invariant: user positions should always have positive collateral when they exist
    function invariant_UserPositionsHavePositiveCollateral() public view {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        
        for (uint256 i = 0; i < users.length; i++) {
            (uint256 collateral, , , bool exists) = lendingVault.getPosition(users[i]);
            if (exists) {
                assertGt(collateral, 0, "User position should have positive collateral");
            }
        }
    }
    
    /// @dev Invariant: health ratios should always be positive for existing positions
    function invariant_HealthRatiosArePositive() public view {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        
        for (uint256 i = 0; i < users.length; i++) {
            (, , uint256 healthRatio, bool exists) = lendingVault.getPosition(users[i]);
            if (exists) {
                assertGt(healthRatio, 0, "Health ratio should be positive for existing positions");
            }
        }
    }
    
    /// @dev Invariant: total collateral should never decrease without explicit withdrawal
    function invariant_TotalCollateralNeverDecreases() public view {
        uint256 currentTotalCollateral = lendingVault.totalCollateral();
        
        // This invariant ensures that the total collateral only increases or stays the same
        // During deposit operations (withdrawals are not part of this invariant test)
        assertGe(currentTotalCollateral, handler.getInitialTotalCollateral(), 
                "Total collateral should never decrease during deposit operations");
    }
    
    /// @dev Invariant: user balances should be consistent with their positions
    function invariant_UserBalancesConsistent() public view {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        
        for (uint256 i = 0; i < users.length; i++) {
            (uint256 collateral, , , bool exists) = lendingVault.getPosition(users[i]);
            uint256 userBalance = wstETH.balanceOf(users[i]);
            uint256 initialBalance = handler.getInitialUserBalance(users[i]);
            uint256 minted = handler.mintedTo(users[i]);
            
            if (exists) {
                // User balance + collateral should equal initial balance + minted
                // This accounts for extra tokens minted by the handler to facilitate deposits
                assertEq(
                    userBalance + collateral,
                    initialBalance + minted,
                    "User balance + collateral should equal initial balance + minted"
                );
            }
        }
    }
}

/*//////////////////////////////////////////////////////////////
                    DEPOSIT HANDLER
//////////////////////////////////////////////////////////////*/

contract DepositHandler is Test {
    LendingVault public lendingVault;
    IERC20 public collateralToken;
    address public user1;
    address public user2;
    address public user3;
    uint256 public maxDepositAmount;
    
    mapping(address => uint256) public initialBalances;
    uint256 public initialTotalCollateral;
     mapping(address => uint256) public mintedTo;
    
    constructor(LendingVault _lendingVault, IERC20 _collateralToken, address _user1, address _user2, address _user3, uint256 _maxDepositAmount) {
        lendingVault = _lendingVault;
        collateralToken = _collateralToken;
        user1 = _user1;
        user2 = _user2;
        user3 = _user3;
        maxDepositAmount = _maxDepositAmount;
        
        // Store initial balances
        initialBalances[user1] = collateralToken.balanceOf(user1);
        initialBalances[user2] = collateralToken.balanceOf(user2);
        initialBalances[user3] = collateralToken.balanceOf(user3);
        initialTotalCollateral = lendingVault.totalCollateral();
    }
    
    function deposit(uint8 userIndex, uint256 amount) public {
        address user = _getUserByIndex(userIndex % 3);
        
        // Bound the amount to reasonable values to avoid overflow
        amount = bound(amount, 1 ether, maxDepositAmount); // Use maxDepositAmount from constructor
        
        // Ensure user has enough balance
        uint256 userBalance = collateralToken.balanceOf(user);
        if (amount > userBalance) {
            // Mint additional tokens if needed
             uint256 toMint = amount - userBalance;
             MockERC20(address(collateralToken)).mint(user, toMint);
             mintedTo[user] += toMint;
        }
        
        // Ensure user has enough allowance
        uint256 allowance = collateralToken.allowance(user, address(lendingVault));
        if (amount > allowance) {
            vm.prank(user);
            collateralToken.approve(address(lendingVault), amount);
        }
        
        // Perform deposit
        vm.prank(user);
        try lendingVault.deposit(amount) {} catch {}
    }
    
    function depositWithMinRatio(uint8 userIndex, uint256 amount, uint256 minRatio) public {
        address user = _getUserByIndex(userIndex % 3);
        
        // Bound the parameters to reasonable values to avoid overflow
        amount = bound(amount, 1 ether, maxDepositAmount); // Use maxDepositAmount from constructor
        minRatio = bound(minRatio, 10000, 20000); // Reduced max ratio to 200%
        
        // Ensure user has enough balance
        uint256 userBalance = collateralToken.balanceOf(user);
        if (amount > userBalance) {
             uint256 toMint = amount - userBalance;
             MockERC20(address(collateralToken)).mint(user, toMint);
             mintedTo[user] += toMint;
        }
        
        // Ensure user has enough allowance
        uint256 allowance = collateralToken.allowance(user, address(lendingVault));
        if (amount > allowance) {
            vm.prank(user);
            collateralToken.approve(address(lendingVault), amount);
        }
        
        // Perform deposit with custom min ratio
        vm.prank(user);
        try lendingVault.deposit(amount, minRatio) {} catch {}
    }
    
    function _getUserByIndex(uint8 index) internal view returns (address) {
        if (index == 0) return user1;
        if (index == 1) return user2;
        return user3;
    }
    
    function getInitialUserBalance(address user) external view returns (uint256) {
        return initialBalances[user];
    }
    
    function getInitialTotalCollateral() external view returns (uint256) {
        return initialTotalCollateral;
    }
}
