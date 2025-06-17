#!/bin/bash

# see https://www.freedesktop.org/software/systemd/man/systemd-cryptenroll.html#--tpm2-pcrs=PCR
TPM_PCRS="7+14"

# TODO
root_partition=/dev/disk/by-uuid/0c944b6c-4cd6-4b6f-98b7-fd1da9b0e3a1

systemd-cryptenroll --tpm2-device=auto ${root_partition} --tpm2-pcrs=${TPM_PCRS}
