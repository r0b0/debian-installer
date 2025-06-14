#!/bin/bash

echo Environ swap: ${ENABLE_SWAP} ${SWAP_SIZE}
echo Environ nvidia: \"${NVIDIA_PACKAGE}\"

for i in {1..5}; do
  echo Counting ${i}
  sleep 1
done
