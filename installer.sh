#!/bin/sh

DISK=/dev/vda
KEYFILE=luks.key

DEBIAN_VERSION=bullseye

# echo create 2 partitions
# sfdisk $DISK <<EOF
# label: gpt
# unit: sectors
# sector-size: 512
# 
# ${DISK}1: start=2048, size=409600, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI system partition"
# ${DISK}2: start=411648, size=4096000, type=CA7D7CCB-63ED-4C53-861C-1742536059CC, name="LUKS partition"
# EOF
# 
# echo resize the second partition to fill available space
# echo ", +" | sfdisk -N 2 $DISK

# echo install required packages
# apt-get update -y
# apt-get install -y cryptsetup debootstrap

# echo generate key file for luks
# if [ ! -f $KEYFILE ]; then
#     uuidgen > $KEYFILE
# fi
# 
# echo setup luks
# cryptsetup luksFormat ${DISK}2 --type luks2 --batch-mode --key-file $KEYFILE
# 
# echo open luks
# cryptsetup luksOpen ${DISK}2 target --key-file $KEYFILE

# echo create filesystem
# mkfs.btrfs /dev/mapper/target

# echo mount filesystem
# mkdir -p /mnt/btrfs1
# mount /dev/mapper/target /mnt/btrfs1 -o compress=zstd:1

# echo create subvolumes
# btrfs subvolume create /mnt/btrfs1/@
# btrfs subvolume create /mnt/btrfs1/@home

# echo install debian
# debootstrap ${DEBIAN_VERISION} /mnt/btrfs1/@ http://deb.debian.org/debian

# echo bind mount dev, proc, etc
# mount --make-rslave --rbind /proc /mnt/btrfs1/@/proc
# mount --make-rslave --rbind /sys /mnt/btrfs1/@/sys
# mount --make-rslave --rbind /dev /mnt/btrfs1/@/dev
# mount --make-rslave --rbind /run /mnt/btrfs1/@/run
# 
# echo setup sources.list
# cat <<EOF > /mnt/btrfs1/@/etc/apt/sources.list
# deb http://deb.debian.org/debian ${DEBIAN_VERSION} main contrib non-free
# deb http://security.debian.org/ ${DEBIAN_VERSION}-security main contrib non-free
# deb http://deb.debian.org/debian ${DEBIAN_VERSION}-backports main contrib non-free
# EOF
# 
# echo install systemd from backports
# cat <<EOF > /mnt/btrfs1/@/tmp/run1.sh
# export DEBIAN_FRONTEND=noninteractive
# apt-get update -y
# apt-get install -t ${DEBIAN_VERSION}-backports systemd cryptsetup -y
# EOF
# chroot /mnt/btrfs1/@/ sh /tmp/run1.sh

echo install kernel and firmware
cat <<EOF > /mnt/btrfs1/@/tmp/packages.txt
linux-image-amd64
firmware-linux
atmel-firmware
bluez-firmware
dahdi-firmware-nonfree
firmware-amd-graphics
firmware-ath9k-htc
firmware-atheros
firmware-bnx2
firmware-bnx2x
firmware-brcm80211
firmware-cavium
firmware-intel-sound
firmware-intelwimax
firmware-iwlwifi
firmware-libertas
firmware-misc-nonfree
firmware-myricom
firmware-netronome
firmware-netxen
firmware-qcom-media
firmware-qcom-soc
firmware-qlogic
firmware-realtek
firmware-samsung
firmware-siano
firmware-sof-signed
firmware-ti-connectivity
firmware-tomu
firmware-zd1211
hdmi2usb-fx2-firmware
midisport-firmware
sigrok-firmware-fx2lafw
EOF
cat <<EOF > /mnt/btrfs1/@/tmp/run2.sh
export DEBIAN_FRONTEND=noninteractive
xargs apt-get install -t ${DEBIAN_VERSION}-backports -y < /tmp/packages.txt
EOF
chroot /mnt/btrfs1/@/ sh /tmp/run2.sh
