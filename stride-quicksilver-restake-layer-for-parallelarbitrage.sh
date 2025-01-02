#!/bin/bash

############################################
# 1. Environment Variables & Setup
############################################

# Archway binaries & paths
ARCHWAYD_BINARY="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/build/archwayd"
ARCHWAYD_HOME="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/dockernet/state/photo1"

# Stride binaries & paths
STRIDED_BINARY="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/build/strided"
STRIDE_HOME="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/dockernet/state/stride1"

# Quicksilver binaries & paths (NEW)
QUICKSILVERD_BINARY="/path/to/quicksilverd"             
QUICKSILVER_HOME="/path/to/quicksilver/home"            

# Archway chain details
CONTRACT_ADDRESS="archway14hj2tavq8fpesdwxxcu44rty3hh90vhujrvcmstl4zr3txmfvw9sy85n2u"
CHAIN_ID="localnet"
NODE_URL="http://localhost:26457"
WALLET_NAME="pval5"             # Archway wallet name
KEYRING_BACKEND="test"

# Stride chain details
STRIDE_CHAIN_ID="STRIDE"
STRIDE_WALLET_ADDRESS="stride1u20df3trc2c2zdhm8qvh2hdjx9ewh00sv6eyy8"

# Quicksilver chain details (NEW) - adapt to your Quicksilver environment
QUICKSILVER_CHAIN_ID="quicksilver-2"                     # Example chain ID
QUICKSILVER_NODE_URL="http://localhost:26659"            # Example RPC
QUICKSILVER_WALLET_NAME="qckWallet"                      # Example Quicksilver wallet name
QUICKSILVER_KEYRING_BACKEND="test"

# Logging paths
REDEMPTIONRATE_LOG="/home/keanu-xbox/.../dockernet/logs/redemptionrate"
ERROR_FILE_PATH="/home/keanu-xbox/.../dockernet/logs/error_file.txt"

# Ensure binaries are executable
chmod +x "$ARCHWAYD_BINARY"
chmod +x "$STRIDED_BINARY"
chmod +x "$QUICKSILVERD_BINARY"  # NEW

# Timestamp log
echo "$(date +"%Y-%m-%d %H:%M:%S")" | jq -R -c '{"timestamp": .}'


############################################
# 2. Query Smart Contract for Liquid-Stake Amount
############################################

AMOUNT=0

echo "Querying reward summaries from the smart contract..." | jq -R -c '{"message": .}'
REWARD_SUMMARIES_OUTPUT=$("$ARCHWAYD_BINARY" query wasm contract-state smart "$CONTRACT_ADDRESS" '{"GetRewardSummaries":{}}' \
  --chain-id "$CHAIN_ID" \
  --node "$NODE_URL" \
  --output json)

if [ $? -ne 0 ]; then
    echo "Error querying reward summaries." | jq -R -c '{"error": .}'
    exit 1
fi

echo "Reward summaries:" | jq -R -c '{"message": .}'
echo "$REWARD_SUMMARIES_OUTPUT" | jq '.'

echo "Querying total liquid stake (including pending and completed deposits) from the smart contract..." | jq -R -c '{"message": .}'
TOTAL_LIQUID_STAKE_OUTPUT=$("$ARCHWAYD_BINARY" query wasm contract-state smart "$CONTRACT_ADDRESS" '{"GetTotalLiquidStakeQuery":{}}' \
  --chain-id "$CHAIN_ID" \
  --node "$NODE_URL" \
  --output json)

if [ $? -ne 0 ]; then
    echo "Error querying total liquid stake." | jq -R -c '{"error": .}'
    exit 1
fi

AMOUNT=$(echo "$TOTAL_LIQUID_STAKE_OUTPUT" | jq -r '.data')
if [ -z "$AMOUNT" ] || [ "$AMOUNT" == "null" ] || [ "$AMOUNT" == "0" ]; then
    echo "No amount available for liquid staking." | jq -R -c '{"message": .}'
    exit 0
fi

echo "Total amount to liquid stake: $AMOUNT" | jq -R -c '{"message": .}'


############################################
# 3. IBC Transfer from Archway to Stride
############################################

