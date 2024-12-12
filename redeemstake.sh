#!/bin/bash

# Directories and Configurations
ARCHWAYD_BINARY="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/build/archwayd"
STRIDED_BINARY="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/build/strided"
ARCHWAYD_HOME="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/dockernet/state/photo1"
STRIDED_HOME="/home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/dockernet/state/stride1"
CONTRACT_ADDRESS="archway14hj2tavq8fpesdwxxcu44rty3hh90vhujrvcmstl4zr3txmfvw9sy85n2u"
CHAIN_ID="localnet"
NODE_URL="http://localhost:26457"
WALLET_NAME="pval5"
KEYRING_BACKEND="test"
FROM_ACCOUNT="archway1n3fvgm3ck5wylx6q4tsywglg82vxflj3h8e90m"
GAS_FEE="30000uarch"

# Ensure binaries are executable
chmod +x "$ARCHWAYD_BINARY"
chmod +x "$STRIDED_BINARY"

# Function to validate Bech32 address
validate_bech32() {
  local ADDRESS="$1"
  if [[ ! "$ADDRESS" =~ ^archway1[0-9a-z]{38}$ ]]; then
    echo "Invalid Bech32 address: $ADDRESS" | jq -R -c '{"error": .}' >&2
    return 1
  fi
  return 0
}

# Function to fetch all contracts
fetch_all_contracts() {
  echo "Fetching all contracts..." | jq -R -c '{"message": .}' >&2

  QUERY_MSG='{"GetAllContracts":{}}'
  CMD="$ARCHWAYD_BINARY query wasm contract-state smart $CONTRACT_ADDRESS '$QUERY_MSG' --chain-id $CHAIN_ID --node $NODE_URL --output json"

  echo "$CMD" | jq -R -c '{"command": .}' >&2
  OUTPUT=$(eval "$CMD")

  if [ $? -ne 0 ]; then
    echo "Error fetching contracts: $OUTPUT" | jq -R -c '{"error": .}' >&2
    exit 1
  fi

  CONTRACTS=$(echo "$OUTPUT" | jq -r '.data[]')

  if [ -z "$CONTRACTS" ] || [ "$CONTRACTS" == "null" ]; then
    echo "Error: Failed to retrieve contracts." | jq -R -c '{"message": .}' >&2
    exit 1
  fi

  echo "Contracts fetched: $CONTRACTS" | jq -R -c '{"message": .}' >&2
}

# Function to get contract metadata
get_contract_metadata() {
  local CONTRACT_ADDR="$1"

  QUERY_MSG="{\"GetContractMetadata\":{\"contract\":\"$CONTRACT_ADDR\"}}"
  CMD="$ARCHWAYD_BINARY query wasm contract-state smart $CONTRACT_ADDRESS '$QUERY_MSG' --home \"$ARCHWAYD_HOME\" --chain-id \"$CHAIN_ID\" --node \"$NODE_URL\" --output json"

  OUTPUT=$(eval "$CMD" 2>&1)
  if [ $? -ne 0 ]; then
    echo "Error fetching metadata for contract $CONTRACT_ADDR: $OUTPUT" | jq -R -c '{"error": .}' >&2
    return 1
  fi

  LIQUIDITY_ADDRESS=$(echo "$OUTPUT" | jq -r '.data.liquidity_provider_address')
  REWARDS_ADDRESS=$(echo "$OUTPUT" | jq -r '.data.rewards_address')

  if [ -z "$LIQUIDITY_ADDRESS" ] || [ -z "$REWARDS_ADDRESS" ]; then
    echo "Error: Missing liquidity or rewards address for contract $CONTRACT_ADDR" | jq -R -c '{"error": .}' >&2
    return 1
  fi

  echo "$LIQUIDITY_ADDRESS|$REWARDS_ADDRESS"
}

