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

- Foundry installed (`forge`, `cast`)

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

MIT
