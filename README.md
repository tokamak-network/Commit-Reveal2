# Getting Started

## Requirements

- [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  - You'll know you did it right if you can run `git --version` and you see a response like `git version x.x.x`
- [foundry](https://getfoundry.sh/)
  - You'll know you did it right if you can run `forge --version` and you see a response like `forge 0.2.0 (d14a7b4 2024-11-24T00:24:44.637144000Z)`

## Quickstart

For a clean installation (recommended for first-time setup or when dependencies fail):

```
make all
```

This command will:

1. Clean the project (`make clean`)
2. Remove existing dependencies (`make remove`)
3. Install fresh dependencies (`make install`)
4. Update dependencies (`make update`)
5. Build the project (`make build`)

### Alternative Installation Options

#### Option 1: Manual Installation (when dependencies are clean)

```
make install
make build
```

#### Option 2: Clean Install (when `make install` fails)

```
make install-clean
make build
```

#### Option 3: Full Clean Build (most reliable)

```
make all
```

**Troubleshooting**: If you encounter "already exists and is not a valid git repo" error:

- **Quick fix**: Use `make install-clean` or `make all`
- **Manual fix**: Delete the `lib/` directory and run `make install`

## Test

```
make test
```

## Deploy and Verify on Explorer

### Set .env

```
PRIVATE_KEY=<Private Key of the DEPLOYER>
DEPLOYER=<EOA ADDRESS>
ETHERSCAN_API_KEY=<Etherscan API Key>
SEPOLIA_RPC_URL=<Sepolia RPC URL>
OP_SEPOLIA_RPC_URL=<Optimism Sepolia RPC URL>
OP_ETHERSCAN_API_KEY=<Optimism Etherscan API Key>
THANOS_SEPOLIA_URL=https://rpc.titan-sepolia.tokamak.network
THANOS_SEPOLIA_EXPLORER=https://explorer.titan-sepolia.tokamak.network/api
```

## Deploy to a real network

You can deploy by setting up an .env file for the network you want to deploy to and referring to the script below.
The command below will deploy and verify two contracts, CommitReveal2 and ConsumerExample.

```
make deploy ARGS="--network thanossepolia"
make deploy ARGS="--network opsepolia"
make deploy ARGS="--network sepolia"
```

## Deploy to a local node

### Start a local node

```
make anvil
```

### Deploy

```
make deploy
```

DEFAULT_ANVIL_ADDRESS = 0xBcd4042DE499D14e55001CcbB24a551F3b954096

DEFAULT_ANVIL_KEY = 0xf214f2b2cd398c806f84e317254e0f0b801d0643303237d97a22a48e01628897
