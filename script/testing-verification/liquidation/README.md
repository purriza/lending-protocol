# Liquidation Scripts

## 📁 Available Scripts

### 1. **CheckPositions.s.sol** - Unified Monitoring
**Purpose**: Main script for monitoring all positions
**Features**:
- ✅ Monitoring of all testing wallets
- ✅ Monitoring of the Target Wallet
- ✅ Oracle information
- ✅ Complete position summary
- ✅ Utility functions for specific wallets
- ✅ Price scenario simulation

**Usage**:
```bash
# Complete monitoring
forge script script/testing/liquidation/CheckPositions.s.sol:CheckPositions --sig "run()" --rpc-url sepolia --via-ir

# Specific wallet monitoring
forge script script/testing/liquidation/CheckPositions.s.sol:CheckPositions --sig "checkWallet(address)" --rpc-url sepolia --via-ir

# Price simulation
forge script script/testing/liquidation/CheckPositions.s.sol:CheckPositions --sig "simulatePriceScenarios(address,uint256[])" --rpc-url sepolia --via-ir
```

### 2. **GeneratePositions.s.sol** - Testing Position Generation
**Purpose**: Create risky positions for liquidation testing
**Features**:
- ✅ Create multiple positions with different risk levels
- ✅ Verify existing position status
- ✅ Flexible LTV ratio configuration

**Usage**:
```bash
# Create risky positions
forge script script/testing/liquidation/GeneratePositions.s.sol:GeneratePositions --sig "run()" --rpc-url sepolia --via-ir --broadcast

# Verify all wallet status
forge script script/testing/liquidation/GeneratePositions.s.sol:GeneratePositions --sig "checkAllWallets()" --rpc-url sepolia --via-ir
```

### 3. **ManipulateOraclePrice.s.sol** - Price Manipulation
**Purpose**: Modify oracle prices to simulate market scenarios
**Features**:
- ✅ Change oracle prices
- ✅ Simulate price drops for liquidation testing
- ✅ Restore original prices

**Usage**:
```bash
# Change oracle price
forge script script/testing/liquidation/ManipulateOraclePrice.s.sol:ManipulateOraclePrice --sig "setPrice(uint256)" --rpc-url sepolia --via-ir --broadcast

# Restore original price
forge script script/testing/liquidation/ManipulateOraclePrice.s.sol:ManipulateOraclePrice --sig "restoreOriginalPrice()" --rpc-url sepolia --via-ir --broadcast
```

### 4. **PlanAndExecuteLiquidations.s.sol** - Liquidation Planning
**Purpose**: Plan and execute liquidation strategies
**Features**:
- ✅ Analyze liquidation opportunities
- ✅ Execute liquidations with optimal parameters
- ✅ Monitor liquidation results

**Usage**:
```bash
# Plan and execute liquidations
forge script script/testing/liquidation/PlanAndExecuteLiquidations.s.sol:PlanAndExecuteLiquidations --sig "run()" --rpc-url sepolia --via-ir --broadcast
```

### 5. **ForkSimulateLiquidation.s.sol** - Fork Simulation
**Purpose**: Simulate liquidations on forked mainnet
**Features**:
- ✅ Fork mainnet state
- ✅ Simulate liquidation scenarios
- ✅ Test with real market conditions

**Usage**:
```bash
# Simulate liquidations on fork
forge script script/testing/liquidation/ForkSimulateLiquidation.s.sol:ForkSimulateLiquidation --sig "run()" --rpc-url sepolia --via-ir --broadcast
```

### 6. **liquidation.sh** - Shell Script
**Purpose**: Automate script execution
**Features**:
- ✅ Execute multiple scripts in sequence
- ✅ Environment variable configuration

## 🎯 Recommended Workflow

### 1. **Regular Monitoring**
```bash
forge script script/testing/liquidation/CheckPositions.s.sol:CheckPositions --sig "run()" --rpc-url sepolia --via-ir
```

### 2. **Create Testing Positions**
```bash
forge script script/testing/liquidation/GeneratePositions.s.sol:GeneratePositions --sig "run()" --rpc-url sepolia --via-ir --broadcast
```

### 3. **Simulate Price Drop for Liquidation**
```bash
# Change price to $2,375 to make first wallet liquidatable
forge script script/testing/liquidation/ManipulateOraclePrice.s.sol:ManipulateOraclePrice --sig "setPrice(237500000000)" --rpc-url sepolia --via-ir --broadcast
```

### 4. **Verify Liquidations**
```bash
forge script script/testing/liquidation/CheckPositions.s.sol:CheckPositions --sig "run()" --rpc-url sepolia --via-ir
```

## 📊 Current Position Status

| Wallet | Collateral | Debt | LTV | Status |
|--------|------------|------|-----|--------|
| Testing Wallet 1 | 100 wstETH | 237,000 PUSD | 79% | ⚠️ AT RISK |
| Testing Wallets 2-5 | 100 wstETH | 500 PUSD | 0.17% | ✅ SAFE |
| Target Wallet | 3 wstETH | 1,000 PUSD | 11.11% | ✅ SAFE |

## 🔧 Configuration

### Required Environment Variables
```bash
export LIQUIDATION_TESTING_1_PRIVATE_KEY="<private_key>"
export LIQUIDATION_TESTING_2_PRIVATE_KEY="<private_key>"
export LIQUIDATION_TESTING_3_PRIVATE_KEY="<private_key>"
export LIQUIDATION_TESTING_4_PRIVATE_KEY="<private_key>"
export LIQUIDATION_TESTING_5_PRIVATE_KEY="<private_key>"
export LIQUIDATIONS_PRIVATE_KEY="<private_key>"
```

### Contract Addresses (Sepolia)
Set these from your own deployment; see `script/NetworkAddresses.sol`.
- **LendingVault**
- **ProtocolConfig**
- **Treasury**
- **Oracle**

## ⚠️ Important Notes

1. **Always use `--via-ir`** to avoid "stack too deep" errors
2. **Use `--broadcast`** only when transactions need to be executed
3. **Verify balances** before creating positions
4. **Monitor regularly** positions at risk
5. **Restore prices** from oracle after testing