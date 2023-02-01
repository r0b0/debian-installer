#!/bin/bash

# edit this:
DISK=/dev/vdb

DEBIAN_VERSION=bookworm
# TODO enable backports here when it becomes available for bookworm
DEBIAN_SOURCE=${DEBIAN_VERSION}
FSFLAGS="compress=zstd:9"

echo install required packages
read -p "Enter to continue"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y debootstrap

if [ ! -f btrfs.uuid ]; then
    echo generate uuid for btrfs filesystem
    uuidgen > btrfs.uuid
fi

btrfs_uuid=$(cat btrfs.uuid)
target=/target
root_device=${DISK}
kernel_params="rd.luks.options=${luks_uuid}=tpm2-device=auto rw quiet rootfstype=btrfs rootflags=${FSFLAGS} rd.auto=1 splash"

if [ ! -f btrfs_created.txt ]; then
    echo create root filesystem on ${root_device}
    read -p "Enter to continue"
    mkfs.btrfs -U ${btrfs_uuid} ${root_device}
    touch btrfs_created.txt
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

mkdir -p ${target}/var/cache/apt/archives
if grep -qs "${target}/var/cache/apt/archives" /proc/mounts ; then
    echo apt cache directory already bind mounted on target
else
    echo bind mounting apt cache directory to target
    mount /var/cache/apt/archives ${target}/var/cache/apt/archives -o bind
fi

echo install required packages on ${target}
cat <<EOF > ${target}/tmp/packages.txt
locales
systemd
btrfs-progs
tasksel
network-manager
cryptsetup
tpm2-tools
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

echo shrinking the filesystem
read -p "Enter to continue"
true
while [ $? -eq 0 ]; do
    btrfs filesystem resize -1G ${target}
done
true
while [ $? -eq 0 ]; do
    btrfs filesystem resize -100M ${target}
done

echo umounting all filesystems
read -p "Enter to continue"
umount -R ${target}
umount -R /mnt/btrfs1

echo "INSTALLATION FINISHED"
