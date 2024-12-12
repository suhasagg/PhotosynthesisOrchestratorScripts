#!/bin/bash

# Configuration Variables
ARCHWAYD_BINARY="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/build/archwayd"
STRIDED_BINARY="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/build/strided"
ARCHWAYD_HOME="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/dockernet/state/photo1"

CONTRACT_ADDRESS="archway14hj2tavq8fpesdwxxcu44rty3hh90vhujrvcmstl4zr3txmfvw9sy85n2u"  # Replace with contract address
CHAIN_ID="localnet"  # Update as per network configuration
NODE_URL="http://localhost:26457"  # Update as per node's RPC URL
KEYRING_BACKEND="test"
OWNER_KEY_NAME="pval5"  # Replace with the contract owner key name

# Contract Metadata Parametersa
CONTRACT_ADDRESS_TO_SET="archway1ghd753shjuwexxywmgs4xz7x2q732vcnkm6h2pyv9s6ah3hylvrqvlzdpl"  # Address of the contract to set metadata for
REWARDS_ADDRESS="archway1m062ly7dt42nke40hsmqsnk0xtag8rqhhruf8x"  # Rewards address associated with the contract
LIQUIDITY_PROVIDER_ADDRESS="archway1he6g65qj44gtgnve7dzre6m55dz7ql0srzn46h"
REDEMPTION_ADDRESS="archway1dpm8hstetl3y8agyznwaak0ruhap0dmznd79lu"  # Liquidity provider address
MINIMUM_REWARD_AMOUNT="1000"  # Minimum reward amount in uarch (example value)
MAXIMUM_REWARD_AMOUNT="100000000000000"  # Maximum reward amount in uarch (example value)

# Ensure binary is executable
chmod +x $ARCHWAYD_BINARY

# Construct the SetContractMetadata execute message
EXECUTE_MSG='{
  "SetContractMetadata": {
    "contract_address": "'$CONTRACT_ADDRESS_TO_SET'",
    "rewards_address": "'$REWARDS_ADDRESS'",
    "liquidity_provider_address": "'$LIQUIDITY_PROVIDER_ADDRESS'",
    "redemption_address": "'$REDEMPTION_ADDRESS'",
    "minimum_reward_amount": "'$MINIMUM_REWARD_AMOUNT'",
    "maximum_reward_amount": "'$MAXIMUM_REWARD_AMOUNT'"
  }
}'

# Print the execute message
echo "Execute Message:"
echo "$EXECUTE_MSG" | jq '.'

# Execute the transaction to set the contract metadata
#SET_METADATA_CMD="$ARCHWAYD_BINARY tx wasm execute $CONTRACT_ADDRESS '$EXECUTE_MSG' \
#    --from $OWNER_KEY_NAME --home $ARCHWAYD_HOME --chain-id $CHAIN_ID \
#    --node $NODE_URL --keyring-backend $KEYRING_BACKEND --gas auto \
#    --gas-adjustment 1.5 --fees 300000uarch -y"

SET_METADATA_CMD="$ARCHWAYD_BINARY tx wasm execute $CONTRACT_ADDRESS '$EXECUTE_MSG' \
    --from $OWNER_KEY_NAME --home $ARCHWAYD_HOME --chain-id $CHAIN_ID \
    --node $NODE_URL --keyring-backend $KEYRING_BACKEND \
    --gas auto --gas-prices $($ARCHWAYD_BINARY q rewards estimate-fees 1 --node $NODE_URL --output json | jq -r '.gas_unit_price | (.amount + .denom)') --gas-adjustment 1.4 -y"


echo "Executing command:"
echo "$SET_METADATA_CMD"

# Execute the command
SET_METADATA_OUTPUT=$(eval "$SET_METADATA_CMD")

# Output the result
echo "Transaction Output:"
echo "$SET_METADATA_OUTPUT"

# Optionally, wait for the transaction to be included in a block
sleep 5

# Query the contract to confirm the metadata is set (optional)
QUERY_MSG='{
  "GetContractMetadata": {
    "contract": "'$CONTRACT_ADDRESS_TO_SET'"
  }
}'

QUERY_CMD="$ARCHWAYD_BINARY query wasm contract-state smart $CONTRACT_ADDRESS '$QUERY_MSG' \
    --home $ARCHWAYD_HOME --chain-id $CHAIN_ID --node $NODE_URL --output json"

echo "Querying contract metadata:"
echo "$QUERY_CMD"

QUERY_OUTPUT=$(eval "$QUERY_CMD")

echo "Query Output:"
echo "$QUERY_OUTPUT" | jq '.'
