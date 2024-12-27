# Getting Started

## Requirements

- [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  - You'll know you did it right if you can run `git --version` and you see a response like `git version x.x.x`
- [foundry](https://getfoundry.sh/)
  - You'll know you did it right if you can run `forge --version` and you see a response like `forge 0.2.0 (d14a7b4 2024-11-24T00:24:44.637144000Z)`

## Quickstart

```
git clone https://github.com/tokamak-network/Commit-Reveal2.git
cd Commit-Reveal2
make install
make build
```

## Test

```
make test
```

## Deploy and Verify on Explorer

### Set .env

```
PRIVATE_KEY=<Private Key>
ETHERSCAN_API_KEY=<Etherscan API Key>
SEPOLIA_RPC_URL=<Sepolia RPC URL>
OP_SEPOLIA_RPC_URL=<Optimism Sepolia RPC URL>
OP_ETHERSCAN_API_KEY=<Optimism Etherscan API Key>
THANOS_SEPOLIA_URL=https://rpc.titan-sepolia.tokamak.network
THANOS_SEPOLIA_EXPLORER=https://explorer.titan-sepolia.tokamak.network/api
```

You can deploy by setting up an .env file for the network you want to deploy to and referring to the script below.
The command below will deploy and verify two contracts, CommitReveal2 and ConsumerExample.

```
make deploy ARGS="--network thanossepolia"
make deploy ARGS="--network opsepolia"
make deploy ARGS="--network sepolia"
```
