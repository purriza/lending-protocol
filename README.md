# Lending Protocol

A decentralized lending protocol built on Ethereum that enables users to deposit collateral and borrow PUSD stablecoin. The protocol features a stability fund, liquidation engine, and treasury for robust risk management.

## Origin and license

This repository is a cleaned-up, rebranded copy of a production DeFi lending
protocol I worked on as part of a two-engineer team. The contracts were
deployed and verified on Ethereum mainnet under a different name. The source
carries an MIT `SPDX-License-Identifier` in every file and is republished here
under those terms; see [LICENSE](LICENSE) for the copyright notice.

Deployment addresses, internal tooling, CI configuration and operational
artifacts have been removed. What remains is the contract source, the test
suite and the deployment scripts. Protocol-owned addresses in
`script/NetworkAddresses.sol` are left as `address(0)` and must be populated
before running any script against a live network; the third-party
infrastructure addresses (Chainlink, Uniswap V3, wstETH) are the canonical
public ones.

## 🏗️ Architecture

This lending protocol consists of several interconnected smart contracts:

### Core Contracts

- **PUSD**: Protocol stablecoin with restricted mint/burn functionality
- **wPUSD**: Wrapped PUSD token for the stability fund with yield generation
- **ProtocolConfig**: Central configuration contract for protocol parameters
- **LendingVault**: Main contract for deposits, borrowing, repayments, and withdrawals
- **StabilityFund**: Manages PUSD deposits, mints wPUSD, and provides liquidation liquidity
- **LiquidationEngine**: Handles liquidation of undercollateralized positions
- **Treasury**: Protocol treasury managing fees and backstop mechanisms

## 🚀 Features

### For Users
- **Deposit Collateral**: Deposit wstETH or other approved collateral
- **Borrow PUSD**: Mint PUSD stablecoin against collateral
- **Repay Debt**: Repay borrowed PUSD to reduce debt
- **Withdraw Collateral**: Withdraw excess collateral
- **Earn Yield**: Deposit PUSD in stability fund to earn yield via wPUSD

### For the Protocol
- **Automated Liquidations**: Liquidate undercollateralized positions
- **Stability Fund**: Provides liquidity and stability to the protocol
- **Treasury Backstop**: Emergency liquidity provision
- **Upgradeable Contracts**: UUPS proxy pattern for contract upgrades
- **Pausable Operations**: Emergency pause functionality

## 🔧 Installation

### Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git

### Setup

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd lending-protocol
   ```

2. **Install dependencies**
   ```bash
   forge install
   ```

3. **Set up environment variables**
   ```bash
   cp .env.example .env
   # Edit .env with your configuration
   ```

4. **Build contracts**
   ```bash
   forge build
   ```

5. **Run tests**
   ```bash
   forge test
   ```

## 📋 Environment Variables

Create a `.env` file with the following variables:

```bash
# Required for all networks
DEPLOYER_PRIVATE_KEY=your_private_key_here
ETHERSCAN_API_KEY=your_etherscan_api_key_here

# RPC URLs (configure the ones you need)
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/your_api_key
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/your_api_key
```

### Variable Descriptions
- **`DEPLOYER_PRIVATE_KEY`**: Private key for contract deployment and upgrades
- **`ETHERSCAN_API_KEY`**: API key for contract verification on Etherscan
- **`SEPOLIA_RPC_URL`**: RPC endpoint for Sepolia testnet
- **`MAINNET_RPC_URL`**: RPC endpoint for Ethereum mainnet

## 🧪 Testing

The project includes comprehensive test coverage for all major contracts and functionality.

### Run all tests
```bash
forge test
```

### Run tests with gas reporting
```bash
forge test --gas-report
```

### Run specific tests
```bash
forge test --match-contract LendingVaultTest
forge test --match-test testDeposit
```

### Test Coverage
```bash
forge coverage
```

#### LCOV report
```bash
# Generate LCOV file for entire repo
forge coverage --report lcov --out lcov.info

