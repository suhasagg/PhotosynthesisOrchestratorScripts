#!/bin/bash

# Set variables for binary and state directories
ARCHWAYD_BINARY="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/build/archwayd"
STRIDED_BINARY="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/build/strided"
ARCHWAYD_HOME="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/dockernet/state/photo1"
STRIDE_HOME="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/dockernet/state/stride1"
CONTRACT_ADDRESS="archway14hj2tavq8fpesdwxxcu44rty3hh90vhujrvcmstl4zr3txmfvw9sy85n2u"  # Replace with actual contract address
CHAIN_ID="localnet"
NODE_URL="http://localhost:26457"
WALLET_NAME="pval5"
KEYRING_BACKEND="test"
STRIDE_CHAIN_ID="STRIDE"
STRIDE_WALLET_ADDRESS="stride1u20df3trc2c2zdhm8qvh2hdjx9ewh00sv6eyy8"
REDEMPTIONRATE_LOG="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/dockernet/logs/redemptionrate"
ERROR_FILE_PATH="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/dockernet/logs/error_file.txt"

# Ensure binaries are executable
chmod +x "$ARCHWAYD_BINARY"
chmod +x "$STRIDED_BINARY"

# Log the timestamp
echo "$(date +"%Y-%m-%d %H:%M:%S")" | jq -R -c '{"timestamp": .}'

# Initialize variables
AMOUNT=0

# Query reward summaries from the smart contract
echo "Querying reward summaries from the smart contract..." | jq -R -c '{"message": .}'
REWARD_SUMMARIES_OUTPUT=$("$ARCHWAYD_BINARY" query wasm contract-state smart "$CONTRACT_ADDRESS" '{"GetRewardSummaries":{}}' --chain-id "$CHAIN_ID" --node "$NODE_URL" --output json)

if [ $? -ne 0 ]; then
    echo "Error querying reward summaries." | jq -R -c '{"error": .}'
    exit 1
fi

# Output the reward summaries
echo "Reward summaries:" | jq -R -c '{"message": .}'
echo "$REWARD_SUMMARIES_OUTPUT" | jq '.'

# Query total liquid stake from the smart contract
echo "Querying total liquid stake (including pending and completed deposits) from the smart contract..." | jq -R -c '{"message": .}'
TOTAL_LIQUID_STAKE_OUTPUT=$("$ARCHWAYD_BINARY" query wasm contract-state smart "$CONTRACT_ADDRESS" '{"GetTotalLiquidStakeQuery":{}}' --chain-id "$CHAIN_ID" --node "$NODE_URL" --output json)
if [ $? -ne 0 ]; then
    echo "Error querying total liquid stake." | jq -R -c '{"error": .}'
    exit 1
fi

# Extract the amount to liquid stake
AMOUNT=$(echo "$TOTAL_LIQUID_STAKE_OUTPUT" | jq -r '.data')
if [ -z "$AMOUNT" ] || [ "$AMOUNT" == "null" ] || [ "$AMOUNT" == "0" ]; then
    echo "No amount available for liquid staking." | jq -R -c '{"message": .}'
    exit 0
fi

echo "Total amount to liquid stake: $AMOUNT" | jq -R -c '{"message": .}'

# Log the timestamp
echo "$(date +"%Y-%m-%d %H:%M:%S")" | jq -R -c '{"timestamp": .}'

# Perform IBC transfer from Archway to Stride
echo "Performing IBC transfer from Archway to Stride..." | jq -R -c '{"message": .}'
IBC_TRANSFER_CMD="$ARCHWAYD_BINARY tx ibc-transfer transfer transfer channel-0 $STRIDE_WALLET_ADDRESS ${AMOUNT}uarch --from $WALLET_NAME --home $ARCHWAYD_HOME --keyring-backend $KEYRING_BACKEND --chain-id $CHAIN_ID --node $NODE_URL --gas auto --gas-prices \$("$ARCHWAYD_BINARY" q rewards estimate-fees 1 --node "$NODE_URL" --output json | jq -r '.gas_unit_price | (.amount + .denom)') --gas-adjustment 1.4 -y"
echo "$IBC_TRANSFER_CMD"

