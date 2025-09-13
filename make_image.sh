#!/bin/bash

set -euo pipefail

# edit this:
DISK=/dev/vdb
USERNAME=live
DEBIAN_VERSION=trixie
BACKPORTS_VERSION=${DEBIAN_VERSION}-backports
FSFLAGS="compress=zstd:15"

target=/target
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

function notify {
  echo -en "\033[32m$*\033[0m> "
  read -r
}

notify install required packages
apt update -y
DEBIAN_FRONTEND=noninteractive apt install -y \
    btrfs-progs \
    debootstrap \
    dosfstools \
    golang-go \
    npm \
    systemd-repart \
    uuid-runtime

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

notify setting up partitions on ${DISK}
mkdir -p /mnt/btrfs1
mkdir -p ${target}/home
rm -rf repart.d
mkdir -p repart.d

cat <<EOF > repart.d/01_efi.conf
[Partition]
Type=esp
UUID=${efi_uuid}
SizeMinBytes=200M
SizeMaxBytes=200M
Format=vfat
EOF

cat <<EOF > repart.d/02_baseImage.conf
[Partition]
Type=root
Label=Opinionated Debian Installer
UUID=${installer_image_uuid}
SizeMinBytes=200M
Format=btrfs
MakeDirectories=/@ /@swap /@home
Subvolumes=/@ /@swap /@home
GrowFileSystem=on
Encrypt=off
EOF

if [ ! -f disk_wiped.txt ]; then
  wipefs --all ${DISK}
  touch disk_wiped.txt
fi

# sector-size: see https://github.com/systemd/systemd/issues/37801
# remove with systemd 258
systemd-repart --sector-size=512 --empty=allow --no-pager --definitions=repart.d --dry-run=no ${DISK}

root_device=/dev/disk/by-partuuid/${installer_image_uuid}
efi_device=/dev/disk/by-partuuid/${efi_uuid}
kernel_params="rw quiet root=${root_device} rootfstype=btrfs rootflags=subvol=@ splash"

if mountpoint -q "/mnt/btrfs1" ; then
    echo top-level subvolume already mounted on /mnt/btrfs1
else
    notify mount top-level subvolume on /mnt/btrfs1
    mkdir -p /mnt/btrfs1
    mount "${root_device}" /mnt/btrfs1 -o ${FSFLAGS},subvolid=5
fi

if mountpoint -q "${target}" ; then
    echo root subvolume already mounted on ${target}
else
    notify mount root and home subvolume on ${target}
    mkdir -p ${target}
    mount "${root_device}" ${target} -o ${FSFLAGS},subvol=@
    mkdir -p ${target}/home
    mount "${root_device}" ${target}/home -o ${FSFLAGS},subvol=@home
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

notify enable 32bit
chroot ${target}/ dpkg --add-architecture i386

notify "preconfigure locales (ignore warnings in this step)"
echo "locales locales/locales_to_be_generated multiselect     en_US.UTF-8 UTF-8" | chroot ${target}/ debconf-set-selections

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
mokutil
pigz
pkg-config
EOF
cat <<EOF > ${target}/tmp/packages_backports.txt
systemd
systemd-cryptsetup
systemd-timesyncd
systemd-ukify
sbsigntool
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
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt update
xargs apt install -y < /tmp/packages.txt
xargs apt install -t ${BACKPORTS_VERSION} -y < /tmp/packages_backports.txt
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
set -e

export DEBIAN_FRONTEND=noninteractive
apt install -y --download-only locales tasksel openssh-server flatpak
apt install -t ${BACKPORTS_VERSION} -y --download-only systemd-boot systemd-boot-efi-signed dracut linux-image-amd64 popularity-contest
if (dpkg --get-selections | grep -w install |grep -qs "task.*desktop"); then
  # libelf1t64:i386 - XXX workaround 2025-09-13
  apt install -t ${BACKPORTS_VERSION} -y --download-only linux-headers-amd64 nvidia-driver nvidia-driver-libs:i386 libelf1t64:i386
fi
if (dpkg --get-selections | grep -w install |grep -qs "task-kde-desktop"); then
  apt install -y --download-only plasma-discover-backend-flatpak
fi
if (dpkg --get-selections | grep -w install |grep -qs "task-gnome-desktop"); then
  apt install -y --download-only gnome-software-plugin-flatpak
