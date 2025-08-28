#!/bin/bash

if [ -z "${NON_INTERACTIVE}" ]; then
# edit this:
DISK=/dev/vda
USERNAME=user
USER_FULL_NAME="Debian User"
USER_PASSWORD=hunter2
ROOT_PASSWORD=changeme
DISABLE_LUKS=false
LUKS_PASSWORD=luke
ENABLE_MOK_SIGNED_UKI=true
MOK_ENROLL_PASSWORD=mokka
ENABLE_TPM=true
HOSTNAME=debian13
SWAP_SIZE=2
NVIDIA_PACKAGE=
ENABLE_POPCON=false
LOCALE=C.UTF-8
TIMEZONE=Europe/Bratislava
KEYMAP=us
SSH_PUBLIC_KEY=
AFTER_INSTALLED_CMD=

echo -e "\033[32m Opinionated Debian Installer \033[0m"
echo Press Enter on all green prompts
fi

function notify () {
    if [ -z "${NON_INTERACTIVE}" ]; then
      echo -en "\033[32m$*\033[0m> "
      read -r
    else
      echo "$*"
    fi
}

DEBIAN_VERSION=trixie
BACKPORTS_VERSION=${DEBIAN_VERSION}  # TODO append "-backports" when available
TPM_PCRS="platform-config+secure-boot-policy+shim-policy"
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

if [ "${DISABLE_LUKS}" != "true" ]; then
  if [ -z "${LUKS_PASSWORD}" ]; then
      echo "LUKS_PASSWORD variable is missing" >&2
      exit 3
  fi
fi

if [ -z "${NON_INTERACTIVE}" ]; then
    notify install required packages
    apt-get update -y  || exit 1
    apt-get install -y cryptsetup debootstrap uuid-runtime btrfs-progs dosfstools pv systemd-repart mokutil || exit 1
fi

KEYFILE=luks.key
dd if=/dev/random of=${KEYFILE} bs=512 count=1 || exit 1
chmod 600 ${KEYFILE}

if [ ! -f efi-part.uuid ]; then
    uuidgen > efi-part.uuid || exit 1
fi
if [ ! -f main-part.uuid ]; then
    uuidgen > main-part.uuid || exit 1
fi

efi_part_uuid=$(cat efi-part.uuid)
main_part_uuid=$(cat main-part.uuid)
efi_partition=/dev/disk/by-partuuid/${efi_part_uuid}
main_partition=/dev/disk/by-partuuid/${main_part_uuid}
top_level_mount=/mnt/top_level_mount
target=/target
kernel_params="rw quiet rootfstype=btrfs rootflags=${FSFLAGS},subvol=@ rd.auto=1 splash"
if [ "${DISABLE_LUKS}" != "true" ]; then
  kernel_params="rd.luks.options=tpm2-device=auto ${kernel_params}"
  luks_device_name=root
  root_device=/dev/mapper/${luks_device_name}
else
  root_device=${main_partition}
fi

notify setting up partitions on ${DISK}
rm -rf repart.d
mkdir -p repart.d
cat <<EOF > repart.d/01_efi.conf || exit 1
[Partition]
Type=esp
UUID=${efi_part_uuid}
SizeMinBytes=1024M
SizeMaxBytes=1024M
Format=vfat
EOF

cat <<EOF > repart.d/02_root.conf || exit 1
[Partition]
Type=root
Label=Debian ${DEBIAN_VERSION}
UUID=${main_part_uuid}
Format=btrfs
MakeDirectories=/@home
Subvolumes=/@home
EOF

if [ "${DISABLE_LUKS}" == "true" ]; then
  echo "Encrypt=off" >> repart.d/02_root.conf
elif [ "${ENABLE_TPM}" == "true" ]; then
  echo "Encrypt=key-file+tpm2" >> repart.d/02_root.conf
else
  echo "Encrypt=key-file" >> repart.d/02_root.conf
fi

if [ ! -f disk_wiped.txt ]; then
  wipefs --all ${DISK} || exit 1
  touch disk_wiped.txt
fi

# sector-size: see https://github.com/systemd/systemd/issues/37801
# remove with systemd 258
# --tpm2-pcrlock= XXX: wtf is pcrlock?
systemd-repart --sector-size=512 --empty=allow --no-pager --definitions=repart.d --dry-run=no ${DISK} \
  --key-file=${KEYFILE} --tpm2-device=auto --tpm2-pcrs=${TPM_PCRS} --tpm2-pcrlock= || exit 1

function wait_for_file {
    filename="$1"
    while [ ! -e $filename ]
    do
        echo waiting for $filename to be created
        sleep 3
    done
}

