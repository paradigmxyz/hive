#!/bin/bash

# Startup script to initialize and boot a reth instance.
#
# This script assumes the following files:
#  - `reth` binary is located in the filesystem root
#  - `genesis.json` file is located in the filesystem root (mandatory)
#  - `chain.rlp` file is located in the filesystem root (optional)
#  - `blocks` folder is located in the filesystem root (optional)
#
# This script can be configured using the following environment variables:
#
#  - HIVE_BOOTNODE             enode URL of the remote bootstrap node
#  - HIVE_NETWORK_ID           network ID number to use for the eth protocol
#  - HIVE_FORK_HOMESTEAD       block number of the homestead transition
#  - HIVE_FORK_DAO_BLOCK       block number of the DAO hard-fork transition
#  - HIVE_FORK_TANGERINE       block number of TangerineWhistle
#  - HIVE_FORK_SPURIOUS        block number of SpuriousDragon
#  - HIVE_FORK_BYZANTIUM       block number for Byzantium transition
#  - HIVE_FORK_CONSTANTINOPLE  block number for Constantinople transition
#  - HIVE_FORK_PETERSBURG      block number for ConstantinopleFix/Petersburg transition
#  - HIVE_FORK_ISTANBUL        block number for Istanbul transition
#  - HIVE_FORK_MUIR_GLACIER    block number for MuirGlacier transition
#  - HIVE_LOGLEVEL             client log level
#
# These flags are NOT supported by reth
#
#  - HIVE_TESTNET              whether testnet nonces (2^20) are needed
#  - HIVE_GRAPHQL_ENABLED      turns on GraphQL server
#  - HIVE_CLIQUE_PRIVATEKEY    private key for clique mining
#  - HIVE_NODETYPE             sync and pruning selector (archive, full, light)
#  - HIVE_SKIP_POW             If set, skip PoW verification during block import
#  - HIVE_MINER                address to credit with mining rewards
#  - HIVE_MINER_EXTRA          extra-data field to set for newly minted blocks

# Immediately abort the script on any error encountered
set -ex

reth=/usr/local/bin/reth

case "$HIVE_LOGLEVEL" in
    0|1) FLAGS="$FLAGS -v" ;;
    2)   FLAGS="$FLAGS -vv" ;;
    3)   FLAGS="$FLAGS -vvv" ;;
    4)   FLAGS="$FLAGS -vvvv" ;;
    5)   FLAGS="$FLAGS -vvvvv" ;;
esac

# Create the data directory.
mkdir /reth-hive-db
FLAGS="$FLAGS --db /reth-hive-db"

# TODO If a specific network ID is requested, use that
#if [ "$HIVE_NETWORK_ID" != "" ]; then
#    FLAGS="$FLAGS --networkid $HIVE_NETWORK_ID"
#else
#    FLAGS="$FLAGS --networkid 1337"
#fi

# Configure the chain.
mv /genesis.json /genesis-input.json
jq -f /mapper.jq /genesis-input.json > /genesis.json

# Dump genesis
echo "Supplied genesis state:"
cat /genesis.json

echo "Command flags till now:"
echo $FLAGS

# Initialize the local testchain with the genesis state
echo "Initializing database with genesis state..."
$reth init $FLAGS --chain /genesis.json

# make sure we use the same genesis each time
FLAGS="$FLAGS --chain /genesis.json"

# Don't immediately abort, some imports are meant to fail
set +ex

# Load the test chain if present
echo "Loading initial blockchain..."
if [ -f /chain.rlp ]; then
    echo "Loading initial blockchain..."
    $reth import $FLAGS /chain.rlp
else
    echo "Warning: chain.rlp not found."
fi

# Load the remainder of the test chain
echo "Loading remaining individual blocks..."
if [ -d /blocks ]; then
    echo "Loading remaining individual blocks..."
    for file in $(ls /blocks | sort -n); do
        echo "Importing " $file
        $reth import $FLAGS /blocks/$file
    done
else
    echo "Warning: blocks folder not found."
fi

# Only set boot nodes in online steps
# It doesn't make sense to dial out, use only a pre-set bootnode.
if [ "$HIVE_BOOTNODE" != "" ]; then
    FLAGS="$FLAGS --bootnodes=$HIVE_BOOTNODE"
fi

set -ex

# Configure any mining operation
# TODO
#if [ "$HIVE_MINER" != "" ]; then
#    FLAGS="$FLAGS --mine --miner.etherbase $HIVE_MINER"
#fi
#if [ "$HIVE_MINER_EXTRA" != "" ]; then
#    FLAGS="$FLAGS --miner.extradata $HIVE_MINER_EXTRA"
#fi

# Import clique signing key.
# TODO
#if [ "$HIVE_CLIQUE_PRIVATEKEY" != "" ]; then
#    # Create password file.
#    echo "Importing clique key..."
#    echo "$HIVE_CLIQUE_PRIVATEKEY" > ./private_key.txt
#
#    # Ensure password file is used when running geth in mining mode.
#    if [ "$HIVE_MINER" != "" ]; then
#        FLAGS="$FLAGS --miner.sigfile private_key.txt"
#    fi
#fi

# Configure RPC.
FLAGS="$FLAGS --http --http.addr=0.0.0.0 --http.api=admin,debug,eth,net"
#FLAGS="$FLAGS --ws"

if [ "$HIVE_TERMINAL_TOTAL_DIFFICULTY" != "" ]; then
    JWT_SECRET="7365637265747365637265747365637265747365637265747365637265747365"
    echo -n $JWT_SECRET > /jwt.secret
    FLAGS="$FLAGS --authrpc.addr=0.0.0.0 --authrpc.jwtsecret=/jwt.secret"
fi

# Configure NAT
FLAGS="$FLAGS --nat none"

# Launch the main client.
echo "Running reth with flags: $FLAGS"
$reth node $FLAGS --debug.tip 0xc95596f4707fb382554b660b4847c599eb5f8fdcf99be2c5654aaadd4ec97840
