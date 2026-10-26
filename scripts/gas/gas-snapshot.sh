#!/bin/bash

# Lending Protocol - Gas Snapshot Script
# ====================================

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Lending Protocol - Gas Snapshot ===${NC}"

# Run gas snapshot tests
echo -e "${YELLOW}Running gas snapshot tests...${NC}"
cd "$(dirname "$0")/../.." && forge test --match-contract GasSnapshot --gas-report

echo -e "${GREEN}✅ Gas snapshot completed${NC}"