wait_for_file ${main_partition}

if [ "${DISABLE_LUKS}" != "true" ]; then
  notify setup luks password on ${main_partition}
  echo -n "${LUKS_PASSWORD}" > /tmp/passwd
  cryptsetup --key-file=luks.key luksAddKey "${main_partition}" /tmp/passwd || exit 1
  rm -f /tmp/passwd
  cryptsetup luksUUID "${main_partition}" > luks.uuid || exit 1
  root_uuid=$(cat luks.uuid)
  if [ ! -e ${root_device} ]; then
      notify open luks on root
      cryptsetup luksOpen ${main_partition} ${luks_device_name} --key-file $KEYFILE || exit 1
  fi
fi

btrfs_uuid=$(lsblk -no UUID ${root_device})

if mountpoint -q "${top_level_mount}" ; then
    echo top-level subvolume already mounted on ${top_level_mount}
else
    notify mount top-level subvolume on ${top_level_mount}
    mkdir -p ${top_level_mount} || exit 1
    mount ${root_device} ${top_level_mount} -o rw,${FSFLAGS},subvolid=5,skip_balance || exit 1
fi

if [ -e /root/btrfs1/opinionated_installer_bootstrap ]; then
    if [ ! -f base_image_copied.txt ]; then
        notify send installer bootrstrap data - see nr of bytes transferred
        btrfs send --compressed-data /root/btrfs1/opinionated_installer_bootstrap | pv -nb | btrfs receive ${top_level_mount} || exit 1
        (cd ${top_level_mount}; btrfs subvolume snapshot opinionated_installer_bootstrap @; btrfs subvolume delete opinionated_installer_bootstrap)
        touch base_image_copied.txt
    fi
else
  notify create @ subvolume on ${top_level_mount}
  btrfs subvolume create ${top_level_mount}/@ || exit 1
fi

if [ ! -e ${top_level_mount}/@swap ]; then
    if [ ${SWAP_SIZE} -gt 0 ]; then
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
    if [ ${SWAP_SIZE} -gt 0 ]; then
        notify mount swap subvolume on ${target}
        mkdir -p ${target}/swap || exit 1
        mount ${root_device} ${target}/swap -o noatime,subvol=@swap || exit 1
    fi
fi

if [ ${SWAP_SIZE} -gt 0 ]; then
    if [ ! -e ${target}/swap/swapfile ]; then
      notify make swap file at ${target}/swap/swapfile
      btrfs filesystem mkswapfile --size ${SWAP_SIZE}G ${target}/swap/swapfile || exit 1
    fi
    if ! grep -qs "${target}/swap/swapfile" /proc/swaps ; then
      notify enable swap file ${target}/swap/swapfile
      swapon ${target}/swap/swapfile || exit 1
    fi
    swapfile_offset=$(btrfs inspect-internal map-swapfile -r ${target}/swap/swapfile)
    kernel_params="${kernel_params} resume=${root_device} resume_offset=${swapfile_offset}"
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

if mountpoint -q "${target}/boot/efi" ; then
    echo efi esp partition ${efi_partition} already mounted on ${target}/boot/efi
else
    notify mount esp partition ${efi_partition} on ${target}/boot/efi
    mkdir -p ${target}/boot/efi || exit 1
    mount ${efi_partition} ${target}/boot/efi -o umask=077 || exit 1
fi

notify setup locale, keymap, timezone, hostname, root password, kernel command line
systemd-firstboot --root=${target} --locale=${LOCALE} --keymap=${KEYMAP} --timezone=${TIMEZONE} \
  --hostname=${HOSTNAME} --root-password=${ROOT_PASSWORD} --kernel-command-line="${kernel_params}" \
  --force || exit 1
echo "127.0.1.1 ${HOSTNAME}" >> ${target}/etc/hosts || exit 1
echo "locales locales/locales_to_be_generated multiselect     en_US.UTF-8 UTF-8" | chroot ${target}/ debconf-set-selections || exit 1

notify setup fstab
mkdir -p ${target}/root/btrfs1 || exit 1
cat <<EOF > ${target}/etc/fstab || exit 1
UUID=${btrfs_uuid} / btrfs defaults,subvol=@,${FSFLAGS} 0 1
UUID=${btrfs_uuid} /home btrfs defaults,subvol=@home,${FSFLAGS} 0 1
UUID=${btrfs_uuid} /root/btrfs1 btrfs defaults,subvolid=5,${FSFLAGS} 0 1
PARTUUID=${efi_part_uuid} /boot/efi vfat defaults,umask=077 0 2
EOF