# Get balance of an address
get_balance() {
  local ADDRESS="$1"

  if [ -z "$ADDRESS" ]; then
    echo "Error: Address is empty" | jq -R -c '{"error": .}' >&2
    return 1
  fi

  validate_bech32 "$ADDRESS"
  if [ $? -ne 0 ]; then
    return 1
  fi

  # Build the command as an array to avoid issues with spaces or special characters
  CMD=("$ARCHWAYD_BINARY" q bank balances "$ADDRESS" --chain-id "$CHAIN_ID" --node "$NODE_URL" --output json)

  # Log the command to stderr
  echo "${CMD[@]}" | jq -R -c '{"command": .}' >&2

  # Execute the command and capture the output
  OUTPUT=$("${CMD[@]}" 2>&1)
  CMD_EXIT_CODE=$?

  if [ $CMD_EXIT_CODE -ne 0 ]; then
    echo "Error fetching balance for $ADDRESS: $OUTPUT" | jq -R -c '{"error": .}' >&2
    return $CMD_EXIT_CODE
  fi

  # Parse the balance from the output
  BALANCE=$(echo "$OUTPUT" | jq -r '.balances[] | select(.denom=="ibc/15CE03505E1F9891F448F53C9A06FD6C6AF9E5BE7CBB0A4B45F7BE5C9CBFC145") | .amount')

  if [ -z "$BALANCE" ]; then
    BALANCE=0
  fi

  # Only output the balance amount to stdout
  echo "$BALANCE"
}

# Function to transfer tokens from liquidity address to FROM_ACCOUNT
transfer_tokens_to_from_account() {
  local FROM_ADDRESS="$1"
  local AMOUNT="$2"

  echo "Transferring $AMOUNT tokens from $FROM_ADDRESS to $FROM_ACCOUNT" | jq -R -c '{"message": .}' >&2

  validate_bech32 "$FROM_ADDRESS"
  if [ $? -ne 0 ]; then
    return 1
  fi

  CMD="$ARCHWAYD_BINARY tx bank send $FROM_ADDRESS $FROM_ACCOUNT ${AMOUNT}ibc/15CE03505E1F9891F448F53C9A06FD6C6AF9E5BE7CBB0A4B45F7BE5C9CBFC145 --from $WALLET_NAME --home $ARCHWAYD_HOME \
      --chain-id $CHAIN_ID --node $NODE_URL --keyring-backend $KEYRING_BACKEND \
      --gas auto --gas-prices $("$ARCHWAYD_BINARY" q rewards estimate-fees 1 --node "$NODE_URL" --output json | jq -r '.gas_unit_price | (.amount + .denom)') --gas-adjustment 1.4 -y"

  echo "$CMD" | jq -R -c '{"command": .}' >&2
  execute_transaction "$CMD"
}

# Function to execute a command with retries
execute_transaction() {
  local CMD=$1
  local MAX_RETRIES=5
  local RETRY_COUNT=0
  local SUCCESS=0

  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    OUTPUT=$(eval "$CMD" 2>&1)
    echo "$OUTPUT" | jq -R -c '{"output": .}' >&2

    # Check if transaction was successful by looking for txhash
    TX_HASH=$(echo "$OUTPUT" | grep -oP 'txhash: \K.*')
    if [ -n "$TX_HASH" ]; then
      echo "Transaction submitted successfully. TX Hash: $TX_HASH" | jq -R -c '{"message": .}' >&2

      # Wait for transaction to be included in a block
      sleep 5

      # Query the transaction result
      TX_RESULT=$("$ARCHWAYD_BINARY" query tx "$TX_HASH" --chain-id "$CHAIN_ID" --node "$NODE_URL" --output json)
      TX_CODE=$(echo "$TX_RESULT" | jq -r '.code')

      if [ "$TX_CODE" == "0" ]; then
        echo "Transaction executed successfully." | jq -R -c '{"message": .}' >&2
        SUCCESS=1
        break
      else
        echo "Transaction failed with code $TX_CODE. Retrying..." | jq -R -c '{"message": .}' >&2
        ((RETRY_COUNT++))
        sleep 5
      fi
    else
      echo "Error submitting transaction: $OUTPUT" | jq -R -c '{"error": .}' >&2
      ((RETRY_COUNT++))
      sleep 5
    fi
  done

  if [ $SUCCESS -ne 1 ]; then
    echo "Transaction failed after $MAX_RETRIES attempts." | jq -R -c '{"message": .}' >&2
    return 1
  fi
}


