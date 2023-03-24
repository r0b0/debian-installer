#!/bin/bash

# edit this:
DISK=/dev/vdb
USERNAME=live

DEBIAN_VERSION=bookworm
# TODO enable backports here when it becomes available for bookworm
DEBIAN_SOURCE=${DEBIAN_VERSION}
FSFLAGS="compress=zstd:9"

target=/target
root_device=${DISK}2
overlay_low_mount=/mnt/overlay_low
overlay_top_device=${DISK}3
overlay_top_mount=/mnt/overlay_top
kernel_params="rd.overlay.lower=${overlay_low_mount} rd.overlay.upper=${overlay_top_mount}/upper rd.overlay.work=${overlay_top_mount}/work systemd.gpt_auto=no rd.systemd.gpt_auto=no rw quiet splash"

DEVICE_SLACK=$(cat device_slack.txt)
efi_uuid=$(cat efi-part.uuid)
base_image_uuid=$(cat base-image-part.uuid)
top_uuid=$(cat top-part.uuid)

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

function install_file() {
  echo "Copying $1 to ${target}"
  rm -rf "${target}/$1"
  cp -r "${SCRIPT_DIR}/installer-files/$1" "${target}/$1"
}

if [ ! -f partition_shrunk.txt ]; then
    echo shrinking the partition by ${DEVICE_SLACK}
    read -p "Enter to continue"
    echo ", -${DEVICE_SLACK}" | sfdisk ${DISK} -N 2
    echo checking the filesystem after partition shrink
    read -p "Enter to continue"
    btrfs check ${DISK}2
    touch partition_shrunk.txt
fi

if [ ! -f top_partition_created.txt ]; then
    echo creating the overlay top partition
    read -p "Enter to continue"
    echo ", +" | sfdisk ${DISK} --append
    sfdisk --part-label ${DISK} 3 "OverlayTop"
    sfdisk --part-uuid ${DISK} 3 "${top_uuid}"
    touch top_partition_created.txt
fi

if [ ! -f fs_top_created.txt ]; then
    echo create overlay top filesystem on ${overlay_top_device}
    read -p "Enter to continue"
    mkfs.btrfs -f ${overlay_top_device}
    touch fs_top_created.txt
fi

if grep -qs "${overlay_low_mount}" /proc/mounts ; then
    echo base image already mounted on ${overlay_low_mount}
else
    echo mount base image read only on ${overlay_low_mount}
    mkdir -p ${overlay_low_mount}
    read -p "Enter to continue"
    mount ${root_device} ${overlay_low_mount} -o ${FSFLAGS},ro
fi

if grep -qs "${overlay_top_mount}" /proc/mounts ; then
    echo overlay top already mounted on ${overlay_top_mount}
else
    echo mount overlay top on ${overlay_top_mount}
    mkdir -p ${overlay_top_mount}
    read -p "Enter to continue"
    mount ${overlay_top_device} ${overlay_top_mount} -o ${FSFLAGS}
    mkdir -p ${overlay_top_mount}/upper
    mkdir -p ${overlay_top_mount}/work
fi

if grep -qs "overlay /target" /proc/mounts ; then
    echo overlay already mounted on /target
else
    echo mount overlay on /target
    read -p "Enter to continue"
    mount -t overlay overlay -olowerdir=${overlay_low_mount},upperdir=${overlay_top_mount}/upper,workdir=${overlay_top_mount}/work ${target}
fi

mkdir -p ${target}/var/cache/apt/archives
if grep -qs "${target}/var/cache/apt/archives" /proc/mounts ; then
    echo apt cache directory already bind mounted on target
else
    echo bind mounting apt cache directory to target
    read -p "Enter to continue"
    mount /var/cache/apt/archives ${target}/var/cache/apt/archives -o bind
fi

if grep -qs "${target}/proc" /proc/mounts ; then
    echo bind mounts already set up on ${target}
else
    echo bind mount dev, proc, sys, run, var/tmp on ${target}
    read -p "Enter to continue"
    mount -t proc none ${target}/proc
    mount --make-rslave --rbind /sys ${target}/sys
    mount --make-rslave --rbind /dev ${target}/dev
    mount --make-rslave --rbind /run ${target}/run
    mount --make-rslave --rbind /var/tmp ${target}/var/tmp
