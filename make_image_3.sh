#!/bin/bash

# edit this:
DISK=/dev/vdb

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
. ${SCRIPT_DIR}/_make_image_lib.sh

DEVICE_SLACK=$(cat device_slack.txt)
shrink_partition ${DEVICE_SLACK} ${DISK} 3

echo "INSTALLATION FINISHED"
echo "Truncate the image file now"
