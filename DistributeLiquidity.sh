#!/bin/bash

# Configuration Variables
ARCHWAYD_BINARY="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/build/archwayd"
STRIDED_BINARY="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/build/strided"
ARCHWAYD_HOME="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/dockernet/state/photo1"
CONTRACT_ADDRESS="archway14hj2tavq8fpesdwxxcu44rty3hh90vhujrvcmstl4zr3txmfvw9sy85n2u"  # Replace with actual smart contract address
CHAIN_ID="localnet"
NODE_URL="http://localhost:26457"
KEYRING_BACKEND="test"
FROM_ACCOUNT="archway1n3fvgm3ck5wylx6q4tsywglg82vxflj3h8e90m"  # Update with sender account
GAS_FEE="17000uarch"
WALLET_NAME="pval5"  # Replace with wallet name

# Ensure binary is executable
chmod +x "$ARCHWAYD_BINARY"

# Log the timestamp
echo "$(date +"%Y-%m-%d %H:%M:%S")" | jq -R -c '{"timestamp": .}'

# Initialize variables
AMOUNT=0


STUARCH_AMOUNT_FILE="/home/keanu-xbox/stuarch_amount.txt"  # Update the path if necessary
if [[ -f "$STUARCH_AMOUNT_FILE" ]]; then
    STUARCH_OBTAINED=$(cat "$STUARCH_AMOUNT_FILE")
    echo "Stuarch amount obtained from liquidstake.sh: $STUARCH_OBTAINED" | jq -R -c '{"message": .}'
else
    echo "Stuarch amount file not found. Ensure liquidstake.sh has run and created the stuarch_amount.txt file." | jq -R -c '{"error": .}'
    exit 1
fi


AMOUNT=$((STUARCH_OBTAINED - 30000))

# Prepare the execute message
DISTRIBUTE_LIQUIDITY_MSG='{"DistributeLiquidity":{}}'