# Retry logic for IBC transfer
MAX_RETRIES=10
RETRY_COUNT=0
SUCCESS=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo "Attempt $((RETRY_COUNT+1)): Executing IBC transfer..." | jq -R -c '{"message": .}'
    echo "$(date +"%Y-%m-%d %H:%M:%S")" | jq -R -c '{"timestamp": .}'
    
    OUTPUT=$(eval "$IBC_TRANSFER_CMD" 2>&1)
    TX_HASH=$(echo "$OUTPUT" | grep -oP 'txhash: \K.*')
    
    if [ -n "$TX_HASH" ]; then
        echo "IBC transfer successful. Transaction hash: $TX_HASH" | jq -R -c '{"message": .}'
        SUCCESS=1
        break
    else
        echo "IBC transfer failed. Retrying in 5 seconds..." | jq -R -c '{"error": .}'
        sleep 5
        RETRY_COUNT=$((RETRY_COUNT+1))
    fi
done

if [ $SUCCESS -eq 0 ]; then
    echo "IBC transfer failed after $MAX_RETRIES attempts." | jq -R -c '{"error": .}'
    exit 1
fi

# Log the timestamp
echo "$(date +"%Y-%m-%d %H:%M:%S")" | jq -R -c '{"timestamp": .}'

# Query Stride account balance
echo "Querying Stride account balance..." | jq -R -c '{"message": .}'
CMD="$STRIDED_BINARY --home $STRIDE_HOME q bank balances --chain-id $STRIDE_CHAIN_ID $STRIDE_WALLET_ADDRESS"
echo "$CMD" | jq -R -c '{"message": .}'
OUTPUT2=$(eval "$CMD")
# Convert the YAML output to JSON using yq
json_output=$(echo "$OUTPUT2" | yq eval -j -)

echo "$json_output"
sleep 5

# Log timestamp
echo "$(date +"%Y-%m-%d %H:%M:%S")" | jq -R -c '{"timestamp": .}'

# Add the command before liquid staking
echo "Listing host zone before liquid staking..." | jq -R -c '{"message": .}'
$STRIDED_BINARY --home "$STRIDE_HOME" q stakeibc list-host-zone >> "$REDEMPTIONRATE_LOG"

# Strided liquid stake
echo "Executing strided liquid stake..." | jq -R -c '{"message": .}'
SUCCESS=0

# If ERROR_FILE_PATH exists and has an amount written, aggregate it with AMOUNT
if [[ -f "$ERROR_FILE_PATH" ]]; then
    PREVIOUS_AMOUNT=$(cat "$ERROR_FILE_PATH")
    AMOUNT=$(( AMOUNT + PREVIOUS_AMOUNT ))
fi

