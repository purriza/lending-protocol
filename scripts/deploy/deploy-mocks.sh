#!/bin/bash

# Lending Protocol Mock Deployment Script (Testnet-only)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to print colored output
print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to run deployment (unified with deploy-contracts.sh style)
run_deployment() {
  local rpc_url=$1
  print_status "Compiling contracts..."
  forge build --force
  print_status "Running deployment script..."
  forge script script/deploy/DeployMock.s.sol:DeployMock --rpc-url "$rpc_url" --broadcast --verify
  print_success "Deployment completed successfully!"
}

# .env check (for RPC and PK)
if [ ! -f .env ]; then
  print_error ".env file not found. Please create one based on env.example"
  exit 1
fi
source .env

show_help() {
  echo "Usage: $0 [OPTIONS] [NETWORK]"
  echo
  echo "Options:"
  echo "  -h, --help     Show this help message"
  echo "  -d, --dry-run  Show what would be done without executing"
  echo "  -f, --force    Skip confirmation prompts"
  echo
  echo "Networks:"
  echo "  sepolia        Sepolia testnet"
  echo "  local          Local network (anvil)"
  echo
  echo "Examples:"
  echo "  $0 sepolia                  # Deploy mocks on Sepolia"
  echo "  $0 --dry-run local          # Show what would be done on local"
}

confirm_action() {
  echo
  print_warning "This will deploy MockCollateralToken and MockOracle on the selected network."
  print_warning "Make sure you have sufficient funds and correct environment configured."
  echo
  read -p "Proceed? (y/N): " -n 1 -r; echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_status "Deployment cancelled"
    exit 0
  fi
}

DRY_RUN=false
FORCE=false
NETWORK=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help) show_help; exit 0 ;;
    -d|--dry-run) DRY_RUN=true; shift ;;
    -f|--force) FORCE=true; shift ;;
    sepolia|local) NETWORK=$1; shift ;;
    *) print_error "Unknown option: $1"; show_help; exit 1 ;;
  esac
done

if [ -z "$NETWORK" ]; then
  print_error "Network must be specified"
  show_help
  exit 1
fi

case "$NETWORK" in
  sepolia) RPC_URL="$SEPOLIA_RPC_URL" ;;
  local) RPC_URL="http://localhost:8545" ;;
  *) print_error "Unsupported network: $NETWORK"; exit 1 ;;
esac

if [ -z "$RPC_URL" ]; then
  print_error "RPC URL not configured for: $NETWORK"
  exit 1
fi

if [ "$NETWORK" != "local" ] && [ -z "$DEPLOYER_PRIVATE_KEY" ]; then
  print_error "DEPLOYER_PRIVATE_KEY is required"
  exit 1
fi

echo
print_status "=== Lending Protocol Mock Deployment ==="
print_status "Network: $NETWORK"
print_status "RPC URL: $RPC_URL"
echo

if [ "$FORCE" = false ]; then
  confirm_action
fi

if [ "$DRY_RUN" = true ]; then
  print_status "DRY RUN - No transactions will be sent"
  print_status "Would run: forge script script/deploy/DeployMock.s.sol:DeployMock --rpc-url \"$RPC_URL\" --broadcast --verify"
else
  print_status "Running mock deployment script..."
  run_deployment "$RPC_URL"
fi

print_success "Script completed!"

# Export deployment artifacts if operation was successful
if [ "$DRY_RUN" = false ]; then
    echo
    print_status "Exporting deployment artifacts..."
    # Export deployment artifacts using absolute path
    EXPORT_SCRIPT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)/scripts/export-deployments.sh"
    
    if [ -f "$EXPORT_SCRIPT" ]; then
        cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
        "$EXPORT_SCRIPT"
        print_success "Deployment artifacts exported successfully!"
    else
        print_warning "export-deployments.sh not found at $EXPORT_SCRIPT, skipping artifact export"
    fi
fi


