#!/bin/bash

echo create 2 partitions
sfdisk ${top_disk_device} <<EOF
label: gpt
unit: sectors
sector-size: 512

${top_disk_device}1: start=2048, size=409600, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI system partition", uuid=${efi_partition_uuid}
${top_disk_device}2: start=411648, size=4096000, type=CA7D7CCB-63ED-4C53-861C-1742536059CC, name="LUKS partition", uuid=${luks_partition_uuid}
EOF

echo resize the second partition to fill available space
echo ", +" | sfdisk -N 2 ${top_disk_device}

echo generate key file for luks
dd if=/dev/random of=${luks_keyfile} bs=512 count=1

echo setup luks
if [ -e ${root_device} ]; then
  cryptsetup luksClose ${luks_device}
fi
cryptsetup luksFormat ${top_disk_device}2 --type luks2 --batch-mode --key-file ${luks_keyfile}
# TODO setup luks password
# cryptsetup --key-file=luks.key luksAddKey ${DISK}2
cryptsetup luksUUID ${top_disk_device}2 > ${luks_crypt_uuid_file}

echo open luks
cryptsetup luksOpen ${top_disk_device}2 ${luks_device} --key-file ${luks_keyfile}

echo create root filesystem on ${root_device}
mkfs.btrfs ${root_device}

echo create esp filesystem on ${top_disk_device}1
mkfs.vfat ${DISK}1

# TODO continue