```

Tip: If you hit "stack too deep" during coverage, try:
```bash
forge coverage --ir-minimum --report lcov --out lcov.info
```

## 📊 Deployment

### Local Deployment (Anvil)

1. **Start local node**
   ```bash
   anvil
   ```

2. **Deploy contracts**
   ```bash
   ./scripts/deploy/deploy-contracts.sh local
   ```

### Testnet Deployment

1. **Configure deployment flags**
   Edit `script/deploy/Deploy.s.sol` and set the deployment flags to `true` for contracts you want to deploy:
   ```solidity
   function setDeployFlags() internal {
       deployProtocolConfig = true;
       deployPUSD = true;
       deployWPUSD = true;
       deployStabilityFund = true;
       deployTreasury = true;
       deployLiquidationEngine = true;
       deployLendingVault = true;
       deployCollateralToken = true; // Only for testnet
   }
   ```

2. **Deploy to Sepolia**
   ```bash
   ./scripts/deploy/deploy-contracts.sh sepolia
   ```

### Mainnet Deployment

⚠️ **Warning**: Mainnet deployment requires careful consideration of gas costs, security, and proper testing.

1. **Configure deployment flags**
   Edit `script/deploy/Deploy.s.sol` and set the deployment flags to `true` for contracts you want to deploy:
   ```solidity
   function setDeployFlags() internal {
       deployProtocolConfig = true;
       deployPUSD = true;
       deployWPUSD = true;
       deployStabilityFund = true;
       deployTreasury = true;
       deployLiquidationEngine = true;
       deployLendingVault = true;
       deployCollateralToken = false; // wstETH exists on mainnet
   }
   ```

2. **Deploy to Mainnet**
   ```bash
   ./scripts/deploy/deploy-contracts.sh mainnet
   ```

### Deployment Scripts

The project includes automated deployment scripts:

- **`./scripts/deploy/deploy-contracts.sh [network]`**: Deploy contracts with selective deployment
- **`./scripts/deploy/upgrade-contracts.sh [network]`**: Upgrade contracts with selective upgrades
- **`./scripts/verification/verify-contracts.sh [network]`**: Verify deployed contracts on Etherscan
- **`./scripts/deploy/configure-contracts.sh [network]`**: Configure contract relationships and parameters

### Examples

```bash
# Deploy on Sepolia
./scripts/deploy/deploy-contracts.sh sepolia

# Deploy on Mainnet
./scripts/deploy/deploy-contracts.sh mainnet

# Deploy on local network
./scripts/deploy/deploy-contracts.sh local

# Dry run (show what would be done)
./scripts/deploy/deploy-contracts.sh --dry-run sepolia

# Force deployment without confirmation
./scripts/deploy/deploy-contracts.sh --force sepolia
```

### ⚠️ Important: Network-Specific Configuration

**Before running any script, ensure you have:**
1. **Correct RPC URL** configured in your `.env` file for the target network
2. **Deployed contracts** on the target network (addresses are auto-resolved)
3. **Proper deployment flags** set in the deployment script for your needs

## ⚙️ Configuration

After deployment, contracts need to be configured with their relationships and parameters.

### Automatic Configuration

Run the configuration script to set up all contract relationships:

```bash
# Configure all contracts on Sepolia
./scripts/deploy/configure-contracts.sh sepolia

# Configure all contracts on Mainnet
./scripts/deploy/configure-contracts.sh mainnet

# Force configuration without confirmation
./scripts/deploy/configure-contracts.sh --force sepolia
```

### Manual Configuration

You can also configure individual contracts:

```bash
# Configure specific contracts
forge script script/config/ConfigurePUSD.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast
forge script script/config/ConfigureLendingVault.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast
forge script script/config/ConfigureProtocolConfig.s.sol --rpc-url $SEPOLIA_RPC_URL --broadcast
```

### Configuration Scripts

Individual configuration scripts for each contract:

- **`script/config/ConfigurePUSD.s.sol`**: Configure PUSD contract relationships
- **`script/config/ConfigureWPUSD.s.sol`**: Configure wPUSD contract relationships
- **`script/config/ConfigureLendingVault.s.sol`**: Configure LendingVault relationships and parameters
- **`script/config/ConfigureStabilityFund.s.sol`**: Configure StabilityFund relationships and parameters
- **`script/config/ConfigureTreasury.s.sol`**: Configure Treasury relationships and parameters
- **`script/config/ConfigureLiquidationEngine.s.sol`**: Configure LiquidationEngine relationships and parameters
- **`script/config/ConfigureProtocolConfig.s.sol`**: Configure ProtocolConfig parameters

### ✅ Automatic Address Resolution

**Contract addresses are automatically resolved based on the current network using `NetworkAddresses.sol`.** No manual configuration required!

The system automatically detects the network and provides the correct addresses:

```solidity
import {NetworkAddresses} from "../NetworkAddresses.sol";

