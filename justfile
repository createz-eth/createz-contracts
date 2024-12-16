alias b := build
alias t := test

default:
  just --list

# build
build:
  forge build --sizes

# build all
build-all: build test solhint pnpm-pack

# pnpm pack
pnpm-pack:
  pnpm pack

# test deploy to anvil
deploy-local:
  forge script script/Deploy.s.sol:DeployScript --fork-url http://localhost:8545 --broadcast

# deploy test data to anvil
deploy-local-test-data:
  forge script script/TestData.s.sol:TestDataScript --fork-url http://localhost:8545 --broadcast

# test deploy to anvil with test data
test-deploy-local: deploy-local deploy-local-test-data

# test deploy to anvil
deploy-update-local:
  forge script script/Update.s.sol:UpdateScript --fork-url http://localhost:8545 --broadcast

# test
test:
  forge test -vvv

# test contract
test-contract CONTRACT:
  forge test -vvv --match-contract {{CONTRACT}}

# run solhint
solhint:
  pnpm run solhint

# clean all
clean: forge-clean pnpm-clean clean-pack

forge-clean:
  forge clean

pnpm-clean:
  pnpm clean

clean-pack:
  rm -f subsub-contracts-*.tgz