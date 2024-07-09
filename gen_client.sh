#!/bin/bash

# Check if the correct number of parameters are provided
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <client_name> <client_host> <interface_index>"
    exit 1
fi

# Assign parameters to variables
CLIENT_NAME=$1
CLIENT_HOST=$2
INTERFACE_INDEX=$3

# Determine PublicKey and Endpoint port based on interface number
case $INTERFACE_INDEX in
    0)
        SERVER_PUBLIC_KEY="???"
        SERVER_PORT="10000"
        ;;
    1)
        SERVER_PUBLIC_KEY="???"
        SERVER_PORT="10010"
        ;;
    2)
        SERVER_PUBLIC_KEY="???"
        SERVER_PORT="10020"
        ;;
    *)
        echo "Invalid interface number"
        exit 1
        ;;
esac

#Generate private key
CLIENT_PRIVATE_KEY=$(wg genkey)

#Generate public key from the private key
CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)

#Create the configuration file for the client side
CLIENT_CONFIG_FILE="client_configs/${CLIENT_NAME}.conf"

cat <<EOL > $CLIENT_CONFIG_FILE
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = 10.0.$INTERFACE_INDEX.$CLIENT_HOST/24
DNS = 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
AllowedIPs = 10.0.0.0/16
Endpoint = ???:$SERVER_PORT
PersistentKeepalive = 25
EOL

#Echo the keys and the configuration file path
echo "#${CLIENT_NAME}"
echo "[Peer]"
echo "PublicKey = $CLIENT_PUBLIC_KEY"
echo "AllowedIPs = 10.0.$INTERFACE_INDEX.$CLIENT_HOST/32"
