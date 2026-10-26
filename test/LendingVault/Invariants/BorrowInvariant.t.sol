// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {TestSetup} from "../../TestSetup.t.sol";

import {LendingVault} from "../../../contracts/LendingVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/*//////////////////////////////////////////////////////////////
                    BORROW INVARIANT TEST
//////////////////////////////////////////////////////////////*/

contract BorrowInvariantTest is StdInvariant, TestSetup {
    
    BorrowHandler public handler;
    
    function setUp() public override {
        super.setUp();
        
        // Setup initial positions for all users
        _setupInitialPositions();
        
        // Create handler for invariant testing
        handler = new BorrowHandler(lendingVault, pusd, user1, user2, user3);
        
        // Set handler as target for invariant testing
        targetContract(address(handler));
    }
    
    function _setupInitialPositions() internal {
        // Setup positions for all users
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        
        for (uint256 i = 0; i < users.length; i++) {
            // Ensure user has enough wstETH
            uint256 userBalance = wstETH.balanceOf(users[i]);
            if (userBalance < INITIAL_COLLATERAL) {
                wstETH.mint(users[i], INITIAL_COLLATERAL - userBalance);
            }
            
            vm.startPrank(users[i]);
            wstETH.approve(address(lendingVault), INITIAL_COLLATERAL);
            lendingVault.deposit(INITIAL_COLLATERAL);
            vm.stopPrank();
        }
    }
    
    /// @dev The core invariant: total debt should always equal sum of user debts
    function invariant_TotalDebtEqualsSumOfUserDebts() public view {
        uint256 totalDebt = lendingVault.totalDebt();
        uint256 sumOfUserDebts = 0;
        
        // Sum up all user debts
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        
        for (uint256 i = 0; i < users.length; i++) {
            (, uint256 debt, , bool exists) = lendingVault.getPosition(users[i]);
            if (exists) {
                sumOfUserDebts += debt;
            }
        }
        
        assertEq(totalDebt, sumOfUserDebts, "Total debt should equal sum of user debts");
    }
    
    /// @dev Invariant: vault PUSD balance should be zero between operations
    /// In this architecture, PUSD is minted to users on borrow and burned on repay,
    /// so the vault should not retain a PUSD balance after operations complete.
    function invariant_VaultPUSDBalanceConsistent() public view {
        uint256 vaultBalance = pusd.balanceOf(address(lendingVault));
        assertEq(vaultBalance, 0, "Vault PUSD balance should be zero");
    }
    
    /// @dev Invariant: user positions should always have valid debt amounts
    function invariant_UserPositionsHaveValidDebts() public view {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        
        for (uint256 i = 0; i < users.length; i++) {
            (uint256 collateral, uint256 debt, , bool exists) = lendingVault.getPosition(users[i]);
            if (exists) {
                assertGe(debt, 0, "User debt should be non-negative");
                
                // If user has debt, they should have collateral
                if (debt > 0) {
                    assertGt(collateral, 0, "User with debt should have collateral");
                }
            }
        }
    }
    
    /// @dev Invariant: health ratios should always be above minimum for positions with debt
    function invariant_HealthRatiosAboveMinimum() public view {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        
        for (uint256 i = 0; i < users.length; i++) {
            (, uint256 debt, uint256 healthRatio, bool exists) = lendingVault.getPosition(users[i]);
            if (exists && debt > 0) {
                uint256 minRatio = lendingVault.protocolConfig().minCollateralRatio();
                // HealthRatio is expressed in basis points (same unit as minRatio)
                assertGe(healthRatio, minRatio, "Health ratio should be above minimum for positions with debt");
            }
        }
    }
    
    /// @dev Invariant: total debt should never exceed debt ceiling
    function invariant_TotalDebtNeverExceedsCeiling() public view {
        uint256 totalDebt = lendingVault.totalDebt();
        uint256 debtCeiling = lendingVault.protocolConfig().debtCeiling();
        
        assertLe(totalDebt, debtCeiling, "Total debt should never exceed debt ceiling");
    }
    
    /// @dev Invariant: user PUSD balances should be consistent with their borrows
    function invariant_UserPUSDBalancesConsistent() public view {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        
        for (uint256 i = 0; i < users.length; i++) {
            uint256 userBalance = pusd.balanceOf(users[i]);
            uint256 initialBalance = handler.getInitialUserBalance(users[i]);
            uint256 borrowedAmount = handler.getUserBorrowedAmount(users[i]);
            
            // User balance should be initial balance plus borrowed amount
            assertEq(userBalance, initialBalance + borrowedAmount, 
                    "User PUSD balance should be initial balance plus borrowed amount");
        }
    }
    
    /// @dev Invariant: collateral ratios should always be valid
    function invariant_CollateralRatiosValid() public view {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        
        for (uint256 i = 0; i < users.length; i++) {
            (, uint256 debt, uint256 healthRatio, bool exists) = lendingVault.getPosition(users[i]);
            if (exists && debt > 0) {
                // Health ratio is already in basis points using oracle USD value
                uint256 minRatio = lendingVault.protocolConfig().minCollateralRatio();
                assertGe(healthRatio, minRatio, "Health ratio should be above minimum");
            }
        }
    }
    
    /// @dev Invariant: no user can borrow more than their max borrow limit
    function invariant_NoUserExceedsMaxBorrow() public view {
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        
        for (uint256 i = 0; i < users.length; i++) {
            (, uint256 debt, uint256 healthRatio, bool exists) = lendingVault.getPosition(users[i]);
            if (exists && debt > 0) {
                uint256 minRatio = lendingVault.protocolConfig().minCollateralRatio();
                assertGe(healthRatio, minRatio, "User health ratio must be >= min ratio");
            }
        }
    }
}

