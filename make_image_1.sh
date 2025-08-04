#!/bin/bash

# edit this:
DISK=/dev/vdb

DEBIAN_VERSION=trixie
BACKPORTS_VERSION=${DEBIAN_VERSION}  # TODO append "-backports" when available
FSFLAGS="compress=zstd:19"

target=/target

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
. ${SCRIPT_DIR}/_make_image_lib.sh

notify install required packages
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y debootstrap uuid-runtime btrfs-progs dosfstools

if [ ! -f efi-part.uuid ]; then
    echo generate uuid for efi partition
    uuidgen > efi-part.uuid
fi
if [ ! -f installer-image-part.uuid ]; then
    echo generate uuid for installer image partition
    uuidgen > installer-image-part.uuid
fi
efi_uuid=$(cat efi-part.uuid)
installer_image_uuid=$(cat installer-image-part.uuid)

root_part_type="4f68bce3-e8cd-4db1-96e7-fbcaf984b709"  # X86_64

if [ ! -f partitions_created.txt ]; then
notify create 2 partitions on ${DISK}
sfdisk $DISK <<EOF
label: gpt
unit: sectors
sector-size: 512

start=2048, size=409600, type=uefi, name="EFI system partition", uuid=${efi_uuid}
start=411648, size=409600, type=${root_part_type}, name="installerImage", uuid=${installer_image_uuid}
EOF

notify resize the second partition on ${DISK} to fill available space
echo ", +" | sfdisk -N 2 $DISK

sfdisk -d $DISK > partitions_created.txt
fi

root_device=/dev/disk/by-partuuid/${installer_image_uuid}
efi_device=/dev/disk/by-partuuid/${efi_uuid}

if [ ! -f btrfs_created.txt ]; then
    notify create root filesystem on ${root_device}
    mkfs.btrfs -f ${root_device} | tee btrfs_created.txt
fi
if [ ! -f vfat_created.txt ]; then
    notify create esp filesystem on ${efi_device}
    mkfs.vfat ${efi_device} | tee vfat_created.txt
fi

if mountpoint -q "/mnt/btrfs1" ; then
    echo top-level subvolume already mounted on /mnt/btrfs1
else
    notify mount top-level subvolume on /mnt/btrfs1
    mkdir -p /mnt/btrfs1
    mount ${root_device} /mnt/btrfs1 -o ${FSFLAGS},subvolid=5
fi

if [ ! -e /mnt/btrfs1/@ ]; then
    notify create @ and @home subvolumes on /mnt/btrfs1
    btrfs subvolume create /mnt/btrfs1/@
    btrfs subvolume create /mnt/btrfs1/@home
fi

if mountpoint -q "${target}" ; then
    echo root subvolume already mounted on ${target}
else
    notify mount root and home subvolume on ${target}
    mkdir -p ${target}
    mount ${root_device} ${target} -o ${FSFLAGS},subvol=@
    mkdir -p ${target}/home
    mount ${root_device} ${target}/home -o ${FSFLAGS},subvol=@home
fi

mkdir -p ${target}/var/cache/apt/archives
if mountpoint -q "${target}/var/cache/apt/archives" ; then
    echo apt cache directory already bind mounted on target
else
    notify bind mounting apt cache directory to target
    mount /var/cache/apt/archives ${target}/var/cache/apt/archives -o bind
fi

if [ ! -f ${target}/etc/debian_version ]; then
    notify install debian on ${target}
    debootstrap ${DEBIAN_VERSION} ${target} http://deb.debian.org/debian
fi

if mountpoint -q "${target}/proc" ; then
    echo bind mounts already set up on ${target}
else
    notify bind mount dev, proc, sys, run, var/tmp on ${target}
    mount -t proc none ${target}/proc
    mount --make-rslave --rbind /sys ${target}/sys
    mount --make-rslave --rbind /dev ${target}/dev
    mount --make-rslave --rbind /run ${target}/run
    mount --make-rslave --rbind /var/tmp ${target}/var/tmp
fi

notify setup sources list
rm -f ${target}/etc/apt/sources.list
mkdir -p ${target}/etc/apt/sources.list.d
cat <<EOF > ${target}/etc/apt/sources.list.d/debian.sources || exit 1
Types: deb
URIs: http://deb.debian.org/debian/
Suites: ${DEBIAN_VERSION}
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://deb.debian.org/debian/
Suites: ${DEBIAN_VERSION}-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

Types: deb
URIs: http://security.debian.org/debian-security/
Suites: ${DEBIAN_VERSION}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

cat <<EOF > ${target}/etc/apt/sources.list.d/debian-backports.sources || exit 1
Types: deb
URIs: http://deb.debian.org/debian/
Suites: ${DEBIAN_VERSION}-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

notify enable 32bit
chroot ${target}/ dpkg --add-architecture i386

notify install required packages on ${target}
cat <<EOF > ${target}/tmp/packages.txt
btrfsmaintenance
locales
adduser
passwd
sudo
tasksel
network-manager
binutils
console-setup
exim4-daemon-light
kpartx
pigz
pkg-config
EOF
cat <<EOF > ${target}/tmp/packages_backports.txt
systemd
systemd-cryptsetup
systemd-timesyncd
btrfs-progs
dosfstools
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
firmware-carl9170
firmware-cavium
firmware-intel-misc
firmware-intel-sound
firmware-iwlwifi
firmware-libertas
firmware-misc-nonfree
firmware-myricom
firmware-netronome
firmware-netxen
firmware-qcom-soc
firmware-qlogic
firmware-realtek
firmware-ti-connectivity
firmware-zd1211
cryptsetup
lvm2
mdadm
plymouth-themes
polkitd
tpm2-tools
tpm-udev
EOF
cat <<EOF > ${target}/tmp/run2.sh
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get update
xargs apt-get install -y < /tmp/packages.txt
xargs apt-get install -t ${BACKPORTS_VERSION} -y < /tmp/packages_backports.txt
EOF
chroot ${target}/ bash /tmp/run2.sh

notify running tasksel
chroot ${target}/ tasksel

if mountpoint -q "${target}/var/cache/apt/archives" ; then
    notify unmounting apt cache directory from target
    umount ${target}/var/cache/apt/archives
else
    echo  apt cache directory not mounted to target
fi

notify downloading remaining .deb files for the installer
cat <<EOF > ${target}/tmp/run3.sh
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get install -y --download-only locales tasksel openssh-server
apt-get install -t ${BACKPORTS_VERSION} -y --download-only systemd-boot dracut linux-image-amd64 popularity-contest
if (dpkg --get-selections | grep -w install |grep -qs "task.*desktop"); then
  apt-get install -t ${BACKPORTS_VERSION} -y --download-only linux-headers-amd64 nvidia-driver nvidia-driver-libs:i386
fi
EOF
chroot ${target}/ bash /tmp/run3.sh

notify cleaning up
chroot ${target}/ apt-get autoremove -y
rm -f ${target}/etc/machine-id
rm -f ${target}/etc/crypttab
rm -f ${target}/var/log/*log
rm -f ${target}/var/log/apt/*log

notify create snapshot after first phase
(cd /mnt/btrfs1; btrfs subvolume snapshot -r @ opinionated_installer_bootstrap)

echo "NOW CONTINUE WITH PART 2"  # TODO merge the 2 scripts (and the _lib script as well)