execute_strided_transaction() {
  local CMD=$1
  local MAX_RETRIES=5
  local RETRY_COUNT=0
  local SUCCESS=0

  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    OUTPUT=$(eval "$CMD" 2>&1)
    echo "$OUTPUT" | jq -R -c '{"output": .}' >&2

    # Check if transaction was successful by looking for txhash
    TX_HASH=$(echo "$OUTPUT" | grep -oP 'txhash: \K.*')
    if [ -n "$TX_HASH" ]; then
      echo "Transaction submitted successfully. TX Hash: $TX_HASH" | jq -R -c '{"message": .}' >&2

      # Wait for transaction to be included in a block
      sleep 5

      # Query the transaction result
      TX_RESULT=$("$STRIDED_BINARY" --home "$STRIDED_HOME" query tx "$TX_HASH" --output json)
      TX_CODE=$(echo "$TX_RESULT" | jq -r '.code')

      if [ "$TX_CODE" == "0" ]; then
        echo "Transaction executed successfully." | jq -R -c '{"message": .}' >&2
        SUCCESS=1
        break
      else
        echo "Transaction failed with code $TX_CODE. Retrying..." | jq -R -c '{"message": .}' >&2
        ((RETRY_COUNT++))
        sleep 5
      fi
    else
      echo "Error submitting transaction: $OUTPUT" | jq -R -c '{"error": .}' >&2
      ((RETRY_COUNT++))
      sleep 5
    fi
  done

  if [ $SUCCESS -ne 1 ]; then
    echo "Transaction failed after $MAX_RETRIES attempts." | jq -R -c '{"message": .}' >&2
    return 1
  fi
}


# Function to redeem stake
redeem_stake() {
  echo "Archwayd IBC transfer" | jq -R -c '{"message": .}'

  CMD="$ARCHWAYD_BINARY --home $ARCHWAYD_HOME tx ibc-transfer transfer transfer channel-0 --chain-id $CHAIN_ID stride1u20df3trc2c2zdhm8qvh2hdjx9ewh00sv6eyy8 ${TOTAL_REDEEM_AMOUNT}ibc/15CE03505E1F9891F448F53C9A06FD6C6AF9E5BE7CBB0A4B45F7BE5C9CBFC145 --from $WALLET_NAME --keyring-backend $KEYRING_BACKEND --gas auto --gas-prices $("$ARCHWAYD_BINARY" q rewards estimate-fees 1 --node "$NODE_URL" --output json | jq -r '.gas_unit_price | (.amount + .denom)') --gas-adjustment 1.4 -y"

  echo "$CMD" | jq -R -c '{"command": .}'
  execute_transaction "$CMD"

  # Delay for another 5 seconds
  sleep 5

  echo "Redeeming total stake..." | jq -R -c '{"message": .}'

  CMD="$STRIDED_BINARY --home /home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/dockernet/state/stride1 tx stakeibc redeem-stake $TOTAL_REDEEM_AMOUNT localnet $FROM_ACCOUNT --from admin --keyring-backend $KEYRING_BACKEND --chain-id STRIDE -y"

  echo "$CMD" | jq -R -c '{"command": .}'
  execute_strided_transaction "$CMD"
}

