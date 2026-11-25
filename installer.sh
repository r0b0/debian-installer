#!/bin/bash

# Opinionated Debian Installer
# Copyright (C) 2022-2025 Robert T.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

set -eo pipefail

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
ENABLE_FLATHUB=true
LOCALE=C.UTF-8
TIMEZONE=Europe/Bratislava
SSH_PUBLIC_KEY=
AFTER_INSTALLED_CMD=

echo -e "\033[32m Opinionated Debian Installer \033[0m"
echo Press Enter at green prompts
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
BACKPORTS_VERSION=${DEBIAN_VERSION}-backports
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
    apt update -y 
    apt install -y cryptsetup debootstrap uuid-runtime btrfs-progs dosfstools pv systemd-repart mokutil tpm2-tools
fi

KEYFILE=luks.key
if [ ! -f ${KEYFILE} ]; then
  dd if=/dev/random of=${KEYFILE} bs=512 count=1
  chmod 600 ${KEYFILE}
fi
if [ ! -f efi-part.uuid ]; then
    uuidgen > efi-part.uuid
fi
if [ ! -f main-part.uuid ]; then
    uuidgen > main-part.uuid
fi

efi_part_uuid=$(cat efi-part.uuid)
main_part_uuid=$(cat main-part.uuid)
efi_partition=/dev/disk/by-partuuid/${efi_part_uuid}
main_partition=/dev/disk/by-partuuid/${main_part_uuid}
top_level_mount=/mnt/top_level_mount
target=/target
kernel_params="rw quiet rootfstype=btrfs rootflags=${FSFLAGS},subvol=@ rd.auto=1 splash"
if [ "${DISABLE_LUKS}" != "true" ]; then
  luks_device_name=root
  root_device=/dev/mapper/${luks_device_name}
else
  root_device=${main_partition}
fi

notify setting up partitions on ${DISK}
rm -rf repart.d
mkdir -p repart.d
cat <<EOF > repart.d/01_efi.conf
[Partition]
Type=esp
UUID=${efi_part_uuid}
SizeMinBytes=1024M
SizeMaxBytes=1024M
Format=vfat
EOF

cat <<EOF > repart.d/02_root.conf
[Partition]
Type=root
Label=Debian
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
  wipefs --all ${DISK}
  touch disk_wiped.txt
fi

# sector-size: see https://github.com/systemd/systemd/issues/37801
# remove with systemd 258
# tpm2-pcrs= If we are enrolling MOK, PCRs would reset anyway. If SB is disabled, we want to allow enabling it.
# tpm2-pcrlock= XXX: wtf is pcrlock?
systemd-repart --sector-size=512 --empty=allow --no-pager --definitions=repart.d --dry-run=no ${DISK} \
  --key-file=${KEYFILE} --tpm2-device=auto --tpm2-pcrs= --tpm2-pcrlock=

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
  cryptsetup --key-file=luks.key luksAddKey "${main_partition}" /tmp/passwd
  rm -f /tmp/passwd
  cryptsetup luksUUID "${main_partition}" > luks.uuid
  root_uuid=$(cat luks.uuid)
  # Add LUKS parameters to kernel cmdline
  kernel_params="rd.luks.uuid=${root_uuid} rd.luks.name=${root_uuid}=${luks_device_name} rd.luks.options=tpm2-device=auto root=${root_device} ${kernel_params}"
  if [ ! -e ${root_device} ]; then
      notify open luks on root
      cryptsetup luksOpen ${main_partition} ${luks_device_name} --key-file $KEYFILE
  fi
else
  # Without LUKS, just set the root device
  kernel_params="root=${root_device} ${kernel_params}"
fi

btrfs_uuid=$(lsblk -no UUID ${root_device})

if mountpoint -q "${top_level_mount}" ; then
    echo top-level subvolume already mounted on ${top_level_mount}
else
    notify mount top-level subvolume on ${top_level_mount}
    mkdir -p ${top_level_mount}
    mount ${root_device} ${top_level_mount} -o rw,${FSFLAGS},subvolid=5,skip_balance
fi

if [ -e /root/btrfs1/opinionated_installer_bootstrap ]; then
    if [ ! -f base_image_copied.txt ]; then
        notify send installer bootrstrap data - see nr of bytes transferred
        btrfs send --compressed-data /root/btrfs1/opinionated_installer_bootstrap | pv -nb | btrfs receive ${top_level_mount}
        (cd ${top_level_mount}; btrfs subvolume snapshot opinionated_installer_bootstrap @; btrfs subvolume delete opinionated_installer_bootstrap)
        touch base_image_copied.txt
    fi
