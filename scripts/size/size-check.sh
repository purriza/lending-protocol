#!/bin/bash

# Lending Protocol - Size Check Script
# ==================================
# This script checks contract sizes and enforces limits:
# 1. Build contracts with size information
# 2. Check if any contract exceeds the 24KB limit
# 3. Show warnings for contracts approaching the limit

set -e

# Size limits
MAX_SIZE=24576
WARNING_THRESHOLD=20000

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Lending Protocol - Size Check ===${NC}"
echo -e "${BLUE}Checking contract sizes and enforcing limits...${NC}"
echo ""

# Build contracts and get size information
echo -e "${YELLOW}Building contracts with size information...${NC}"
cd "$(dirname "$0")/../.." && forge build --sizes > contract-sizes.txt

echo -e "${GREEN}✅ Build completed${NC}"
echo ""

# Check critical contracts
echo -e "${YELLOW}Checking contract size limits...${NC}"
echo "Max contract size: $MAX_SIZE bytes"
echo "Warning threshold: $WARNING_THRESHOLD bytes"
echo ""

contracts=("LendingVault" "LiquidationEngine" "ProtocolConfig" "StabilityFund" "Treasury" "PUSD")
has_errors=false

for contract_name in "${contracts[@]}"; do
    if grep -q "| $contract_name " contract-sizes.txt; then
        size=$(grep "| $contract_name " contract-sizes.txt | awk -F'|' '{print $3}' | awk '{print $1}' | tr -d ',')
        echo "Checking $contract_name: $size bytes"
        
        if [ "$size" -gt "$MAX_SIZE" ]; then
            echo -e "${RED}❌ $contract_name exceeds maximum size limit ($MAX_SIZE bytes)${NC}"
            has_errors=true
        elif [ "$size" -gt "$WARNING_THRESHOLD" ]; then
            echo -e "${YELLOW}⚠️  $contract_name exceeds warning threshold ($WARNING_THRESHOLD bytes)${NC}"
        else
            echo -e "${GREEN}✅ $contract_name size is acceptable${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  $contract_name not found in size report${NC}"
    fi
done

echo ""

if [ "$has_errors" = true ]; then
    echo -e "${RED}❌ Size check failed - some contracts exceed limits${NC}"
    exit 1
else
    echo -e "${GREEN}✅ All contracts within size limits${NC}"
fi
