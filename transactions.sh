#!/bin/bash

# Configuration Variables
ARCHWAYD_BINARY="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/build/archwayd"
ARCHWAYD_HOME="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/dockernet/state/photo1"
CHAIN_ID="localnet"
KEYRING_BACKEND="test"
GAS="205000"
FEES="20000aarch"
RETRY_DELAY=5
MAX_RETRIES=5
NODE_URL="http://localhost:26457"

# Function to execute a command with retries
execute_with_retries() {
    local CMD="$1"
    local RETRY_COUNT=0
    local SUCCESS=0
    local OUTPUT=""
    local TX_HASH=""

    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        echo "Attempt $((RETRY_COUNT+1)) executing command..."

        OUTPUT=$(eval "$CMD" 2>&1)
        echo "$OUTPUT"

        TX_HASH=$(echo "$OUTPUT" | grep -oP 'txhash: \K.*')

        if [ -n "$TX_HASH" ]; then
            echo "Transaction submitted successfully. TX Hash: $TX_HASH"
            SUCCESS=1
            break
        else
            echo "Error submitting transaction: $OUTPUT"
            echo "Retrying in $RETRY_DELAY seconds..."
            sleep $RETRY_DELAY
            RETRY_COUNT=$((RETRY_COUNT+1))
        fi
    done

    if [ $SUCCESS -eq 1 ]; then
        echo "Command executed successfully."
        echo "TX Hash: $TX_HASH"
    else
        echo "Failed to execute command after $MAX_RETRIES attempts."
    fi

    # Return the output
    echo "$OUTPUT"
}

# First loop with random iterations between 4 and 8
loop_iterations=0
echo "First loop will run $loop_iterations times."
for ((n=1; n<=loop_iterations; n++)); do
    echo "Iteration $n of the first loop."
    
    CMD="$ARCHWAYD_BINARY --home $ARCHWAYD_HOME tx wasm execute archway1nc5tatafv6eyq7llkr2gv50ff9e22mnf70qgjlv737ktmt4eswrqgj33g6 '{\"increase_allowance\": {\"spender\": \"archway1qygx0pxuttycdddzz5lre5rlxcxjemthwmlh63\", \"amount\": \"1\"}}' --from pval2 --chain-id $CHAIN_ID --keyring-backend=$KEYRING_BACKEND --gas auto --gas-prices \$($ARCHWAYD_BINARY q rewards estimate-fees 1 --node \"\$NODE_URL\" --output json | jq -r '.gas_unit_price | (.amount + .denom)') --gas-adjustment 1.4 -y"

    OUTPUT=$(eval $CMD)
    sleep 2
    echo "Script execution completed."

    # Extract txhash if needed
    txhash=$(echo "$OUTPUT" | grep -oP 'txhash: \K.*')
    echo "Transaction Hash: $txhash"
done

# Second loop with random iterations between 4 and 8
loop_iterations=0
echo "Second loop will run $loop_iterations times."
for ((n=1; n<=loop_iterations; n++)); do
    echo "Iteration $n of the second loop."

    CMD="$ARCHWAYD_BINARY --home $ARCHWAYD_HOME tx wasm execute archway17p9rzwnnfxcjp32un9ug7yhhzgtkhvl9jfksztgw5uh69wac2pgssf05p7 '{\"add_ad\": {\"id\": \"ad$n\", \"image_url\": \"http://example.com/image$n\", \"target_url\": \"http://example.com\", \"reward_address\": \"reward$n\"}}' --from pval2 --chain-id $CHAIN_ID --keyring-backend=$KEYRING_BACKEND --gas auto --gas-prices \$($ARCHWAYD_BINARY q rewards estimate-fees 1 --node \"\$NODE_URL\" --output json | jq -r '.gas_unit_price | (.amount + .denom)') --gas-adjustment 1.4 -y"

    OUTPUT=$(eval $CMD)
    sleep 2
    echo "Script execution completed."

    # Extract txhash if needed
    txhash=$(echo "$OUTPUT" | grep -oP 'txhash: \K.*')
    echo "Transaction Hash: $txhash"
done

# Third loop with random iterations between 4 and 8
loop_iterations=1
echo "Third loop will run $loop_iterations times."
for ((n=1; n<=loop_iterations; n++)); do
    echo "Iteration $n of the third loop."

    CMD="$ARCHWAYD_BINARY --home $ARCHWAYD_HOME tx wasm execute archway1ghd753shjuwexxywmgs4xz7x2q732vcnkm6h2pyv9s6ah3hylvrqvlzdpl '{\"add_cookie\": {\"id\": \"cookie$n\", \"domain\": \"example.com\", \"data\": \"cookie_data\", \"expiration\": 1609459200}}' --from pval2 --chain-id $CHAIN_ID --keyring-backend=$KEYRING_BACKEND --gas auto --gas-prices \$($ARCHWAYD_BINARY q rewards estimate-fees 1 --node \"\$NODE_URL\" --output json | jq -r '.gas_unit_price | (.amount + .denom)') --gas-adjustment 1.4 -y"

    OUTPUT=$(eval $CMD)
    sleep 2
    echo "Script execution completed."

    # Extract txhash if needed
    txhash=$(echo "$OUTPUT" | grep -oP 'txhash: \K.*')
    echo "Transaction Hash: $txhash"
done
