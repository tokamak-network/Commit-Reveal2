# Commit-Reveal²

> A provably secure distributed randomness generation protocol with randomized reveal order for mitigating last-revealer attacks

[![Solidity](https://img.shields.io/badge/Solidity-0.8.30-blue)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-black)](https://book.getfoundry.sh/)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

## 📋 Table of Contents

- [Commit-Reveal²](#commit-reveal)
  - [📋 Table of Contents](#-table-of-contents)
  - [Overview](#overview)
    - [Problem \& Solution](#problem--solution)
  - [Key Features](#key-features)
  - [Architecture](#architecture)
    - [Contract Hierarchy](#contract-hierarchy)
  - [Quick Start](#quick-start)
  - [Installation](#installation)
    - [Option 1: Standard Install](#option-1-standard-install)
    - [Option 2: Clean Install (if standard fails)](#option-2-clean-install-if-standard-fails)
    - [Option 3: Manual Commands](#option-3-manual-commands)
  - [Testing](#testing)
    - [Run All Tests](#run-all-tests)
    - [Run Specific Test Suites](#run-specific-test-suites)
  - [Gas Analysis](#gas-analysis)
    - [Gas Report Files](#gas-report-files)
  - [Protocol Flow](#protocol-flow)
    - [Phase 1: Commit](#phase-1-commit)
    - [Phase 2: Reveal-1](#phase-2-reveal-1)
    - [Phase 3: Reveal-2](#phase-3-reveal-2)
  - [Deployment](#deployment)
    - [Environment Setup](#environment-setup)
    - [Deploy to Networks](#deploy-to-networks)
  - [Documentation](#documentation)
    - [Resources](#resources)
  - [Contributing](#contributing)
    - [Reporting Issues](#reporting-issues)
  - [Contact](#contact)
  - [](#)

## Overview

Commit-Reveal² is an innovative distributed randomness generation protocol implemented as a smart contract on Ethereum. This protocol extends the traditional Commit-Reveal mechanism by introducing a **two-layer reveal process** that effectively mitigates the "last revealer attack" - a critical vulnerability in conventional randomness generation systems.

### Problem & Solution

**🔴 The Last Revealer Problem**
Traditional Commit-Reveal mechanisms suffer from poor liveness guarantees. When generating randomness for blockchain applications, a malicious actor who reveals last can choose whether to reveal their secret based on the potential result, creating unfair advantages when financial incentives are involved.

**✅ The Commit-Reveal² Solution**
Our protocol employs a dual-phase approach:

1. **First Layer**: Participants commit and reveal their initial values, generating an intermediate random value (Ωᵥ)
2. **Second Layer**: The intermediate randomness determines the reveal order for the final phase, preventing adversaries from positioning themselves as the last revealer

## Key Features

- 🛡️ **Provably Secure**: Cryptographically secure against manipulation attempts
- ⚡ **Gas Efficient**: Hybrid off-chain/on-chain model reduces gas costs
- 🔄 **Randomized Reveal Order**: Uses `dᵢ = hash(|Ωᵥ - cᵥ,ᵢ|)` to determine reveal sequence
- 📝 **Signatures**: Secure, replay-resistant authentication
- 🚨 **Comprehensive Dispute Resolution**: Handles participant and leader failures gracefully
- 💰 **Economic Incentives**: Deposit requirements and slashing mechanisms

## Architecture

### Contract Hierarchy

```
CommitReveal2.sol (Main Entry Point)
├── FailLogics.sol (Failure Recovery)
│   ├── DisputeLogics.sol (Dispute Resolution)
│   │   ├── OperatorManager.sol (Node Management)
│   │   └── CommitReveal2Storage.sol (State Management)
│   │       └── EIP712 (Signature Verification)
```

## Quick Start

```bash
# Clone the repository
git clone <repository-url>
cd Commit-Reveal2

# Run complete setup (recommended for first-time users)
make all
```

This command automatically:

1. 🧹 Cleans the project
2. 🗑️ Removes existing dependencies
3. 📦 Installs fresh dependencies
4. 🔄 Updates dependencies
5. 🔨 Builds the project

## Installation

### Option 1: Standard Install

```bash
make install
make build
```

### Option 2: Clean Install (if standard fails)

```bash
make install-clean
make build
```

### Option 3: Manual Commands

```bash
make clean
make remove
make install
make update
make build
```

## Testing

### Run All Tests

```bash
make test
```

### Run Specific Test Suites

```bash
# Gas analysis tests
forge test --match-path "test/gas/*" -vv --gas-limit 9999999999999999999 --isolate

# Manuscript-specific gas tests (see Gas Analysis section)
forge test --match-path "test/gas/ForManuscriptGas.t.sol" -vv --gas-limit 9999999999999999999 --isolate

# Protocol flow tests
forge test --mp test/staging/CommitReveal2Flowchart.t.sol -vvv --gas-limit 9999999999999999999

# Fuzz tests
forge test --match-path "test/fuzz/*"
```

## Gas Analysis

### Gas Report Files

- `output/gasreport.json` - Main gas analysis results
- `output/gasreportForManuscript.json` - Manuscript-specific analysis

## Protocol Flow

The protocol operates in three main phases:

### Phase 1: Commit

1. Generate secret: `Sᵢ = Gen()`
2. Create commitments:
   - `Cₒ,ᵢ = hash(Sᵢ)`
   - `Cᵥ,ᵢ = hash(Cₒ,ᵢ)`
3. Submit Merkle Root (leader)

### Phase 2: Reveal-1

1. Broadcast `Cₒ,ᵢ`
2. Verify: `hash(Cₒ,ᵢ) = Cᵥ,ᵢ`
3. Calculate reveal order:
   - `Ωᵥ = hash(Cₒ,₁||...||Cₒ,ₙ)`
   - `dᵢ = hash(|Ωᵥ - Cᵥ,ᵢ|)`
   - Sort by descending `dᵢ` values

### Phase 3: Reveal-2

1. Broadcast `Sᵢ` according to reveal order
2. Verify: `hash(Sᵢ) = Cₒ,ᵢ` and `i = π(k)`
3. Generate random number: `Ωₒ = hash(S₁||...||Sₙ)`

## Deployment

### Environment Setup

Create a `.env` file:

```bash
# Deployer Configuration
PRIVATE_KEY=<your-private-key>
DEPLOYER=<your-eoa-address>

# Ethereum Sepolia
ETHERSCAN_API_KEY=<etherscan-api-key>
SEPOLIA_RPC_URL=<sepolia-rpc-url>

# Optimism Sepolia
OP_SEPOLIA_RPC_URL=<op-sepolia-rpc-url>
OP_ETHERSCAN_API_KEY=<op-etherscan-api-key>
```

### Deploy to Networks

```bash
# Local (Anvil)
make anvil  # In terminal 1
make deploy # In terminal 2

# Testnets
make deploy ARGS="--network sepolia"
make deploy ARGS="--network opsepolia"
```

## Documentation

### Resources

- 📊 [Protocol Flowchart](https://excalidraw.com/#json=6gr9LfUBozMdFagAMMPzk,pARfIn49cdAU8NrDn86tKA) - Visual representation of all protocol states
- 📄 [ICBC 2025 Paper](https://arxiv.org/abs/2504.03936) - Academic publication
- 📖 [Medium Article](https://medium.com/tokamak-network/distributed-random-beacon-a-trusted-decentralized-randomness-generation-on-blockchains-bbeee97df0f4) - Non-technical overview

## Contributing

We welcome contributions! Please follow these steps:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make changes and test: `make all && make test`
4. Commit changes: `git commit -m "feat: description"`
5. Push to branch: `git push origin feature-name`
6. Submit a pull request

### Reporting Issues

Create issues on the [GitHub repository](https://github.com/tokamak-network/Commit-Reveal2/issues)

## Contact

- **Justin**: usgeeus@gmail.com | justin@tokamak.network
- **Suhyeon**: suhyeon@tokamak.network

##
