#!/bin/bash

# Configuration
ARCHWAYD_BINARY="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/build/archwayd"
ARCHWAYD_HOME="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/dockernet/state/photo1"
CHAIN_ID="localnet"
WALLET="pval5"
NODE_URL="http://localhost:26457"
CONTRACT_ADDR="archway14hj2tavq8fpesdwxxcu44rty3hh90vhujrvcmstl4zr3txmfvw9sy85n2u"  # Replace with actual contract address

# Execute cron tasks via smart contract transaction
echo "Executing cron tasks using smart contract..." | jq -R -c '{"message": .}'
OUTPUT=$($ARCHWAYD_BINARY tx wasm execute $CONTRACT_ADDR '{"CronJob":{}}' \
  --from $WALLET --home $ARCHWAYD_HOME --chain-id $CHAIN_ID \
  --node http://localhost:26457 --gas auto --gas-prices $($ARCHWAYD_BINARY q rewards estimate-fees 1 --node $NODE_URL --output json | jq -r '.gas_unit_price | (.amount + .denom)') --gas-adjustment 1.4 -y)

# Check if the transaction was successful
echo "$OUTPUT" | jq -R -c '{"transaction_output": .}'

# Extract transaction hash
TX_HASH=$(echo "$OUTPUT" | grep -oP 'txhash: \K.*')
if [ -n "$TX_HASH" ]; then
  echo "Transaction successfully broadcasted. TX Hash: $TX_HASH" | jq -R -c '{"message": .}'
else
  echo "Failed to extract TX Hash." | jq -R -c '{"error": .}'
  exit 1
fi

# Query the transaction details
sleep 2  # Wait for the transaction to propagate
TX_DETAILS=$($ARCHWAYD_BINARY q tx $TX_HASH --home $ARCHWAYD_HOME --chain-id $CHAIN_ID --output json)
echo "$TX_DETAILS" | jq -R -c '{"transaction_details": .}'

# Check for any errors in the transaction
if echo "$TX_DETAILS" | grep -q '"code": 0'; then
  echo "Transaction executed successfully." | jq -R -c '{"message": .}'
else
  echo "Transaction failed." | jq -R -c '{"error": .}'
  exit 1
fi

# Print final message
echo "Script execution completed." | jq -R -c '{"message": .}'
