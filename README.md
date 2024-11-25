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

## Set .env

```
PRIVATE_KEY=
TITAN_SEPOLIA_URL=https://rpc.titan-sepolia.tokamak.network
TITAN_SEPOLIA_EXPLORER=https://explorer.titan-sepolia.tokamak.network/api
OP_MAINNET_RPC_URL=<Optimism Mainnet RPC URL>
```

## Deploy

The evm_version is set to “paris” for the Titan network. Deploy CommitReveal2 and ConsumerExample contracts to Titan-Sepolia for testing.

```
make deploy-commit-reveal2 ARGS="--network titansepolia"
make deploy-consumer-example ARGS="--network titansepolia"
```

## Verify on Blockscout

```
make verify-commitreveal2 ADDRESS="<address>"
// eg. make verify-commitreveal2 ADDRESS="0x898FBed6452ed884954544CA93753bd5f974a459"

make verify-consumer-example DRB="<commitreveal2Address>" ADDRESS="<consumerExampleAddress>"
// eg.  make verify-consumer-example DRB="0x898FBed6452ed884954544CA93753bd5f974a459" ADDRESS="0xCf2A4d6FC95172FcF44221fB06592ffe49492F89"
```
