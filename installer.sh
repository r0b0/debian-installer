#!/bin/bash

if [ x"${NON_INTERACTIVE}" == "x" ]; then
# edit this:
DISK=/dev/vda
USERNAME=user
USER_FULL_NAME="Debian User"
USER_PASSWORD=hunter2
ROOT_PASSWORD=changeme
LUKS_PASSWORD=luke
DEBIAN_VERSION=bookworm
HOSTNAME=debian12
fi

function notify () {
    echo $@
    if [ x"${NON_INTERACTIVE}" == "x" ]; then
      read -p "Enter to continue"
    fi
}

# TODO enable backports here when it becomes available for bookworm
DEBIAN_SOURCE=${DEBIAN_VERSION}
# see https://www.freedesktop.org/software/systemd/man/systemd-cryptenroll.html#--tpm2-device=PATH
TPM_PCRS="7+14"
# do not enable this on a live-cd
SHARE_APT_ARCHIVE=false
FSFLAGS="compress=zstd:1"
DEBIAN_FRONTEND=noninteractive
export DEBIAN_FRONTEND

notify install required packages
apt-get update -y
apt-get install -y cryptsetup debootstrap uuid-runtime

KEYFILE=luks.key
if [ ! -f efi-part.uuid ]; then
    notify generate uuid for efi partition
    uuidgen > efi-part.uuid
fi
if [ ! -f luks-part.uuid ]; then
    notify generate uuid for luks partition
    uuidgen > luks-part.uuid
fi
if [ ! -f luks.uuid ]; then
    notify generate uuid for luks device
    uuidgen > luks.uuid
fi
if [ ! -f btrfs.uuid ]; then
    notify generate uuid for btrfs filesystem
    uuidgen > btrfs.uuid
fi

root_part_type="4f68bce3-e8cd-4db1-96e7-fbcaf984b709"  # X86_64
efi_uuid=$(cat efi-part.uuid)
luks_part_uuid=$(cat luks-part.uuid)
luks_uuid=$(cat luks.uuid)
btrfs_uuid=$(cat btrfs.uuid)
top_level_mount=/mnt/top_level_mount
target=/target
luks_device=root
root_device=/dev/mapper/${luks_device}
kernel_params="rd.luks.options=${luks_uuid}=tpm2-device=auto rw quiet rootfstype=btrfs rootflags=${FSFLAGS} rd.auto=1 splash"

if [ ! -f partitions_created.txt ]; then
notify create 2 partitions on ${DISK}
sfdisk $DISK <<EOF
label: gpt
unit: sectors
sector-size: 512

${DISK}1: start=2048, size=2097152, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI system partition", uuid=${efi_uuid}
${DISK}2: start=2099200, size=4096000, type=${root_part_type}, name="LUKS partition", uuid=${luks_part_uuid}
EOF

notify resize the second partition on ${DISK} to fill available space
echo ", +" | sfdisk -N 2 $DISK

sfdisk -d $DISK > partitions_created.txt
fi

if [ ! -f $KEYFILE ]; then
    notify generate key file for luks
    dd if=/dev/random of=${KEYFILE} bs=512 count=1
    notify remove any old luks on ${DISK}2
    cryptsetup erase ${DISK}2
    wipefs -a ${DISK}2
fi

cryptsetup isLuks ${DISK}2
retVal=$?
if [ $retVal -ne 0 ]; then
    notify setup luks on ${DISK}2
    cryptsetup luksFormat ${DISK}2 --type luks2 --batch-mode --key-file $KEYFILE
    notify setup luks password
    echo "${LUKS_PASSWORD}" > /tmp/passwd
    cryptsetup --key-file=luks.key luksAddKey ${DISK}2 /tmp/passwd
    rm -f /tmp/passwd
    cryptsetup luksUUID ${DISK}2 > luks.uuid
else
    echo luks already set up
fi

if [ ! -e ${root_device} ]; then
    notify open luks
    cryptsetup luksOpen ${DISK}2 ${luks_device} --key-file $KEYFILE
fi

if [ -e /dev/disk/by-partlabel/BaseImage ]; then
    if [ ! -f base_image_copied.txt ]; then
        notify copy base image to ${root_device}
        dd if=/dev/disk/by-partlabel/BaseImage of=${root_device} bs=4M status=progress
        btrfs check ${root_device}
        btrfstune -U ${btrfs_uuid} -f ${root_device}  # change the uuid
        touch base_image_copied.txt
    fi
else
    if [ ! -f btrfs_created.txt ]; then
        notify create root filesystem on ${root_device}
        mkfs.btrfs -U ${btrfs_uuid} ${root_device} | tee btrfs_created.txt
    fi
fi
    
if [ ! -f vfat_created.txt ]; then
    notify create esp filesystem on ${DISK}1
    mkfs.vfat ${DISK}1
    touch vfat_created.txt
fi

if grep -qs "${top_level_mount}" /proc/mounts ; then
    echo top-level subvolume already mounted on ${top_level_mount}
else
    notify mount top-level subvolume on ${top_level_mount}
    mkdir -p ${top_level_mount}
    mount ${root_device} ${top_level_mount} -o rw,${FSFLAGS},subvolid=5
    btrfs filesystem resize max ${top_level_mount}
fi

if [ ! -e ${top_level_mount}/@ ]; then
    notify create @ and @home subvolumes on ${top_level_mount}
    btrfs subvolume create ${top_level_mount}/@
    btrfs subvolume create ${top_level_mount}/@home
    btrfs subvolume set-default ${top_level_mount}/@
fi

if grep -qs "${target}" /proc/mounts ; then
    echo root subvolume already mounted on ${target}
