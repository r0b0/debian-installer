#!/bin/bash

# edit this:
DISK=/dev/vda
USERNAME=user
DEBIAN_VERSION=bookworm
# TODO enable backports here when it becomes available for bookworm
DEBIAN_SOURCE=${DEBIAN_VERSION}
# TODO enable 7 and 14 here?
# see https://www.freedesktop.org/software/systemd/man/systemd-cryptenroll.html#--tpm2-device=PATH
TPM_PCRS=

KEYFILE=luks.key
if [ ! -f efi-part.uuid ]; then
    echo generate uuid for efi partition
    uuidgen > efi-part.uuid
fi
if [ ! -f luks-part.uuid ]; then
    echo generate uuid for luks partition
    uuidgen > luks-part.uuid
fi
if [ ! -f luks.uuid ]; then
    echo generate uuid for luks device
    uuidgen > luks.uuid
fi
if [ ! -f btrfs.uuid ]; then
    echo generate uuid for btrfs filesystem
    uuidgen > btrfs.uuid
fi

efi_uuid=$(cat efi-part.uuid)
luks_part_uuid=$(cat luks-part.uuid)
luks_uuid=$(cat luks.uuid)
btrfs_uuid=$(cat btrfs.uuid)
target=/target
luks_device=luksroot
root_device=/dev/mapper/${luks_device}
kernel_params="rd.luks.name=${luks_uuid}=${luks_device} rd.luks.options=${luks_uuid}=tpm2-device=auto root=UUID=${btrfs_uuid} rw quiet rootfstype=btrfs rootflags=subvol=@,compress=zstd:1 rd.auto=1 splash"

if [ ! -f partitions_created.txt ]; then
echo create 2 partitions on ${DISK}
read -p "Enter to continue"
sfdisk $DISK <<EOF
label: gpt
unit: sectors
sector-size: 512

${DISK}1: start=2048, size=409600, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI system partition", uuid=${efi_uuid}
${DISK}2: start=411648, size=4096000, type=CA7D7CCB-63ED-4C53-861C-1742536059CC, name="LUKS partition", uuid=${luks_part_uuid}
EOF

echo resize the second partition on ${DISK} to fill available space
read -p "Enter to continue"
echo ", +" | sfdisk -N 2 $DISK

sfdisk -d $DISK > partitions_created.txt
fi

echo install required packages
read -p "Enter to continue"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y cryptsetup debootstrap

if [ ! -f $KEYFILE ]; then
    echo generate key file for luks
    dd if=/dev/random of=${KEYFILE} bs=512 count=1
fi

cryptsetup isLuks ${DISK}2
if [ ! $? ]; then
    echo setup luks on ${DISK}2
    read -p "Enter to continue"
    cryptsetup luksFormat ${DISK}2 --type luks2 --batch-mode --key-file $KEYFILE
    echo setup luks password
    cryptsetup --key-file=luks.key luksAddKey ${DISK}2
    cryptsetup luksUUID ${DISK}2 > luks.uuid
else
    echo luks already set up
fi

if [ ! -e ${root_device} ]; then
    echo open luks
    read -p "Enter to continue"
    cryptsetup luksOpen ${DISK}2 ${luks_device} --key-file $KEYFILE
fi

if [ ! -f btrfs_created.txt ]; then
    echo create root filesystem on ${root_device}
    read -p "Enter to continue"
    mkfs.btrfs -U ${btrfs_uuid} ${root_device}
    touch btrfs_created.txt
fi
if [ ! -f vfat_created.txt ]; then
    echo create esp filesystem on ${DISK}1
    read -p "Enter to continue"
    mkfs.vfat ${DISK}1
    touch vfat_created.txt
fi

if grep -qs "/mnt/btrfs1" /proc/mounts ; then
    echo top-level subvolume already mounted on /mnt/btrfs1
else
    echo mount top-level subvolume on /mnt/btrfs1
    mkdir -p /mnt/btrfs1
    read -p "Enter to continue"
    mount ${root_device} /mnt/btrfs1 -o compress=zstd:1
fi

if [ ! -e /mnt/btrfs1/@ ]; then
    echo create @ and @home subvolumes on /mnt/btrfs1
    read -p "Enter to continue"
    btrfs subvolume create /mnt/btrfs1/@
    btrfs subvolume create /mnt/btrfs1/@home
fi

if grep -qs "${target}" /proc/mounts ; then
    echo root subvolume already mounted on ${target}
