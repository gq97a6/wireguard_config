#!/bin/bash

# Check if the correct number of parameters are provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <interface_index>"
    exit 1
fi

wg-quick down wg$1
wg-quick up wg$1