/*//////////////////////////////////////////////////////////////
                    BORROW HANDLER
//////////////////////////////////////////////////////////////*/

contract BorrowHandler is Test {
    LendingVault public lendingVault;
    IERC20 public pusdToken;
    address public user1;
    address public user2;
    address public user3;
    
    mapping(address => uint256) public initialBalances;
    mapping(address => uint256) public borrowedAmounts;
    uint256 public initialVaultBalance;
    uint256 public initialTotalDebt;
    
    constructor(LendingVault _lendingVault, IERC20 _pusdToken, address _user1, address _user2, address _user3) {
        lendingVault = _lendingVault;
        pusdToken = _pusdToken;
        user1 = _user1;
        user2 = _user2;
        user3 = _user3;
        
        // Store initial balances
        initialBalances[user1] = pusdToken.balanceOf(user1);
        initialBalances[user2] = pusdToken.balanceOf(user2);
        initialBalances[user3] = pusdToken.balanceOf(user3);
        initialVaultBalance = pusdToken.balanceOf(address(lendingVault));
        initialTotalDebt = lendingVault.totalDebt();
    }
    
    function borrow(uint8 userIndex, uint256 amount) public {
        address user = _getUserByIndex(userIndex % 3);
        
        // Bound the amount to reasonable values to avoid overflow
        amount = bound(amount, 1 ether, 10_000 ether); // Use 10k PUSD (BORROW_AMOUNT equivalent)
        
        // Check if user can borrow this amount
        uint256 maxBorrow = lendingVault.getMaxBorrow(user);
        if (amount > maxBorrow) {
            // Skip this test case if amount exceeds max borrow
            return;
        }
        
        // Perform borrow
        vm.prank(user);
        try lendingVault.borrow(amount) {
            // Update borrowed amount if successful
            borrowedAmounts[user] += amount;
        } catch {}
    }
    
    function borrowMultiple(uint8 userIndex, uint256 amount, uint8 iterations) public {
        address user = _getUserByIndex(userIndex % 3);
        
        // Bound the parameters to reasonable values to avoid overflow
        amount = bound(amount, 1 ether, 5_000 ether); // Use 5k PUSD (BORROW_AMOUNT / 2) instead of hardcoded 750k ether
        iterations = uint8(bound(iterations, 1, 3)); // Reduced max iterations
        
        uint256 totalAmount = amount * iterations;
        uint256 maxBorrow = lendingVault.getMaxBorrow(user);
        
        if (totalAmount > maxBorrow) {
            // Skip this test case if total amount exceeds max borrow
            return;
        }
        
        // Perform multiple borrows
        vm.startPrank(user);
        for (uint256 i = 0; i < iterations; i++) {
            try lendingVault.borrow(amount) {
                borrowedAmounts[user] += amount;
            } catch {
                break; // Stop if one borrow fails
            }
        }
        vm.stopPrank();
    }
    
    function _getUserByIndex(uint8 index) internal view returns (address) {
        if (index == 0) return user1;
        if (index == 1) return user2;
        return user3;
    }
    
    function getInitialUserBalance(address user) external view returns (uint256) {
        return initialBalances[user];
    }
    
    function getUserBorrowedAmount(address user) external view returns (uint256) {
        return borrowedAmounts[user];
    }
    
    function getInitialVaultBalance() external view returns (uint256) {
        return initialVaultBalance;
    }
    
    function getInitialTotalDebt() external view returns (uint256) {
        return initialTotalDebt;
    }
}