contract ConfigurePUSD is Script {
    function run() external {
        address pusd = NetworkAddresses.pusd();
        address lendingVault = NetworkAddresses.lendingVault();
        address stabilityFund = NetworkAddresses.stabilityFund();
        // Addresses are automatically resolved based on block.chainid
    }
}
```

**Supported networks:** Sepolia (11155111), Mainnet (1)

## 🔄 Upgrades

The protocol uses UUPS proxy pattern for upgradeable contracts.

### Upgrade Process

1. **Configure upgrade flags**
   Edit `script/deploy/Upgrade.s.sol` and set the upgrade flags to `true` for contracts you want to upgrade:
   ```solidity
   function setUpgradeFlags() internal {
       upgradeProtocolConfig = false;
       upgradePUSD = true;
       upgradeWPUSD = false;
       upgradeStabilityFund = false;
       upgradeTreasury = false;
       upgradeLiquidationEngine = false;
       upgradeLendingVault = false;
   }
   ```

2. **Automatic address resolution**
   Contract addresses are automatically resolved using `NetworkAddresses.sol` based on the current network:

   ```solidity
   import {NetworkAddresses} from "../NetworkAddresses.sol";
   
   contract Upgrade is Script {
       function run() external {
           address pusdProxy = NetworkAddresses.pusd();
           address lendingVaultProxy = NetworkAddresses.lendingVault();
           // Addresses automatically resolved by chainId
       }
   }
   ```

3. **Run upgrade**
   ```bash
   ./scripts/deploy/upgrade-contracts.sh sepolia
   ```

### Upgrade Examples

```bash
# Upgrade on Sepolia
./scripts/deploy/upgrade-contracts.sh sepolia

# Upgrade on Mainnet
./scripts/deploy/upgrade-contracts.sh mainnet

# Dry run upgrade
./scripts/deploy/upgrade-contracts.sh --dry-run sepolia