for i in {1..5}; do
    CMD="$STRIDED_BINARY --home $STRIDE_HOME tx stakeibc liquid-stake ${AMOUNT} uarch --keyring-backend $KEYRING_BACKEND --from admin --chain-id $STRIDE_CHAIN_ID -y"
    echo "$CMD" | jq -R -c '{"message": .}'
    echo "$(date +"%Y-%m-%d %H:%M:%S")" | jq -R -c '{"message": .}'
    
    OUTPUT2=$(eval "$CMD")
    json_output=$(echo "$OUTPUT2" | yq eval -j -)
    echo "$json_output"
    txhash=$(echo "$OUTPUT2" | grep -oP 'txhash: \K.*')
    
    if [ -z "$txhash" ]; then
        echo "Error: Failed to extract txhash." | jq -R -c '{"message": .}'
        sleep 10
        continue
    fi
    
    echo "Transaction hash: $txhash" | jq -R -c '{"message": .}'
    txhash=$(echo "$txhash" | tr -dc '[:xdigit:]')
    sleep 4
    string=$($STRIDED_BINARY --home "$STRIDE_HOME" q tx "$txhash" --output json)
        
    if [[ "$string" != *"failed to execute message"* ]]; then
        # Successful execution
        SUCCESS=1

        # Subtract the supplied amount from TOTAL_LIQUID_STAKE in the smart contract
        echo "Subtracting supplied amount from TOTAL_LIQUID_STAKE in the smart contract..." | jq -R -c '{"message": .}'
        SUBTRACT_LIQUID_STAKE_CMD="$ARCHWAYD_BINARY tx wasm execute $CONTRACT_ADDRESS '{\"SubtractFromTotalLiquidStake\":{\"amount\":\"$AMOUNT\"}}' --from $WALLET_NAME --home $ARCHWAYD_HOME --chain-id $CHAIN_ID --node $NODE_URL --gas auto --gas-prices \$("$ARCHWAYD_BINARY" q rewards estimate-fees 1 --node "$NODE_URL" --output json | jq -r '.gas_unit_price | (.amount + .denom)') --gas-adjustment 1.4 -y"
        echo "$SUBTRACT_LIQUID_STAKE_CMD" | jq -R -c '{"message": .}'
        SUBTRACT_OUTPUT=$(eval "$SUBTRACT_LIQUID_STAKE_CMD")
        echo "$SUBTRACT_OUTPUT" | jq -R -c '{"message": .}'

        # Remove error file if exists
        if [[ -f "$ERROR_FILE_PATH" ]]; then
            rm "$ERROR_FILE_PATH"
            echo "Error file removed successfully!" | jq -R -c '{"message": .}'
        fi
        break
    else
        # Error encountered; sleep before retry
        echo "Failed to execute message detected. Retrying in 30 seconds..." | jq -R -c '{"message": .}'
        sleep 30
    fi
done

# Add the command after liquid staking
echo "Listing host zone after liquid staking..." | jq -R -c '{"message": .}'
$STRIDED_BINARY --home "$STRIDE_HOME" q stakeibc list-host-zone >> "$REDEMPTIONRATE_LOG"

# Querying Stride balance
echo "Querying Stride account balance after liquid staking..." | jq -R -c '{"message": .}'
OUTPUT1=$($STRIDED_BINARY --home "$STRIDE_HOME" q bank balances --chain-id $STRIDE_CHAIN_ID $STRIDE_WALLET_ADDRESS --output json)
echo "$OUTPUT1" | jq '.'

# Extract liquid token amount (stuarch)
amount=$(echo "$OUTPUT1" | jq -r '.balances[] | select(.denom=="stuarch") | .amount')
echo "Liquid token amount (stuarch): $amount" | jq -R -c '{"message": .}'

sleep 5

STUARCH_OBTAINED=$amount
echo "$STUARCH_OBTAINED - 30000" > /home/keanu-xbox/stuarch_amount.txt
# Prepare the execute message for emitting the event
EMIT_EVENT_MSG=$(cat <<EOF
{
  "EmitLiquidStakeEvent": {
    "total_liquid_stake": "$AMOUNT",
    "stuarch_obtained": "$STUARCH_OBTAINED",
    "tx_hash": "$txhash"
  }
}
EOF
)

echo "Emitting liquid stake event..." | jq -R -c '{"message": .}'

