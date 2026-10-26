// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {TestSetup, StabilityFundHarness} from "../../TestSetup.t.sol";

import {StabilityFund} from "../../../contracts/StabilityFund.sol";
import {PUSD} from "../../../contracts/PUSD.sol";
import {wPUSD} from "../../../contracts/wPUSD.sol";

/*//////////////////////////////////////////////////////////////
                    DEPOSIT INVARIANT TEST
//////////////////////////////////////////////////////////////*/

contract DepositInvariantTest is StdInvariant, TestSetup {
    
    DepositHandler public handler;
    
    function setUp() public override{
        super.setUp();

        _mintPUSD(user1, INITIAL_PUSD_AMOUNT);
        _mintPUSD(user2, INITIAL_PUSD_AMOUNT);
        
        // Create handler for invariant testing
        handler = new DepositHandler(StabilityFundHarness(address(stabilityFund)), pusd, wpusd, user1, user2, user3, admin);
        
        // Set handler as target for invariant testing
        targetContract(address(handler));
        
        // Give the handler some PUSD to work with for deposits
        vm.prank(address(lendingVault));
        pusd.mint(address(handler), 1_000_000 ether);
    }
    
    /// @dev The core invariant: total wPUSD minted ≤ total PUSD received across lifetime
    function invariant_TotalWPUSDMintedLessOrEqualTotalPUSDReceived() public view {
        uint256 totalWPUSDMinted = handler.ghost_totalWPUSDMinted();
        uint256 totalPUSDReceived = handler.ghost_totalPUSDReceived();
        
        // The fundamental invariant: we should never mint more wPUSD than the PUSD we received
        // This accounts for exchange rate changes - even if exchange rate increases,
        // the total value minted should not exceed what was deposited
        assertLe(
            totalWPUSDMinted, 
            totalPUSDReceived, 
            "Total wPUSD minted should never exceed total PUSD received"
        );
    }
    
    /// @dev Additional invariant: StabilityFund's PUSD balance + liquidation funds sent should equal total deposits
    function invariant_PUSDAccountingBalance() public view {
        uint256 currentPUSDBalance = pusd.balanceOf(address(stabilityFund));
        uint256 totalDeposited = handler.ghost_totalPUSDReceived();
        uint256 totalRedeemed = handler.ghost_totalPUSDRedeemed();
        uint256 totalLiquidationFundsSent = handler.ghost_totalLiquidationFundsSent();
        
        // Balance should equal: total deposited - total redeemed - liquidation funds sent
        uint256 expectedBalance = totalDeposited - totalRedeemed - totalLiquidationFundsSent;
        
        assertEq(
            currentPUSDBalance,
            expectedBalance,
            "StabilityFund PUSD balance accounting mismatch"
        );
    }
    
    /// @dev Invariant: wPUSD total supply should match total minted minus total burned
    function invariant_WPUSDSupplyAccounting() public view {
        uint256 currentWPUSDSupply = wpusd.totalSupply();
        uint256 totalMinted = handler.ghost_totalWPUSDMinted();
        uint256 totalBurned = handler.ghost_totalWPUSDBurned();
        
        assertEq(
            currentWPUSDSupply,
            totalMinted - totalBurned,
            "wPUSD total supply should equal total minted minus total burned"
        );
    }
}

/*//////////////////////////////////////////////////////////////
                    DEPOSIT HANDLER
//////////////////////////////////////////////////////////////*/

