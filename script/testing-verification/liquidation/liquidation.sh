#!/bin/bash

# Liquidation Testing Scripts
# Usage: ./script/testing-verification/liquidation/liquidation.sh <action> <network>

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    echo -e "${1}${2}${NC}"
}

# Function to show help
show_help() {
    print_color "$BLUE" "=== LIQUIDATION TESTING SCRIPTS ==="
    echo ""
    print_color "$YELLOW" "Usage:"
    echo "  ./script/testing-verification/liquidation/liquidation.sh <action> <network>"
    echo ""
    print_color "$YELLOW" "Actions:"
    echo "  generate     - Create test positions across wallets"
    echo "  positions    - Show positions status (LTV/health/liquidable)"
    echo "  balances     - Show SF/Treasury balances and user positions"
    echo "  price-set    - Set oracle absolute USD price (arg: <usd>)"
    echo "  plan         - Preview liquidation plan (no execution)"
    echo "  execute      - Execute liquidation plan for liquidatable wallets"
    echo "  simulate-one - Fork simulate liquidation for a wallet (arg: <address>)"
    echo "  help         - Show this help message"
    echo ""
    print_color "$YELLOW" "Networks:"
    echo "  sepolia      - Ethereum Sepolia testnet"
    echo "  mainnet      - Ethereum Mainnet"
    echo "  local        - Local development network"
    echo ""
    print_color "$YELLOW" "Examples:"
    echo "  ./script/testing-verification/liquidation/liquidation.sh generate sepolia"
    echo "  ./script/testing-verification/liquidation/liquidation.sh positions sepolia"
    echo "  ./script/testing-verification/liquidation/liquidation.sh balances sepolia"
    echo "  ./script/testing-verification/liquidation/liquidation.sh price-set sepolia 2600"
    echo "  ./script/testing-verification/liquidation/liquidation.sh plan sepolia"
    echo "  ./script/testing-verification/liquidation/liquidation.sh execute sepolia"
    echo "  ./script/testing-verification/liquidation/liquidation.sh simulate-one sepolia 0x...wallet"
    echo "  ./script/testing-verification/liquidation/liquidation.sh simulate-all sepolia"
    echo "  ./script/testing-verification/liquidation/liquidation.sh simulate-one-sf sepolia 0x...wallet"
}

# Function to get RPC URL
get_rpc_url() {
    local network=$1
    case $network in
        sepolia)
            echo "sepolia"
            ;;
        mainnet)
            echo "mainnet"
            ;;
        local)
            echo "http://localhost:8545"
            ;;
        *)
            print_color "$RED" "ERROR: Unknown network '$network'"
            echo "Supported networks: sepolia, mainnet, local"
            exit 1
            ;;
    esac
}

# Function to run forge script
run_script() {
    local script=$1
    local function=$2
    local rpc_url=$3
    local broadcast=$4
    
    local cmd="forge script $script"
    
    if [ -n "$function" ]; then
        cmd="$cmd --sig \"$function\""
    fi
    
    cmd="$cmd --rpc-url $rpc_url"
    
    if [ "$broadcast" = "true" ]; then
        cmd="$cmd --broadcast"
    fi
    
    print_color "$BLUE" "Running: $cmd"
    eval $cmd
}