# Initialize retry variables
MAX_RETRIES=5
RETRY_COUNT=0
SUCCESS=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    EMIT_EVENT_CMD="$ARCHWAYD_BINARY tx wasm execute $CONTRACT_ADDRESS '$EMIT_EVENT_MSG' --from $WALLET_NAME --home $ARCHWAYD_HOME --chain-id $CHAIN_ID --node $NODE_URL --keyring-backend $KEYRING_BACKEND --gas auto --gas-prices \$("$ARCHWAYD_BINARY" q rewards estimate-fees 1 --node "$NODE_URL" --output json | jq -r '.gas_unit_price | (.amount + .denom)') --gas-adjustment 1.4 -y"
    echo "$EMIT_EVENT_CMD" | jq -R -c '{"command": .}'

    EMIT_EVENT_OUTPUT=$(eval "$EMIT_EVENT_CMD")
    echo "$EMIT_EVENT_OUTPUT" | jq -R -c '{"emit_event_output": .}'

    # Check if the transaction was successful
    TX_HASH_EVENT=$(echo "$EMIT_EVENT_OUTPUT" | grep -oP 'txhash: \K.*')
    if [ -n "$TX_HASH_EVENT" ]; then
        echo "Event emitted successfully. Transaction hash: $TX_HASH_EVENT" | jq -R -c '{"message": .}'
        SUCCESS=1
        break
    else
        echo "Failed to emit event. Retrying in 5 seconds..." | jq -R -c '{"error": .}'
        sleep 5
        RETRY_COUNT=$((RETRY_COUNT+1))
    fi
done

if [ $SUCCESS -eq 0 ]; then
    echo "Failed to emit event after $MAX_RETRIES attempts." | jq -R -c '{"error": .}'
    exit 1
fi

sleep 5

# Perform IBC transfer of liquid tokens back to Archway
amount=$((amount - 30000))
echo "Performing IBC transfer of liquid tokens back to Archway..." | jq -R -c '{"message": .}'
RETRY_COUNT=0
MAX_RETRIES=5
SUCCESS=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    CMD="$STRIDED_BINARY --home $STRIDE_HOME tx ibc-transfer transfer transfer channel-0 archway1n3fvgm3ck5wylx6q4tsywglg82vxflj3h8e90m ${amount}stuarch --from admin --keyring-backend $KEYRING_BACKEND --chain-id $STRIDE_CHAIN_ID -y --fees 30000stuarch"
    echo "$CMD" | jq -R -c '{"message": .}'

    OUTPUT=$(eval "$CMD")
    json_output=$(echo "$OUTPUT" | yq eval -j -)
    echo "$json_output"

    txhash=$(echo "$OUTPUT" | grep -oP 'txhash: \K.*')

    if [ -z "$txhash" ]; then
        echo "Error: Failed to extract txhash." | jq -R -c '{"message": .}'
        ((RETRY_COUNT++))
        sleep 10
        continue
    fi

    echo "Transaction hash for IBC transfer to Archway: $txhash" | jq -R -c '{"message": .}'
    txhash=$(echo "$txhash" | tr -dc '[:xdigit:]')
    sleep 4
    string=$($STRIDED_BINARY --home "$STRIDE_HOME" q tx "$txhash" --output json)

    if [[ "$string" != *"failed to execute message"* ]]; then
        SUCCESS=1
        break
    else
        echo "Failed to execute message detected. Retrying in 30 seconds..." | jq -R -c '{"message": .}'
        ((RETRY_COUNT++))
        sleep 30
    fi
done

sleep 5

# Query Archway liquidity account balance
echo "Querying Archway liquidity account balance..." | jq -R -c '{"message": .}'
ARCHWAY_LIQUIDITY_ACCOUNT="archway1n3fvgm3ck5wylx6q4tsywglg82vxflj3h8e90m"
CMD="$ARCHWAYD_BINARY --home $ARCHWAYD_HOME q bank balances --chain-id $CHAIN_ID $ARCHWAY_LIQUIDITY_ACCOUNT --node $NODE_URL --output json"
echo "$CMD" | jq -R -c '{"message": .}'
OUTPUT1=$(eval "$CMD")
echo "$OUTPUT1" | jq '.'

# Final timestamp and completion message
echo "$(date +"%Y-%m-%d %H:%M:%S")" | jq -R -c '{"message": .}'
echo "Script execution completed." | jq -R -c '{"message": .}'
