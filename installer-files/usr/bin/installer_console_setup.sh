#!/bin/bash

if [ -z $KEYMAP ]; then
  echo "No KEYMAP specified, nothing to do"
  exit 0
fi

echo "Configuring keyboard to $KEYMAP"
echo "keyboard-configuration keyboard-configuration/layoutcode string ${KEYMAP}"| debconf-set-selections
export DEBIAN_FRONTEND=noninteractive
dpkg-reconfigure keyboard-configuration
setupcon