# Claim undelegated tokens for claimable records
claim_undelegated_tokens() {
  local json="$1"

  echo "$json" | jq -c '.epoch_unbonding_record[]' | while read epoch_record; do
    epoch_number=$(echo "$epoch_record" | jq -r '.epoch_number')

    # Check if host_zone_unbondings exists and is not empty
    host_zone_unbondings=$(echo "$epoch_record" | jq -c '.host_zone_unbondings // empty')

    if [ -n "$host_zone_unbondings" ]; then
      echo "$host_zone_unbondings" | jq -c '.[]' | while read host_zone_unbonding; do
        status=$(echo "$host_zone_unbonding" | jq -r '.status')

        if [ "$status" = "CLAIMABLE" ]; then
          # Check if user_redemption_records exists and is not empty
          user_redemption_records=$(echo "$host_zone_unbonding" | jq -c '.user_redemption_records // empty')

          if [ -n "$user_redemption_records" ]; then
            echo "$user_redemption_records" | jq -r '.[]' | while read record; do
              # Since the record is a string like "localnet.39.stride1..."
              # Split the record into parts
              IFS='.' read -r hostzone epoch stride_address <<< "$record"

              echo "Claiming undelegated tokens for Hostzone: $hostzone, Epoch: $epoch, Address: $stride_address" | jq -R -c '{"message": .}'

              CMD="$STRIDED_BINARY --home $STRIDED_HOME tx stakeibc claim-undelegated-tokens $hostzone $epoch $stride_address --from admin --keyring-backend $KEYRING_BACKEND --chain-id STRIDE -y"
              execute_strided_transaction "$CMD"
            done
          else
            echo "No user redemption records for host zone unbonding in epoch $epoch_number" | jq -R -c '{"message": .}' >&2
          fi
        else
          echo "Host zone unbonding in epoch $epoch_number is not CLAIMABLE (status: $status)" | jq -R -c '{"message": .}' >&2
        fi
      done
    else
      echo "No host zone unbondings in epoch $epoch_number" | jq -R -c '{"message": .}' >&2
    fi
  done
}


# Query and claim epoch unbonding records
process_epoch_unbonding_records() {
  local CMD="$STRIDED_BINARY --home /home/keanu-xbox/photov10/Photosynthesis-Dorahacks-web3-competition-winner/photosynthesisv13/photosynthesis-main/sap-with-full-liquid-stake-redemption-workflow/dockernet/state/stride1 q records list-epoch-unbonding-record --output json"
  JSON_OUTPUT=$(eval "$CMD")
  echo "Raw JSON Output: $JSON_OUTPUT" | jq -R -c '{"message": .}'
  echo "Processing epoch unbonding records" | jq -R -c '{"message": .}'
  claim_undelegated_tokens "$JSON_OUTPUT"
}


set_redeem_tokens() {
  local CONTRACT_ADDR="$1"
  local AMOUNT="$2"

  echo "Setting redeem tokens for contract $CONTRACT_ADDR with amount $AMOUNT" | jq -R -c '{"message": .}' >&2

  # Build the execute message
  EXECUTE_MSG="{\"SetRedeemTokens\":{\"amount\":\"$AMOUNT\",\"contract_address\":\"$CONTRACT_ADDR\"}}"

  CMD="$ARCHWAYD_BINARY tx wasm execute $CONTRACT_ADDRESS '$EXECUTE_MSG' --from $WALLET_NAME --home $ARCHWAYD_HOME \
      --chain-id $CHAIN_ID --node $NODE_URL --gas auto --gas-prices $("$ARCHWAYD_BINARY" q rewards estimate-fees 1 --node "$NODE_URL" --output json | jq -r '.gas_unit_price | (.amount + .denom)') --gas-adjustment 1.4 --keyring-backend $KEYRING_BACKEND -y"

  echo "$CMD" | jq -R -c '{"command": .}' >&2
  execute_transaction "$CMD"
}