elif [ ! -e ${top_level_mount}/@ ]; then
  notify create @ subvolume on ${top_level_mount}
  btrfs subvolume create ${top_level_mount}/@
else
  notify the @ subvolume already created
fi

if [ ! -e ${top_level_mount}/@swap ]; then
    if [ ${SWAP_SIZE} -gt 0 ]; then
        notify create @swap subvolume for swap file on ${top_level_mount}
        btrfs subvolume create ${top_level_mount}/@swap
        chmod 700 ${top_level_mount}/@swap
    fi
fi

if mountpoint -q "${target}" ; then
    echo root subvolume already mounted on ${target}
else
    notify mount root and home subvolume on ${target}
    mkdir -p ${target}
    mount ${root_device} ${target} -o ${FSFLAGS},subvol=@
    mkdir -p ${target}/home
    mount ${root_device} ${target}/home -o ${FSFLAGS},subvol=@home
    if [ ${SWAP_SIZE} -gt 0 ]; then
        notify mount swap subvolume on ${target}
        mkdir -p ${target}/swap
        mount ${root_device} ${target}/swap -o noatime,subvol=@swap
    fi
fi

if [ ${SWAP_SIZE} -gt 0 ]; then
    if [ ! -e ${target}/swap/swapfile ]; then
      notify make swap file at ${target}/swap/swapfile
      btrfs filesystem mkswapfile --size ${SWAP_SIZE}G ${target}/swap/swapfile
    fi
    if ! grep -qs "${target}/swap/swapfile" /proc/swaps ; then
      notify enable swap file ${target}/swap/swapfile
      swapon ${target}/swap/swapfile
    fi
    swapfile_offset=$(btrfs inspect-internal map-swapfile -r ${target}/swap/swapfile)
    kernel_params="${kernel_params} resume=${root_device} resume_offset=${swapfile_offset}"
fi

if [ ! -f ${target}/etc/debian_version ]; then
    notify install debian on ${target}
    debootstrap ${DEBIAN_VERSION} ${target} http://deb.debian.org/debian
fi

if mountpoint -q "${target}/proc" ; then
    echo bind mounts already set up on ${target}
else
    notify bind mount dev, proc, sys, run on ${target}
    mount -t proc none ${target}/proc
    mount --make-rslave --rbind /sys ${target}/sys
    mount --make-rslave --rbind /dev ${target}/dev
    mount --make-rslave --rbind /run ${target}/run
    mount --bind /etc/resolv.conf ${target}/etc/resolv.conf
fi

if mountpoint -q "${target}/boot/efi" ; then
    echo efi esp partition ${efi_partition} already mounted on ${target}/boot/efi
else
    notify mount esp partition ${efi_partition} on ${target}/boot/efi
    mkdir -p ${target}/boot/efi
    mount ${efi_partition} ${target}/boot/efi -o umask=077
fi

notify setup locale, timezone, hostname, root password, kernel command line
systemd-firstboot --root=${target} --locale=${LOCALE} --keymap=us --timezone=${TIMEZONE} \
  --hostname=${HOSTNAME} --root-password=${ROOT_PASSWORD} --kernel-command-line="${kernel_params}" \
  --force
echo "127.0.1.1 ${HOSTNAME}" >> ${target}/etc/hosts
echo "locales locales/locales_to_be_generated multiselect     en_US.UTF-8 UTF-8" | chroot ${target}/ debconf-set-selections

notify setup fstab
mkdir -p ${target}/root/btrfs1
cat <<EOF > ${target}/etc/fstab
UUID=${btrfs_uuid} / btrfs defaults,subvol=@,${FSFLAGS} 0 1
UUID=${btrfs_uuid} /home btrfs defaults,subvol=@home,${FSFLAGS} 0 1
UUID=${btrfs_uuid} /root/btrfs1 btrfs defaults,subvolid=5,${FSFLAGS} 0 1
PARTUUID=${efi_part_uuid} /boot/efi vfat defaults,umask=077 0 2
EOF

if [ ${SWAP_SIZE} -gt 0 ]; then
cat <<EOF >> ${target}/etc/fstab
UUID=${btrfs_uuid} /swap btrfs defaults,subvol=@swap,noatime,${FSFLAGS} 0 0
/swap/swapfile none swap defaults 0 0
EOF
fi

notify setup sources list
rm -f ${target}/etc/apt/sources.list
mkdir -p ${target}/etc/apt/sources.list.d
cat <<EOF > ${target}/etc/apt/sources.list.d/debian.sources
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

