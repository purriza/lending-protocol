#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./verify.sh oracle  <sepolia|mainnet|local> [extra forge args]
#   ./verify.sh quoter  <sepolia|mainnet|local> [extra forge args]
#   ./verify.sh router  <sepolia|mainnet|local> [extra forge args]
#   ./verify.sh pool    <sepolia|mainnet|local> [extra forge args]
#   ./verify.sh all     <sepolia|mainnet|local> [extra forge args]

ACTION=${1:-}
NETWORK=${2:-}
shift 2 || true

VFLAG="-vvvv"

# Hardcoded ProtocolConfig per network (no .env for addresses)
PROTOCOL_CONFIG_SEPOLIA=
PROTOCOL_CONFIG_MAINNET=

# Well-known external addresses per network (factory, PUSD)
UNISWAP_FACTORY_SEPOLIA=0x0227628f3F023bb0B980b67D528571c95c6DaC1c
PUSD_SEPOLIA=
UNISWAP_FACTORY_MAINNET=
PUSD_MAINNET=

# Load .env if present (export all) for RPC URLs only
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

# Resolve per-network config address
NET_UPPER=$(echo "$NETWORK" | tr '[:lower:]' '[:upper:]')
case "$NETWORK" in
  sepolia)
    PROTOCOL_CONFIG="$PROTOCOL_CONFIG_SEPOLIA"
    FACTORY_ADDR="$UNISWAP_FACTORY_SEPOLIA"
    PUSD_ADDR="$PUSD_SEPOLIA"
    ;;
  mainnet)
    PROTOCOL_CONFIG="$PROTOCOL_CONFIG_MAINNET"
    FACTORY_ADDR="$UNISWAP_FACTORY_MAINNET"
    PUSD_ADDR="$PUSD_MAINNET"
    ;;
  local)
    PROTOCOL_CONFIG="${PROTOCOL_CONFIG_LOCAL-}"
    FACTORY_ADDR="${FACTORY_LOCAL-}"
    PUSD_ADDR="${PUSD_LOCAL-}"
    ;;
  *)
    echo "Unknown network: $NETWORK"
    echo "Usage: $0 <oracle|quoter|router|all> <sepolia|mainnet|local> [extra forge args]"
    exit 1
    ;;
esac

if [[ -z "${PROTOCOL_CONFIG}" ]]; then
  echo "ERROR: ProtocolConfig address not configured for network '$NETWORK' (set in verify.sh or PROTOCOL_CONFIG_LOCAL)"
  exit 1
fi

# Resolve RPC URL from env: <NET>_RPC_URL, with fallbacks
RPC_URL_VAR="${NET_UPPER}_RPC_URL"
RPC_URL=${!RPC_URL_VAR-}

if [[ -z "${RPC_URL}" ]]; then
  # Fallbacks: allow Foundry named endpoints (e.g., --rpc-url sepolia)
  case "$NETWORK" in
    sepolia|mainnet)
      RPC_FLAG="--rpc-url $NETWORK"
      ;;
    local)
      RPC_FLAG="--rpc-url http://localhost:8545"
      ;;
    *)
      echo "ERROR: \$${RPC_URL_VAR} not set and unknown network '$NETWORK'"
      exit 1
      ;;
  esac
else
  RPC_FLAG="--rpc-url ${RPC_URL}"
fi

case "$ACTION" in
  oracle)
    forge script script/testing-verification/VerifyOracle.s.sol:VerifyOracle --sig "run(address)" "$PROTOCOL_CONFIG" "$RPC_FLAG" "$@" "$VFLAG"
    ;;
  quoter)
    forge script script/testing-verification/VerifyQuoter.s.sol:VerifyQuoter --sig "run(address,address,address)" "$PROTOCOL_CONFIG" "$FACTORY_ADDR" "$PUSD_ADDR" "$RPC_FLAG" "$@" "$VFLAG"
    ;;
  router)
    forge script script/testing-verification/VerifyRouter.s.sol:VerifyRouter --sig "run(address,address,address)" "$PROTOCOL_CONFIG" "$FACTORY_ADDR" "$PUSD_ADDR" "$RPC_FLAG" --via-ir "$@" $VFLAG
    ;;
  pool)
    forge script script/testing-verification/VerifyPool.s.sol:VerifyPool --sig "run(address,address,address)" $PROTOCOL_CONFIG $FACTORY_ADDR $PUSD_ADDR $RPC_FLAG "$@" $VFLAG
    ;;
  all)
    echo "[1/3] Oracle"
    forge script script/testing-verification/VerifyOracle.s.sol:VerifyOracle --sig "run(address)" $PROTOCOL_CONFIG $RPC_FLAG "$@" $VFLAG
    echo "[2/3] Quoter"
    forge script script/testing-verification/VerifyQuoter.s.sol:VerifyQuoter --sig "run(address,address,address)" "$PROTOCOL_CONFIG" "$FACTORY_ADDR" "$PUSD_ADDR" "$RPC_FLAG" "$@" "$VFLAG"
    echo "[3/4] Router"
    forge script script/testing-verification/VerifyRouter.s.sol:VerifyRouter --sig "run(address,address,address)" $PROTOCOL_CONFIG $FACTORY_ADDR $PUSD_ADDR $RPC_FLAG --via-ir "$@" $VFLAG
    echo "[4/4] Pool"
    forge script script/testing-verification/VerifyPool.s.sol:VerifyPool --sig "run(address,address,address)" $PROTOCOL_CONFIG $FACTORY_ADDR $PUSD_ADDR $RPC_FLAG "$@" $VFLAG
    ;;
  *)
    echo "Unknown action: $ACTION"
    echo "Valid actions: oracle | quoter | router | all"
    exit 1
    ;;
esac