# Function to call DistributeRedeemTokens on the smart contract
distribute_redeem_tokens() {
  echo "Distributing redeem tokens..." | jq -R -c '{"message": .}' >&2

  EXECUTE_MSG='{"DistributeRedeemTokens":{}}'

  CMD="$ARCHWAYD_BINARY tx wasm execute $CONTRACT_ADDRESS '$EXECUTE_MSG' --from $WALLET_NAME --home $ARCHWAYD_HOME \
      --chain-id $CHAIN_ID --node $NODE_URL --gas auto --gas-prices $("$ARCHWAYD_BINARY" q rewards estimate-fees 1 --node "$NODE_URL" --output json | jq -r '.gas_unit_price | (.amount + .denom)') --gas-adjustment 1.4 --keyring-backend $KEYRING_BACKEND -y"

  echo "$CMD" | jq -R -c '{"command": .}' >&2
  execute_transaction "$CMD"
}

# Function to fetch redemption ratios
fetch_redemption_ratios() {
  echo "Fetching redemption ratios..." | jq -R -c '{"message": .}' >&2

  QUERY_MSG='{"GetAllRedemptionRatios":{}}'
  CMD="$ARCHWAYD_BINARY query wasm contract-state smart $CONTRACT_ADDRESS '$QUERY_MSG' --chain-id $CHAIN_ID --node $NODE_URL --output json"

  echo "$CMD" | jq -R -c '{"command": .}' >&2
  OUTPUT=$(eval "$CMD")
  if [ $? -ne 0 ]; then
    echo "Error fetching redemption ratios: $OUTPUT" | jq -R -c '{"error": .}' >&2
    exit 1
  fi

  echo "$OUTPUT"
}

# Function to distribute redeemed amounts to contract redemption addresses
distribute_redeemed_amounts() {
  local TOTAL_REDEEMED_AMOUNT="$1"
  local RATIOS_JSON="$2"

  echo "Distributing redeemed amounts based on ratios..." | jq -R -c '{"message": .}' >&2

  # Iterate over the ratios
  echo "$RATIOS_JSON" | jq -c '.ratios[]' | while read ratio_entry; do
    CONTRACT_ADDR=$(echo "$ratio_entry" | jq -r '.contract_address')
    REDEMPTION_RATIO=$(echo "$ratio_entry" | jq -r '.redemption_ratio')

    # Calculate the amount to send
    AMOUNT=$(echo "$TOTAL_REDEEMED_AMOUNT * $REDEMPTION_RATIO" | bc | cut -d'.' -f1)
    if [ "$AMOUNT" -le 0 ]; then
      echo "Calculated amount is zero or negative for contract $CONTRACT_ADDR, skipping..." | jq -R -c '{"message": .}' >&2
      continue
    fi

    # Get the redemption address
    REDEMPTION_ADDRESS=$(get_redemption_address "$CONTRACT_ADDR")
    if [ -z "$REDEMPTION_ADDRESS" ]; then
      echo "Redemption address not found for contract $CONTRACT_ADDR, skipping..." | jq -R -c '{"message": .}' >&2
      continue
    fi

    # Transfer tokens from central redemption address to contract's redemption address
    transfer_redeemed_tokens "$FROM_ACCOUNT" "$REDEMPTION_ADDRESS" "$AMOUNT"
  done
}

# Function to get the redemption address for a contract
get_redemption_address() {
  local CONTRACT_ADDR="$1"

  # Assuming the redemption address is stored in CONTRACT_METADATA under 'redemption_address'
  QUERY_MSG="{\"GetContractMetadata\":{\"contract\":\"$CONTRACT_ADDR\"}}"
  CMD="$ARCHWAYD_BINARY query wasm contract-state smart $CONTRACT_ADDRESS '$QUERY_MSG' --home \"$ARCHWAYD_HOME\" --chain-id \"$CHAIN_ID\" --node \"$NODE_URL\" --output json"

  OUTPUT=$(eval "$CMD" 2>&1)
  if [ $? -ne 0 ]; then
    echo "Error fetching metadata for contract $CONTRACT_ADDR: $OUTPUT" | jq -R -c '{"error": .}' >&2
    return 1
  fi

  REDEMPTION_ADDRESS=$(echo "$OUTPUT" | jq -r '.data.redemption_address')

  if [ -z "$REDEMPTION_ADDRESS" ] || [ "$REDEMPTION_ADDRESS" == "null" ]; then
    echo "Redemption address not found in metadata for contract $CONTRACT_ADDR" | jq -R -c '{"error": .}' >&2
    return 1
  fi

  echo "$REDEMPTION_ADDRESS"
}