contract DepositHandler is Test {
    StabilityFundHarness public stabilityFund;
    PUSD public pusd;
    wPUSD public wpusd;
    address public user1;
    address public user2; 
    address public user3;
    address public admin;
    
    // Ghost variables to track invariant state
    uint256 public ghost_totalPUSDReceived;
    uint256 public ghost_totalWPUSDMinted;
    uint256 public ghost_totalPUSDBurned;
    uint256 public ghost_totalWPUSDBurned;
    uint256 public ghost_totalPUSDRedeemed;
    uint256 public ghost_totalLiquidationFundsSent;
    
    constructor(
        StabilityFundHarness _stabilityFund, 
        PUSD _pusd, 
        wPUSD _wpusd, 
        address _user1, 
        address _user2, 
        address _user3,
        address _admin
    ) {
        stabilityFund = _stabilityFund;
        pusd = _pusd;
        wpusd = _wpusd;
        user1 = _user1;
        user2 = _user2;
        user3 = _user3;
        admin = _admin;
    }
    
    /// @dev Handles PUSD deposits into StabilityFund
    function depositPUSD(uint256 amount, uint8 userIndex) public {
        address user = _getAddressByIndex(userIndex % 3);
        
        // Bound amount to reasonable values
        amount = bound(amount, stabilityFund.getMinDepositAmount(), 1_000_000 ether);
        
        // Ensure handler has enough PUSD
        uint256 handlerBalance = pusd.balanceOf(address(this));
        if (handlerBalance < amount) return;
        
        // Transfer PUSD to user for deposit
        pusd.transfer(user, amount);
        
        uint256 wpusdBalanceBefore = wpusd.balanceOf(user);
        
        vm.startPrank(user);
        pusd.approve(address(stabilityFund), amount);
        
        try stabilityFund.depositPUSD(amount) returns (uint256 wpusdMinted) {
            // Update ghost variables
            ghost_totalPUSDReceived += amount;
            ghost_totalWPUSDMinted += wpusdMinted;
            
            // Verify the actual wPUSD minted matches what we expect
            uint256 wpusdBalanceAfter = wpusd.balanceOf(user);
            assert(wpusdBalanceAfter - wpusdBalanceBefore == wpusdMinted);
        } catch {
            // If deposit failed, return PUSD to handler
            pusd.transfer(address(this), amount);
        }
        vm.stopPrank();
    }
    
    /// @dev Handles wPUSD redemption for PUSD
    function redeemWPUSD(uint256 amount, uint8 userIndex) public {
        address user = _getAddressByIndex(userIndex % 3);
        
        uint256 userWPUSDBalance = wpusd.balanceOf(user);
        if (userWPUSDBalance == 0) return;
        
        // Bound amount to user's balance
        amount = bound(amount, 1, userWPUSDBalance);
        
        uint256 pusdBalanceBefore = pusd.balanceOf(user);
        uint256 stabilityFundPUSDBalance = pusd.balanceOf(address(stabilityFund));
        
        // Calculate expected PUSD to receive
        uint256 expectedPUSDToReceive = (amount * stabilityFund.exchangeRate()) / 1e18;
        
        // Only proceed if StabilityFund has enough PUSD
        if (stabilityFundPUSDBalance < expectedPUSDToReceive) return;
        
        vm.prank(user);
        try stabilityFund.redeemWPUSD(amount) {
            uint256 pusdBalanceAfter = pusd.balanceOf(user);
            uint256 actualPUSDReceived = pusdBalanceAfter - pusdBalanceBefore;
            
            // Update ghost variables
            ghost_totalWPUSDBurned += amount;
            ghost_totalPUSDRedeemed += actualPUSDReceived;
            
            // Verify redemption accounting
            assert(actualPUSDReceived == expectedPUSDToReceive);
        } catch {
            // Redemption failed, no state changes
        }
    }
    
    /// @dev Simulates exchange rate updates (only increases allowed)
    function updateExchangeRate(uint256 newRate) public {
        uint256 currentRate = stabilityFund.exchangeRate();
        
        // Bound to reasonable values and ensure it's higher than current
        newRate = bound(newRate, currentRate + 1, currentRate * 2);
        
        try stabilityFund.updateExchangeRate(newRate) {
            // Exchange rate updated successfully
        } catch {
            // Update failed, no state changes
        }
    }
    
    /// @dev Simulates liquidation funds being sent (only owner can call)
    function sendLiquidationFunds(uint256 amount) public {
        uint256 stabilityFundBalance = pusd.balanceOf(address(stabilityFund));
        
        if (stabilityFundBalance == 0) return;
        
        // Bound amount to available balance
        amount = bound(amount, 1, stabilityFundBalance);
        
        vm.prank(admin);
        try stabilityFund.sendLiquidationFunds(amount) {
            ghost_totalLiquidationFundsSent += amount;
        } catch {
            // Failed to send funds
        }
    }
    
    function _getAddressByIndex(uint8 index) internal view returns (address) {
        if (index == 0) return user1;
        if (index == 1) return user2;
        return user3;
    }
}