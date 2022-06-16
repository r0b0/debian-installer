#!/bin/sh

DISK=/dev/vda
KEYFILE=luks.key

DEBIAN_VERSION=bullseye

if [ ! -f efi.uuid ]; then
    echo generate uuid for efi partition
    uuidgen > efi.uuid
fi
if [ ! -f luks.uuid ]; then
    echo generate uuid for luks partition
    uuidgen > luks.uuid
fi

efi_uuid=$(cat efi.uuid)
luks_uuid=$(cat luks.uuid)

if [ ! -f partitions_created.txt ]; then
echo create 2 partitions
sfdisk $DISK <<EOF
label: gpt
unit: sectors
sector-size: 512

${DISK}1: start=2048, size=409600, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI system partition", uuid=${efi_uuid}
${DISK}2: start=411648, size=4096000, type=CA7D7CCB-63ED-4C53-861C-1742536059CC, name="LUKS partition", uuid=${luks_uuid}
EOF

echo resize the second partition to fill available space
echo ", +" | sfdisk -N 2 $DISK

sfdisk -d $DISK > partitions_created.txt
fi

echo install required packages
apt-get update -y
apt-get install -y cryptsetup debootstrap

if [ ! -f $KEYFILE ]; then
    echo generate key file for luks
    uuidgen > $KEYFILE
fi

if cryptsetup isLuks ${DISK}2 ; then
    echo luks already set up
else
    echo setup luks
    cryptsetup luksFormat ${DISK}2 --type luks2 --batch-mode --key-file $KEYFILE
fi

if [ ! -e /dev/mapper/luksroot ]; then
    echo open luks
    cryptsetup luksOpen ${DISK}2 luksroot --key-file $KEYFILE
fi

if [ ! -f btrfs_created.txt ]; then
    echo create root filesystem
    mkfs.btrfs /dev/mapper/luksroot
    touch btrfs_created.txt
fi
if [ ! -f vfat_created.txt ]; then
    echo create esp filesystem
    mkfs.vfat ${DISK}1
    touch vfat_created.txt
fi

if grep -qs "${DISK}2 " /proc/mounts ; then
    echo root already mounted
else
    echo mount root filesystem
    mkdir -p /mnt/btrfs1
    mount /dev/mapper/luksroot /mnt/btrfs1 -o compress=zstd:1
fi

if [ ! -e /mnt/btrfs1/@ ]; then
    echo create subvolumes
    btrfs subvolume create /mnt/btrfs1/@
    btrfs subvolume create /mnt/btrfs1/@home
fi

if [ ! -f /mnt/btrfs1/@/etc/debian_version ]; then
    echo install debian
    debootstrap ${DEBIAN_VERSION} "/mnt/btrfs1/@" http://deb.debian.org/debian
fi

if grep -qs "/mnt/btrfs1/@/proc" /proc/mounts ; then
    echo bind mounts already set up
else
    echo bind mount dev, proc, etc
    mount --make-rslave --rbind /proc /mnt/btrfs1/@/proc
    mount --make-rslave --rbind /sys /mnt/btrfs1/@/sys
    mount --make-rslave --rbind /dev /mnt/btrfs1/@/dev
    mount --make-rslave --rbind /run /mnt/btrfs1/@/run
fi

if grep -qs "${DISK}1 " /proc/mounts ; then
    echo efi already mounted
else
    echo mount efi
    mkdir -p /mnt/btrfs1/@/boot/efi
    mount ${DISK}1 /mnt/btrfs1/@/boot/efi
fi

echo setup crypttab
cat <<EOF > /mnt/btrfs1/@/etc/crypttab
luksroot UUID=${luks_uuid} initramfs luks
EOF

echo setup fstab
cat <<EOF > /mnt/btrfs1/@/etc/fstab
/dev/mapper/luksroot / btrfs subvol=@,compress=zstd:1 0 1
UUID=${efi_uuid} /boot/efi vfat defaults 0 2
EOF

echo setup sources.list
cat <<EOF > /mnt/btrfs1/@/etc/apt/sources.list
deb http://deb.debian.org/debian ${DEBIAN_VERSION} main contrib non-free
deb http://security.debian.org/ ${DEBIAN_VERSION}-security main contrib non-free
deb http://deb.debian.org/debian ${DEBIAN_VERSION}-backports main contrib non-free
EOF

echo setup efistup scripts
mkdir -p /mnt/btrfs1/@/etc/kernel/postinst.d
mkdir -p /mnt/btrfs1/@/boot/efi/EFI/debian/
cat <<EOF > /mnt/btrfs1/@/etc/kernel/postinst.d/zz-update-efistub
#!/bin/sh

cp -L /vmlinuz /boot/efi/EFI/debian/
EOF
chmod +x /mnt/btrfs1/@/etc/kernel/postinst.d/zz-update-efistub
mkdir -p /mnt/btrfs1/@/etc/initramfs/post-update.d
cat <<EOF > /mnt/btrfs1/@/etc/initramfs/post-update.d/zz-update-efistub
#!/bin/sh

cp -L /initrd.img /boot/efi/EFI/debian/
EOF
chmod +x /mnt/btrfs1/@/etc/initramfs/post-update.d/zz-update-efistub

echo install systemd from backports
cat <<EOF > /mnt/btrfs1/@/tmp/run1.sh
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -t ${DEBIAN_VERSION}-backports systemd cryptsetup efibootmgr btrfs-progs cryptsetup-initramfs -y
EOF
chroot /mnt/btrfs1/@/ sh /tmp/run1.sh

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
# chroot /mnt/btrfs1/@/ sh /tmp/run2.sh

cat <<EOF > /mnt/btrfs1/@/tmp/run3.sh
efibootmgr -v > /tmp/efi.txt
if grep -qs "${efi_uuid}" /tmp/efi.txt ; then
    echo efibootmgr already set up
else
    echo setting up efibootmgr
    efibootmgr -c -g -L "Debian efistub" -l "\\EFI\\debian\\vmlinuz" -u "root=/dev/mapper/luksroot rw quiet rootfstype=btrfs rootflags=subvol=@,compress=zstd:1 splash add_efi_mmap initrd=\\EFI\\debian\\initrd.img"
fi
EOF
chroot /mnt/btrfs1/@/ sh /tmp/run3.sh

echo umounting all filesystems
umount /mnt/btrfs1/@/proc
umount /mnt/btrfs1/@/sys
umount /mnt/btrfs1/@/dev
umount /mnt/btrfs1/@/run
umount /mnt/btrfs1/@/boot/efi
umount /mnt/btrfs1

echo closing luks
cryptsetup luksClose luksroot

echo "INSTALLATION FINISHED"
echo "You will want to store the luks.key file safely"
echo "You will also want to set up a new luks password by running "
echo cryptsetup --key-file=luks.key luksAddKey ${DISK}2