else
    echo mount root and home subvolume on ${target}
    mkdir -p ${target}
    read -p "Enter to continue"
    mount ${root_device} ${target} -o compress=zstd:1,subvol=@
    mkdir -p ${target}/home
    mount ${root_device} ${target}/home -o compress=zstd:1,subvol=@home
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

if grep -qs "${DISK}1 " /proc/mounts ; then
    echo efi esp partition ${DISK}1 already mounted on ${target}/boot/efi
else
    echo mount efi esp partition ${DISK}1 on ${target}/boot/efi
    mkdir -p ${target}/boot/efi
    read -p "Enter to continue"
    mount ${DISK}1 ${target}/boot/efi
fi

echo setup fstab
mkdir -p ${target}/root/btrfs1
read -p "Enter to continue"
cat <<EOF > ${target}/etc/fstab
UUID=${btrfs_uuid} / btrfs defaults,subvol=@,compress=zstd:1 0 1
UUID=${btrfs_uuid} /home btrfs defaults,subvol=@home,compress=zstd:1 0 1
UUID=${btrfs_uuid} /root/btrfs1 btrfs defaults,subvolid=5,compress=zstd:1 0 1
PARTUUID=${efi_uuid} /boot/efi vfat defaults 0 2
EOF

echo setup sources.list
read -p "Enter to continue"
cat <<EOF > ${target}/etc/apt/sources.list
deb http://deb.debian.org/debian ${DEBIAN_VERSION} main contrib non-free
deb http://security.debian.org/ ${DEBIAN_VERSION}-security main contrib non-free
deb http://deb.debian.org/debian ${DEBIAN_VERSION}-backports main contrib non-free
EOF

if grep -qs 'root:\$' ${target}/etc/shadow ; then
    echo root password already set up
else
    echo set up root password
    read -p "Enter to continue"
    chroot ${target}/ passwd
fi

if grep -qs "^${USERNAME}:" ${target}/etc/shadow ; then
    echo ${USERNAME} user already set up
else
    echo set up ${USERNAME} user
    chroot ${target}/ adduser ${USERNAME}
fi

echo configuring dracut and kernel command line
read -p "Enter to continue"
mkdir -p ${target}/etc/dracut.conf.d
cat <<EOF > ${target}/etc/dracut.conf.d/90-luks.conf
add_dracutmodules+=" systemd crypt btrfs tpm2-tss "
kernel_cmdline="${kernel_params}"
EOF
cat <<EOF > ${target}/etc/kernel/cmdline
${kernel_params}
EOF

echo install required packages on ${target}
cat <<EOF > ${target}/tmp/run1.sh
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -t ${DEBIAN_SOURCE} locales systemd systemd-boot dracut btrfs-progs tasksel network-manager cryptsetup tpm2-tools -y
bootctl install
EOF
read -p "Enter to continue"
chroot ${target}/ sh /tmp/run1.sh

echo checking for tpm
cp ${KEYFILE} ${target}/
chmod 600 ${target}/${KEYFILE}
cat <<EOF > ${target}/tmp/run4.sh
systemd-cryptenroll --tpm2-device=list > /tmp/tpm-list.txt
if grep -qs "/dev/tpm" /tmp/tpm-list.txt ; then
    echo tpm available, enrolling
    read -p "Enter to continue"
    cp $KEYFILE /target
    systemd-cryptenroll --unlock-key-file=/${KEYFILE} --tpm2-device=auto ${DISK}2 --tpm2-pcrs=${TPM_PCRS}
else
    echo tpm not avaialble
fi
EOF
chroot ${target}/ bash /tmp/run4.sh
rm ${target}/${KEYFILE}

echo install kernel and firmware on ${target}
cat <<EOF > ${target}/tmp/packages.txt
dracut
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
cat <<EOF > ${target}/tmp/run2.sh
!/bin/bash
export DEBIAN_FRONTEND=noninteractive
xargs apt-get install -t ${DEBIAN_SOURCE} -y < /tmp/packages.txt
EOF
read -p "Enter to continue"
chroot ${target}/ bash /tmp/run2.sh

echo running tasksel
read -p "Enter to continue"
chroot ${target}/ tasksel

echo umounting all filesystems
read -p "Enter to continue"
umount -R ${target}
umount -R /mnt/btrfs1

echo closing luks
read -p "Enter to continue"
cryptsetup luksClose ${luks_device}

echo "INSTALLATION FINISHED"
echo "You will want to store the luks.key file safely"
