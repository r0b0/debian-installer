#!/bin/bash

# edit this:
DISK=/dev/vdb
USERNAME=live

DEBIAN_VERSION=trixie
BACKPORTS_VERSION=${DEBIAN_VERSION}  # TODO append "-backports" when available
FSFLAGS="compress=zstd:19"

target=/target
root_device=${DISK}2
overlay_low_mount=/mnt/overlay_low
overlay_top_device=${DISK}3
overlay_top_mount=/mnt/overlay_top
kernel_params="rd.overlay.lower=${overlay_low_mount} rd.overlay.upper=${overlay_top_mount}/upper rd.overlay.work=${overlay_top_mount}/work systemd.gpt_auto=no rd.systemd.gpt_auto=no rw quiet splash"

efi_uuid=$(cat efi-part.uuid)
base_image_uuid=$(cat base-image-part.uuid)
top_uuid=$(cat top-part.uuid)

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
. ${SCRIPT_DIR}/_make_image_lib.sh

function install_file() {
  echo "Copying $1 to ${target}"
  rm -rf "${target}/$1"
  cp -r "${SCRIPT_DIR}/installer-files/$1" "${target}/$1"
}

DEVICE_SLACK=$(cat device_slack.txt)
shrink_partition ${DEVICE_SLACK} ${DISK} 2

if [ ! -f top_partition_created.txt ]; then
    notify creating the overlay top partition
    echo ", +" | sfdisk ${DISK} --append
    sfdisk --part-label ${DISK} 3 "OverlayTop"
    sfdisk --part-uuid ${DISK} 3 "${top_uuid}"
    touch top_partition_created.txt
fi

if [ ! -f fs_top_created.txt ]; then
    notify create overlay top filesystem on ${overlay_top_device}
    mkfs.btrfs -f -d single -m single --mixed ${overlay_top_device}
    touch fs_top_created.txt
fi

if mountpoint -q "${overlay_low_mount}" ; then
    echo base image already mounted on ${overlay_low_mount}
else
    notify mount base image read only on ${overlay_low_mount}
    mkdir -p ${overlay_low_mount}
    mount ${root_device} ${overlay_low_mount} -o ${FSFLAGS},ro,subvol=@
fi

if mountpoint -q "${overlay_top_mount}" ; then
    echo overlay top already mounted on ${overlay_top_mount}
else
    notify mount overlay top on ${overlay_top_mount}
    mkdir -p ${overlay_top_mount}
    mount ${overlay_top_device} ${overlay_top_mount} -o ${FSFLAGS}
    mkdir -p ${overlay_top_mount}/upper
    mkdir -p ${overlay_top_mount}/work
fi

if mountpoint -q "/target" ; then
    echo overlay already mounted on /target
else
    notify mount overlay on /target
    mount -t overlay overlay -olowerdir=${overlay_low_mount},upperdir=${overlay_top_mount}/upper,workdir=${overlay_top_mount}/work ${target}
fi

mkdir -p ${target}/var/cache/apt/archives
if mountpoint -q "${target}/var/cache/apt/archives" ; then
    echo apt cache directory already bind mounted on target
else
    notify bind mounting apt cache directory to target
    mount /var/cache/apt/archives ${target}/var/cache/apt/archives -o bind
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

if mountpoint -q "${target}/boot/efi" ; then
    echo efi esp partition ${DISK}1 already mounted on ${target}/boot/efi
else
    notify mount efi esp partition ${DISK}1 on ${target}/boot/efi
    mkdir -p ${target}/boot/efi
    mount ${DISK}1 ${target}/boot/efi -o umask=077
fi

notify setup fstab
cat <<EOF > ${target}/etc/fstab
PARTUUID=${base_image_uuid} ${overlay_low_mount} btrfs defaults,ro,subvol=@ 0 1
PARTUUID=${top_uuid} ${overlay_top_mount} btrfs defaults 0 1
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
install_file etc/repart.d/01-BaseImage.conf
install_file etc/repart.d/02-OverlayTop.conf

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
mkdir -p ${target}/usr/lib/dracut/modules.d/
install_file usr/lib/dracut/modules.d/90overlay-generic
mkdir -p ${target}/etc/dracut.conf.d
cat <<EOF > ${target}/etc/dracut.conf.d/90-odin.conf
add_dracutmodules+=" systemd overlay-generic "
omit_dracutmodules+=" lvm dm crypt dmraid mdraid "
kernel_cmdline="${kernel_params}"
use_fstab="yes"
add_fstab+=" /etc/fstab "
EOF
cat <<EOF > ${target}/etc/kernel/cmdline
${kernel_params}
EOF

notify install required packages on ${target}
mkdir -p ${target}/etc/systemd/system
install_file etc/systemd/system/lighttpd.service
cat <<EOF > ${target}/tmp/run1.sh
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y  debootstrap uuid-runtime lighttpd python3-pip python3-venv curl
apt-get install -y -t ${BACKPORTS_VERSION} systemd-boot systemd-repart libsystemd-dev dracut cryptsetup python3-systemd
apt-get purge initramfs-tools initramfs-tools-core -y
bootctl install
systemctl enable lighttpd
systemctl enable NetworkManager.service
systemctl disable systemd-networkd.service  # seems to fight with NetworkManager
systemctl disable systemd-networkd.socket
systemctl disable systemd-networkd-wait-online.service
systemctl mask systemd-networkd-wait-online.service
systemctl disable apt-daily-upgrade.timer
systemctl disable apt-daily.timer
python3 -m venv /opt/installer-venv
source /opt/installer-venv/bin/activate
pip install flask flask-sock flask-cors systemd-python
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
install_file backend.py
install_file var/www/html/opinionated-debian-installer
install_file etc/systemd/system/installer_backend.service
install_file etc/systemd/system/link_volatile_root.service
install_file etc/systemd/system/grow_overlay_top_filesystem.service
install_file boot/efi/installer.ini
chroot ${target}/ systemctl enable installer_backend
chroot ${target}/ systemctl enable link_volatile_root
chroot ${target}/ systemctl enable grow_overlay_top_filesystem.service

notify installing tui frontend
cp ${SCRIPT_DIR}/frontend-tui/opinionated-installer-tui ${target}/sbin/opinionated-installer-tui
chmod +x ${target}/sbin/opinionated-installer-tui
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

notify umounting the overlay filesystem and the lower
sync
umount -R ${target}
umount -R ${overlay_low_mount}

shrink_btrfs_filesystem ${overlay_top_mount}
notify umounting the overlay top
umount -R ${overlay_top_mount}

echo "NOW REBOOT AND CONTINUE WITH PART 3"
