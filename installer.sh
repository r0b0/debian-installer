#!/bin/bash

if [ -z "${NON_INTERACTIVE}" ]; then
# edit this:
DISK=/dev/vda
USERNAME=user
USER_FULL_NAME="Debian User"
USER_PASSWORD=hunter2
ROOT_PASSWORD=changeme
LUKS_PASSWORD=luke
ENABLE_TPM=true
HOSTNAME=debian13
ENABLE_SWAP=partition
SWAP_SIZE=2
NVIDIA_PACKAGE=
ENABLE_POPCON=false
SSH_PUBLIC_KEY=
AFTER_INSTALLED_CMD=
fi

function notify () {
    echo $@
    if [ -z "${NON_INTERACTIVE}" ]; then
      read -p "Enter to continue"
    fi
}

DEBIAN_VERSION=trixie
BACKPORTS_VERSION=${DEBIAN_VERSION}  # TODO append "-backports" when available
# see https://www.freedesktop.org/software/systemd/man/systemd-cryptenroll.html#--tpm2-pcrs=PCR
TPM_PCRS="7+14"
# do not enable this on a live-cd
SHARE_APT_ARCHIVE=false
FSFLAGS="compress=zstd:1"
DEBIAN_FRONTEND=noninteractive
export DEBIAN_FRONTEND

if [ "$(id -u)" -ne 0 ]; then
    echo 'This script must be run by root' >&2
    exit 1
fi

if [ -z "${DISK}" ]; then
    echo "DISK variable is missing" >&2
    exit 2
fi

if [ -z "${LUKS_PASSWORD}" ]; then
    echo "LUKS_PASSWORD variable is missing" >&2
    exit 3
fi

if [ -z "${NON_INTERACTIVE}" ]; then
    notify install required packages
    apt-get update -y  || exit 1
    apt-get install -y cryptsetup debootstrap uuid-runtime btrfs-progs dosfstools || exit 1
fi

KEYFILE=luks.key
if [ ! -f efi-part.uuid ]; then
    notify generate uuid for efi partition
    uuidgen > efi-part.uuid || exit 1
fi
if [ ! -f luks-part.uuid ]; then
    notify generate uuid for luks partition
    uuidgen > luks-part.uuid || exit 1
fi

if [ "${ENABLE_SWAP}" == "partition" ]; then
    if [ ! -f swap-part.uuid ]; then
        notify generate uuid for swap partition
        uuidgen > swap-part.uuid || exit 1
    fi
fi

if [ ! -f btrfs.uuid ]; then
    notify generate uuid for btrfs filesystem
    uuidgen > btrfs.uuid || exit 1
fi

root_part_type="4f68bce3-e8cd-4db1-96e7-fbcaf984b709"  # X86_64
system_part_type="C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
swap_part_type="0657FD6D-A4AB-43C4-84E5-0933C84B4F4F "
efi_part_uuid=$(cat efi-part.uuid)
luks_part_uuid=$(cat luks-part.uuid)
btrfs_uuid=$(cat btrfs.uuid)
top_level_mount=/mnt/top_level_mount
target=/target
luks_device=root
root_device=/dev/mapper/${luks_device}
kernel_params="rd.luks.options=tpm2-device=auto rw quiet rootfstype=btrfs rootflags=${FSFLAGS},subvol=@ rd.auto=1 splash"
efi_partition=/dev/disk/by-partuuid/${efi_part_uuid}
root_partition=/dev/disk/by-partuuid/${luks_part_uuid}

if [ "${ENABLE_SWAP}" == "partition" ]; then
swap_part_uuid=$(cat swap-part.uuid)
swap_size_blocks=$((${SWAP_SIZE}*2048*1024))
root_start_blocks=$((2099200+${swap_size_blocks}))
swap_partition=/dev/disk/by-partuuid/${swap_part_uuid}
swap_device=swap1
root_partition_nr=3
sfdisk_format=$(cat <<EOF
start=2048, size=2097152, type=${system_part_type}, name="EFI system partition", uuid=${efi_part_uuid}
start=2099200, size=${swap_size_blocks}, type=${swap_part_type}, name="Swap partition", uuid=${swap_part_uuid}
start=${root_start_blocks}, size=4096000, type=${root_part_type}, name="Root partition", uuid=${luks_part_uuid}
EOF
)
else
root_partition_nr=2
swap_partition=none
sfdisk_format=$(cat <<EOF
start=2048, size=2097152, type=${system_part_type}, name="EFI system partition", uuid=${efi_part_uuid}
start=2099200, size=4096000, type=${root_part_type}, name="LUKS partition", uuid=${luks_part_uuid}
EOF
)
fi

