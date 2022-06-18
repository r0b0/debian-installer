#!/bin/bash

DISK=/dev/vda
KEYFILE=luks.key

DEBIAN_VERSION=bullseye

if [ ! -f efi-part.uuid ]; then
    echo generate uuid for efi partition
    uuidgen > efi-part.uuid
fi
if [ ! -f luks-part.uuid ]; then
    echo generate uuid for luks partition
    uuidgen > luks-part.uuid
fi

efi_uuid=$(cat efi-part.uuid)
luks_uuid=$(cat luks-part.uuid)
target=/target

if [ ! -f partitions_created.txt ]; then
echo create 2 partitions
read -p "Enter to continue"
sfdisk $DISK <<EOF
label: gpt
unit: sectors
sector-size: 512

${DISK}1: start=2048, size=409600, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI system partition", uuid=${efi_uuid}
${DISK}2: start=411648, size=4096000, type=CA7D7CCB-63ED-4C53-861C-1742536059CC, name="LUKS partition", uuid=${luks_uuid}
EOF

echo resize the second partition to fill available space
read -p "Enter to continue"
echo ", +" | sfdisk -N 2 $DISK

sfdisk -d $DISK > partitions_created.txt
fi

echo install required packages
read -p "Enter to continue"
apt-get update -y
apt-get install -y cryptsetup debootstrap

if [ ! -f $KEYFILE ]; then
    echo generate key file for luks
    uuidgen > $KEYFILE
fi

if [ ! -f luks.uuid ]; then
    echo setup luks
    read -p "Enter to continue"
    cryptsetup luksFormat ${DISK}2 --type luks2 --batch-mode --key-file $KEYFILE
    cryptsetup luksUUID ${DISK}2 > luks.uuid
else
    echo luks already set up
fi

luks_crypt_uuid=$(cat luks.uuid)

if [ ! -e /dev/mapper/luksroot ]; then
    echo open luks
    read -p "Enter to continue"
    cryptsetup luksOpen ${DISK}2 luksroot --key-file $KEYFILE
fi

if [ ! -f btrfs_created.txt ]; then
    echo create root filesystem
    read -p "Enter to continue"
    mkfs.btrfs /dev/mapper/luksroot
    touch btrfs_created.txt
fi
if [ ! -f vfat_created.txt ]; then
    echo create esp filesystem
    read -p "Enter to continue"
    mkfs.vfat ${DISK}1
    touch vfat_created.txt
fi

if grep -qs "/mnt/btrfs1" /proc/mounts ; then
    echo root already mounted
else
    echo mount root filesystem
    mkdir -p /mnt/btrfs1
    read -p "Enter to continue"
    mount /dev/mapper/luksroot /mnt/btrfs1 -o compress=zstd:1
fi

if [ ! -e /mnt/btrfs1/@ ]; then
    echo create subvolumes
    read -p "Enter to continue"
    btrfs subvolume create /mnt/btrfs1/@
    btrfs subvolume create /mnt/btrfs1/@home
fi

if grep -qs "${target}" /proc/mounts ; then
    echo target already mounted
else
    echo mount target
    mkdir -p /target
    read -p "Enter to continue"
    mount /dev/mapper/luksroot ${target} -o compress=zstd:1,subvol=@
fi

if [ ! -f ${target}/etc/debian_version ]; then
    echo install debian
    read -p "Enter to continue"
    debootstrap ${DEBIAN_VERSION} ${target} http://deb.debian.org/debian
fi

if grep -qs "${target}/proc" /proc/mounts ; then
    echo bind mounts already set up
else
    echo bind mount dev, proc, sys, run
    read -p "Enter to continue"
    mount -t proc none ${target}/proc
    mount --make-rslave --rbind /sys ${target}/sys
    mount --make-rslave --rbind /dev ${target}/dev
    mount --make-rslave --rbind /run ${target}/run
fi

if grep -qs "${DISK}1 " /proc/mounts ; then
    echo efi already mounted
else
    echo mount efi
    mkdir -p ${target}/boot/efi
    read -p "Enter to continue"
    mount ${DISK}1 ${target}/boot/efi
