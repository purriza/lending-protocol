#!/bin/bash

# Export Lending Protocol Deployments
# Manual script to export deployment artifacts and update NetworkAddresses.sol

set -e  # Exit on any error

echo "🚀 Starting Lending Protocol deployment export..."

# Check if we're in the right directory
if [ ! -f "tools/export-deployments.js" ]; then
    echo "❌ Error: Please run this script from the project root directory"
    exit 1
fi

# Check if Node.js is available
if ! command -v node &> /dev/null; then
    echo "❌ Error: Node.js is not installed or not in PATH"
    exit 1
fi

# Check if Foundry is available
if ! command -v forge &> /dev/null; then
    echo "❌ Error: Foundry is not installed or not in PATH"
    exit 1
fi

echo "📋 Building contracts with Foundry..."
forge build

echo "📦 Exporting deployment artifacts..."
node tools/export-deployments.js

echo "✅ Deployment export completed successfully!"
echo ""
echo "📁 Generated files:"
echo "   - deployments/abi/ (contract ABIs)"
echo "   - deployments/addresses/ (deployment addresses by chain)"
echo "   - deployments/index.json (summary)"
echo "   - script/config/NetworkAddresses.sol (updated if found)"
echo ""
echo "💡 To commit changes:"
echo "   git add deployments/ script/config/NetworkAddresses.sol"
echo "   git commit -m '🚀 Update deployment addresses and NetworkAddresses.sol'"