# Function to transfer redeemed tokens to redemption address
transfer_redeemed_tokens() {
  local FROM_ADDRESS="$1"
  local TO_ADDRESS="$2"
  local AMOUNT="$3"

  echo "Transferring $AMOUNT tokens from $FROM_ADDRESS to $TO_ADDRESS" | jq -R -c '{"message": .}' >&2

  CMD="$ARCHWAYD_BINARY tx bank send $FROM_ADDRESS $TO_ADDRESS ${AMOUNT}uarch --from $WALLET_NAME --home $ARCHWAYD_HOME \
      --chain-id $CHAIN_ID --node $NODE_URL --keyring-backend $KEYRING_BACKEND \
      --gas auto --gas-prices $("$ARCHWAYD_BINARY" q rewards estimate-fees 1 --node "$NODE_URL" --output json | jq -r '.gas_unit_price | (.amount + .denom)') --gas-adjustment 1.4 -y"

  echo "$CMD" | jq -R -c '{"command": .}' >&2
  execute_transaction "$CMD"
}


get_wallet_balance() {
  local WALLET_NAME="$1"

  local ADDRESS
  ADDRESS=$("$ARCHWAYD_BINARY" keys show "$WALLET_NAME" --address --keyring-backend "$KEYRING_BACKEND" --home "$ARCHWAYD_HOME")
  if [ -z "$ADDRESS" ]; then
    echo "Error: Could not get address for wallet $WALLET_NAME" | jq -R -c '{"error": .}' >&2
    return 1
  fi

  echo "Wallet address for $WALLET_NAME is $ADDRESS" | jq -R -c '{"message": .}' >&2

  # Get balance
  CMD=("$ARCHWAYD_BINARY" q bank balances "$ADDRESS" --chain-id "$CHAIN_ID" --node "$NODE_URL" --output json)
  echo "${CMD[@]}" | jq -R -c '{"command": .}' >&2

  OUTPUT=$("${CMD[@]}" 2>&1)
  CMD_EXIT_CODE=$?

  if [ $CMD_EXIT_CODE -ne 0 ]; then
    echo "Error fetching balance for $ADDRESS: $OUTPUT" | jq -R -c '{"error": .}' >&2
    return $CMD_EXIT_CODE
  fi

  # Parse the balance for 'uarch'
  BALANCE=$(echo "$OUTPUT" | jq -r '.balances[] | select(.denom=="ibc/15CE03505E1F9891F448F53C9A06FD6C6AF9E5BE7CBB0A4B45F7BE5C9CBFC145") | .amount')

  if [ -z "$BALANCE" ]; then
    BALANCE=0
  fi

  echo "Balance for wallet $WALLET_NAME ($ADDRESS): $BALANCE ibc/15CE03505E1F9891F448F53C9A06FD6C6AF9E5BE7CBB0A4B45F7BE5C9CBFC145" | jq -R -c '{"message": .}'
}


