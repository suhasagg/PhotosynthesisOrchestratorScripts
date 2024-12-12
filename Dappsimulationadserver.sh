#!/bin/bash

set -e  # Stop the script on errors

# Define Variables
PASSPHRASE="your_passphrase"
CONTAINER_HOME="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/dockernet/state/photo1"
CONTRACT_BINARY_PATH="/home/keanu-xbox/smartcontractlogs/adserver-cw_multi_test/artifacts/dapps.wasm"
CHAIN_ID="localnet"
FEES="500000uarch"
LABEL="AdServer"
GAS="2000000"

# Store Contract
echo "Storing the WASM contract..."
STORE_OUTPUT=$(build/archwayd --home "$CONTAINER_HOME" tx wasm store "$CONTRACT_BINARY_PATH" \
    --from pval5 --keyring-backend test --fees "$FEES" --gas "$GAS" --chain-id "$CHAIN_ID" -y)

echo "$STORE_OUTPUT"
sleep 5  # Allow time for the transaction to process

# Extract transaction hash
TX_HASH=$(echo "$STORE_OUTPUT" | grep -oP 'txhash: \K.*')
TX_HASH=$(echo "$TX_HASH" | tr -dc '[:xdigit:]')

echo "Transaction Hash: $TX_HASH"
sleep 2

# Query transaction to get Code ID
echo "Querying transaction details..."
QUERY_OUTPUT=$(build/archwayd --home "$CONTAINER_HOME" q tx "$TX_HASH")
echo "$QUERY_OUTPUT"
sleep 3

# Extract Code ID
CODE_ID=$(echo "$QUERY_OUTPUT" | grep -oP '"code_id","value":"\K[0-9]+')
echo "Code ID: $CODE_ID"
sleep 2

# Add Keys
KEYS=("l112" "l212" "l312" "l412")
ADDRESSES=()

for KEY in "${KEYS[@]}"; do
    echo "Adding key: $KEY"
    sleep 2
    KEY_OUTPUT=$(echo -e "$PASSPHRASE\n$PASSPHRASE" | build/archwayd --home "$CONTAINER_HOME" keys add "$KEY" --keyring-backend=test)
    echo "$KEY_OUTPUT"
    ADDRESS=$(echo "$KEY_OUTPUT" | grep "address:" | awk '{print $2}')
    ADDRESSES+=("$ADDRESS")
done
sleep 3

REWARD_ADDRESS=${ADDRESSES[0]}
MINTER_ADDRESS=${ADDRESSES[1]}
LIQUIDITY_ADDRESS=${ADDRESSES[2]}
REDEMPTION_ADDRESS=${ADDRESSES[3]}

echo "Reward Address: $REWARD_ADDRESS"
echo "Minter Address: $MINTER_ADDRESS"
echo "Liquidity Address: $LIQUIDITY_ADDRESS"
echo "Redemption Address: $REDEMPTION_ADDRESS"
sleep 2

# Instantiate AdServer Contract
echo "Instantiating the AdServer contract..."
INIT_MSG=$(cat <<EOF
{
    "ads": [],
    "total_views": 0,
    "plt_address": "$REWARD_ADDRESS"
}
EOF
)

OUTPUT=$(build/archwayd --home "$CONTAINER_HOME" tx wasm instantiate "$CODE_ID" "$INIT_MSG" \
    --label "$LABEL" --from pval5 --keyring-backend test --chain-id "$CHAIN_ID" --fees "$FEES" --gas "$GAS" --no-admin -y)

sleep 5
echo "$OUTPUT"

txhash=$(echo "$OUTPUT" | grep -oP 'txhash: \K.*')
txhash=$(echo $txhash | tr -dc '[:xdigit:]')
sleep 4

# Execute the command and retrieve the output
string=$(build/archwayd q tx --home "$CONTAINER_HOME" $txhash)
sleep 3
echo "$string"

# Pattern to search
pattern="archway"

# Extract sender
sender=$(echo "$string" | grep -oP 'sender:\s*\Karchway[\w]*')

# Extract contract address
contract_address=$(echo "$string" | grep -oP '"_contract_address","value":"\Karchway[\w]*')

# Check if pattern exists in each string
for variable in "$sender" "$contract_address"; do
  if [[ $variable == *"$pattern"* ]]; then
    echo "Pattern found in $variable"
  else
    echo "Pattern not found in $variable"
  fi
done

# Print the variables
echo "Sender: $sender"
echo "Contract Address: $contract_address"
sleep 4


OUTPUT13=$(/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/build/archwayd --home /home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/dockernet/state/photo1  tx bank send  archway14zd6utea6u2zy5pd2yecphz8j9ydsq7x7qc8fu ${LIQUIDITY_ADDRESS} 100000uarch --from pval4 --keyring-backend=test --chain-id localnet --fees 17000uarch -y)

sleep 2
echo "$OUTPUT13"


# Set Contract Metadata
echo "Setting contract metadata..."
SET_METADATA_OUTPUT=$(build/archwayd --home "$CONTAINER_HOME" tx rewards set-contract-metadata "$contract_address" \
    --contract-address "$contract_address" --owner-address "$MINTER_ADDRESS" \
    --rewards-address "$REWARD_ADDRESS" --liquidity-provider-address "$LIQUIDITY_ADDRESS" \
    --redemption-address "$REDEMPTION_ADDRESS" --from pval3 --keyring-backend test \
    --chain-id "$CHAIN_ID" --fees "$FEES" --gas 205000 -y)

sleep 5
echo "$SET_METADATA_OUTPUT"

echo "Script execution completed successfully!"

