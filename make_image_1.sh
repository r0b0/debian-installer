#!/bin/bash

# edit this:
DISK=/dev/vdb

DEBIAN_VERSION=bookworm
# TODO enable backports here when it becomes available for bookworm
DEBIAN_SOURCE=${DEBIAN_VERSION}
FSFLAGS="compress=zstd:9"

target=/target
root_device=${DISK}2

echo install required packages
read -p "Enter to continue"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y debootstrap uuid-runtime

if [ ! -f efi-part.uuid ]; then
    echo generate uuid for efi partition
    uuidgen > efi-part.uuid
fi
if [ ! -f base-image-part.uuid ]; then
    echo generate uuid for base image partition
    uuidgen > base-image-part.uuid
fi
if [ ! -f top-part.uuid ]; then
    echo generate uuid for top partition
    uuidgen > top-part.uuid
fi
efi_uuid=$(cat efi-part.uuid)
base_image_uuid=$(cat base-image-part.uuid)
top_uuid=$(cat top-part.uuid)

if [ ! -f partitions_created.txt ]; then
# TODO mark the BaseImage partition as read-only (bit 60 - 0x1000000000000000)
echo create 2 partitions on ${DISK}
read -p "Enter to continue"
sfdisk $DISK <<EOF
label: gpt
unit: sectors
sector-size: 512

${DISK}1: start=2048, size=409600, type=uefi, name="EFI system partition", uuid=${efi_uuid}
${DISK}2: start=411648, size=409600, type=linux, name="BaseImage", uuid=${base_image_uuid}
EOF

echo resize the second partition on ${DISK} to fill available space
read -p "Enter to continue"
echo ", +" | sfdisk -N 2 $DISK

sfdisk -d $DISK > partitions_created.txt
fi

if [ ! -f btrfs_created.txt ]; then
    echo create root filesystem on ${root_device}
    read -p "Enter to continue"
    mkfs.btrfs -f ${root_device} | tee btrfs_created.txt
fi
if [ ! -f vfat_created.txt ]; then
    echo create esp filesystem on ${DISK}1
    read -p "Enter to continue"
    mkfs.vfat ${DISK}1 | tee vfat_created.txt
fi

if grep -qs "/mnt/btrfs1" /proc/mounts ; then
    echo top-level subvolume already mounted on /mnt/btrfs1
else
    echo mount top-level subvolume on /mnt/btrfs1
    mkdir -p /mnt/btrfs1
    read -p "Enter to continue"
    mount ${root_device} /mnt/btrfs1 -o ${FSFLAGS}
fi

if [ ! -e /mnt/btrfs1/@ ]; then
    echo create @ and @home subvolumes on /mnt/btrfs1
    read -p "Enter to continue"
    btrfs subvolume create /mnt/btrfs1/@
    btrfs subvolume create /mnt/btrfs1/@home
    btrfs subvolume set-default /mnt/btrfs1/@
fi

if grep -qs "${target}" /proc/mounts ; then
    echo root subvolume already mounted on ${target}
else
    echo mount root and home subvolume on ${target}
    mkdir -p ${target}
    read -p "Enter to continue"
    mount ${root_device} ${target} -o ${FSFLAGS},subvol=@
    mkdir -p ${target}/home
    mount ${root_device} ${target}/home -o ${FSFLAGS},subvol=@home
fi

mkdir -p ${target}/var/cache/apt/archives
if grep -qs "${target}/var/cache/apt/archives" /proc/mounts ; then
    echo apt cache directory already bind mounted on target
else
    echo bind mounting apt cache directory to target
    read -p "Enter to continue"
    mount /var/cache/apt/archives ${target}/var/cache/apt/archives -o bind
fi

if [ ! -f ${target}/etc/debian_version ]; then
    echo install debian on ${target}
    read -p "Enter to continue"
    debootstrap ${DEBIAN_VERSION} ${target} http://deb.debian.org/debian
fi

if grep -qs "${target}/proc" /proc/mounts ; then
    echo bind mounts already set up on ${target}
else
    echo bind mount dev, proc, sys, run on ${target}
    read -p "Enter to continue"
    mount -t proc none ${target}/proc
    mount --make-rslave --rbind /sys ${target}/sys
    mount --make-rslave --rbind /dev ${target}/dev
    mount --make-rslave --rbind /run ${target}/run
fi

echo setup sources.list
read -p "Enter to continue"
cat <<EOF > ${target}/etc/apt/sources.list
deb http://deb.debian.org/debian ${DEBIAN_VERSION} main contrib non-free non-free-firmware
deb http://security.debian.org/ ${DEBIAN_VERSION}-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${DEBIAN_VERSION}-backports main contrib non-free non-free-firmware
EOF

echo install required packages on ${target}
cat <<EOF > ${target}/tmp/packages.txt
locales
adduser
passwd
sudo
systemd
btrfs-progs
tasksel
network-manager
firmware-linux
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
firmware-ti-connectivity
firmware-tomu
firmware-zd1211
hdmi2usb-fx2-firmware
midisport-firmware
sigrok-firmware-fx2lafw
EOF
cat <<EOF > ${target}/tmp/run2.sh
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get update
xargs apt-get install -t ${DEBIAN_SOURCE} -y < /tmp/packages.txt
EOF
read -p "Enter to continue"
chroot ${target}/ bash /tmp/run2.sh

echo running tasksel
read -p "Enter to continue"
chroot ${target}/ tasksel

echo cleaning up
read -p "Enter to continue"
rm -f ${target}/etc/machine-id
rm -f ${target}/etc/crypttab
rm -f ${target}/var/log/*log
rm -f ${target}/var/log/apt/*log

echo balancing and shrinking the filesystem
read -p "Enter to continue"
btrfs balance start -dusage=90 ${target}
true
while [ $? -eq 0 ]; do
    btrfs filesystem resize -1G ${target}
done
true
while [ $? -eq 0 ]; do
    btrfs filesystem resize -100M ${target}
done
true
while [ $? -eq 0 ]; do
    btrfs filesystem resize -10M ${target}
done

btrfs filesystem usage -m ${target} |grep slack | cut -f 3 | tr -d '[:space:]' > device_slack.txt
DEVICE_SLACK=$(cat device_slack.txt)
echo device slack is ${DEVICE_SLACK}

echo umounting all filesystems
read -p "Enter to continue"
umount -R ${target}
umount -R /mnt/btrfs1

echo "NOW REBOOT AND CONTINUE WITH PART 2"
