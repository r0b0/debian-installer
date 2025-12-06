#!/bin/bash

echo Environ swap: ${ENABLE_SWAP} ${SWAP_SIZE}
echo Environ nvidia: \"${NVIDIA_PACKAGE}\"
echo Environ luks password: \"$LUKS_PASSWORD\"

for i in {1..5}; do
  echo Counting ${i}
  echo ${i} > ${PROGRESS_PIPE}
  sleep 2
done