# Function to execute the transaction with retries
execute_with_retries() {
    local MAX_RETRIES=3
    local RETRY_DELAY=5
    local RETRY_COUNT=0
    local SUCCESS=0

    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        echo "Attempt $(($RETRY_COUNT + 1)) to distribute liquidity..." | jq -R -c '{"message": .}'

        CMD="$ARCHWAYD_BINARY tx wasm execute $CONTRACT_ADDRESS '$DISTRIBUTE_LIQUIDITY_MSG' --from $WALLET_NAME --home $ARCHWAYD_HOME --chain-id $CHAIN_ID --node $NODE_URL --keyring-backend $KEYRING_BACKEND --gas auto --gas-prices $("$ARCHWAYD_BINARY" q rewards estimate-fees 1 --node "$NODE_URL" --output json | jq -r '.gas_unit_price | (.amount + .denom)') --gas-adjustment 1.4 -y"
        echo "$CMD" | jq -R -c '{"command": .}'

        OUTPUT=$(eval "$CMD" 2>&1)
        TX_HASH=$(echo "$OUTPUT" | grep -oP 'txhash: \K.*')

        if [ $? -eq 0 ] && [ -n "$TX_HASH" ]; then
            echo "Transaction submitted successfully. TX Hash: $TX_HASH" | jq -R -c '{"message": .}'
            SUCCESS=1

            # Wait for the transaction to be included in a block
            sleep 5

            # Query the transaction result
            TX_RESULT=$("$ARCHWAYD_BINARY" query tx "$TX_HASH" --chain-id "$CHAIN_ID" --node "$NODE_URL" --output json)
            TX_CODE=$(echo "$TX_RESULT" | jq -r '.code')

            if [ "$TX_CODE" == "0" ]; then
                echo "Transaction executed successfully." | jq -R -c '{"message": .}'
                break
            else
                echo "Transaction failed with code $TX_CODE. Retrying..." | jq -R -c '{"message": .}'
                SUCCESS=0
            fi
        else
            echo "Error submitting transaction: $OUTPUT" | jq -R -c '{"error": .}'
        fi

        RETRY_COUNT=$(($RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "Retrying in $RETRY_DELAY seconds..." | jq -R -c '{"message": .}'
            sleep $RETRY_DELAY
        else
            echo "Maximum retries reached. Exiting." | jq -R -c '{"message": .}'
            exit 1
        fi
    done

    if [ $SUCCESS -ne 1 ]; then
        echo "Failed to distribute liquidity after $MAX_RETRIES attempts." | jq -R -c '{"message": .}'
        exit 1
    fi
}

# Execute the transaction with retries
execute_with_retries

# Query all stake ratios from the smart contract
echo "Querying all stake ratios from the smart contract..." | jq -R -c '{"message": .}'
ALL_STAKE_RATIOS_OUTPUT=$("$ARCHWAYD_BINARY" query wasm contract-state smart "$CONTRACT_ADDRESS" '{"GetAllStakeRatios":{}}' --chain-id "$CHAIN_ID" --node "$NODE_URL" --output json)
if [ $? -ne 0 ]; then
    echo "Error querying stake ratios." | jq -R -c '{"error": .}'
    exit 1
fi

# Parse the output for stake ratios
STAKING_RATIOS=$(echo "$ALL_STAKE_RATIOS_OUTPUT" | jq '.data')
if [ -z "$STAKING_RATIOS" ] || [ "$STAKING_RATIOS" == "null" ]; then
    echo "No stake ratios available." | jq -R -c '{"message": .}'
    exit 0
fi

echo "Stake ratios fetched successfully: $STAKING_RATIOS" | jq -R -c '{"message": .}'

# Declare associative arrays for mapping
declare -A contractToLiquidityAddress
declare -A contractToStakeRatio

# Initialize total stake ratio
TOTAL_STAKE_RATIO=0

# Iterate over each contract and store stake ratios
while read -r entry; do
    CONTRACT_ADDR=$(echo "$entry" | jq -r '.[0]')
    STAKE_RATIO=$(echo "$entry" | jq -r '.[1]')
    contractToStakeRatio["$CONTRACT_ADDR"]=$STAKE_RATIO
    TOTAL_STAKE_RATIO=$(echo "$TOTAL_STAKE_RATIO + $STAKE_RATIO" | bc)
done < <(echo "$STAKING_RATIOS" | jq -c '.[]')

echo "Total Stake Ratio: $TOTAL_STAKE_RATIO" | jq -R -c '{"message": .}'

# For each contract, fetch the liquidity_address
for CONTRACT_ADDR in "${!contractToStakeRatio[@]}"; do
    echo "Processing contract: $CONTRACT_ADDR" | jq -R -c '{"message": .}'

    # Fetch contract metadata
    METADATA_OUTPUT=$("$ARCHWAYD_BINARY" query wasm contract-state smart "$CONTRACT_ADDRESS" '{"GetContractMetadata":{"contract":"'"$CONTRACT_ADDR"'"}}' --home "$ARCHWAYD_HOME" --chain-id "$CHAIN_ID" --node "$NODE_URL" --output json)
    if [ $? -ne 0 ]; then
        echo "Error querying contract metadata for $CONTRACT_ADDR." | jq -R -c '{"error": .}'
        continue
    fi

    # Extract liquidity_address from metadata
    LIQUIDITY_ADDRESS=$(echo "$METADATA_OUTPUT" | jq -r '.data.liquidity_provider_address')
    echo "Liquidity address for contract $CONTRACT_ADDR: $LIQUIDITY_ADDRESS" | jq -R -c '{"message": .}'

    # Map contract address to liquidity_address
    contractToLiquidityAddress["$CONTRACT_ADDR"]=$LIQUIDITY_ADDRESS
done

# Now, distribute liquidity tokens by calling the DistributeLiquidity execute message
echo "Processing distribution of liquidity tokens via smart contract..." | jq -R -c '{"message": .}'


sleep 5

# Now, distribute liquidity tokens based on stake ratios
for CONTRACT_ADDR in "${!contractToLiquidityAddress[@]}"; do
    LIQUIDITY_ADDRESS=${contractToLiquidityAddress["$CONTRACT_ADDR"]}
    STAKE_RATIO=${contractToStakeRatio["$CONTRACT_ADDR"]}
    echo "Processing distribution for contract: $CONTRACT_ADDR, Liquidity Address: $LIQUIDITY_ADDRESS, Stake Ratio: $STAKE_RATIO" | jq -R -c '{"message": .}'

    # Calculate the proportional liquidity amount
    PROPORTIONAL_AMOUNT=$(echo "scale=0; ($AMOUNT * $STAKE_RATIO) / $TOTAL_STAKE_RATIO" | bc)
    PROPORTIONAL_AMOUNT_INT=${PROPORTIONAL_AMOUNT%.*}  # Get integer part

    echo "Distributing $PROPORTIONAL_AMOUNT_INT tokens to $LIQUIDITY_ADDRESS" | jq -R -c '{"message": .}'

    # Execute the liquidity transfer command
    CMD="$ARCHWAYD_BINARY tx bank send $FROM_ACCOUNT $LIQUIDITY_ADDRESS ${PROPORTIONAL_AMOUNT_INT}ibc/15CE03505E1F9891F448F53C9A06FD6C6AF9E5BE7CBB0A4B45F7BE5C9CBFC145 --home $ARCHWAYD_HOME --chain-id $CHAIN_ID --node $NODE_URL --keyring-backend $KEYRING_BACKEND --gas auto --gas-prices $("$ARCHWAYD_BINARY" q rewards estimate-fees 1 --node "$NODE_URL" --output json | jq -r '.gas_unit_price | (.amount + .denom)') --gas-adjustment 1.4 -y"

    echo "Executing: $CMD" | jq -R -c '{"command": .}'

    # Retry logic for the transfer command
    MAX_RETRIES=5
    RETRY_COUNT=0
    SUCCESS=0

    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        output=$($CMD 2>&1)
        echo "$output" | jq -R -c '{"output": .}'

        # Check if the transaction was successful
        TX_HASH=$(echo "$output" | grep -oP 'txhash: \K.*')
        if [ -n "$TX_HASH" ]; then
            echo "Successfully distributed $PROPORTIONAL_AMOUNT_INT tokens to $LIQUIDITY_ADDRESS. Transaction hash: $TX_HASH" | jq -R -c '{"message": .}'
            SUCCESS=1
            break
        else
            echo "Error distributing liquidity to $LIQUIDITY_ADDRESS: $output" | jq -R -c '{"error": .}'
            echo "Retrying in 5 seconds..." | jq -R -c '{"message": .}'
            sleep 5
            RETRY_COUNT=$((RETRY_COUNT + 1))
        fi
    done

    if [ $SUCCESS -eq 0 ]; then
        echo "Failed to distribute liquidity to $LIQUIDITY_ADDRESS after $MAX_RETRIES attempts." | jq -R -c '{"error": .}'
    fi

    # Collect successful distributions
    if [ $SUCCESS -eq 1 ]; then
        distributions+=("{\"liquidity_address\":\"$LIQUIDITY_ADDRESS\",\"amount\":\"$PROPORTIONAL_AMOUNT_INT\"}")
    fi

    sleep 1 # Optional delay to prevent rate-limiting issues
done

sleep 5


distributions_json=$(printf "%s\n" "${distributions[@]}" | jq -s '.')

# Prepare the execute message for emitting the event
EMIT_EVENT_MSG=$(cat <<EOF
{
  "EmitDistributeLiquidityEvent": {
    "distributions": $distributions_json
  }
}
EOF
)

echo "Emitting distribute liquidity event..." | jq -R -c '{"message": .}'

# Retry logic for emitting the distribute liquidity event
MAX_RETRIES=5
RETRY_COUNT=0
SUCCESS=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    EMIT_EVENT_CMD="$ARCHWAYD_BINARY tx wasm execute $CONTRACT_ADDRESS '$EMIT_EVENT_MSG' --from $WALLET_NAME --home $ARCHWAYD_HOME --chain-id $CHAIN_ID --node $NODE_URL --keyring-backend $KEYRING_BACKEND --gas auto --gas-prices $("$ARCHWAYD_BINARY" q rewards estimate-fees 1 --node "$NODE_URL" --output json | jq -r '.gas_unit_price | (.amount + .denom)') --gas-adjustment 1.4 -y"
    echo "$EMIT_EVENT_CMD" | jq -R -c '{"command": .}'

    EMIT_EVENT_OUTPUT=$(eval "$EMIT_EVENT_CMD")
    echo "$EMIT_EVENT_OUTPUT" | jq -R -c '{"emit_event_output": .}'

    # Check if the transaction was successful
    TX_HASH_EVENT=$(echo "$EMIT_EVENT_OUTPUT" | grep -oP 'txhash: \K.*')
    if [ -n "$TX_HASH_EVENT" ]; then
        echo "Distribute liquidity event emitted successfully. Transaction hash: $TX_HASH_EVENT" | jq -R -c '{"message": .}'
        SUCCESS=1
        break
    else
        echo "Failed to emit distribute liquidity event. Retrying in 5 seconds..." | jq -R -c '{"error": .}'
        sleep 5
        RETRY_COUNT=$((RETRY_COUNT + 1))
    fi
done

if [ $SUCCESS -eq 0 ]; then
    echo "Failed to emit distribute liquidity event after $MAX_RETRIES attempts." | jq -R -c '{"error": .}'
    exit 1
fi

sleep 5

# Reset the stake ratios in the smart contract with retries
echo "Resetting stake ratios in the smart contract..." | jq -R -c '{"message": .}'

MAX_RETRIES=5
RETRY_COUNT=0
SUCCESS=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    RESET_STAKE_RATIOS_MSG='{"ResetStakeRatios":{}}'

    RESET_STAKE_RATIOS_CMD="$ARCHWAYD_BINARY tx wasm execute $CONTRACT_ADDRESS '$RESET_STAKE_RATIOS_MSG' --from $WALLET_NAME --home $ARCHWAYD_HOME --chain-id $CHAIN_ID --node $NODE_URL --keyring-backend $KEYRING_BACKEND --gas auto --gas-prices $("$ARCHWAYD_BINARY" q rewards estimate-fees 1 --node "$NODE_URL" --output json | jq -r '.gas_unit_price | (.amount + .denom)') --gas-adjustment 1.4 -y"

    echo "$RESET_STAKE_RATIOS_CMD" | jq -R -c '{"command": .}'

    RESET_OUTPUT=$(eval "$RESET_STAKE_RATIOS_CMD" 2>&1)
    echo "$RESET_OUTPUT" | jq -R -c '{"output": .}'
    RESET_TX_HASH=$(echo "$RESET_OUTPUT" | grep -oP 'txhash: \K.*')

    if [ $? -eq 0 ] && [ -n "$RESET_TX_HASH" ]; then
        echo "Stake ratios reset transaction submitted. TX Hash: $RESET_TX_HASH" | jq -R -c '{"message": .}'

        # Wait for the transaction to be included in a block
        sleep 5

        # Query the transaction result
        RESET_TX_RESULT=$("$ARCHWAYD_BINARY" query tx "$RESET_TX_HASH" --chain-id "$CHAIN_ID" --node "$NODE_URL" --output json)
        RESET_TX_CODE=$(echo "$RESET_TX_RESULT" | jq -r '.code')

        if [ "$RESET_TX_CODE" == "0" ]; then
            echo "Stake ratios reset successfully." | jq -R -c '{"message": .}'
            SUCCESS=1
            break
        else
            echo "Failed to reset stake ratios. Transaction code: $RESET_TX_CODE" | jq -R -c '{"error": .}'
        fi
    else
        echo "Error resetting stake ratios: $RESET_OUTPUT" | jq -R -c '{"error": .}'
    fi

    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        echo "Retrying in 5 seconds..." | jq -R -c '{"message": .}'
        sleep 5
    else
        echo "Maximum retries reached. Exiting." | jq -R -c '{"message": .}'
        exit 1
    fi
done

if [ $SUCCESS -ne 1 ]; then
    echo "Failed to reset stake ratios after $MAX_RETRIES attempts." | jq -R -c '{"message": .}'
    exit 1
fi

# Query balance of each liquidity address
for CONTRACT_ADDR in "${!contractToLiquidityAddress[@]}"; do
    LIQUIDITY_ADDRESS=${contractToLiquidityAddress["$CONTRACT_ADDR"]}
    echo "Querying balance for Liquidity Address: $LIQUIDITY_ADDRESS" | jq -R -c '{"message": .}'

    CMD="$ARCHWAYD_BINARY q bank balances $LIQUIDITY_ADDRESS --chain-id $CHAIN_ID --node $NODE_URL --output json"
    BALANCE_OUTPUT=$($CMD 2>&1)

    if [ $? -ne 0 ]; then
        echo "Error querying balance for $LIQUIDITY_ADDRESS: $BALANCE_OUTPUT" | jq -R -c '{"error": .}'
        continue
    fi

    echo "Balance for $LIQUIDITY_ADDRESS:" | jq -R -c '{"message": .}'
    echo "$BALANCE_OUTPUT" | jq '.'
done

# Final timestamp and completion message
echo "$(date +"%Y-%m-%d %H:%M:%S")" | jq -R -c '{"timestamp": .}'
echo "Script execution completed." | jq -R -c '{"message": .}'
