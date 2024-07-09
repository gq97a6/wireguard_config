#!/bin/bash

#Generate private key
PRIVATE_KEY=$(wg genkey)

#Generate public key from the private key
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

#Echo the keys
echo "PRIVATE: $PRIVATE_KEY"
echo "PUBLIC: $PUBLIC_KEY"