if [ ! -f partitions_created.txt ]; then
notify create ${root_partition_nr} partitions on ${DISK}
sfdisk $DISK <<EOF || exit 1
label: gpt
unit: sectors
sector-size: 512

${sfdisk_format}
EOF

notify resize the root partition on ${DISK} to fill available space
echo ", +" | sfdisk -N ${root_partition_nr} $DISK || exit 1

sfdisk -d $DISK > partitions_created.txt || exit 1
fi

function wait_for_file {
    filename="$1"
    while [ ! -e $filename ]
    do
        echo waiting for $filename to be created
        sleep 3
    done
}

wait_for_file ${root_partition}
if [ "${ENABLE_SWAP}" == "partition" ]; then
    wait_for_file ${swap_partition}
fi

if [ ! -f $KEYFILE ]; then
    # TODO do we want to store this file in the installed system?
    notify generate key file for luks
    dd if=/dev/random of=${KEYFILE} bs=512 count=1 || exit 1
    notify "remove any old luks on ${root_partition} (root)"
    cryptsetup erase --batch-mode ${root_partition}
    wait_for_file ${root_partition}
    wipefs -a ${root_partition} || exit 1
    wait_for_file ${root_partition}
    if [ -e ${swap_partition} ]; then
        notify "remove any old luks on ${swap_partition} (swap)"
        cryptsetup erase --batch-mode ${swap_partition}
        wait_for_file ${swap_partition}
        wipefs -a ${swap_partition} || exit 1
        wait_for_file ${swap_partition}
    fi
fi

function setup_luks {
  cryptsetup isLuks "$1"
  retVal=$?
  if [ $retVal -ne 0 ]; then
      notify setup luks on "$1"
      cryptsetup luksFormat "$1" --type luks2 --batch-mode --key-file $KEYFILE || exit 1
      notify setup luks password on "$1"
      echo -n "${LUKS_PASSWORD}" > /tmp/passwd
      cryptsetup --key-file=luks.key luksAddKey "$1" /tmp/passwd || exit 1
      rm -f /tmp/passwd
  else
      echo luks already set up on "$1"
  fi
  cryptsetup luksUUID "$1" > luks.uuid || exit 1
}

setup_luks ${root_partition}
root_uuid=$(cat luks.uuid)

if [ ! -e ${root_device} ]; then
    notify open luks on root
    cryptsetup luksOpen ${root_partition} ${luks_device} --key-file $KEYFILE || exit 1
fi

if [ -e /dev/disk/by-partlabel/BaseImage ]; then
    if [ ! -f base_image_copied.txt ]; then
        notify copy base image to ${root_device}
        wipefs -a ${root_device} || exit 1
        dd if=/dev/disk/by-partlabel/BaseImage of=${root_device} bs=256M oflag=dsync status=progress || exit 1
        notify check the filesystem on root
        btrfs check ${root_device} || exit 1
        notify change the filesystem uuid on root
        btrfstune -U ${btrfs_uuid} -f ${root_device} || exit 1  # change the uuid
        touch base_image_copied.txt
    fi
else
    if [ ! -f btrfs_created.txt ]; then
        notify create root filesystem on ${root_device}
        wipefs -a ${root_device} || exit 1
        mkfs.btrfs -U ${btrfs_uuid} ${root_device} | tee btrfs_created.txt || exit 1
    fi
fi

if [ ! -f vfat_created.txt ]; then
    notify create esp filesystem on ${efi_partition}
    wipefs -a ${efi_partition} || exit 1
    mkfs.vfat ${efi_partition} || exit 1
    touch vfat_created.txt
fi

if [ "${ENABLE_SWAP}" == "partition" ]; then
    setup_luks ${swap_partition} || exit 1
    swap_uuid=$(cat luks.uuid)

    kernel_params="${kernel_params} rd.luks.name=${swap_uuid}=${swap_device} resume=/dev/mapper/${swap_device}"

    if [ ! -e /dev/mapper/${swap_device} ]; then
        notify open luks swap
        cryptsetup luksOpen ${swap_partition} ${swap_device} --key-file $KEYFILE || exit 1
    fi

    notify making swap
    mkswap /dev/mapper/${swap_device} || exit 1
    swapon /dev/mapper/${swap_device} || exit 1