fi

if grep -qs "${DISK}1 " /proc/mounts ; then
    echo efi esp partition ${DISK}1 already mounted on ${target}/boot/efi
else
    echo mount efi esp partition ${DISK}1 on ${target}/boot/efi
    mkdir -p ${target}/boot/efi
    read -p "Enter to continue"
    mount ${DISK}1 ${target}/boot/efi
fi

echo setup fstab
read -p "Enter to continue"
cat <<EOF > ${target}/etc/fstab
PARTUUID=${base_image_uuid} ${overlay_low_mount} btrfs defaults,ro 0 1
PARTUUID=${top_uuid} ${overlay_top_mount} btrfs defaults 0 1
EOF

if grep -qs 'root:\$' ${target}/etc/shadow ; then
    echo root password already set up
else
    echo set up root password
    read -p "Enter to continue"
    echo "root:live" > ${target}/tmp/passwd
    chroot ${target}/ bash -c "chpasswd < /tmp/passwd"
    rm ${target}/tmp/passwd
fi

if grep -qs "^${USERNAME}:" ${target}/etc/shadow ; then
    echo ${USERNAME} user already set up
else
    echo set up ${USERNAME} user
    read -p "Enter to continue"
    chroot ${target}/ useradd -m ${USERNAME} -s /bin/bash -G sudo
    echo "${USERNAME}:live" > ${target}/tmp/passwd
    chroot ${target}/ bash -c "chpasswd < /tmp/passwd"
    rm ${target}/tmp/passwd
    mkdir -p ${target}/home/live/Desktop
    install_file home/live/Desktop/installer.desktop
    chown -R 1000:1000 ${target}/home/live
fi

echo configuring dracut
read -p "Enter to continue"
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

echo install required packages on ${target}
mkdir -p ${target}/etc/systemd/system
install_file etc/systemd/system/lighttpd.service
cat <<EOF > ${target}/tmp/run1.sh
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -t ${DEBIAN_SOURCE} systemd-boot dracut cryptsetup debootstrap uuid-runtime lighttpd python3-pip python3-flask python3-flask-cors python3-h11 python3-wsproto -y
apt-get purge initramfs-tools initramfs-tools-core -y
bootctl install
systemctl enable lighttpd
systemctl enable NetworkManager.service
systemctl disable systemd-networkd.service  # seems to fight with NetworkManager
systemctl disable systemd-networkd-wait-online.service
pip install flask-sock --break-system-packages
EOF
read -p "Enter to continue"
chroot ${target}/ sh /tmp/run1.sh

echo install kernel on ${target}
cat <<EOF > ${target}/tmp/run1.sh
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get install -t ${DEBIAN_SOURCE} linux-image-amd64 -y
EOF
read -p "Enter to continue"
chroot ${target}/ sh /tmp/run1.sh

echo configuring autologin
# TODO gdm etc.
mkdir -p ${target}/etc/sddm.conf.d/
install_file etc/sddm.conf.d/autologin.conf

echo cleaning up
read -p "Enter to continue"
rm -f ${target}/etc/machine-id
rm -f ${target}/etc/crypttab
rm -f ${target}/var/log/*log
rm -f ${target}/var/log/apt/*log

echo building the frontend
read -p "Enter to continue"
(cd ${SCRIPT_DIR}/frontend && npm run build)
mkdir -p ${SCRIPT_DIR}/installer-files/var/www/html/opinionated-debian-installer
cp -r ${SCRIPT_DIR}/frontend/dist/* ${SCRIPT_DIR}/installer-files/var/www/html/opinionated-debian-installer

echo copying the opinionated debian installer to ${target}
read -p "Enter to continue"
cp ${SCRIPT_DIR}/installer.sh ${target}/
chmod +x ${target}/installer.sh
install_file backend.py
install_file var/www/html/opinionated-debian-installer
install_file etc/systemd/system/installer_backend.service
chroot ${target}/ systemctl enable installer_backend

echo umounting all filesystems
read -p "Enter to continue"
umount -R ${target}
umount -R ${overlay_low_mount}
umount -R ${overlay_top_mount}

echo "INSTALLATION FINISHED"