cat <<EOF > ${target}/etc/apt/sources.list.d/debian-backports.sources
Types: deb
URIs: http://deb.debian.org/debian/
Suites: ${DEBIAN_VERSION}-backports
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF

if [ "$SHARE_APT_ARCHIVE" = true ] ; then
    mkdir -p ${target}/var/cache/apt/archives
    if mountpoint -q "${target}/var/cache/apt/archives" ; then
        echo apt cache directory already bind mounted on target
    else
        notify bind mounting apt cache directory to target
        mount /var/cache/apt/archives ${target}/var/cache/apt/archives -o bind
    fi
fi

notify enable 32bit
chroot ${target}/ dpkg --add-architecture i386

if [ ! -z "${USERNAME}" ]; then
    if grep -qs "^${USERNAME}:" ${target}/etc/shadow ; then
        echo ${USERNAME} user already set up
    else
        notify set up ${USERNAME} user
        chroot ${target}/ bash -c "adduser ${USERNAME} --disabled-password --gecos "${USER_FULL_NAME}""
        chroot ${target}/ bash -c "adduser ${USERNAME} sudo"
        if [ ! -z "${USER_PASSWORD}" ]; then
            echo "${USERNAME}:${USER_PASSWORD}" > ${target}/tmp/passwd
            chroot ${target}/ bash -c "chpasswd < /tmp/passwd"
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
cat <<EOF > ${target}/etc/dracut.conf.d/89-btrfs.conf
add_dracutmodules+=" systemd btrfs "
EOF
if [ "${DISABLE_LUKS}" != "true" ]; then
cat <<EOF > ${target}/etc/dracut.conf.d/90-luks.conf
add_dracutmodules+=" crypt tpm2-tss "
EOF
fi

if [ "${ENABLE_MOK_SIGNED_UKI}" == "true" ]; then
cat <<EOF > ${target}/etc/kernel/install.conf
layout=uki
uki_generator=ukify
initrd_generator=dracut
EOF
cat <<EOF > ${target}/etc/kernel/uki.conf
[UKI]
Cmdline=@/etc/kernel/cmdline
SecureBootCertificate=/etc/kernel/mok.cert.pem
SecureBootPrivateKey=/etc/kernel/mok.priv.pem
EOF
fi # ENABLE_MOK_SIGNED_UKI

notify install required packages on ${target}
if [ -z "${NON_INTERACTIVE}" ]; then
    chroot ${target}/ apt update -y
fi
cat <<EOF > ${target}/tmp/run1.sh
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt install -y locales tasksel network-manager sudo
apt install -y -t ${BACKPORTS_VERSION} systemd shim-signed systemd-boot systemd-boot-efi-amd64-signed systemd-ukify sbsigntool dracut btrfs-progs cryptsetup tpm2-tools tpm-udev

# see https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1095646
ln -s /dev/null /etc/kernel/install.d/50-dracut.install
# XXX this didn't seem to work
EOF
chroot ${target}/ sh /tmp/run1.sh

if [ "${ENABLE_MOK_SIGNED_UKI}" == "true" ]; then
  mokutil "--generate-hash=${MOK_ENROLL_PASSWORD}" > ${target}/tmp/mok.key
cat <<EOF > ${target}/tmp/run1.sh
#!/bin/bash
# generate cert and key in pem format in /etc/kernel/mok.*.pem
ukify genkey --config /etc/kernel/uki.conf

# convert to der format
openssl x509 -in /etc/kernel/mok.cert.pem -out /etc/kernel/mok.cert.der -outform der
openssl rsa -in /etc/kernel/mok.priv.pem -out /etc/kernel/mok.priv.der -outform der

# symlink for DKMS
mkdir -p /var/lib/dkms
ln -s /etc/kernel/mok.priv.pem /var/lib/dkms/mok.key
ln -s /etc/kernel/mok.cert.der /var/lib/dkms/mok.pub

# symlink in "ubuntu" de-facto standard directory
mkdir -p /var/lib/shim-signed/mok
ln -s /etc/kernel/mok.cert.der /var/lib/shim-signed/mok/MOK-Kernel.der
ln -s /etc/kernel/mok.cert.pem /var/lib/shim-signed/mok/MOK-Kernel.pem
ln -s /etc/kernel/mok.priv.der /var/lib/shim-signed/mok/MOK-Kernel.priv