echo "Performing IBC transfer from Archway to Stride..." | jq -R -c '{"message": .}'
IBC_TRANSFER_CMD="$ARCHWAYD_BINARY tx ibc-transfer transfer transfer channel-0 $STRIDE_WALLET_ADDRESS ${AMOUNT}uarch \
  --from $WALLET_NAME \
  --home $ARCHWAYD_HOME \
  --keyring-backend $KEYRING_BACKEND \
  --chain-id $CHAIN_ID \
  --node $NODE_URL \
  --gas auto \
  --gas-prices \$("$ARCHWAYD_BINARY" q rewards estimate-fees 1 --node "$NODE_URL" --output json | jq -r '.gas_unit_price | (.amount + .denom)') \
  --gas-adjustment 1.4 -y"

echo "$IBC_TRANSFER_CMD"

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

echo "$(date +"%Y-%m-%d %H:%M:%S")" | jq -R -c '{"timestamp": .}'


############################################
# 4. Query Stride Account Balance
############################################

echo "Querying Stride account balance..." | jq -R -c '{"message": .}'
CMD="$STRIDED_BINARY --home $STRIDE_HOME q bank balances --chain-id $STRIDE_CHAIN_ID $STRIDE_WALLET_ADDRESS"
echo "$CMD" | jq -R -c '{"message": .}'
OUTPUT2=$(eval "$CMD")

# Convert YAML to JSON
json_output=$(echo "$OUTPUT2" | yq eval -j -)
echo "$json_output"
sleep 5


############################################
# 5. Liquid Stake on Stride (Mint stTokens)
############################################

echo "Listing host zone before liquid staking..." | jq -R -c '{"message": .}'
$STRIDED_BINARY --home "$STRIDE_HOME" q stakeibc list-host-zone >> "$REDEMPTIONRATE_LOG"

echo "Executing strided liquid stake..." | jq -R -c '{"message": .}'
SUCCESS=0

# Aggregate any previously errored amounts
if [[ -f "$ERROR_FILE_PATH" ]]; then
    PREVIOUS_AMOUNT=$(cat "$ERROR_FILE_PATH")
    AMOUNT=$(( AMOUNT + PREVIOUS_AMOUNT ))
fi

for i in {1..5}; do
    CMD="$STRIDED_BINARY --home $STRIDE_HOME tx stakeibc liquid-stake ${AMOUNT} uarch \
      --keyring-backend $KEYRING_BACKEND \
      --from admin \
      --chain-id $STRIDE_CHAIN_ID \
      -y"

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
        # Success
        SUCCESS=1

        echo "Subtracting supplied amount from TOTAL_LIQUID_STAKE in the smart contract..." | jq -R -c '{"message": .}'
        SUBTRACT_LIQUID_STAKE_CMD="$ARCHWAYD_BINARY tx wasm execute $CONTRACT_ADDRESS '{\"SubtractFromTotalLiquidStake\":{\"amount\":\"$AMOUNT\"}}' \
          --from $WALLET_NAME \
          --home $ARCHWAYD_HOME \
          --chain-id $CHAIN_ID \
          --node $NODE_URL \
          --gas auto \
          --gas-prices \$("$ARCHWAYD_BINARY" q rewards estimate-fees 1 --node "$NODE_URL" --output json | jq -r '.gas_unit_price | (.amount + .denom)') \
          --gas-adjustment 1.4 \
          -y"

        echo "$SUBTRACT_LIQUID_STAKE_CMD" | jq -R -c '{"message": .}'
        SUBTRACT_OUTPUT=$(eval "$SUBTRACT_LIQUID_STAKE_CMD")
        echo "$SUBTRACT_OUTPUT" | jq -R -c '{"message": .}'

        # Remove error file if it exists
        if [[ -f "$ERROR_FILE_PATH" ]]; then
            rm "$ERROR_FILE_PATH"
            echo "Error file removed successfully!" | jq -R -c '{"message": .}'
        fi
        break
    else
        echo "Failed to execute message detected. Retrying in 30 seconds..." | jq -R -c '{"message": .}'
        sleep 30
    fi