else
    notify mount root and home subvolume on ${target}
    mkdir -p ${target}
    mount ${root_device} ${target} -o ${FSFLAGS},subvol=@
    mkdir -p ${target}/home
    mount ${root_device} ${target}/home -o ${FSFLAGS},subvol=@home
fi

if [ ! -f ${target}/etc/debian_version ]; then
    notify install debian on ${target}
    debootstrap ${DEBIAN_VERSION} ${target} http://deb.debian.org/debian
fi

if grep -qs "${target}/proc" /proc/mounts ; then
    echo bind mounts already set up on ${target}
else
    notify bind mount dev, proc, sys, run on ${target}
    mount -t proc none ${target}/proc
    mount --make-rslave --rbind /sys ${target}/sys
    mount --make-rslave --rbind /dev ${target}/dev
    mount --make-rslave --rbind /run ${target}/run
fi

if grep -qs "${DISK}1 " /proc/mounts ; then
    echo efi esp partition ${DISK}1 already mounted on ${target}/boot/efi
else
    notify mount efi esp partition ${DISK}1 on ${target}/boot/efi
    mkdir -p ${target}/boot/efi
    mount ${DISK}1 ${target}/boot/efi
fi

notify setup hostname
echo "$HOSTNAME" > ${target}/etc/hostname

notify setup timezone
echo "${TIMEZONE}" > ${target}/etc/timezone
(cd ${target} && ln -s usr/share/zoneinfo/${TIMEZONE} etc/localtime)

notify setup fstab
mkdir -p ${target}/root/btrfs1
cat <<EOF > ${target}/etc/fstab
UUID=${btrfs_uuid} /home btrfs defaults,subvol=@home,${FSFLAGS} 0 1
UUID=${btrfs_uuid} /root/btrfs1 btrfs defaults,subvolid=5,${FSFLAGS} 0 1
PARTUUID=${efi_uuid} /boot/efi vfat defaults 0 2
EOF

notify setup sources.list
cat <<EOF > ${target}/etc/apt/sources.list
deb http://deb.debian.org/debian ${DEBIAN_VERSION} main contrib non-free non-free-firmware
deb http://security.debian.org/ ${DEBIAN_VERSION}-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${DEBIAN_VERSION}-backports main contrib non-free non-free-firmware
EOF

if [ "$SHARE_APT_ARCHIVE" = true ] ; then
    mkdir -p ${target}/var/cache/apt/archives
    if grep -qs "${target}/var/cache/apt/archives" /proc/mounts ; then
        echo apt cache directory already bind mounted on target
    else
        notify bind mounting apt cache directory to target
        mount /var/cache/apt/archives ${target}/var/cache/apt/archives -o bind
    fi
fi

if grep -qs 'root:\$' ${target}/etc/shadow ; then
    echo root password already set up
else
    notify set up root password
    echo "root:${ROOT_PASSWORD}" > ${target}/tmp/passwd
    chroot ${target}/ bash -c "chpasswd < /tmp/passwd"
    rm -f ${target}/tmp/passwd
fi

if grep -qs "^${USERNAME}:" ${target}/etc/shadow ; then
    # XXX: check this - the user was not created
    echo ${USERNAME} user already set up
else
    notify set up ${USERNAME} user
    chroot ${target}/ adduser ${USERNAME} --disabled-password --gecos "${USER_FULL_NAME}"
    echo "${USERNAME}:${USER_PASSWORD}" > ${target}/tmp/passwd
    chroot ${target}/ bash -c "chpasswd < /tmp/passwd"
    rm -f ${target}/tmp/passwd
fi

notify configuring dracut and kernel command line
mkdir -p ${target}/etc/dracut.conf.d
cat <<EOF > ${target}/etc/dracut.conf.d/90-luks.conf
add_dracutmodules+=" systemd crypt btrfs tpm2-tss "
kernel_cmdline="${kernel_params}"
EOF
cat <<EOF > ${target}/etc/kernel/cmdline
${kernel_params}
EOF
rm -f ${target}/etc/crypttab

notify install required packages on ${target}
cat <<EOF > ${target}/tmp/run1.sh
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -t ${DEBIAN_SOURCE} locales systemd systemd-boot dracut btrfs-progs tasksel network-manager cryptsetup tpm2-tools -y
bootctl install
EOF
chroot ${target}/ sh /tmp/run1.sh

notify checking for tpm
cp ${KEYFILE} ${target}/
chmod 600 ${target}/${KEYFILE}
cat <<EOF > ${target}/tmp/run4.sh
systemd-cryptenroll --tpm2-device=list > /tmp/tpm-list.txt
if grep -qs "/dev/tpm" /tmp/tpm-list.txt ; then
    echo tpm available, enrolling
    cp $KEYFILE /target
    systemd-cryptenroll --unlock-key-file=/${KEYFILE} --tpm2-device=auto ${DISK}2 --tpm2-pcrs=${TPM_PCRS}
else
    echo tpm not avaialble
fi
EOF
chroot ${target}/ bash /tmp/run4.sh
rm ${target}/${KEYFILE}

notify install kernel and firmware on ${target}
cat <<EOF > ${target}/tmp/packages.txt
dracut
linux-image-amd64
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
xargs apt-get install -t ${DEBIAN_SOURCE} -y < /tmp/packages.txt
EOF
chroot ${target}/ bash /tmp/run2.sh

# notify running tasksel
# chroot ${target}/ tasksel

notify umounting all filesystems
umount -R ${target}
umount -R ${top_level_mount}

notify closing luks
cryptsetup luksClose ${luks_device}

notify "INSTALLATION FINISHED"
notify "You will want to store the luks.key file safely"
