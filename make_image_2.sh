#!/bin/bash

# edit this:
DISK=/dev/vdb
USERNAME=live

DEBIAN_VERSION=trixie
BACKPORTS_VERSION=${DEBIAN_VERSION}  # TODO append "-backports" when available
FSFLAGS="compress=zstd:19"

efi_uuid=$(cat efi-part.uuid)
installer_image_uuid=$(cat installer-image-part.uuid)
target=/target
root_device=/dev/disk/by-partuuid/${installer_image_uuid}
efi_device=/dev/disk/by-partuuid/${efi_uuid}
kernel_params="rw quiet root=${root_device} rootfstype=btrfs rootflags=subvol=@ splash"

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
. ${SCRIPT_DIR}/_make_image_lib.sh

function install_file() {
  echo "Copying $1 to ${target}"
  rm -rf "${target}/$1"
  cp -r "${SCRIPT_DIR}/installer-files/$1" "${target}/$1"
}

if mountpoint -q "${target}/var/cache/apt/archives" ; then
    echo apt cache directory already bind mounted on target
else
    notify bind mounting apt cache directory to target
    mount /var/cache/apt/archives ${target}/var/cache/apt/archives -o bind
fi

if mountpoint -q "${target}/boot/efi" ; then
    echo efi esp partition ${DISK}1 already mounted on ${target}/boot/efi
else
    notify mount efi esp partition ${DISK}1 on ${target}/boot/efi
    mkdir -p ${target}/boot/efi
    mount ${DISK}1 ${target}/boot/efi -o umask=077
fi

notify setup fstab
mkdir -p ${target}/root/btrfs1
cat <<EOF > ${target}/etc/fstab
PARTUUID=${installer_image_uuid} / btrfs defaults,subvol=@ 0 1
PARTUUID=${installer_image_uuid} /root/btrfs1 btrfs defaults,subvolid=5 0 1
PARTUUID=${efi_uuid} /boot/efi vfat defaults,umask=077 0 2
EOF

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

notify install required packages on ${target}
mkdir -p ${target}/etc/systemd/system
cat <<EOF > ${target}/tmp/run1.sh
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y  debootstrap uuid-runtime curl
apt-get install -y -t ${BACKPORTS_VERSION} systemd-boot systemd-repart libsystemd-dev dracut cryptsetup nvidia-detect
apt-get purge initramfs-tools initramfs-tools-core -y
bootctl install
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
export DEBIAN_FRONTEND=noninteractive
apt-get -t ${BACKPORTS_VERSION} install linux-image-amd64 -y
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
chroot ${target}/ apt-get autoremove -y
rm -f ${target}/etc/machine-id
rm -f ${target}/etc/crypttab
rm -f ${target}/var/log/*log
rm -f ${target}/var/log/apt/*log

notify building the frontend
(cd ${SCRIPT_DIR}/frontend && npm run build)
mkdir -p ${SCRIPT_DIR}/installer-files/var/www/html/opinionated-debian-installer
cp -r ${SCRIPT_DIR}/frontend/dist/* ${SCRIPT_DIR}/installer-files/var/www/html/opinionated-debian-installer

notify copying the opinionated debian installer to ${target}
cp ${SCRIPT_DIR}/installer.sh ${target}/
chmod +x ${target}/installer.sh
mkdir -p ${target}/var/www/html
install_file var/www/html/opinionated-debian-installer
install_file etc/systemd/system/installer_backend.service
install_file etc/systemd/system/grow_installer_filesystem.service
install_file boot/efi/installer.ini
chroot ${target}/ systemctl enable installer_backend
# TODO replace by systemd-growfs
chroot ${target}/ systemctl enable grow_installer_filesystem.service

notify installing tui frontend
cp ${SCRIPT_DIR}/backend/opinionated-installer ${target}/sbin/opinionated-installer
chmod +x ${target}/sbin/opinionated-installer
install_file etc/systemd/system/installer_tui.service
cat <<EOF > ${target}/tmp/run1.sh
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

notify umounting the installer filesystem
sync
umount -R ${target}
umount -R /mnt/btrfs1

echo "INSTALLATION FINISHED"