done

echo "Listing host zone after liquid staking..." | jq -R -c '{"message": .}'
$STRIDED_BINARY --home "$STRIDE_HOME" q stakeibc list-host-zone >> "$REDEMPTIONRATE_LOG"

echo "Querying Stride account balance after liquid staking..." | jq -R -c '{"message": .}'
OUTPUT1=$($STRIDED_BINARY --home "$STRIDE_HOME" q bank balances --chain-id $STRIDE_CHAIN_ID $STRIDE_WALLET_ADDRESS --output json)
echo "$OUTPUT1" | jq '.'

# Extract minted stTokens, e.g. stuarch
STUARCH_OBTAINED=$(echo "$OUTPUT1" | jq -r '.balances[] | select(.denom=="stuarch") | .amount')
echo "Liquid token amount (stuarch): $STUARCH_OBTAINED" | jq -R -c '{"message": .}'

sleep 5

# Prepare and emit event
echo "$STUARCH_OBTAINED - 30000" > /home/keanu-xbox/stuarch_amount.txt
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
MAX_RETRIES=5
RETRY_COUNT=0
SUCCESS=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    EMIT_EVENT_CMD="$ARCHWAYD_BINARY tx wasm execute $CONTRACT_ADDRESS '$EMIT_EVENT_MSG' \
      --from $WALLET_NAME \
      --home $ARCHWAYD_HOME \
      --chain-id $CHAIN_ID \
      --node $NODE_URL \
      --keyring-backend $KEYRING_BACKEND \
      --gas auto \
      --gas-prices \$("$ARCHWAYD_BINARY" q rewards estimate-fees 1 --node "$NODE_URL" --output json | jq -r '.gas_unit_price | (.amount + .denom)') \
      --gas-adjustment 1.4 \
      -y"

    echo "$EMIT_EVENT_CMD" | jq -R -c '{"command": .}'
    EMIT_EVENT_OUTPUT=$(eval "$EMIT_EVENT_CMD")
    echo "$EMIT_EVENT_OUTPUT" | jq -R -c '{"emit_event_output": .}'

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


############################################
# 6. (NEW) IBC Transfer from Stride to Quicksilver (Restake in Quicksilver)
############################################

# Instead of sending all stTokens back to Archway, let's restake them on Quicksilver!
# We'll transfer some or all of our stTokens (stuarch) to Quicksilver's deposit address.

# 6.1. Define how much to send to Quicksilver
STUARCH_TO_QUICKSILVER=$((STUARCH_OBTAINED - 30000))
if [ "$STUARCH_TO_QUICKSILVER" -le 0 ]; then
  echo "No stuarch to restake in Quicksilver. Exiting..." | jq -R -c '{"message": .}'
  exit 0
fi

echo "Performing IBC transfer of $STUARCH_TO_QUICKSILVER stuarch to Quicksilver deposit address..." | jq -R -c '{"message": .}'

# 6.2. Find Quicksilver deposit address for the 'Archway' host zone
#    - This step assumes that Quicksilver has an ICS zone registered for Archway.
#    - We'll query Quicksilver for the zone info:
QUICKSILVER_ZONE_ID="arch-localnet-1"   

echo "Querying Quicksilver zone info for $QUICKSILVER_ZONE_ID..." | jq -R -c '{"message": .}'
ZONE_INFO=$($QUICKSILVERD_BINARY --home "$QUICKSILVER_HOME" --node "$QUICKSILVER_NODE_URL" \
            q interchainstaking zone "$QUICKSILVER_ZONE_ID" --chain-id "$QUICKSILVER_CHAIN_ID" --output json 2>/dev/null)

DEPOSIT_ADDRESS=$(echo "$ZONE_INFO" | jq -r '.deposit_address.address')
if [ -z "$DEPOSIT_ADDRESS" ] || [ "$DEPOSIT_ADDRESS" == "null" ]; then
  echo "ERROR: Could not find deposit address on Quicksilver. Ensure the zone is registered." | jq -R -c '{"error": .}'
  exit 1
fi

echo "Quicksilver deposit address for Archway zone: $DEPOSIT_ADDRESS" | jq -R -c '{"message": .}'

