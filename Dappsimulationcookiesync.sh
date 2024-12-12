#!/bin/bash

set -e  # Stop the script on errors

# Define Variables
PASSPHRASE="your_passphrase"
CONTAINER_HOME="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/dockernet/state/photo1"
CONTRACT_BINARY_PATH="/home/keanu-xbox/smartcontractlogs/cookiesync-cw-multi_test/artifacts/dapps.wasm"
CHAIN_ID="localnet"
FEES="500000uarch"
LABEL="CookieSync"
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

if [ -z "$TX_HASH" ]; then
    echo "Failed to retrieve transaction hash. Exiting..."
    exit 1
fi

echo "Transaction Hash: $TX_HASH"
sleep 5  # Wait before querying the transaction

# Query transaction to get Code ID
echo "Querying transaction details..."
QUERY_OUTPUT=$(build/archwayd --home "$CONTAINER_HOME" q tx "$TX_HASH")
echo "$QUERY_OUTPUT"
sleep 5  # Allow time for the query to complete

# Extract Code ID
CODE_ID=$(echo "$QUERY_OUTPUT" | grep -oP '"code_id","value":"\K[0-9]+')
if [ -z "$CODE_ID" ]; then
    echo "Failed to retrieve Code ID. Exiting..."
    exit 1
fi

echo "Code ID: $CODE_ID"
sleep 5

# Add Keys
KEYS=("l113" "l213" "l313" "l413")
ADDRESSES=()

for KEY in "${KEYS[@]}"; do
    echo "Adding key: $KEY"
    sleep 2
    KEY_OUTPUT=$(echo -e "$PASSPHRASE\n$PASSPHRASE" | build/archwayd --home "$CONTAINER_HOME" keys add "$KEY" --keyring-backend=test)
    echo "$KEY_OUTPUT"
    ADDRESS=$(echo "$KEY_OUTPUT" | grep "address:" | awk '{print $2}')
    ADDRESSES+=("$ADDRESS")
done

REWARD_ADDRESS=${ADDRESSES[0]}
MINTER_ADDRESS=${ADDRESSES[1]}
LIQUIDITY_ADDRESS=${ADDRESSES[2]}
REDEMPTION_ADDRESS=${ADDRESSES[3]}

echo "Reward Address: $REWARD_ADDRESS"
echo "Minter Address: $MINTER_ADDRESS"
echo "Liquidity Address: $LIQUIDITY_ADDRESS"
echo "Redemption Address: $REDEMPTION_ADDRESS"
sleep 3

# Instantiate CookieSync Contract
echo "Instantiating the CookieSync contract..."
INIT_MSG=$(cat <<EOF
{
    "cookies": [],
    "total_cookies": 0
}
EOF
)

OUTPUT=$(build/archwayd --home "$CONTAINER_HOME" tx wasm instantiate "$CODE_ID" "$INIT_MSG" \
    --label "$LABEL" --from pval3 --keyring-backend test --chain-id "$CHAIN_ID" --fees "$FEES" --gas "$GAS" --no-admin -y)
echo "$OUTPUT"
sleep 5  # Allow time for the instantiation to process

# Extract transaction hash of the instantiation
txhash=$(echo "$OUTPUT" | grep -oP 'txhash: \K.*')
txhash=$(echo "$txhash" | tr -dc '[:xdigit:]')

if [ -z "$txhash" ]; then
    echo "Failed to retrieve instantiation transaction hash. Exiting..."
    exit 1
fi

sleep 5

# Query the instantiation transaction
echo "Querying the instantiation transaction..."
string=$(build/archwayd q tx --home "$CONTAINER_HOME" "$txhash")
echo "$string"
sleep 5

# Extract sender and contract address
pattern="archway"

sender=$(echo "$string" | grep -oP 'sender:\s*\Karchway[\w]*')
contract_address=$(echo "$string" | grep -oP '"_contract_address","value":"\Karchway[\w]*')

for variable in "$sender" "$contract_address"; do
  if [[ $variable == *"$pattern"* ]]; then
    echo "Pattern found in $variable"
  else
    echo "Pattern not found in $variable"
  fi
done

echo "Sender: $sender"
echo "Contract Address: $contract_address"
sleep 5

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

