#!/bin/bash

# Configuration Variables
ARCHWAYD_BINARY="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/build/archwayd"
ARCHWAYD_HOME="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/dockernet/state/photo1"
CONTRACT_ADDRESS="archway14hj2tavq8fpesdwxxcu44rty3hh90vhujrvcmstl4zr3txmfvw9sy85n2u"  # Replace with actual smart contract address
CHAIN_ID="localnet"
NODE_URL="http://localhost:26457"
KEYRING_BACKEND="test"
OWNER_KEY_NAME="pval5"  # Replace with the key name of the contract owner

# Ensure binary is executable
chmod +x $ARCHWAYD_BINARY

# Log the timestamp
echo $(date +"%Y-%m-%d %H:%M:%S") | jq -R -c '{"timestamp": .}'

# Fetch all contract addresses and their metadata from the smart contract
echo "Fetching all contract addresses from the smart contract..." | jq -R -c '{"message": .}'

# Query all contract addresses
CONTRACTS_OUTPUT=$($ARCHWAYD_BINARY query wasm contract-state smart $CONTRACT_ADDRESS '{"GetAllContracts":{}}' --home $ARCHWAYD_HOME --chain-id $CHAIN_ID --node $NODE_URL --output json)
if [ $? -ne 0 ]; then
    echo "Error querying contract addresses." | jq -R -c '{"error": .}'
    exit 1
fi

# Parse the contract addresses from the output
CONTRACT_ADDRESSES=$(echo $CONTRACTS_OUTPUT | jq -r '.data[]')
echo "Contract addresses fetched: $CONTRACT_ADDRESSES" | jq -R -c '{"message": .}'

# Declare associative arrays for mapping
declare -A contractToKeyName
declare -A contractToRewardsAddress

# For each contract, fetch the metadata and store rewards_address
for CONTRACT_ADDR in $CONTRACT_ADDRESSES; do
    echo "Processing contract: $CONTRACT_ADDR" | jq -R -c '{"message": .}'

    # Fetch contract metadata
    METADATA_OUTPUT=$($ARCHWAYD_BINARY query wasm contract-state smart $CONTRACT_ADDRESS '{"GetContractMetadata":{"contract":"'$CONTRACT_ADDR'"}}' --home $ARCHWAYD_HOME --chain-id $CHAIN_ID --node $NODE_URL --output json)
    if [ $? -ne 0 ]; then
        echo "Error querying contract metadata for $CONTRACT_ADDR." | jq -R -c '{"error": .}'
        continue
    fi

    # Extract rewards_address from metadata
    REWARDS_ADDRESS=$(echo $METADATA_OUTPUT | jq -r '.data.rewards_address')
    echo "Rewards address for contract $CONTRACT_ADDR: $REWARDS_ADDRESS" | jq -R -c '{"message": .}'

    # Map contract address to rewards_address
    contractToRewardsAddress[$CONTRACT_ADDR]=$REWARDS_ADDRESS
done

# Fetch local key names and addresses
echo "Fetching local key names and addresses..." | jq -R -c '{"message": .}'
KEYS_OUTPUT=$($ARCHWAYD_BINARY keys list --home $ARCHWAYD_HOME --keyring-backend $KEYRING_BACKEND --output json)
if [ $? -ne 0 ]; then
    echo "Error fetching key list." | jq -R -c '{"error": .}'
    exit 1
fi

# Build a map of addresses to key names
for row in $(echo "${KEYS_OUTPUT}" | jq -r '.[] | @base64'); do
    _jq() {
     echo ${row} | base64 --decode | jq -r ${1}
    }
    KEY_NAME=$(_jq '.name')
    ADDRESS=$(_jq '.address')
    contractToKeyName[$ADDRESS]=$KEY_NAME
    echo "Key name: $KEY_NAME, Address: $ADDRESS" | jq -R -c '{"message": .}'
done

# Prepare the list of reward updates
updates=()