# 6.3. IBC-transfer stTokens from Stride -> Quicksilver
#     channel-XX must be the IBC channel from Stride to Quicksilver
STRIDE_TO_QS_CHANNEL="channel-0" 

CMD="$STRIDED_BINARY --home $STRIDE_HOME tx ibc-transfer transfer transfer \
  $STRIDE_TO_QS_CHANNEL \
  $DEPOSIT_ADDRESS \
  ${STUARCH_TO_QUICKSILVER}stuarch \
  --from admin \
  --keyring-backend $KEYRING_BACKEND \
  --chain-id $STRIDE_CHAIN_ID \
  -y --fees 30000stuarch"

echo "$CMD" | jq -R -c '{"message": .}'

MAX_RETRIES=5
RETRY_COUNT=0
SUCCESS=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    OUTPUT=$(eval "$CMD")
    json_output=$(echo "$OUTPUT" | yq eval -j -)
    echo "$json_output"

    txhash=$(echo "$OUTPUT" | grep -oP 'txhash: \K.*')
    if [ -z "$txhash" ]; then
        echo "Error: Failed to extract txhash for Stride->Quicksilver transfer." | jq -R -c '{"message": .}'
        ((RETRY_COUNT++))
        sleep 10
        continue
    fi

    echo "Transaction hash: $txhash" | jq -R -c '{"message": .}'
    txhash=$(echo "$txhash" | tr -dc '[:xdigit:]')
    sleep 4

    string=$($STRIDED_BINARY --home "$STRIDE_HOME" q tx "$txhash" --output json)
    if [[ "$string" != *"failed to execute message"* ]]; then
        SUCCESS=1
        break
    else
        echo "Failed to execute message. Retrying in 30 seconds..." | jq -R -c '{"message": .}'
        ((RETRY_COUNT++))
        sleep 30
    fi
done

if [ $SUCCESS -eq 0 ]; then
    echo "IBC transfer to Quicksilver failed after $MAX_RETRIES attempts." | jq -R -c '{"error": .}'
    exit 1
fi

echo "IBC transfer to Quicksilver deposit address complete." | jq -R -c '{"message": .}'
sleep 5


############################################
# 7. (NEW) Optional: Signal Intent on Quicksilver
############################################

# If Quicksilver requires manually signaling how to delegate to validators on the host chain (Archway),
# do here. Otherwise, Quicksilver may auto-delegate based on default settings.

echo "Signaling intent on Quicksilver (if required)..." | jq -R -c '{"message": .}'

SIGNAL_CMD="$QUICKSILVERD_BINARY --home $QUICKSILVER_HOME \
  tx interchainstaking signal-intent $QUICKSILVER_ZONE_ID \
  --intent \"archwayvaloper1xyz...,1.0\" \
  --from $QUICKSILVER_WALLET_NAME \
  --keyring-backend $QUICKSILVER_KEYRING_BACKEND \
  --chain-id $QUICKSILVER_CHAIN_ID \
  --node $QUICKSILVER_NODE_URL \
  --gas auto --gas-adjustment 1.5 \
  -y"

echo "$SIGNAL_CMD" | jq -R -c '{"message": .}'
SIGNAL_OUTPUT=$(eval "$SIGNAL_CMD")
echo "$SIGNAL_OUTPUT" | jq -R -c '{"signal_intent_output": .}'


############################################
# 8. (NEW) [Optional] Redeem from Quicksilver
############################################

# If one need to "unbond" from Quicksilver, one can redeem the q(stuarch) and finally can redeem stuarch at 2x rate obtained via parallel redemption rate arbitrage
# For example:
#   quicksilverd tx interchainstaking redeem 100000<qDenom> --from <myQckKey> ...
#


echo "Quicksilver restake flow completed successfully." | jq -R -c '{"message": .}'


############################################
# 10. Final Timestamp & Completion
############################################

echo "$(date +"%Y-%m-%d %H:%M:%S")" | jq -R -c '{"message": .}'
echo "Script execution completed with Quicksilver restake." | jq -R -c '{"message": .}'

