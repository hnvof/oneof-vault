#!/bin/bash

# Load environment variables
source $PWD/vault/.env

BASE_DIR=$PWD/vault
VAULT_ROOT_TOKEN_PATH=$BASE_DIR/.root

PLUGIN_MOUNT_PATH=quorum
PLUGIN_FILE=$PWD/plugins/quorum-hashicorp-vault-plugin

# Executes a vault read command using curl
# $1: URI vault path to be executed
# $2: optional VAULT_TOKEN for authentication
read() {
  URL=$VAULT_ADDR/$1
  X_VAULT_TOKEN=$2

  if [ -z "$X_VAULT_TOKEN" ]; then
    curl -s $URL
  else
    curl -s --header "X-Vault-Token: $VAULT_TOKEN" $URL
  fi
}

# Executes a vault write command using curl
# $1: data payload to be sent by command 
# $2: URI vault path to be executed
# $3: optional VAULT_TOKEN for authentication
write() {
  DATA=$1
  URL=$VAULT_ADDR/$2
  X_VAULT_TOKEN=$3

  if [ -z "$X_VAULT_TOKEN" ]; then
    curl -s --request POST --data "$DATA" $URL
  else
    curl -s --request POST --header "X-Vault-Token: $X_VAULT_TOKEN" --data "$DATA" $URL
  fi
}

# # Initialize Vault to retreive root token and unseal keys and store them .root file
init_vault() {
  init_response=$(write '{"secret_shares": '$VAULT_UNSEAL_SECRET_SHARES', "secret_threshold": '$VAULT_UNSEAL_SECRET_THRESHOLD'}' v1/sys/init)

  VAULT_TOKEN=$(echo $init_response | jq -r .root_token)
  UNSEAL_KEYS=$(echo $init_response | jq -r .keys)

  ERRORS=$(echo $init_response | jq .errors | jq '.[0]')
  if [ "$UNSEAL_KEYS" = "null" ]; then
    echo "cannot retrieve unseal key: $ERRORS"
    exit 1
  fi

  echo $init_response | jq '{root_token, keys}' > $VAULT_ROOT_TOKEN_PATH
}

# Using Unseal Keys to unseal Vault
unseal_vault() {
  UNSEAL_KEY_1=$(cat $VAULT_ROOT_TOKEN_PATH | jq .keys | jq '.[1]')
  UNSEAL_KEY_2=$(cat $VAULT_ROOT_TOKEN_PATH | jq .keys | jq '.[2]')
  UNSEAL_KEY_3=$(cat $VAULT_ROOT_TOKEN_PATH | jq .keys | jq '.[3]')

  write '{"key": '${UNSEAL_KEY_1}'}' v1/sys/unseal

  write '{"key": '${UNSEAL_KEY_2}'}' v1/sys/unseal

  write '{"key": '${UNSEAL_KEY_3}'}' v1/sys/unseal
}

# Enable KV V2 engine
enable_kv2_key_engine() {
  write '{"type": "kv-v2", "config": {"force_no_cache": true} }' v1/sys/mounts/secret $VAULT_TOKEN
}

enable_vault_transit() {
  write '{"type":"transit"}' v1/sys/mounts/transit $VAULT_TOKEN
}

register_quorum_vault_plugin() {
  SHA256SUM=$(sha256sum -b ${PLUGIN_FILE} | cut -d' ' -f1)
  write '{"sha256": "'$SHA256SUM'", "command": "quorum-hashicorp-vault-plugin" }' \
    v1/sys/plugins/catalog/secret/quorum-hashicorp-vault-plugin \
    $VAULT_TOKEN
}

enable_quorum_vault_plugin() {
  write '{"type": "plugin", "plugin_name": "quorum-hashicorp-vault-plugin", "config": {"force_no_cache": true, "passthrough_request_headers": ["X-Vault-Namespace"]}} }' \
    v1/sys/mounts/${PLUGIN_MOUNT_PATH} \
    $VAULT_TOKEN
}

# VAULT_TOKEN=$(cat $VAULT_ROOT_TOKEN_PATH | jq -r .root_token)

echo "Initialize Vault"
init_vault

echo "Unseal Vault"
unseal_vault

echo "Enable Vault Transit"
enable_vault_transit

echo "Enable KV V2 Secret Engine"
enable_kv2_key_engine

echo "Registering Quorum Hashicorp Vault plugin..."
register_quorum_vault_plugin

echo "Enabling Quorum Hashicorp Vault engine..."
enable_quorum_vault_plugin