# Now, for each contract, retrieve reward amounts and collect updates
for CONTRACT_ADDR in "${!contractToRewardsAddress[@]}"; do
    REWARDS_ADDRESS=${contractToRewardsAddress[$CONTRACT_ADDR]}
    KEY_NAME=${contractToKeyName[$CONTRACT_ADDR]}
    echo "Processing rewards for contract: $CONTRACT_ADDR, Rewards Address: $REWARDS_ADDRESS, Key Name: $KEY_NAME" | jq -R -c '{"message": .}'

    # Fetch the reward amount for the rewards_address
    REWARDS_OUTPUT=$($ARCHWAYD_BINARY query rewards outstanding-rewards $REWARDS_ADDRESS --home $ARCHWAYD_HOME --chain-id $CHAIN_ID --node $NODE_URL --output json)
    if [ $? -ne 0 ]; then
        echo "Error querying outstanding rewards for $REWARDS_ADDRESS." | jq -R -c '{"error": .}'
        continue
    fi

    # Extract total reward amount
    TOTAL_REWARDS=$(echo $REWARDS_OUTPUT | jq -r '.total_rewards[0].amount')
    if [ -z "$TOTAL_REWARDS" ] || [ "$TOTAL_REWARDS" == "null" ]; then
        echo "No rewards available for $REWARDS_ADDRESS." | jq -R -c '{"message": .}'
        continue
    fi
    echo "Total rewards for $REWARDS_ADDRESS: $TOTAL_REWARDS" | jq -R -c '{"message": .}'

    # Claim reward records
    echo "Claiming reward records for $REWARDS_ADDRESS..." | jq -R -c '{"message": .}'
    CLAIM_CMD="$ARCHWAYD_BINARY tx rewards withdraw-rewards --from $KEY_NAME --home $ARCHWAYD_HOME --chain-id $CHAIN_ID --node $NODE_URL --keyring-backend $KEYRING_BACKEND --gas auto --gas-prices $(archwayd q rewards estimate-fees 1 --node 'http://localhost:26457' --output json | jq -r '.gas_unit_price | (.amount + .denom)') --gas-adjustment 1.4 -y"
    echo "$CLAIM_CMD" | jq -R -c '{"command": .}'
    CLAIM_OUTPUT=$(eval $CLAIM_CMD)
    echo "$CLAIM_OUTPUT" | jq -R -c '{"claim_output": .}'
    sleep 5
    # TOTAL_REWARDS=$((TOTAL_REWARDS / 1000))
    # Add to updates array
    updates+=("{\"contract_address\":\"$CONTRACT_ADDR\",\"amount\":\"$TOTAL_REWARDS\"}")
done

# Check if there are any updates to process
if [ ${#updates[@]} -eq 0 ]; then
    echo "No rewards to update." | jq -R -c '{"message": .}'
    exit 0
fi

# Construct the bulk_update_rewards message
updates_json=$(printf "%s\n" "${updates[@]}" | jq -s '.')
BULK_UPDATE_MSG='{
    "BulkUpdateRewards": {
        "updates": '$updates_json'
    }
}'

# Execute the bulk update rewards transaction
echo "Executing bulk update rewards..." | jq -R -c '{"message": .}'
BULK_UPDATE_CMD="$ARCHWAYD_BINARY tx wasm execute $CONTRACT_ADDRESS '$BULK_UPDATE_MSG' --from $OWNER_KEY_NAME --home $ARCHWAYD_HOME --chain-id $CHAIN_ID --node $NODE_URL --keyring-backend $KEYRING_BACKEND --gas auto --gas-prices $(archwayd q rewards estimate-fees 1 --node 'http://localhost:26457' --output json | jq -r '.gas_unit_price | (.amount + .denom)') --gas-adjustment 1.4 -y"
echo "$BULK_UPDATE_CMD" | jq -R -c '{"command": .}'
BULK_UPDATE_OUTPUT=$(eval $BULK_UPDATE_CMD)
echo "$BULK_UPDATE_OUTPUT" | jq -R -c '{"bulk_update_output": .}'
sleep 5

# Final timestamp and completion message
echo $(date +"%Y-%m-%d %H:%M:%S") | jq -R -c '{"timestamp": .}'
echo "Script execution completed." | jq -R -c '{"message": .}'
