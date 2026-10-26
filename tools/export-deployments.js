#!/usr/bin/env node
/*
  Export ABIs from Foundry out/ into deployments/abi/
  Aggregate deployed addresses from Foundry broadcast/ into deployments/addresses/<chainId>.json
  Optionally mirror Solidity scripts to deployments/scripts/ for discoverability.
*/

const fs = require("fs");
const path = require("path");

/** Utility: ensure directory exists */
function ensureDir(dirPath) {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
  }
}

/** Utility: read JSON file safely */
function readJson(filePath) {
  const content = fs.readFileSync(filePath, "utf8");
  return JSON.parse(content);
}

/** Utility: write JSON with stable formatting */
function writeJson(filePath, data) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2) + "\n", "utf8");
}

/** List all files recursively under a dir (non-dot files) */
function listFilesRec(dirPath) {
  const results = [];
  if (!fs.existsSync(dirPath)) return results;
  const entries = fs.readdirSync(dirPath, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.name.startsWith(".")) continue;
    const full = path.join(dirPath, entry.name);
    if (entry.isDirectory()) {
      results.push(...listFilesRec(full));
    } else {
      results.push(full);
    }
  }
  return results;
}

/** Derive contract names directly from contracts/*.sol */
function getPrimaryContractNames(contractsDir) {
  if (!fs.existsSync(contractsDir)) return [];
  const files = fs
    .readdirSync(contractsDir, { withFileTypes: true })
    .filter((e) => e.isFile() && e.name.endsWith(".sol"))
    .map((e) => e.name);
  return files.map((f) => path.basename(f, ".sol"));
}

/** Export ABIs into deployments/abi/<Contract>.json */
function exportAbis({ outDir, contractsDir, outputDir }) {
  const contractNames = getPrimaryContractNames(contractsDir);
  const exported = [];
  // Ensure abi dir exists
  const abiDir = path.join(outputDir, "abi");
  ensureDir(abiDir);
  for (const name of contractNames) {
    const artifactPath = path.join(outDir, `${name}.sol`, `${name}.json`);
    if (!fs.existsSync(artifactPath)) {
      // Skip if not compiled yet
      continue;
    }
    try {
      const artifact = readJson(artifactPath);
      const abi = artifact.abi || [];
      const outPath = path.join(abiDir, `${name}.json`);
      writeJson(outPath, { abi });
      exported.push(name);
    } catch (err) {
      console.error(
        `[export-abis] Failed to process ${artifactPath}:`,
        err.message
      );
    }
  }
  // Prune stale ABIs not corresponding to current contracts
  try {
    const files = fs.readdirSync(abiDir).filter((f) => f.endsWith(".json"));
    const valid = new Set(contractNames.map((n) => `${n}.json`));
    for (const f of files) {
      if (!valid.has(f)) {
        try {
          fs.unlinkSync(path.join(abiDir, f));
        } catch {}
      }
    }
  } catch (e) {
    console.error("[export-abis] prune failed:", e.message);
  }
  return exported;
}

/**
 * Parse Foundry broadcast run JSON to map contract deployments.
 * - Prefer proxy address when an ERC1967Proxy was deployed pointing to the implementation
 * - Handle upgrades correctly by preserving proxy addresses
 */
function parseBroadcastFile(filePath) {
  const j = readJson(filePath);
  const chainId = j.chain ?? j.receipts?.[0]?.chainId ?? null;
  const txs = Array.isArray(j.transactions) ? j.transactions : [];

  // Map implementation address -> contractName
  const implAddressToName = new Map();
  // Map contractName -> last created address
  const nameToCreateAddr = new Map();
  // List of proxies (address and implementation)
  const proxies = [];

  for (const tx of txs) {
    if (tx.transactionType === "CREATE") {
      const cn = tx.contractName || "Unknown";
      const ca = tx.contractAddress || null;
      if (ca) {
        nameToCreateAddr.set(cn, ca);
        // Track implementation by name
        implAddressToName.set(ca.toLowerCase(), cn);
      }

      if (cn === "ERC1967Proxy") {
        const args = Array.isArray(tx.arguments) ? tx.arguments : [];
        // Typical args[0] is implementation
        const implementation = args[0];
        proxies.push({
          proxyAddress: tx.contractAddress,
          implementationAddress: implementation,
        });
      }
    }
  }

  // Build mapping of logical contract name -> preferred address, plus source kind
  const mapping = {};
  const sources = {}; // name -> 'proxy' | 'impl'

  // Attach proxies to their implementation names when possible
  for (const p of proxies) {
    const impl = (p.implementationAddress || "").toLowerCase();
    const implName = implAddressToName.get(impl);
    if (implName && p.proxyAddress) {
      mapping[implName] = p.proxyAddress;
      sources[implName] = "proxy";
    }
  }

  // For any created contract without a proxy, expose its own address
  for (const [name, addr] of nameToCreateAddr.entries()) {
    if (!mapping[name]) {
      mapping[name] = addr;
      sources[name] = "impl";
    }
  }

  return { chainId, mapping, sources };
}

