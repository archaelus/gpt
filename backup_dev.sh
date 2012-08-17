#!/bin/bash

DEV=$1
SIZE=$2
NAME=$3

if [[ -z "$DEV" || -z "$SIZE" || -z "$NAME" ]]; then
    echo "Usage: $0 <device> <size> <name>"
    exit 1
fi

dd if=$DEV of="${NAME}_mbr" count=1
dd if=$DEV of="${NAME}_gpt" count=1 skip=1
dd if=$DEV of="${NAME}_gptdata" count=32 skip=2
dd if=$DEV of="${NAME}_second_gpt" count=1 skip=$(( $SIZE ))
dd if=$DEV of="${NAME}_second_gptdata" count=32 skip=$(($SIZE - 32))