# Force upgrade without confirmation
./scripts/deploy/upgrade-contracts.sh --force sepolia
```

## 🔒 Security Features

### Access Control
- **Role-based permissions**: Centralized role system managed through ProtocolConfig
- **Multi-sig recommended**: Use multi-signature wallet as owner for production

#### Access Control Roles
- **`ADMIN_ROLE`**: `keccak256("ADMIN_ROLE")` - Controls all administrative functions across contracts
- **`UPGRADER_ROLE`**: `keccak256("UPGRADER_ROLE")` - Controls contract upgrades via UUPS proxy pattern  
- **`DEFAULT_ADMIN_ROLE`**: `0x00` - Supreme admin role (initially granted to deployer)

**Key Functions:**
- `grantRole(bytes32 role, address account)` - Grant role to address
- `revokeRole(bytes32 role, address account)` - Revoke role from address

### Safety Mechanisms
- **Pausable contracts**: Emergency pause functionality
- **Reentrancy protection**: Guards against reentrancy attacks
- **Input validation**: Comprehensive parameter validation
- **Upgradeability**: UUPS proxy pattern for contract upgrades

### Risk Management
- **Collateralization ratios**: Configurable minimum collateral requirements
- **Liquidation thresholds**: Automatic liquidation of risky positions
- **Debt ceiling**: Maximum protocol debt limits
- **Interest rate models**: Dynamic interest rate calculations

## 📋 Contract Interactions

### Basic User Flow

1. **Deposit Collateral**
   ```solidity
   // Approve collateral token
   wstETH.approve(lendingVault, amount);
   
   // Deposit collateral
   lendingVault.deposit(amount, minCollateralRatio);
   ```

2. **Borrow PUSD**
   ```solidity
   lendingVault.borrow(pusdAmount);
   ```

3. **Repay Debt**
   ```solidity
   // Approve PUSD
   pusd.approve(lendingVault, repayAmount);
   
   // Repay debt
   lendingVault.repay(repayAmount);
   ```

4. **Withdraw Collateral**
   ```solidity
   lendingVault.withdraw(collateralAmount);
   ```

### Stability Fund Operations

1. **Deposit PUSD for Yield**
   ```solidity
   // Approve PUSD
   pusd.approve(stabilityFund, pusdAmount);
   
   // Deposit to stability fund
   stabilityFund.depositPUSD(pusdAmount);
   ```

2. **Redeem wPUSD**
   ```solidity
   stabilityFund.redeemWPUSD(wpusdAmount);
   ```

## 📈 Protocol Parameters

### Default Configuration
- **LTV Ratio**: 80%
- **Liquidation Threshold**: 80%
- **Minimum Collateral Ratio**: 120%
- **Liquidation Penalty**: 10%
- **Interest Rate**: ~0.5% APY
- **Debt Ceiling**: 1,000,000 PUSD

### Configurable Parameters
All parameters can be updated by the protocol owner through the ProtocolConfig contract.

## 🛠️ Development

### Code Style
- Solidity ^0.8.20
- OpenZeppelin contracts for security
- NatSpec documentation
- Comprehensive event logging

### Directory Structure
```
lending-protocol/
├── contracts/           # Smart contracts
├── deployments/        # Auto-generated deployment artifacts
│   ├── abi/           # Contract ABIs
│   ├── addresses/     # Deployed addresses by network
│   └── index.json     # Deployment summary
├── lib/                # Dependencies
├── script/             # Foundry deployment and configuration scripts
│   ├── NetworkAddresses.sol    # Network addresses (shared across all scripts)
│   ├── config/         # Configuration scripts for deployed contracts
│   ├── deploy/         # Deployment scripts
│   └── testing-verification/   # Testing, debugging and verification scripts
│       └── liquidation/        # Liquidation testing scripts
├── scripts/            # Bash automation scripts
│   ├── deploy/         # Deployment automation
│   ├── gas/            # Gas management
│   ├── size/           # Size management
│   └── verification/   # Verification automation
├── test/               # Test files
├── tools/              # Node.js tooling
│   └── export-deployments.js  # Deployment artifact exporter
├── foundry.toml        # Foundry configuration
├── remappings.txt      # Import remappings
└── README.md          # Documentation
```

### 🔄 Address Management System

This project uses a **unified address management system** that automatically syncs deployment addresses across different formats:

**🎯 Single Source of Truth**: All addresses come from Foundry broadcast files
**🤖 Auto-Sync**: Deployment artifacts and Solidity code stay in sync automatically
**🌐 Multi-Format**: Supports both JSON (frontend) and Solidity (scripts) consumption

#### How It Works

1. **Deploy contracts** using Foundry deploy scripts
2. **GitHub Action detects** changes in `broadcast/` directory  
3. **Auto-export runs** (`tools/export-deployments.js`)
4. **Updates multiple targets**:
   - `deployments/addresses/*.json` → For frontend integration
   - `script/config/NetworkAddresses.sol` → For Foundry scripts
5. **Auto-commits** changes back to repository

#### Usage in Code

**Frontend (JavaScript/TypeScript):**
```javascript
import sepoliaDeployments from './deployments/addresses/sepolia.json';
const pusdAddress = sepoliaDeployments.contracts.PUSD.address;
```

**Foundry Scripts (Solidity):**
```solidity
import {NetworkAddresses} from "./script/NetworkAddresses.sol";

contract MyScript is Script {
    function run() external {
        address pusd = NetworkAddresses.pusd(); // Auto-resolves by chain ID
    }
}
```

**Manual Export:**
```bash
node tools/export-deployments.js
```

### Contributing
1. Fork the repository
2. Create a feature branch
3. Write comprehensive tests
4. Ensure all tests pass
5. Submit a pull request

## 📚 Documentation

### Additional Resources
- [Foundry Book](https://book.getfoundry.sh/)
- [OpenZeppelin Docs](https://docs.openzeppelin.com/)
- [Solidity Documentation](https://docs.soliditylang.org/)

### Architecture Decisions
- **UUPS Proxy Pattern**: Chosen for upgradeability while maintaining security
- **Interest Rate Model**: Simple compound interest with configurable rates
- **Liquidation Mechanism**: Dutch auction style with external AMM integration
- **Yield Generation**: Time-based yield calculation for stability fund

## ⚠️ Disclaimers

- **Audit**: These contracts were audited prior to their original mainnet deployment. This repository is published as a reference and portfolio artifact, not as deployment-ready code; any redeployment should be independently reviewed and audited.
- **Testing**: Thoroughly test on testnets before production use
- **Risk**: DeFi protocols carry inherent smart contract and financial risks
- **Upgrades**: Contract upgrades should be done through governance mechanisms