# Main script logic
main() {
    local action=$1
    local network=$2
    
    if [ "$action" = "help" ] || [ -z "$action" ]; then
        show_help
        exit 0
    fi
    
    if [ -z "$network" ]; then
        print_color "$RED" "ERROR: Network is required"
        echo "Usage: ./script/testing-verification/liquidation/liquidation.sh <action> <network>"
        echo "Run './script/testing-verification/liquidation/liquidation.sh help' for more information"
        exit 1
    fi
    
    local rpc_url=$(get_rpc_url $network)
    
    case $action in
        generate)
            print_color "$GREEN" "=== GENERATING TEST POSITIONS ==="
            run_script "script/testing-verification/liquidation/GeneratePositions.s.sol:GeneratePositions" "run()" "$rpc_url" "true"
            ;;
        positions)
            print_color "$GREEN" "=== CHECKING POSITIONS STATUS ==="
            run_script "script/testing-verification/liquidation/CheckPositions.s.sol:CheckPositions" "run()" $rpc_url "false"
            ;;
        balances)
            print_color "$GREEN" "=== PRINTING BALANCES & POSITIONS ==="
            # Use --via-ir to avoid stack-too-deep in the diagnostics script
            print_color "$BLUE" "Running: forge script script/testing-verification/PrintBalances.s.sol:PrintBalances --sig \"run()\" --rpc-url $rpc_url --via-ir"
            forge script script/testing-verification/PrintBalances.s.sol:PrintBalances --sig "run()" --rpc-url "$rpc_url" --via-ir
            ;;
        price-set)
            if [ -z "$3" ]; then
                print_color "$RED" "ERROR: Missing <usd> argument"
                echo "Usage: ./script/testing-verification/liquidation/liquidation.sh price-set <network> <usd>"
                exit 1
            fi
            print_color "$GREEN" "=== SET ORACLE ABSOLUTE PRICE ($3 USD) ==="
            forge script script/testing-verification/liquidation/ManipulateOraclePrice.s.sol:ManipulateOraclePrice --sig "setOraclePriceUSD(uint256)" "$3" --rpc-url "$rpc_url" --broadcast
            ;;
        plan)
            print_color "$GREEN" "=== PREVIEW LIQUIDATION PLAN ==="
            run_script "script/testing-verification/liquidation/PlanAndExecuteLiquidations.s.sol:PlanAndExecuteLiquidations" "preview()" "$rpc_url" "false"
            ;;
        execute)
            print_color "$GREEN" "=== EXECUTING LIQUIDATION PLAN ==="
            run_script "script/testing-verification/liquidation/PlanAndExecuteLiquidations.s.sol:PlanAndExecuteLiquidations" "run()" "$rpc_url" "true"
            ;;
        simulate-one)
            if [ -z "$3" ]; then
                print_color "$RED" "ERROR: Missing <wallet> argument"
                echo "Usage: ./script/testing-verification/liquidation/liquidation.sh simulate-one <network> <wallet>"
                exit 1
            fi
            print_color "$GREEN" "=== FORK SIMULATION FOR WALLET $3 ==="
            # Use --via-ir to avoid potential stack issues
            print_color "$BLUE" "Running: forge script script/testing-verification/liquidation/ForkSimulateLiquidation.s.sol:ForkSimulateLiquidation --sig \"runFor(address)\" $3 --rpc-url $rpc_url --via-ir"
            forge script script/testing-verification/liquidation/ForkSimulateLiquidation.s.sol:ForkSimulateLiquidation --sig "runFor(address)" "$3" --rpc-url "$rpc_url" --via-ir
            ;;
        simulate-one-sf)
            if [ -z "$3" ]; then
                print_color "$RED" "ERROR: Missing <wallet> argument"
                echo "Usage: ./script/testing-verification/liquidation/liquidation.sh simulate-one-sf <network> <wallet>"
                exit 1
            fi
            print_color "$GREEN" "=== FORK SIMULATION (SF-ONLY) FOR WALLET $3 ==="
            print_color "$BLUE" "Running: forge script script/testing-verification/liquidation/ForkSimulateLiquidation.s.sol:ForkSimulateLiquidation --sig \"runForSF(address)\" $3 --rpc-url $rpc_url --via-ir"
            forge script script/testing-verification/liquidation/ForkSimulateLiquidation.s.sol:ForkSimulateLiquidation --sig "runForSF(address)" $3 --rpc-url $rpc_url --via-ir
            ;;
        simulate-all)
            print_color "$GREEN" "=== FORK SIMULATION FOR ALL LIQUIDATABLE WALLETS ==="
            print_color "$BLUE" "Running: forge script script/testing-verification/liquidation/ForkSimulateLiquidation.s.sol:ForkSimulateLiquidation --sig \"runAll()\" --rpc-url $rpc_url --via-ir"
            forge script script/testing-verification/liquidation/ForkSimulateLiquidation.s.sol:ForkSimulateLiquidation --sig "runAll()" --rpc-url "$rpc_url" --via-ir
            ;;
        *)
            print_color "$RED" "ERROR: Unknown action '$action'"
            echo "Run './script/testing-verification/liquidation/liquidation.sh help' for available actions"
            exit 1
            ;;
    esac
    
    print_color "$GREEN" "=== ACTION COMPLETED SUCCESSFULLY ==="
}

main "$@"

