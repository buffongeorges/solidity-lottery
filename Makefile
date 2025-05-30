-include .env

.PHONY: all test deploy # these are targets that we are gonna use. So dont do funny things with those words

build:; forge build

test :
	forge test

install:; forge install cyfrin/foundry-devops@0.2.2 && forge install smartcontractkit/chainlink-brownie-contracts@1.1.1 && forge install foundry-rs/forge-std@v1.8.2 && forge install transmissions11/solmate@v6

deploy-sepolia :
	@forge script script/DeployRaffle.s.sol:DeployRaffle --rpc-url $(SEPOLIA_RPC_URL) --account myUser --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
# we are doing @forge do obfuscate in the terminal