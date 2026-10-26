# Lending Protocol Deployment Guide

This guide provides a step-by-step process for deploying and configuring all Lending Protocol contracts.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Network Configuration](#network-configuration)
3. [Deployment Order](#deployment-order)
4. [Deployment Scripts](#deployment-scripts)
5. [Configuration Scripts](#configuration-scripts)
6. [Post-Deployment Verification](#post-deployment-verification)
7. [Parameters by Contract](#parameters-by-contract)

---

## Prerequisites

### Environment Variables
```bash
# Deployer private key
DEPLOYER_PRIVATE_KEY=0x...

# RPC URLs per network
SEPOLIA_RPC_URL=https://...
MAINNET_RPC_URL=https://...

# API keys for verification
ETHERSCAN_API_KEY=...
```

### Required External Addresses
Before deployment, ensure you have configured in `NetworkAddresses.sol`:

- **Price Oracle**: Chainlink wstETH/USD price feed
- **Uniswap V3 Router**: For swaps during liquidations
- **Uniswap V3 Quoter**: For price quotations
- **Collateral Token**: wstETH on mainnet
- **Treasury Wallet**: Address to receive fees

---

## Network Configuration

### 1. Update NetworkAddresses.sol

Before deploying, update addresses in `script/NetworkAddresses.sol`:

```solidity
// For Mainnet (chainId = 1)
function oracle() internal view returns (address) {
    if (block.chainid == 1) return 0x...; // Chainlink wstETH/USD
    // ...
}

function swapRouter() internal view returns (address) {
    if (block.chainid == 1) return 0x...; // Uniswap V3 Router
    // ...
}
```

### 2. Review Protocol Parameters

The protocol uses **hardcoded default values** in `initialize()` functions that are applied during deployment. Most parameters do NOT require post-deployment configuration.

#### Parameters Set in `initialize()` 

**ProtocolConfig:**
- **Liquidation Threshold**: 12,000 (120%) - Ratio below which positions become liquidatable
- **Min Collateral Ratio**: 15,000 (150%) - Minimum ratio required for new positions/borrowing
- **Debt Ceiling**: 100,000,000 ether (100M PUSD) - Maximum total debt allowed in the protocol
- **Min Debt**: 500 ether (500 PUSD) - Minimum debt amount per position
- **Close Factor**: 5,000 (50%) - Maximum percentage of debt that can be liquidated at once
- **Liquidation Bonus**: 1,000 (10%) - Bonus given to liquidators
- **Uniswap Fee Tier**: 3,000 (0.3%) - Fee tier for Uniswap V3 swaps

**LendingVault:**
- **APR**: 50 basis points (0.5% annually) - Interest rate for borrowing
- **Min Deposit Amount**: 0.01 ether - Minimum collateral deposit

**LiquidationEngine:**
- **Liquidation Penalty**: 1,000 (10%) - Penalty applied during liquidations
- **Max Slippage**: 1,000 (10%) - Maximum slippage allowed for swaps
- **Treasury Revenue Fee**: 2,000 (20%) - Percentage of liquidation profits going to treasury

**StabilityFund:**
- **Exchange Rate**: 1:1 ratio - Initial PUSD to wPUSD exchange rate
- **Min Deposit Amount**: 0.001 ether - Minimum PUSD deposit
- **Max Deposit Amount**: 1,000,000 ether - Maximum PUSD deposit

**Treasury:**
- **Swap Slippage**: 500 (5%) - Maximum slippage for internal swaps
- **Oracle Stale After**: 1 hour - Oracle price staleness threshold
- **Swap Deadline**: 60 seconds - Swap transaction deadline

#### What Requires Post-Deployment Configuration

**These items need configuration after deployment:**
- ✅ **Contract Address References** - Each contract needs to know other contract addresses
- ✅ **Treasury Wallet Address** - Set in ProtocolConfig
- ⚠️ **AccessControl Roles Configuration** - Critical for protocol security 

### 3. Verify Parameters Match Your Requirements

If you want different values, modify them directly in the contract `initialize()` functions before deployment. The individual configuration scripts are available for future parameter updates only.

---

## Deployment Order

The protocol must be deployed in the following order due to dependencies:

### Phase 1: Core Contracts (No dependencies)
1. **PUSD** - Stablecoin token
2. **wPUSD** - Wrapped PUSD token
3. **ProtocolConfig** - Central configuration

### Phase 2: Protocol Contracts (Depend on Core)
4. **LendingVault** - Main lending vault
5. **StabilityFund** - Stability fund
6. **LiquidationEngine** - Liquidation engine
7. **Treasury** - Protocol treasury

---

## Deployment Scripts

### Main Deployment Script

The `script/deploy/Deploy.s.sol` script handles the entire deployment process:

```bash
# Deploy all contracts using shell script (recommended)
./scripts/deploy/deploy-contracts.sh sepolia

# Or for mainnet
./scripts/deploy/deploy-contracts.sh mainnet

# Alternative: Direct forge command
forge script script/deploy/Deploy.s.sol:Deploy --rpc-url $SEPOLIA_RPC_URL --broadcast --verify
```

### Deployment Flags Configuration

In `Deploy.s.sol`, you can control which contracts to deploy:

```solidity
// Deployment flags - set these to true for contracts you want to deploy
bool public deployProtocolConfig = true;
bool public deployPUSD = true;
bool public deployWPUSD = true;
bool public deployLendingVault = true;
bool public deployStabilityFund = true;
bool public deployTreasury = true;
bool public deployLiquidationEngine = true;
```

### Selective Deployment

To redeploy only certain contracts, modify the flags and execute:

```bash
# Example: Only redeploy LendingVault and Treasury
# Change deployLendingVault = true, deployTreasury = true
# Change the rest to false
./scripts/deploy/deploy-contracts.sh sepolia
```

---

## Post-Deployment Configuration

⚠️ **CRITICAL: AccessControl roles must be configured after deployment for production security!**

The main `Deploy.s.sol` script automatically handles **contract setup**:
1. ✅ Deploys all contracts with proper `initialize()` parameters
2. ✅ Configures all contract address references via `configureContracts()`
3. ✅ Sets treasury wallet in ProtocolConfig

### Required AccessControl Configuration

**⚠️ SECURITY CRITICAL - Required for Production Deployment:**

After deployment, you **MUST** configure AccessControl roles properly:

1. **Grant ADMIN_ROLE to designated admin addresses** in ProtocolConfig
2. **Grant UPGRADER_ROLE to designated upgrader addresses** in ProtocolConfig  
3. **Revoke DEFAULT_ADMIN_ROLE from deployer** (if transferring control)

#### AccessControl Functions

**Critical Functions for Role Management:**

- **`grantRole(bytes32 role, address account)`**: Grants a role to an account
- **`revokeRole(bytes32 role, address account)`**: Revokes a role from an account

**Available Roles:**

- **`ADMIN_ROLE`**: `keccak256("ADMIN_ROLE")` - Controls all administrative functions
- **`UPGRADER_ROLE`**: `keccak256("UPGRADER_ROLE")` - Controls contract upgrades  
- **`DEFAULT_ADMIN_ROLE`**: `0x00` - Supreme admin role (granted to deployer initially)

#### AccessControl Architecture

The protocol uses a **centralized role-based access control system**:

- **ProtocolConfig**: Defines `ADMIN_ROLE` and `UPGRADER_ROLE` 
- **All Contracts**: Use `onlyRole(protocolConfig.ADMIN_ROLE())` for admin functions
- **Upgrade Authorization**: Uses `onlyRole(protocolConfig.UPGRADER_ROLE())`
- **Initial Setup**: Deployer gets `DEFAULT_ADMIN_ROLE` in each contract

**Key Security Points:**
- ✅ All admin functions go through ProtocolConfig role checks
- ✅ Upgrades require UPGRADER_ROLE from ProtocolConfig
- ✅ Role management is centralized in ProtocolConfig
- ⚠️ **Deployer has full control until roles are properly configured**

### Individual Configuration Scripts (Future Use Only)

The individual configuration scripts are available for **future parameter updates only**:

```bash
# Configure all contracts (future parameter updates)
./scripts/deploy/configure-contracts.sh sepolia

# Configure specific contracts only
./scripts/deploy/configure-contracts.sh sepolia --contract protocol-config,pusd

# Alternative: Direct forge commands
forge script script/config/ConfigureProtocolConfig.s.sol:ConfigureProtocolConfig --rpc-url $SEPOLIA_RPC_URL --broadcast
```

**Available individual scripts:**
- `ConfigureProtocolConfig.s.sol` - Update risk parameters, fees, limits
- `ConfigurePUSD.s.sol` - Update PUSD contract references  
- `ConfigureWPUSD.s.sol` - Update wPUSD contract references
- `ConfigureLendingVault.s.sol` - Update LendingVault parameters/references
- `ConfigureStabilityFund.s.sol` - Update StabilityFund parameters/references
- `ConfigureLiquidationEngine.s.sol` - Update LiquidationEngine parameters/references
- `ConfigureTreasury.s.sol` - Update Treasury parameters/references

**These scripts are NOT needed for initial deployment.**

---

## Complete Parameter Reference

This section shows exactly what gets configured where and when.

### Configuration Summary

| Component | Configure in `initialize()` | Post-Deploy Config Needed |
|-----------|------------------------------|---------------------------|
| **ProtocolConfig** | ✅ All risk parameters, external addresses | ⚠️ Only treasuryWallet |
| **PUSD** | ✅ Token metadata | ⚠️ Only contract addresses |
| **wPUSD** | ✅ Token metadata | ⚠️ Only contract addresses |
| **LendingVault** | ✅ All parameters | ⚠️ Only contract addresses |
| **StabilityFund** | ✅ All parameters | ⚠️ Only contract addresses |
| **LiquidationEngine** | ✅ All parameters | ⚠️ Only contract addresses |
| **Treasury** | ✅ All parameters | ⚠️ Only contract addresses |

### Detailed Configuration by Contract

#### ProtocolConfig

**Configured in `initialize()`:**
- ✅ **oracle**: Chainlink wstETH/USD price feed address
- ✅ **swapRouter**: Uniswap V3 SwapRouter address
- ✅ **quoter**: Uniswap V3 QuoterV2 address
- ✅ **collateralToken**: wstETH token address

**Hardcoded default values in `initialize()`:**
- ✅ **liquidationThreshold**: 12,000 (120%)
- ✅ **minCollateralRatio**: 15,000 (150%)
- ✅ **debtCeiling**: 100,000,000 ether (100M PUSD)
- ✅ **minDebt**: 500 ether (500 PUSD)
- ✅ **closeFactorBps**: 5,000 (50%)
- ✅ **liquidationBonusBps**: 1,000 (10%)
- ✅ **uniswapFee**: 3,000 (0.3%)

**Configured post-deployment via Deploy.s.sol:**
- ✅ **treasuryWallet**: Treasury wallet address

#### PUSD

**Configured in `initialize()`:**
- ✅ **name**: "Protocol USD" (hardcoded)
- ✅ **symbol**: "PUSD" (hardcoded)
- ✅ **decimals**: 18 (hardcoded)

**Configured post-deployment via Deploy.s.sol:**
- ✅ **lendingVault**: LendingVault contract address (only minter)
- ✅ **stabilityFund**: StabilityFund contract address (can burn)

#### wPUSD

**Configured in `initialize()`:**
- ✅ **name**: "Wrapped Protocol USD" (hardcoded)
- ✅ **symbol**: "wPUSD" (hardcoded)
- ✅ **decimals**: 18 (hardcoded)

**Configured post-deployment via Deploy.s.sol:**
- ✅ **stabilityFund**: StabilityFund contract address (only minter/burner)

#### LendingVault

**Configured in `initialize()`:**
- ✅ **pusd**: PUSD contract address
- ✅ **protocolConfig**: ProtocolConfig contract address
- ✅ **collateralToken**: wstETH token address

**Hardcoded default values in `initialize()`:**
- ✅ **aprBasisPoints**: 50 (0.5% APR)
- ✅ **lastInterestUpdate**: block.timestamp
- ✅ **globalInterestIndex**: 1e12 (PRECISION)
- ✅ **minDepositAmount**: 0.01 ether

**Configured post-deployment via Deploy.s.sol:**
- ✅ **liquidationEngine**: LiquidationEngine contract address
- ✅ **stabilityFund**: StabilityFund contract address
- ✅ **treasury**: Treasury contract address

#### StabilityFund

**Configured in `initialize()`:**
- ✅ **pusd**: PUSD contract address
- ✅ **wpusd**: wPUSD contract address

**Hardcoded default values in `initialize()`:**
- ✅ **exchangeRate**: 1e18 (1:1 ratio)
- ✅ **minDepositAmount**: 0.001 ether
- ✅ **maxDepositAmount**: 1,000,000 ether

**Configured post-deployment via Deploy.s.sol:**
- ✅ **lendingVault**: LendingVault contract address
- ✅ **liquidationEngine**: LiquidationEngine contract address
- ✅ **treasury**: Treasury contract address

#### LiquidationEngine

**Configured in `initialize()`:**
- ✅ **protocolConfig**: ProtocolConfig contract address
- ✅ **pusd**: PUSD contract address

**Hardcoded default values in `initialize()`:**
- ✅ **liquidationPenalty**: 1,000 (10%)
- ✅ **maxSlippage**: 1,000 (10%)
- ✅ **treasuryRevenueFee**: 2,000 (20%)
- ✅ **liquidationCounter**: 1

**Configured post-deployment via Deploy.s.sol:**
- ✅ **lendingVault**: LendingVault contract address
- ✅ **stabilityFund**: StabilityFund contract address
- ✅ **treasury**: Treasury contract address

#### Treasury

**Configured in `initialize()`:**
- ✅ **protocolConfig**: ProtocolConfig contract address
- ✅ **pusd**: PUSD contract address
- ✅ **wstETH**: wstETH token address

**Hardcoded default values in `initialize()`:**
- ✅ **swapSlippageBps**: 500 (5%)
- ✅ **oracleStaleAfter**: 1 hour
- ✅ **swapDeadlineSeconds**: 60 seconds

**Configured post-deployment via Deploy.s.sol:**
- ✅ **lendingVault**: LendingVault contract address
- ✅ **liquidationEngine**: LiquidationEngine contract address
- ✅ **stabilityFund**: StabilityFund contract address

---

## Deployment Checklist

### Pre-Deployment
- [ ] Environment variables configured
- [ ] NetworkAddresses.sol updated for target network
- [ ] Configuration parameters reviewed
- [ ] Sufficient gas funds in deployer wallet
- [ ] **Production admin addresses prepared** (for AccessControl setup)

### Deployment
- [ ] Execute main Deploy.s.sol script
- [ ] Verify all contracts deployed correctly
- [ ] Save all deployed contract addresses

### Configuration
- [ ] Verify Deploy.s.sol completed successfully

### Post-Deployment Security Setup ⚠️
- [ ] **Configure ADMIN_ROLE in ProtocolConfig** (grant to production admin)
- [ ] **Configure UPGRADER_ROLE in ProtocolConfig** (grant to upgrade admin)
- [ ] **Consider revoking DEFAULT_ADMIN_ROLE from deployer**
- [ ] Verify contracts on Etherscan
- [ ] Verify contract references are correct
- [ ] Document final addresses and admin setup
