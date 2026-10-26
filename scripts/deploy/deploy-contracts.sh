#!/bin/bash

# Lending Protocol Contract Deployment Script
# This script facilitates deploying the contracts

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if .env file exists
if [ ! -f .env ]; then
    print_error ".env file not found. Please create one based on env.example"
    exit 1
fi

# Load environment variables
source .env

# Function to confirm action
confirm_action() {
    echo
    print_warning "This will deploy selected Lending Protocol contracts."
    print_warning "Make sure you have:"
    print_warning "1. Set the deploy flags to true for contracts you want to deploy"
    print_warning "2. Tested the contract code thoroughly"
    print_warning "3. Have sufficient gas for all transactions"
    echo
    read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Deployment cancelled"
        exit 0
    fi
}

# Function to run deployment
run_deployment() {
    local network=$1
    
    print_status "Starting deployment on network: \"$network\""
    
    # Compile contracts
    print_status "Compiling contracts..."
    forge build --force
    
    # Run deployment script
    print_status "Running deployment script..."
    forge script script/deploy/Deploy.s.sol:Deploy --rpc-url "$network" --broadcast --verify
    
    print_success "Deployment completed successfully!"
}

# Function to show help
show_help() {
    echo "Usage: $0 [OPTIONS] [NETWORK]"
    echo
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -d, --dry-run  Show what would be done without executing"
    echo "  -f, --force    Skip confirmation prompts"
    echo
    echo "Networks:"
    echo "  mainnet        Ethereum mainnet"
    echo "  sepolia        Sepolia testnet"
    echo "  local          Local network (anvil)"
    echo
    echo "Examples:"
    echo "  $0 sepolia                    # Deploy on Sepolia testnet"
    echo "  $0 --dry-run mainnet         # Show what would be done on mainnet"
    echo "  $0 --force local             # Deploy on local network without confirmation"
    echo
    echo "Note: Before running, make sure to:"
    echo "1. Set deploy flags to true for contracts you want to deploy"
    echo "2. Review the configuration parameters in Deploy.s.sol"
    echo "3. Configure the appropriate RPC URL in your .env file"
}

# Parse command line arguments
DRY_RUN=false
FORCE=false
NETWORK=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        mainnet|sepolia|local)
            NETWORK=$1
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Check if network is specified
if [ -z "$NETWORK" ]; then
    print_error "Network must be specified"
    show_help
    exit 1
fi

# Set RPC URL based on network
case "$NETWORK" in
    mainnet)
        RPC_URL="$MAINNET_RPC_URL"
        ;;
    sepolia)
        RPC_URL="$SEPOLIA_RPC_URL"
        ;;
    local)
        RPC_URL="http://localhost:8545"
        ;;
    *)
        print_error "Unknown network: \"$NETWORK\""
        exit 1
        ;;
esac

# Check if RPC URL is available for the specified network
if [ -z "$RPC_URL" ]; then
            print_error "RPC URL not configured for network: \"$NETWORK\""
    if [ "$NETWORK" = "mainnet" ]; then
        print_error "Please add MAINNET_RPC_URL to your .env file"
    elif [ "$NETWORK" = "sepolia" ]; then
        print_error "Please add SEPOLIA_RPC_URL to your .env file"
    else
        print_error "Please add ${NETWORK^^}_RPC_URL to your .env file"
    fi
    exit 1
fi

# Check required environment variables for the specified network
if [ "$NETWORK" != "local" ]; then
    if [ -z "$DEPLOYER_PRIVATE_KEY" ]; then
        print_error "Required environment variable DEPLOYER_PRIVATE_KEY is not set"
        exit 1
    fi
fi

# Display deployment information
echo
print_status "=== Lending Protocol Contract Deployment ==="
    print_status "Network: \"$NETWORK\""
    print_status "RPC URL: \"$RPC_URL\""
echo
print_warning "IMPORTANT: Make sure you have set the deploy flags to true for contracts you want to deploy"
print_warning "and reviewed the configuration parameters in Deploy.s.sol."
echo

# Confirm action unless --force is used
if [ "$FORCE" = false ]; then
    confirm_action
fi

# Run deployment
if [ "$DRY_RUN" = true ]; then
    print_status "DRY RUN - No actual transactions will be sent"
    print_status "Would run: forge script script/deploy/Deploy.s.sol:Deploy --rpc-url \"$RPC_URL\" --broadcast --verify"
else
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