if [ ${SWAP_SIZE} -gt 0 ]; then
cat <<EOF >> ${target}/etc/fstab || exit 1
UUID=${btrfs_uuid} /swap btrfs defaults,subvol=@swap,noatime,${FSFLAGS} 0 0
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
cat <<EOF > ${target}/etc/dracut.conf.d/89-btrfs.conf || exit 1
add_dracutmodules+=" systemd btrfs "
EOF
if [ "${DISABLE_LUKS}" != "true" ]; then
cat <<EOF > ${target}/etc/dracut.conf.d/90-luks.conf || exit 1
add_dracutmodules+=" crypt tpm2-tss "
EOF
fi

if [ "${ENABLE_MOK_SIGNED_UKI}" == "true" ]; then
cat <<EOF > ${target}/etc/kernel/install.conf || exit 1
layout=uki
uki_generator=ukify
initrd_generator=dracut
EOF
cat <<EOF > ${target}/etc/kernel/uki.conf || exit 1
[UKI]
Cmdline=@/etc/kernel/cmdline
SecureBootCertificate=/etc/kernel/mok.cert.pem
SecureBootPrivateKey=/etc/kernel/mok.priv.pem
EOF
fi # ENABLE_MOK_SIGNED_UKI

notify install required packages on ${target}
if [ -z "${NON_INTERACTIVE}" ]; then
    chroot ${target}/ apt-get update -y || exit 1
fi
cat <<EOF > ${target}/tmp/run1.sh || exit 1
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get install -y locales tasksel network-manager sudo || exit 1
apt-get install -y -t ${BACKPORTS_VERSION} systemd shim-signed shim-helpers-amd64-signed systemd-boot systemd-boot-efi-amd64-signed systemd-ukify sbsigntool dracut btrfs-progs cryptsetup tpm2-tools tpm-udev || exit 1

# see https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1095646
ln -s /dev/null /etc/kernel/install.d/50-dracut.install
# XXX this didn't seem to work
EOF
chroot ${target}/ sh /tmp/run1.sh || exit 1

if [ "${ENABLE_MOK_SIGNED_UKI}" == "true" ]; then
  mokutil "--generate-hash=${MOK_ENROLL_PASSWORD}" > ${target}/tmp/mok.key
cat <<EOF > ${target}/tmp/run1.sh || exit 1
#!/bin/bash
# generate cert and key in pem format in /etc/kernel/mok.*.pem
ukify genkey --config /etc/kernel/uki.conf || exit 1

# convert to der format
openssl x509 -in /etc/kernel/mok.cert.pem -out /etc/kernel/mok.cert.der -outform der || exit 1
openssl rsa -in /etc/kernel/mok.priv.pem -out /etc/kernel/mok.priv.der -outform der || exit 1

# symlink for DKMS
mkdir -p /var/lib/dkms || exit 1
ln -s /etc/kernel/mok.priv.pem /var/lib/dkms/mok.key || exit 1
ln -s /etc/kernel/mok.cert.der /var/lib/dkms/mok.pub || exit 1

# symlink in "ubuntu" de-facto standard directory
mkdir -p /var/lib/shim-signed/mok || exit 1
ln -s /etc/kernel/mok.cert.der /var/lib/shim-signed/mok/MOK-Kernel.der || exit 1
ln -s /etc/kernel/mok.cert.pem /var/lib/shim-signed/mok/MOK-Kernel.pem || exit 1
ln -s /etc/kernel/mok.priv.der /var/lib/shim-signed/mok/MOK-Kernel.priv || exit 1

# XXX: Failed to get Subject Key ID
mokutil --import /etc/kernel/mok.cert.der --hash-file /tmp/mok.key
EOF
chroot ${target}/ sh /tmp/run1.sh || exit 1
rm -f ${target}/tmp/mok.key
fi # ENABLE_MOK_SIGNED_UKI

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
dracut
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
initramfs-tools-
initramfs-tools-core-
initramfs-tools-bin-
busybox-
klibc-utils-
libklibc-
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
    # XXX this does not open for some reason
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
if [ ${SWAP_SIZE} -gt 0 ]; then
    swapoff ${target}/swap/swapfile
fi
umount -R ${target}
umount -R ${top_level_mount}

if [ "${DISABLE_LUKS}" != "true" ]; then
  notify closing luks
  cryptsetup luksClose ${luks_device_name}
fi

notify INSTALLATION FINISHED

if [ ! -z "${AFTER_INSTALLED_CMD}" ]; then
  notify running ${AFTER_INSTALLED_CMD}
  sh -c "${AFTER_INSTALLED_CMD}" || exit 1
fi