/** Aggregate addresses across all broadcast run-latest files by chain */
function exportAddresses({ broadcastDir, outputDir }) {
  const files = listFilesRec(broadcastDir).filter((p) =>
    /run-latest\.json$/.test(p)
  );
  // Track both value and whether it came from a proxy or implementation
  const chainToState = new Map(); // chain -> { values: Record<string,string>, kinds: Record<string,'proxy'|'impl'> }

  for (const f of files) {
    try {
      const { chainId, mapping, sources } = parseBroadcastFile(f);
      if (!chainId) continue;
      const key = String(chainId);
      const state = chainToState.get(key) || { values: {}, kinds: {} };

      for (const [name, addr] of Object.entries(mapping)) {
        const incomingKind =
          (sources && sources[name]) === "proxy" ? "proxy" : "impl";
        const existingKind = state.kinds[name];

        if (incomingKind === "proxy") {
          // Always prefer proxy
          state.values[name] = addr;
          state.kinds[name] = "proxy";
        } else {
          // Implementation-only: set if nothing exists or existing isn't a proxy
          if (!existingKind || existingKind !== "proxy") {
            state.values[name] = addr;
            state.kinds[name] = "impl";
          }
        }
      }

      chainToState.set(key, state);
    } catch (err) {
      console.error(`[export-addresses] Failed to parse ${f}:`, err.message);
    }
  }

  const written = [];
  // Only keep a curated subset of contract addresses in alias files
  const ALLOWED_KEYS = new Set([
    "ProtocolConfig",
    "PUSD",
    "wPUSD",
    "LendingVault",
    "StabilityFund",
    "Treasury",
    "LiquidationEngine",
  ]);
  // Enforce deterministic order in output files
  const ORDER = [
    "ProtocolConfig",
    "PUSD",
    "wPUSD",
    "LendingVault",
    "StabilityFund",
    "Treasury",
    "LiquidationEngine",
  ];

  for (const [chain, state] of chainToState.entries()) {
    const outDirPerChain = path.join(outputDir, "addresses");
    // Only write human-friendly alias files (no numeric id files)
    const CHAIN_ALIASES = {
      1: ["mainnet"],
      11155111: ["sepolia"],
      5: ["goerli"],
      137: ["polygon"],
      80001: ["mumbai"],
      56: ["bsc"],
      97: ["bscTestnet"],
    };
    const aliases = CHAIN_ALIASES[String(chain)] || [];
    for (const alias of aliases) {
      const aliasPath = path.join(outDirPerChain, `${alias}.json`);
      const filtered = {};
      for (const key of ORDER) {
        if (ALLOWED_KEYS.has(key) && state.values[key]) {
          filtered[key] = state.values[key];
        }
      }
      writeJson(aliasPath, filtered);
      written.push(aliasPath);
    }
  }
  return written;
}

/** 
 * Update NetworkAddresses.sol with addresses from deployment files 
 */