fi  # swap as partition

if mountpoint -q "${top_level_mount}" ; then
    echo top-level subvolume already mounted on ${top_level_mount}
else
    notify mount top-level subvolume on ${top_level_mount} and resize to fit the whole partition
    mkdir -p ${top_level_mount} || exit 1
    mount ${root_device} ${top_level_mount} -o rw,${FSFLAGS},subvolid=5,skip_balance || exit 1
    btrfs filesystem resize max ${top_level_mount} || exit 1
fi

if [ ! -e ${top_level_mount}/@ ]; then
    notify create @ and @home subvolumes on ${top_level_mount}
    btrfs subvolume create ${top_level_mount}/@ || exit 1
    btrfs subvolume create ${top_level_mount}/@home || exit 1
    if [ "${ENABLE_SWAP}" == "file" ]; then
        notify create @swap subvolume for swap file on ${top_level_mount}
        btrfs subvolume create ${top_level_mount}/@swap || exit 1
        chmod 700 ${top_level_mount}/@swap || exit 1
    fi
fi

if mountpoint -q "${target}" ; then
    echo root subvolume already mounted on ${target}
else
    notify mount root and home subvolume on ${target}
    mkdir -p ${target} || exit 1
    mount ${root_device} ${target} -o ${FSFLAGS},subvol=@ || exit 1
    mkdir -p ${target}/home || exit 1
    mount ${root_device} ${target}/home -o ${FSFLAGS},subvol=@home || exit 1
    if [ "${ENABLE_SWAP}" == "file" ]; then
        notify mount swap subvolume on ${target}
        mkdir -p ${target}/swap || exit 1
        mount ${root_device} ${target}/swap -o noatime,subvol=@swap || exit 1
    fi
fi