fi

echo setup crypttab
read -p "Enter to continue"
mkdir -p ${target}/root/btrfs1
cat <<EOF > ${target}/etc/crypttab
luksroot UUID=${luks_crypt_uuid} none initramfs,luks
EOF

echo setup fstab
read -p "Enter to continue"
cat <<EOF > ${target}/etc/fstab
/dev/mapper/luksroot / btrfs subvol=@,compress=zstd:1 0 1
/dev/mapper/luksroot /home btrfs subvol=@home,compress=zstd:1 0 1
/dev/mapper/luksroot /root/btrfs1 btrfs subvolid=5,compress=zstd:1 0 1
PARTUUID=${efi_uuid} /boot/efi vfat defaults 0 2
EOF

echo setup sources.list
read -p "Enter to continue"
cat <<EOF > ${target}/etc/apt/sources.list
deb http://deb.debian.org/debian ${DEBIAN_VERSION} main contrib non-free
deb http://security.debian.org/ ${DEBIAN_VERSION}-security main contrib non-free
deb http://deb.debian.org/debian ${DEBIAN_VERSION}-backports main contrib non-free
EOF

echo setup efistub scripts
mkdir -p ${target}/etc/kernel/postinst.d
mkdir -p ${target}/boot/efi/EFI/debian/
read -p "Enter to continue"
cat <<EOF > ${target}/etc/kernel/postinst.d/zz-update-efistub
#!/bin/bash

cp -L /vmlinuz /boot/efi/EFI/debian/
EOF
chmod +x ${target}/etc/kernel/postinst.d/zz-update-efistub
mkdir -p ${target}/etc/initramfs/post-update.d
cat <<EOF > ${target}/etc/initramfs/post-update.d/zz-update-efistub
#!/bin/bash

cp -L /initrd.img /boot/efi/EFI/debian/
EOF
chmod +x ${target}/etc/initramfs/post-update.d/zz-update-efistub

if grep -qs 'root:\$' ${target}/etc/shadow ; then
    echo root password already set up
else
    echo set up root password
    read -p "Enter to continue"
    chroot ${target}/ passwd
fi

echo install systemd from backports
cat <<EOF > ${target}/tmp/run1.sh
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -t ${DEBIAN_VERSION}-backports systemd cryptsetup efibootmgr btrfs-progs cryptsetup-initramfs -y
EOF
read -p "Enter to continue"
chroot ${target}/ sh /tmp/run1.sh

echo install kernel and firmware
cat <<EOF > ${target}/tmp/packages.txt
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
cat <<EOF > ${target}/tmp/run2.sh
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
xargs apt-get install -t ${DEBIAN_VERSION}-backports -y < /tmp/packages.txt
EOF
read -p "Enter to continue"
chroot ${target}/ bash /tmp/run2.sh

cat <<EOF > ${target}/tmp/run3.sh
#!/bin/bash
efibootmgr -v > /tmp/efi.txt
if grep -qs "${efi_uuid}" /tmp/efi.txt ; then
    echo efibootmgr already set up
else
    echo setting up efibootmgr
    read -p "Enter to continue"
    efibootmgr -c -g -L "Debian efistub" -d ${DISK} -l "\\EFI\\debian\\vmlinuz" -u "root=/dev/mapper/luksroot rw quiet rootfstype=btrfs rootflags=subvol=@,compress=zstd:1 splash add_efi_mmap initrd=\\EFI\\debian\\initrd.img"
fi
EOF
chroot ${target}/ bash /tmp/run3.sh

echo umounting all filesystems
read -p "Enter to continue"
umount ${target}/proc
umount ${target}/sys
umount ${target}/dev
umount ${target}/run
umount ${target}/boot/efi
umount /mnt/btrfs1

echo closing luks
read -p "Enter to continue"
cryptsetup luksClose luksroot

echo "INSTALLATION FINISHED"
echo "You will want to store the luks.key file safely"
echo "You will also want to set up a new luks password by running "
echo cryptsetup --key-file=luks.key luksAddKey ${DISK}2
