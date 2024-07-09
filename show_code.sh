#!/bin/bash

# Check if the correct number of parameters are provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <client_name>"
    exit 1
fi

qrencode -t ansiutf8 < ./client_configs/$1.conf