if [ "${ENABLE_SWAP}" == "file" ]; then
    notify make swap file at ${target}/swap/swapfile
    btrfs filesystem mkswapfile --size ${SWAP_SIZE}G ${target}/swap/swapfile || exit 1
    swapon ${target}/swap/swapfile || exit 1
    swapfile_offset=$(btrfs inspect-internal map-swapfile -r ${target}//swap/swapfile)
    kernel_params="${kernel_params} rd.luks.name=${root_uuid}=${luks_device} resume=${root_device} resume_offset=${swapfile_offset}"
fi

if [ ! -f ${target}/etc/debian_version ]; then
    notify install debian on ${target}
    debootstrap ${DEBIAN_VERSION} ${target} http://deb.debian.org/debian || exit 1
fi

if mountpoint -q "${target}/proc" ; then
    echo bind mounts already set up on ${target}
else
    notify bind mount dev, proc, sys, run on ${target}
    mount -t proc none ${target}/proc || exit 1
    mount --make-rslave --rbind /sys ${target}/sys || exit 1
    mount --make-rslave --rbind /dev ${target}/dev || exit 1
    mount --make-rslave --rbind /run ${target}/run || exit 1
    mount --bind /etc/resolv.conf ${target}/etc/resolv.conf || exit 1
fi

if mountpoint -q "${efi_partition}" ; then
    echo efi esp partition ${efi_partition} already mounted on ${target}/boot/efi
else
    notify mount efi esp partition ${efi_partition} on ${target}/boot/efi
    mkdir -p ${target}/boot/efi || exit 1
    mount ${efi_partition} ${target}/boot/efi -o umask=077 || exit 1
fi

if [ ! -z "${HOSTNAME}" ]; then
    notify setup hostname
    echo "$HOSTNAME" > ${target}/etc/hostname || exit 1
fi

notify setup timezone
echo "${TIMEZONE}" > ${target}/etc/timezone || exit 1
rm -f ${target}/etc/localtime
(cd ${target} && ln -s /usr/share/zoneinfo/${TIMEZONE} etc/localtime)

notify setup fstab
mkdir -p ${target}/root/btrfs1 || exit 1
cat <<EOF > ${target}/etc/fstab || exit 1
UUID=${btrfs_uuid} / btrfs defaults,subvol=@,${FSFLAGS} 0 1
UUID=${btrfs_uuid} /home btrfs defaults,subvol=@home,${FSFLAGS} 0 1
UUID=${btrfs_uuid} /root/btrfs1 btrfs defaults,subvolid=5,${FSFLAGS} 0 1
PARTUUID=${efi_part_uuid} /boot/efi vfat defaults,umask=077 0 2
EOF

if [ "${ENABLE_SWAP}" == "partition" ]; then
cat <<EOF >> ${target}/etc/fstab || exit 1
/dev/mapper/${swap_device} swap swap defaults 0 0
EOF
elif [ "${ENABLE_SWAP}" == "file" ]; then
cat <<EOF >> ${target}/etc/fstab || exit 1
UUID=${btrfs_uuid} /swap btrfs defaults,subvol=@swap,noatime 0 0
/swap/swapfile none swap defaults 0 0
EOF
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

if [ "$SHARE_APT_ARCHIVE" = true ] ; then
    mkdir -p ${target}/var/cache/apt/archives || exit 1
    if mountpoint -q "${target}/var/cache/apt/archives" ; then
        echo apt cache directory already bind mounted on target
    else
        notify bind mounting apt cache directory to target
        mount /var/cache/apt/archives ${target}/var/cache/apt/archives -o bind || exit 1
    fi
fi

notify enable 32bit
chroot ${target}/ dpkg --add-architecture i386

if grep -qs 'root:\$' ${target}/etc/shadow ; then
    echo root password already set up
elif [ ! -z "${ROOT_PASSWORD}" ]; then
    notify set up root password
    echo "root:${ROOT_PASSWORD}" > ${target}/tmp/passwd || exit 1
    chroot ${target}/ bash -c "chpasswd < /tmp/passwd" || exit 1
    rm -f ${target}/tmp/passwd
fi

if [ ! -z "${USERNAME}" ]; then
    if grep -qs "^${USERNAME}:" ${target}/etc/shadow ; then
        echo ${USERNAME} user already set up
    else
        notify set up ${USERNAME} user
        chroot ${target}/ bash -c "adduser ${USERNAME} --disabled-password --gecos "${USER_FULL_NAME}"" || exit 1
        chroot ${target}/ bash -c "adduser ${USERNAME} sudo" || exit 1
        if [ ! -z "${USER_PASSWORD}" ]; then
            echo "${USERNAME}:${USER_PASSWORD}" > ${target}/tmp/passwd || exit 1
            chroot ${target}/ bash -c "chpasswd < /tmp/passwd" || exit 1
            rm -f ${target}/tmp/passwd
        fi
    fi
fi

if [ ! -z "${NVIDIA_PACKAGE}" ]; then
  # TODO the debian page says to do this instead:
  # echo "options nvidia-drm modeset=1" >> /etc/modprobe.d/nvidia-options.conf
  kernel_params="${kernel_params} nvidia-drm.modeset=1"
fi

notify configuring dracut and kernel command line
mkdir -p ${target}/etc/dracut.conf.d
cat <<EOF > ${target}/etc/dracut.conf.d/90-luks.conf || exit 1
add_dracutmodules+=" systemd crypt btrfs tpm2-tss "
kernel_cmdline="${kernel_params}"
EOF
cat <<EOF > ${target}/etc/kernel/cmdline || exit 1
${kernel_params}
EOF

if [ "${ENABLE_SWAP}" == "partition" ]; then
cat <<EOF > ${target}/etc/dracut.conf.d/90-hibernate.conf || exit 1
add_dracutmodules+=" resume "
EOF
fi

notify install required packages on ${target}
if [ -z "${NON_INTERACTIVE}" ]; then
    chroot ${target}/ apt-get update -y || exit 1
fi
cat <<EOF > ${target}/tmp/run1.sh || exit 1
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get install -y locales  tasksel network-manager sudo || exit 1
apt-get install -y -t ${BACKPORTS_VERSION} systemd systemd-boot dracut btrfs-progs cryptsetup tpm2-tools tpm-udev || exit 1
bootctl install || exit 1
EOF
chroot ${target}/ sh /tmp/run1.sh || exit 1

if [ "${ENABLE_TPM}" == "true" ]; then
  notify checking for tpm
  cp ${KEYFILE} ${target}/ || exit 1
  chmod 600 ${target}/${KEYFILE} || exit 1
  cat <<EOF > ${target}/tmp/run4.sh || exit 1
systemd-cryptenroll --tpm2-device=list > /tmp/tpm-list.txt || exit 1
if grep -qs "/dev/tpm" /tmp/tpm-list.txt ; then
      echo tpm available, enrolling
      echo "... on root"
      systemd-cryptenroll --unlock-key-file=/${KEYFILE} --tpm2-device=auto ${root_partition} --tpm2-pcrs=${TPM_PCRS} || exit 1
      if [ -e "${swap_partition}" ]; then
          echo "... on swap"
          systemd-cryptenroll --unlock-key-file=/${KEYFILE} --tpm2-device=auto ${swap_partition} --tpm2-pcrs=${TPM_PCRS} || exit 1
      fi
else
    echo tpm not available
fi
EOF
  chroot ${target}/ bash /tmp/run4.sh || exit 1
  rm ${target}/${KEYFILE} || exit 1
else
  notify tpm disabled
fi

notify install kernel and firmware on ${target}
cat <<EOF > ${target}/tmp/packages.txt || exit 1
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
cat <<EOF > ${target}/tmp/packages_backports.txt || exit 1
linux-image-amd64
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
cat <<EOF > ${target}/tmp/run2.sh || exit 1
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
xargs apt-get install -y < /tmp/packages.txt || exit 1
xargs apt-get install -t ${BACKPORTS_VERSION} -y < /tmp/packages_backports.txt || exit 1
systemctl disable systemd-networkd.service  # seems to fight with NetworkManager
systemctl disable systemd-networkd.socket
systemctl disable systemd-networkd-wait-online.service
EOF
chroot ${target}/ bash /tmp/run2.sh || exit 1

if [ "$ENABLE_POPCON" = true ] ; then
  notify enabling popularity-contest
  cat <<EOF > ${target}/tmp/run3.sh || exit 1
#!/bin/bash
echo "popularity-contest      popularity-contest/participate  boolean true" | debconf-set-selections
apt-get install -y popularity-contest
EOF
  chroot ${target}/ bash /tmp/run3.sh || exit 1
fi

if [ ! -z "${SSH_PUBLIC_KEY}" ]; then
    notify adding ssh public key to user and root authorized_keys file
    mkdir -p ${target}/root/.ssh || exit 1
    chmod 700 ${target}/root/.ssh || exit 1
    echo "${SSH_PUBLIC_KEY}" > ${target}/root/.ssh/authorized_keys || exit 1
    chmod 600 ${target}/root/.ssh/authorized_keys || exit 1

    if [ ! -z "${USERNAME}" ]; then
        mkdir -p ${target}/home/${USERNAME}/.ssh || exit 1
        chmod 700 ${target}/home/${USERNAME}/.ssh || exit 1
        echo "${SSH_PUBLIC_KEY}" > ${target}/home/${USERNAME}/.ssh/authorized_keys || exit 1
        chmod 600 ${target}/home/${USERNAME}/.ssh/authorized_keys || exit 1
        chroot ${target}/ chown -R ${USERNAME} /home/${USERNAME}/.ssh || exit 1
    fi

    notify installing openssh-server
    chroot ${target}/ apt-get install -y openssh-server || exit 1
fi

if [ -z "${NON_INTERACTIVE}" ]; then
    notify running tasksel
    chroot ${target}/ tasksel
fi

if [ ! -z "${NVIDIA_PACKAGE}" ]; then
  notify installing ${NVIDIA_PACKAGE}
  # XXX dracut-install: ERROR: installing nvidia-blacklists-nouveau.conf nvidia.conf
  cat <<EOF > ${target}/etc/dracut.conf.d/10-nvidia.conf || exit 1
install_items+=" /etc/modprobe.d/nvidia-blacklists-nouveau.conf /etc/modprobe.d/nvidia.conf /etc/modprobe.d/nvidia-options.conf "
EOF
  chroot ${target}/ apt-get install -t ${BACKPORTS_VERSION} -y "${NVIDIA_PACKAGE}" nvidia-driver-libs:i386 linux-headers-amd64 || exit 1
fi

notify cleaning up
chroot ${target}/ apt-get autoremove -y

notify umounting all filesystems
if [ "${ENABLE_SWAP}" == "partition" ]; then
    swapoff /dev/mapper/${swap_device}
elif [ "${ENABLE_SWAP}" == "file" ]; then
    swapoff ${target}/swap/swapfile
fi
umount -R ${target}
umount -R ${top_level_mount}

notify closing luks
cryptsetup luksClose ${luks_device}
if [ "${ENABLE_SWAP}" == "partition" ]; then
  cryptsetup luksClose /dev/mapper/${swap_device}
fi

notify INSTALLATION FINISHED

if [ ! -z "${AFTER_INSTALLED_CMD}" ]; then
  notify running ${AFTER_INSTALLED_CMD}
  sh -c "${AFTER_INSTALLED_CMD}" || exit 1
fi
