## Commit-Reveal²

This repository contains an implementation of the Commit-Reveal² protocol, as described in the paper:

Suhyeon Lee, Euisin Gee, Najmeh Soroush, and Kaibin Huang, "Commit-Reveal²: Securing Randomness Beacons with Randomized Reveal Order in Smart Contracts," <Journal-Info>

### What this repo focuses on

- Reproducible gas measurements across dispute and failure scenarios
- JSON and Markdown artifacts under `output/` that summarize scenario-by-scenario gas costs
- A Foundry-based test suite that generates the artifacts deterministically

## Outputs

Artifacts are written to `output/` by the gas tests:

- `gasreport.json`: Consolidated gas measurements across scenarios
- `gasreportForManuscript.json`: Subset tailored for manuscript figures/tables
- `failToSubmitCv_GasUsageRegressionAnalysis.md`, `failToSubmitCo_GasUsageRegressionAnalysis.md`, `generateRandomNumber_GasUsageRegressionAnalysis.md`: Human-readable summaries
- `commitreveal2hybrid.json`, `commitreveal2onchain.json`: Additional aggregated results for hybrid vs on-chain flows

All JSON artifacts include a `description` that explains each scenario key and parameters. Refer to those in-file descriptions for exact meanings used in figures/tables.

Note: The `output/` folder contains all datasets used in the manuscript. The generating tests live under `test/gas/` and write the artifacts above.

## Reproduce the outputs

### Prerequisites

- 🛡️ **Provably Secure**: Cryptographically secure against manipulation attempts
- ⚡ **Gas Efficient**: Hybrid off-chain/on-chain model reduces gas costs
- 🔄 **Randomized Reveal Order**: Uses `dᵢ = hash(Ωᵥ || cᵥ,ᵢ)` to determine reveal sequence
- 📝 **Signatures**: Secure, replay-resistant authentication
- 🚨 **Comprehensive Dispute Resolution**: Handles participant and leader failures gracefully
- 💰 **Economic Incentives**: Deposit requirements and slashing mechanisms

### Install & build

```bash
make all
```

### Run tests

```bash
make test
```

The tests write JSON/Markdown into `output/`.

## Minimal protocol overview

- Commit: operators generate `Sᵢ`, set `Cₒ,ᵢ = hash(Sᵢ)`, `Cᵥ,ᵢ = hash(Cₒ,ᵢ)`, and the leader submits a Merkle root
- Reveal-1: publish `Cₒ,ᵢ`; verify `hash(Cₒ,ᵢ) = Cᵥ,ᵢ`; compute `Ωᵥ = hash(Cₒ,⋯)`, sort by `dᵢ = hash(|Ωᵥ, Cᵥ,ᵢ|)`
- Reveal-2: operators reveal `Sᵢ` in the sorted order; verify consistency; aggregate randomness

## Project structure (selected)

- `src/` core contracts (`CommitReveal2.sol`, `DisputeLogics.sol`, storage, operator mgmt)
- `test/gas/` gas measurement suites (dispute and failure paths)
- `script/` deployment and interaction scripts; `Makefile` contains convenience targets
- `output/` generated gas artifacts

## Deployment (optional)

Create `.env` (RPCs, keys), then:

```bash
make anvil          # start local chain
make deploy         # deploy contracts and consumer example
```

## License

### Gas Report Files

- `output/gasreport.json` - Main gas analysis results
- `output/gasreportForManuscript.json` - Manuscript-specific analysis

## Protocol Flow

The protocol operates in three main phases:

### Phase 1: Commit

1. Generate secret: `Sᵢ = Gen()`
2. Create commitments:
   - `Cₒ,ᵢ = hash(Sᵢ)`
   - `Cᵥ,ᵢ = hash(Cₒ,ᵢ || i)` where `i` is the operator's index
3. Submit Merkle Root (leader)

### Phase 2: Reveal-1

1. Broadcast `Cₒ,ᵢ`
2. Verify: `hash(Cₒ,ᵢ || i) = Cᵥ,ᵢ` where `i` is the operator's index
3. Calculate reveal order:
   - `Ωᵥ = hash(Cₒ,₁||...||Cₒ,ₙ)`
   - `dᵢ = hash(|Ωᵥ || Cᵥ,ᵢ|)`
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