fi
EOF
chroot ${target}/ bash /tmp/run3.sh

notify cleaning up
chroot ${target}/ apt autoremove -y
rm -f ${target}/etc/machine-id
rm -f ${target}/etc/crypttab
rm -f ${target}/var/log/*log
rm -f ${target}/var/log/apt/*log

if [ ! -f first_phase_done.txt ]; then
  notify create snapshot after first phase
  (cd /mnt/btrfs1; btrfs subvolume snapshot -r @ opinionated_installer_bootstrap)
  touch first_phase_done.txt
fi

function install_file() {
  echo "Copying $1 to ${target}"
  rm -rf "${target:?}/$1"
  cp -r "${SCRIPT_DIR}/installer-files/$1" "${target}/$1"
}

if mountpoint -q "${target}/var/cache/apt/archives" ; then
    echo apt cache directory already bind mounted on target
else
    notify bind mounting apt cache directory to target
    mount /var/cache/apt/archives ${target}/var/cache/apt/archives -o bind
fi

if mountpoint -q "${target}/boot/efi" ; then
    echo efi esp partition ${efi_device} already mounted on ${target}/boot/efi
else
    notify mount efi esp partition ${efi_device} on ${target}/boot/efi
    mkdir -p ${target}/boot/efi
    mount "${efi_device}" ${target}/boot/efi -o umask=077
fi

notify setup fstab
mkdir -p ${target}/root/btrfs1
cat <<EOF > ${target}/etc/fstab
PARTUUID=${installer_image_uuid} / btrfs defaults,subvol=@,x-systemd.growfs 0 1
PARTUUID=${installer_image_uuid} /home btrfs defaults,subvol=@home 0 1
PARTUUID=${installer_image_uuid} /root/btrfs1 btrfs defaults,subvolid=5 0 1
PARTUUID=${efi_uuid} /boot/efi vfat defaults,umask=077 0 2
EOF

# TODO use systemd-firstboot

if grep -qs 'root:\$' ${target}/etc/shadow ; then
    echo root password already set up
else
    notify set up root password
    echo "root:live" > ${target}/tmp/passwd
    chroot ${target}/ bash -c "chpasswd < /tmp/passwd"
    rm ${target}/tmp/passwd
fi

if grep -qs "^${USERNAME}:" ${target}/etc/shadow ; then
    echo ${USERNAME} user already set up
else
    notify set up ${USERNAME} user
    chroot ${target}/ useradd -m ${USERNAME} -s /bin/bash -G sudo
    echo "${USERNAME}:live" > ${target}/tmp/passwd
    chroot ${target}/ bash -c "chpasswd < /tmp/passwd"
    rm ${target}/tmp/passwd
fi

notify setup systemd-repart
mkdir -p ${target}/etc/repart.d
install_file etc/repart.d/01-installer.conf

# place the icon in the apps menu
mkdir -p ${target}/usr/share/applications
install_file usr/share/applications/installer.desktop
# kde - place the icon on the desktop
mkdir -p ${target}/home/live/Desktop
install_file home/live/Desktop/installer.desktop
# kde - customize the welcome center
mkdir -p ${target}/home/live/.config
install_file home/live/.config/plasma-welcomerc
mkdir -p ${target}/usr/share/pixmaps
install_file usr/share/pixmaps/Ceratopsian_installer.svg
mkdir -p ${target}/usr/share/plasma/plasma-welcome
install_file usr/share/plasma/plasma-welcome/intro-customization.desktop
# gnome - place the icon to the 'dash'
if [ -f ${target}/usr/bin/dconf ]; then
  mkdir -p ${target}/etc/dconf/profile
  install_file etc/dconf/profile/user
  mkdir -p ${target}/etc/dconf/db/local.d
  install_file etc/dconf/db/local.d/01-favorite-apps
  echo running dconf update
  chroot ${target}/ dconf update
else
  echo dconf not installed, skipping
fi
chown -R 1000:1000 ${target}/home/live

notify configuring dracut
mkdir -p ${target}/etc/dracut.conf.d
cat <<EOF > ${target}/etc/dracut.conf.d/90-odin.conf
add_dracutmodules+=" systemd "
omit_dracutmodules+=" lvm dmraid mdraid "
kernel_cmdline="${kernel_params}"
use_fstab="yes"
add_fstab+=" /etc/fstab "
EOF
cat <<EOF > ${target}/etc/kernel/cmdline
${kernel_params}
EOF

notify install required installer packages on ${target}
mkdir -p ${target}/etc/systemd/system
cat <<EOF > ${target}/tmp/run1.sh
#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt update -y
apt upgrade -y
apt install -y debootstrap uuid-runtime curl pv
apt install -y -t ${BACKPORTS_VERSION} systemd-boot systemd-boot-efi-amd64-signed shim-signed systemd-repart dracut cryptsetup nvidia-detect
apt purge initramfs-tools initramfs-tools-core initramfs-tools-bin busybox klibc-utils libklibc -y
systemctl enable NetworkManager.service
systemctl disable systemd-networkd.service  # seems to fight with NetworkManager
systemctl disable systemd-networkd.socket
systemctl disable systemd-networkd-wait-online.service
systemctl mask systemd-networkd-wait-online.service
systemctl disable apt-daily-upgrade.timer
systemctl disable apt-daily.timer
EOF
chroot ${target}/ bash /tmp/run1.sh

notify install kernel on ${target}
cat <<EOF > ${target}/tmp/run1.sh
#!/bin/bash
set -euo pipefail

# see https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=1095646
ln -s /dev/null /etc/kernel/install.d/50-dracut.install

export DEBIAN_FRONTEND=noninteractive
apt -t ${BACKPORTS_VERSION} install linux-image-amd64 -y
EOF
chroot ${target}/ bash /tmp/run1.sh

echo configuring autologin
mkdir -p ${target}/etc/sddm.conf.d/
install_file etc/sddm.conf.d/autologin.conf
mkdir -p ${target}/etc/gdm3
install_file etc/gdm3/daemon.conf
mkdir -p ${target}/etc/lightdm/lightdm.conf.d
install_file etc/lightdm/lightdm.conf.d/10-autologin.conf

notify cleaning up
chroot ${target}/ apt autoremove -y
rm -f ${target}/etc/machine-id
rm -f ${target}/etc/crypttab
rm -f ${target}/var/log/*log
rm -f ${target}/var/log/apt/*log

notify building the frontend
(cd "${SCRIPT_DIR}/frontend" && npm install && npm run build)
mkdir -p "${SCRIPT_DIR}/installer-files/var/www/html/opinionated-debian-installer"
cp -r ${SCRIPT_DIR}/frontend/dist/* "${SCRIPT_DIR}/installer-files/var/www/html/opinionated-debian-installer"

notify copying the opinionated debian installer to ${target}
cp "${SCRIPT_DIR}/installer.sh" "${target}/"
chmod +x ${target}/installer.sh
mkdir -p ${target}/var/www/html
install_file var/www/html/opinionated-debian-installer
install_file etc/systemd/system/installer_backend.service
install_file boot/efi/installer.ini
chroot ${target}/ systemctl enable installer_backend

(cd "${SCRIPT_DIR}/backend" && CGO_ENABLED=0 go build -v -ldflags="-s -w" -o opinionated-installer)

notify installing tui frontend
cp "${SCRIPT_DIR}/backend/opinionated-installer" "${target}/sbin/opinionated-installer"
chmod +x ${target}/sbin/opinionated-installer
install_file etc/systemd/system/installer_tui.service
cat <<EOF > ${target}/tmp/run1.sh
#!/bin/bash
set -euo pipefail

if systemctl is-enabled display-manager.service ; then
    echo "A login manager enabled in systemd, disabling installer TUI frontend"
    systemctl disable installer_tui.service
    # we need to remove the file because systemd.preset would re-enable the unit
    rm /etc/systemd/system/installer_tui.service
else
    echo "No login manager enabled in systemd, enabling installer TUI frontend"
    systemctl enable installer_tui.service
fi
EOF
chroot ${target}/ bash /tmp/run1.sh
rm -f ${target}/tmp/run1.sh

notify note the filesystem usage
df -h ${target}
btrfs filesystem df ${target}
df -h ${target}/boot/efi

notify umounting the installer filesystem
sync
umount -R ${target}
umount -R /mnt/btrfs1

echo "INSTALLATION FINISHED"
