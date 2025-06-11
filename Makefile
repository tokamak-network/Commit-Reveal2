-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

DEFAULT_ANVIL_KEY := 0xf214f2b2cd398c806f84e317254e0f0b801d0643303237d97a22a48e01628897

help:
	@echo "Usage:"
	@echo "  make deploy [ARGS=...]\n    example: make deploy ARGS=\"--network thanossepolia\""
	@echo "    make deploy ARGS=\"--network sepolia\""
	@echo "    make deploy ARGS=\"--network opsepolia\""

.PHONY: all test clean deploy fund help install snapshot format anvil 

all: clean remove install update build

# Clean the repo
clean :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install OpenZeppelin/openzeppelin-contracts --no-commit && forge install Cyfrin/foundry-devops --no-commit && forge install vectorized/solady --no-commit

# Update Dependencies
update :; forge update

build :; forge build

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1 --accounts 11

NETWORK_ARGS := --rpc-url 127.0.0.1:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast -vv

NO_SIMULATION := --rpc-url 127.0.0.1:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast -vv --skip-simulation


ifeq ($(findstring --network sepolia,$(ARGS)), --network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --retries 20 --etherscan-api-key $(ETHERSCAN_API_KEY) -vv
endif
ifeq ($(findstring --network scriptsepolia,$(ARGS)), --network scriptsepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) -vvv --skip-simulation --broadcast
endif
ifeq ($(findstring --network scriptopsepolia,$(ARGS)), --network scriptopsepolia)
	NETWORK_ARGS := --rpc-url $(OP_SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) -vvv --skip-simulation --broadcast --disable-block-gas-limit
endif
ifeq ($(findstring --network scriptthanossepolia,$(ARGS)), --network scriptthanossepolia)
	NETWORK_ARGS := --rpc-url $(THANOS_SEPOLIA_URL) --private-key $(PRIVATE_KEY) -vvv --skip-simulation --broadcast --disable-block-gas-limit -g 300
endif
ifeq ($(findstring --network testsepolia,$(ARGS)), --network testsepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) -vvv
endif
ifeq ($(findstring --network testmainnet,$(ARGS)), --network testmainnet)
	NETWORK_ARGS := --rpc-url $(MAINNET_RPC_URL)  --private-key $(PRIVATE_KEY) -vvv
endif
ifeq ($(findstring --network opsepolia,$(ARGS)), --network opsepolia)
	NETWORK_ARGS := --rpc-url $(OP_SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(OP_ETHERSCAN_API_KEY) -vv --retries 20
endif
ifeq ($(findstring --network thanossepolia,$(ARGS)), --network thanossepolia)
	NETWORK_ARGS := --rpc-url $(THANOS_SEPOLIA_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --verifier blockscout --verifier-url $(THANOS_SEPOLIA_EXPLORER) -vv
endif

deploy: deploy-commit-reveal2 deploy-consumer-example-v2

set-test: deploy fundMyAccounts activateAndDeposit

anvil-deploy: anvil-deploy-commit-reveal2 deploy-consumer-example-v2

deploy-commit-reveal2:
	@forge script script/DeployCommitReveal2.s.sol:DeployCommitReveal2 $(NETWORK_ARGS)

anvil-deploy-commit-reveal2:
	@forge script script/DeployCommitReveal2.s.sol:AnvilDeployCommitReveal2 $(NETWORK_ARGS) --skip-simulation

deploy-consumer-example:
	@forge script script/DeployConsumerExample.s.sol:DeployConsumerExample $(NETWORK_ARGS)

deploy-consumer-example-v2:
	@forge script script/DeployConsumerExampleV2.s.sol:DeployConsumerExampleV2 $(NETWORK_ARGS)

deploy-consumer-v2-with-cr2:
	@forge script script/DeployConsumerExampleV2.s.sol:DeployConsumerExampleV2 $(NETWORK_ARGS) $(CR2) --sig "run(address)"

activateAndDeposit:
	@forge script script/Interactions.s.sol:OperatorsActivateAndDeposit $(NETWORK_ARGS)

anvilActivateAndDeposit:
	@forge script script/Interactions.s.sol:AnvilActivateAndDeposit $(NETWORK_ARGS)

testOneRound: testrequestAndSubmitMerkleRoot testgenerateRand

CE := 0x0000000000000000000000000000000000000000

requestRandomNumber:
	@forge script script/Interactions.s.sol:RequestRandomNumber $(NETWORK_ARGS) $(CE) --sig "run(address)"

testrequestAndSubmitMerkleRoot:
	@forge script script/Interactions.s.sol:SuccessfulPaths $(NETWORK_ARGS)

testSubmitAndGenerate: testsubmitMerkleRoot testgenerateRand

testsubmitMerkleRoot:
	@forge script script/Interactions.s.sol:SuccessfulPaths --sig "submitMerkleRoot()" $(NETWORK_ARGS)

testgenerateRand:
	@forge script script/Interactions.s.sol:SuccessfulPaths --sig "generateRandomNumber()" $(NETWORK_ARGS) -vv

withdraw:
	@forge script script/Interactions.s.sol:Withdraw $(NETWORK_ARGS)

## * Dispute Logic Interactions

fundMyAccounts:
	@forge script script/Interactions.s.sol:FundMyAccounts $(NETWORK_ARGS)

resume:
	@forge script script/AnvilDisputeLogicInteractions.s.sol:Resume $(NETWORK_ARGS)

requestToSubmitCv:
	@forge script script/AnvilDisputeLogicInteractions.s.sol:RequestToSubmitCv $(NETWORK_ARGS)

requestToSubmitCo:
	@forge script script/AnvilDisputeLogicInteractions.s.sol:RequestToSubmitCo $(NETWORK_ARGS)

requestToSubmitS:
	@forge script script/AnvilDisputeLogicInteractions.s.sol:RequestToSubmitS $(NETWORK_ARGS)

INDEX := 0

submitCv:
	@forge script script/AnvilDisputeLogicInteractions.s.sol:SubmitCv $(NETWORK_ARGS) --sig "run(uint256)" $(INDEX)

submitCo:
	@forge script script/AnvilDisputeLogicInteractions.s.sol:SubmitCo $(NETWORK_ARGS) --sig "run(uint256)" $(INDEX)

submitS:
	@forge script script/AnvilDisputeLogicInteractions.s.sol:SubmitS $(NETWORK_ARGS) --sig "run(uint256)" $(INDEX)

generateRandomNumberWhenSomeCvsAreOnChain:
	@forge script script/AnvilDisputeLogicInteractions.s.sol:GenerateRandomNumberWhenSomeCvsAreOnChain $(NETWORK_ARGS)

failToRequestSubmitCvOrSubmitMerkleRoot:
	@forge script script/AnvilDisputeLogicInteractions.s.sol:FailToRequestSubmitCvOrSubmitMerkleRoot $(NETWORK_ARGS)

failToRequestSorGenerateRandomNumber:
	@forge script script/AnvilDisputeLogicInteractions.s.sol:FailToRequestSorGenerateRandomNumber $(NETWORK_ARGS)


deploy-vrf:
	@forge script script/ChainlinkConsumerTest.s.sol:DeployChainlinkConsumer $(NETWORK_ARGS)

request-vrf:
	@forge script script/ChainlinkConsumerTest.s.sol:RequestRandomNumber $(NETWORK_ARGS)

test:
	@forge test --gas-limit 9999999999999999999 --isolate

test-vv:
	@forge test --gas-limit 9999999999999999999 --isolate -vv

test-flowchart:
	@forge test --mp test/staging/CommitReveal2Flowchart.t.sol -vvv --gas-limit 9999999999999999999

fuzz_test:
	@forge test --mp test/fuzz/CommitReveal2Fuzz.t.sol -vv --isolate

doc:
	@forge doc --serve --open