# Main workflow logic
main() {
  
  declare -A contractToLiquidityAddress
  declare -A contractToRewardsAddress
  declare -A contractToRedeemAmount
  process_epoch_unbonding_records
  # Fetch all contracts
  fetch_all_contracts

  # Initialize total balances
  TOTAL_LIQUIDITY_BALANCE=0
  TOTAL_REDEEM_AMOUNT=0

  # For each contract, get metadata, transfer tokens, and calculate total redeem amount
  for CONTRACT_ADDR in $CONTRACTS; do
    echo "Processing contract: $CONTRACT_ADDR" | jq -R -c '{"message": .}' >&2

    METADATA=$(get_contract_metadata "$CONTRACT_ADDR")
    if [ $? -ne 0 ]; then
      continue
    fi

    LIQUIDITY_ADDRESS=$(echo "$METADATA" | cut -d '|' -f1)
    REWARDS_ADDRESS=$(echo "$METADATA" | cut -d '|' -f2)

    # Get balance of liquidity address
    BALANCE=$(get_balance "$LIQUIDITY_ADDRESS")
    if [ $? -ne 0 ]; then
      echo "Failed to get balance for $LIQUIDITY_ADDRESS" | jq -R -c '{"error": .}' >&2
      continue
    fi

    echo "Balance for liquidity address $LIQUIDITY_ADDRESS: $BALANCE" | jq -R -c '{"message": .}' >&2

    # Ensure BALANCE is numeric
    if ! [[ "$BALANCE" =~ ^[0-9]+$ ]]; then
      echo "Invalid balance amount for $LIQUIDITY_ADDRESS: $BALANCE" | jq -R -c '{"error": .}' >&2
      continue
    fi

    # Update total liquidity balance
    TOTAL_LIQUIDITY_BALANCE=$((TOTAL_LIQUIDITY_BALANCE + BALANCE))

    if [ "$BALANCE" -gt 0 ]; then
      # Deduct transaction fee or buffer
      ADJUSTED_BALANCE=$((BALANCE - 30000))
      if [ "$ADJUSTED_BALANCE" -le 0 ]; then
        echo "Insufficient balance after deduction for $LIQUIDITY_ADDRESS" | jq -R -c '{"error": .}' >&2
        continue
      fi

      # Transfer tokens from liquidity address to FROM_ACCOUNT
      transfer_tokens_to_from_account "$LIQUIDITY_ADDRESS" "$ADJUSTED_BALANCE"

      # Print balance of wallet after transfer
      get_wallet_balance "$WALLET_NAME"

      # Store data in associative arrays
      contractToLiquidityAddress["$CONTRACT_ADDR"]="$LIQUIDITY_ADDRESS"
      contractToRewardsAddress["$CONTRACT_ADDR"]="$REWARDS_ADDRESS"
      contractToRedeemAmount["$CONTRACT_ADDR"]="$ADJUSTED_BALANCE"

      # Update total redemption amount
      TOTAL_REDEEM_AMOUNT=$((TOTAL_REDEEM_AMOUNT + ADJUSTED_BALANCE))
  
    else
      echo "No balance to transfer for contract $CONTRACT_ADDR" | jq -R -c '{"message": .}' >&2
    fi
  done

  echo "Total Liquidity Balance: $TOTAL_LIQUIDITY_BALANCE" | jq -R -c '{"message": .}' >&2
  echo "Total Redemption Amount: $TOTAL_REDEEM_AMOUNT" | jq -R -c '{"message": .}' >&2
  
  if [ "$TOTAL_REDEEM_AMOUNT" -eq 0 ]; then
    echo "No tokens to redeem. Exiting." | jq -R -c '{"message": .}' >&2
    exit 0
  fi

  #TOTAL_REDEEM_AMOUNT=$((TOTAL_REDEEM_AMOUNT / 10))

  # Redeem total liquid tokens
  redeem_stake

  # Sleep to allow redemption to process (adjust sleep time as needed)
  sleep 1000

  # Process epoch unbonding records
  process_epoch_unbonding_records

  # Set redeem tokens in the smart contract
  for CONTRACT_ADDR in "${!contractToRedeemAmount[@]}"; do
    set_redeem_tokens "$CONTRACT_ADDR" "${contractToRedeemAmount[$CONTRACT_ADDR]}"
  done

  # Distribute redeem tokens
  distribute_redeem_tokens

  # Fetch redemption ratios
  RATIOS_JSON=$(fetch_redemption_ratios)

  # Distribute redeemed amounts based on ratios
  distribute_redeemed_amounts "$TOTAL_REDEEM_AMOUNT" "$RATIOS_JSON"
}

# Start the script
main