# XXX: Failed to get Subject Key ID
mokutil --import /etc/kernel/mok.cert.der --hash-file /tmp/mok.key
EOF
chroot ${target}/ sh /tmp/run1.sh
rm -f ${target}/tmp/mok.key
fi # ENABLE_MOK_SIGNED_UKI

notify install kernel and firmware on ${target}
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
dracut
lvm2
mdadm
plymouth-themes
polkitd
tpm2-tools
tpm-udev
EOF
cat <<EOF > ${target}/tmp/run2.sh
#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
xargs apt install -y < /tmp/packages.txt
apt install -t ${BACKPORTS_VERSION} -y dracut initramfs-tools- initramfs-tools-core- initramfs-tools-bin- \
  busybox- klibc-utils- libklibc-
xargs apt install -t ${BACKPORTS_VERSION} -y < /tmp/packages_backports.txt
systemctl disable systemd-networkd.service  # seems to fight with NetworkManager
systemctl disable systemd-networkd.socket
systemctl disable systemd-networkd-wait-online.service
EOF
chroot ${target}/ bash /tmp/run2.sh

if [ "$ENABLE_POPCON" = true ] ; then
  notify enabling popularity-contest
  cat <<EOF > ${target}/tmp/run3.sh
#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
echo "popularity-contest      popularity-contest/participate  boolean true" | debconf-set-selections
apt install -y popularity-contest
EOF
  chroot ${target}/ bash /tmp/run3.sh
fi

if [ ! -z "${SSH_PUBLIC_KEY}" ]; then
    notify adding ssh public key to user and root authorized_keys file
    mkdir -p ${target}/root/.ssh
    chmod 700 ${target}/root/.ssh
    echo "${SSH_PUBLIC_KEY}" > ${target}/root/.ssh/authorized_keys
    chmod 600 ${target}/root/.ssh/authorized_keys

    if [ ! -z "${USERNAME}" ]; then
        mkdir -p ${target}/home/${USERNAME}/.ssh
        chmod 700 ${target}/home/${USERNAME}/.ssh
        echo "${SSH_PUBLIC_KEY}" > ${target}/home/${USERNAME}/.ssh/authorized_keys
        chmod 600 ${target}/home/${USERNAME}/.ssh/authorized_keys
        chroot ${target}/ chown -R ${USERNAME} /home/${USERNAME}/.ssh
    fi

    notify installing openssh-server
    chroot ${target}/ apt install -y openssh-server
fi

if [ -z "${NON_INTERACTIVE}" ]; then
    notify running tasksel
    # XXX this does not open for some reason
    chroot ${target}/ tasksel
fi

if [ "${ENABLE_FLATHUB}" = true ] ; then
  notify enabling flatpak and flathub
  cat <<EOF > ${target}/tmp/run4.sh
#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
apt install -y flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
if (dpkg --get-selections | grep -w install |grep -qs "task-kde-desktop"); then
  apt install -y plasma-discover-backend-flatpak
fi
if (dpkg --get-selections | grep -w install |grep -qs "task-gnome-desktop"); then
  apt install -y gnome-software-plugin-flatpak
fi
EOF
  chroot ${target}/ bash /tmp/run4.sh
  rm ${target}/tmp/run4.sh
fi

if [ ! -z "${NVIDIA_PACKAGE}" ]; then
  notify installing ${NVIDIA_PACKAGE}
  # XXX dracut-install: ERROR: installing nvidia-blacklists-nouveau.conf nvidia.conf
  cat <<EOF > ${target}/etc/dracut.conf.d/10-nvidia.conf
install_items+=" /etc/modprobe.d/nvidia-blacklists-nouveau.conf /etc/modprobe.d/nvidia.conf /etc/modprobe.d/nvidia-options.conf "
EOF
  chroot ${target}/ apt install -t ${BACKPORTS_VERSION} -y "${NVIDIA_PACKAGE}" nvidia-driver-libs:i386 linux-headers-amd64
fi

notify cleaning up
chroot ${target}/ apt autoremove -y

notify umounting all filesystems
if [ ${SWAP_SIZE} -gt 0 ]; then
    swapoff ${target}/swap/swapfile
fi
umount -R ${target}
umount -R ${top_level_mount}

if [ "${DISABLE_LUKS}" != "true" ]; then
  notify closing luks
  cryptsetup luksClose ${luks_device_name} || true
fi

notify INSTALLATION FINISHED

if [ ! -z "${AFTER_INSTALLED_CMD}" ]; then
  notify running ${AFTER_INSTALLED_CMD}
  sh -c "${AFTER_INSTALLED_CMD}"
fi