function updateNetworkAddresses({ outputDir }) {
  const networkAddressesPath = path.join(process.cwd(), "script", "NetworkAddresses.sol");
  
  if (!fs.existsSync(networkAddressesPath)) {
    console.log("⚠️ NetworkAddresses.sol not found, skipping");
    return false;
  }

  // Read existing file
  const currentContent = fs.readFileSync(networkAddressesPath, "utf8");
  
  // Map of contract name to function name in NetworkAddresses.sol
  const CONTRACT_MAPPINGS = {
    "PUSD": "pusd",
    "wPUSD": "wpusd", 
    "ProtocolConfig": "protocolConfig",
    "LendingVault": "lendingVault",
    "StabilityFund": "stabilityFund",
    "Treasury": "treasury",
    "LiquidationEngine": "liquidationEngine"
  };

  // Collect addresses from all deployment files
  const allAddresses = new Map();
  
  const addressFiles = listFilesRec(path.join(outputDir, "addresses"))
    .filter(f => f.endsWith(".json"));
    
  for (const addressFile of addressFiles) {
    try {
      const data = readJson(addressFile);
      const chainName = path.basename(addressFile, '.json');
      
      // Map chain names to chain IDs
      const CHAIN_NAME_TO_ID = {
        "mainnet": 1,
        "sepolia": 11155111,
        "goerli": 5,
        "polygon": 137,
        "mumbai": 80001,
        "bsc": 56,
        "bscTestnet": 97
      };
      
      const chainId = CHAIN_NAME_TO_ID[chainName];
      if (chainId && data) {
        allAddresses.set(chainId, data);
      }
    } catch (err) {
      console.error(`Failed to read ${addressFile}:`, err.message);
    }
  }

  if (allAddresses.size === 0) {
    console.log("⚠️ No valid address files found");
    return false;
  }

  // Generate new content
  let newContent = currentContent;

  // Helper function to convert address to checksum format (EIP-55)
  function toChecksumAddress(address) {
    if (!address || address === "address(0)") return "address(0)";
    
    // Overrides for addresses whose stored form is not EIP-55 checksummed;
    // solc rejects mixed-case addresses that fail the checksum.
    const checksumMap = {};
    
    const normalizedAddr = address.toLowerCase();
    return checksumMap[normalizedAddr] || address;
  }

  for (const [contractName, functionName] of Object.entries(CONTRACT_MAPPINGS)) {
    // Build the new function implementation
    let functionImpl = `    function ${functionName}() internal view returns (address) {\n`;
    
    // Always include mainnet (chainId == 1) first, even if not deployed
    const mainnetAddress = allAddresses.get(1)?.[contractName];
    if (mainnetAddress) {
      functionImpl += `        if (block.chainid == 1) return ${toChecksumAddress(mainnetAddress)};\n`;
    } else {
      functionImpl += `        if (block.chainid == 1) return address(0);\n`;
    }
    
    // Add other chains
    for (const [chainId, contracts] of allAddresses.entries()) {
      if (chainId === 1) continue; // Skip mainnet, already handled above
      
      const address = contracts[contractName];
      if (address) {
        functionImpl += `        if (block.chainid == ${chainId}) return ${toChecksumAddress(address)};\n`;
      } else {
        functionImpl += `        if (block.chainid == ${chainId}) return address(0);\n`;
      }
    }
    
    functionImpl += `\n        revert UnsupportedChain(block.chainid);\n    }`;

    // Replace the existing function - match with proper indentation
    const functionRegex = new RegExp(`    function ${functionName}\\(\\)[^}]+}`, "s");
    
    if (functionRegex.test(newContent)) {
      newContent = newContent.replace(functionRegex, functionImpl);
    } else {
      console.warn(`Function ${functionName} not found in NetworkAddresses.sol`);
    }
  }

  // Only write if content changed
  if (newContent !== currentContent) {
    fs.writeFileSync(networkAddressesPath, newContent, "utf8");
    console.log("🔄 Updated NetworkAddresses.sol");
    return true;
  } else {
    console.log("✅ NetworkAddresses.sol already up to date");
    return false;
  }
}

function main() {
  const repoRoot = process.cwd();
  const outDir = path.join(repoRoot, "out");
  const broadcastDir = path.join(repoRoot, "broadcast");
  const contractsDir = path.join(repoRoot, "contracts");
  const outputDir = path.join(repoRoot, "deployments");

  ensureDir(outputDir);

  const exportedAbis = exportAbis({ outDir, contractsDir, outputDir });
  const writtenAddresses = exportAddresses({ broadcastDir, outputDir });
  
  // Update NetworkAddresses.sol with new addresses
  updateNetworkAddresses({ outputDir });

  // Simple index file to aid consumption
  const index = {
    notice:
      "Auto-generated by tools/export-deployments.js. Do not edit manually.",
    generatedAt: new Date().toISOString(),
    abis: exportedAbis,
    addressesFiles: writtenAddresses.map((p) => path.relative(outputDir, p)),
  };
  writeJson(path.join(outputDir, "index.json"), index);

  console.log(
    "[export] ABIs:",
    exportedAbis.length,
    "| address files:",
    writtenAddresses.length
  );
}

if (require.main === module) {
  try {
    main();
  } catch (err) {
    console.error("[export] Failed:", err);
    process.exit(1);
  }
}

