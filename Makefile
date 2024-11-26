# Copyright 2024 justin
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     https://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

all: clean remove install update build

# Clean the repo
clean :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install OpenZeppelin/openzeppelin-contracts --no-commit && forge install Cyfrin/foundry-devops --no-commit

# Update Dependencies
update :; forge update

build :; forge build

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast --legacy --gas-limit 9999999999999999999

ifeq ($(findstring --network thanossepolia,$(ARGS)), --network thanossepolia)
	NETWORK_ARGS := --rpc-url $(THANOS_SEPOLIA_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --verifier blockscout --verifier-url https://explorer.thanos-sepolia.tokamak.network/api --etherscan-api-key 11 -vv
endif
ifeq ($(findstring --network sepolia,$(ARGS)), --network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vv
endif
ifeq ($(findstring --network opsepolia,$(ARGS)), --network opsepolia)
	NETWORK_ARGS := --rpc-url $(OP_SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(OP_ETHERSCAN_API_KEY) -vv
endif
ifeq ($(findstring --network titansepolia,$(ARGS)), --network titansepolia)
	NETWORK_ARGS := --rpc-url $(TITAN_SEPOLIA_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --verifier blockscout --verifier-url $(TITAN_SEPOLIA_EXPLORER) -vv --legacy
endif
# ifeq ($(findstring --network titan,$(ARGS)), --network titan)
# 	NETWORK_ARGS := --rpc-url $(TITAN_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --verifier blockscout --verifier-url $(TITAN_EXPLORER) -vv --legacy
# endif

deploy-commit-reveal2:
	@forge script script/DeployCommitReveal2.s.sol:DeployCommitReveal2 $(NETWORK_ARGS)

deploy-consumer-example:
	@forge script script/DeployConsumerExample.s.sol:DeployConsumerExample $(NETWORK_ARGS)

verify-commitreveal2:
	@CONSTRUCTOR_ARGS=$$(cast abi-encode "constructor(uint256,uint256,uint256,string,string)" 1000000000000000 10000000000000 10 "Tokamak DRB" "1") \
	forge verify-contract --constructor-args CONSTRUCTOR_ARGS --verifier blockscout --verifier-url $(TITAN_SEPOLIA_EXPLORER) --rpc-url $(TITAN_SEPOLIA_URL) $(ADDRESS) CommitReveal2

verify-consumer-example:
	@CONSTRUCTOR_ARGS=$$(cast abi-encode "constructor(address)" $(DRB)) \
	forge verify-contract --constructor-args CONSTRUCTOR_ARGS --verifier blockscout --verifier-url $(TITAN_SEPOLIA_EXPLORER) --rpc-url $(TITAN_SEPOLIA_URL) $(ADDRESS) ConsumerExample

test:
	@forge test --gas-limit 9999999999999999999 --isolate -vv