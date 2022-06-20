#!/bin/bash

DISK=/dev/sda
KEYFILE=luks.key
USERNAME=user
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
luks_device=luksroot
root_device=/dev/mapper/${luks_device}
kernel_params="root=${root_device} rw quiet rootfstype=btrfs rootflags=subvol=@,compress=zstd:1 splash add_efi_mmap"

if [ ! -f partitions_created.txt ]; then
echo create 2 partitions on ${DISK}
read -p "Enter to continue"
sfdisk $DISK <<EOF
label: gpt
unit: sectors
sector-size: 512

${DISK}1: start=2048, size=409600, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI system partition", uuid=${efi_uuid}
${DISK}2: start=411648, size=4096000, type=CA7D7CCB-63ED-4C53-861C-1742536059CC, name="LUKS partition", uuid=${luks_uuid}
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

if [ ! -f luks.uuid ]; then
    echo setup luks on ${DISK}2
    read -p "Enter to continue"
    cryptsetup luksFormat ${DISK}2 --type luks2 --batch-mode --key-file $KEYFILE
    echo setup luks password
    cryptsetup --key-file=luks.key luksAddKey ${DISK}2
    cryptsetup luksUUID ${DISK}2 > luks.uuid
else
    echo luks already set up
fi

luks_crypt_uuid=$(cat luks.uuid)

if [ ! -e ${root_device} ]; then
    echo open luks
    read -p "Enter to continue"
    cryptsetup luksOpen ${DISK}2 ${luks_device} --key-file $KEYFILE
fi

if [ ! -f btrfs_created.txt ]; then
    echo create root filesystem on ${root_device}
    read -p "Enter to continue"
    mkfs.btrfs ${root_device}
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

if [ ! -f ${target}/etc/crypttab ]; then
    echo setup crypttab
    read -p "Enter to continue"
    mkdir -p ${target}/root/btrfs1
    cat <<EOF > ${target}/etc/crypttab
${luks_device} UUID=${luks_crypt_uuid} none luks
EOF
else
    echo crypttab already set up
fi

echo setup fstab
read -p "Enter to continue"
cat <<EOF > ${target}/etc/fstab
${root_device} / btrfs defaults,subvol=@,compress=zstd:1 0 1
${root_device} /home btrfs defaults,subvol=@home,compress=zstd:1 0 1
${root_device} /root/btrfs1 btrfs defaults,subvolid=5,compress=zstd:1 0 1
PARTUUID=${efi_uuid} /boot/efi vfat defaults 0 2
EOF

echo setup sources.list
read -p "Enter to continue"
cat <<EOF > ${target}/etc/apt/sources.list
deb http://deb.debian.org/debian ${DEBIAN_VERSION} main contrib non-free
deb http://security.debian.org/ ${DEBIAN_VERSION}-security main contrib non-free
deb http://deb.debian.org/debian ${DEBIAN_VERSION}-backports main contrib non-free
EOF

if [ ! -f ${target}/etc/kernel/postinst.d/zz-update-efistub ]; then
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
else
    echo efistub scripts already set up
fi

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

echo install required packages on ${target}
cat <<EOF > ${target}/tmp/run1.sh
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -t ${DEBIAN_VERSION}-backports systemd libtss2-esys-3.0.2-0 libtss2-rc0 efibootmgr btrfs-progs tasksel network-manager -y
EOF
read -p "Enter to continue"
chroot ${target}/ sh /tmp/run1.sh

echo install kernel and firmware on ${target}
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
chroot ${target}/ apt-get install -t ${DEBIAN_VERSION}-backports dracut -y

cat <<EOF > ${target}/tmp/run3.sh
#!/bin/bash
efibootmgr -v > /tmp/efi.txt
if grep -qs "${efi_uuid}" /tmp/efi.txt ; then
    echo efibootmgr already set up
else
    echo setting up efibootmgr
    read -p "Enter to continue"
    efibootmgr -c -g -L "Debian efistub" -d ${DISK} -l "\\EFI\\debian\\vmlinuz" -u "${kernel_params} initrd=\\EFI\\debian\\initrd.img"
fi
EOF
chroot ${target}/ bash /tmp/run3.sh

echo running tasksel
chroot ${target}/ tasksel

echo checking for tpm
cat <<EOF > ${target}/tmp/run4.sh
systemd-cryptenroll --tpm2-device=list > /tmp/tpm-list.txt
if grep -qs "/dev/tpm" /tmp/tpm-list.txt ; then
    echo tpm available, enrolling
    read -p "Enter to continue"
    systemd-cryptenroll --tpm2-device=auto ${DISK}2
    cat <<TARGETEOF > /etc/crypttab
${luks_device} UUID=${luks_crypt_uuid} none luks,tpm2-device=auto
TARGETEOF
else
    echo tpm not avaialble
fi
EOF
chroot ${target}/ bash /tmp/run4.sh

echo umounting all filesystems
read -p "Enter to continue"
umount -R ${target}/proc
umount -R ${target}/sys
umount -R ${target}/dev
umount -R ${target}/run
umount -R ${target}/boot/efi
umount -R ${target}
umount -R /mnt/btrfs1

echo closing luks
read -p "Enter to continue"
cryptsetup luksClose ${luks_device}

echo "INSTALLATION FINISHED"
echo "You will want to store the luks.key file safely"
