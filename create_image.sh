#!/bin/bash

DEBIAN_SUITE=bullseye
IMAGE=/mnt/btrfs1/image_installer/$DEBIAN_SUITE.img
DEBOOTSTRAP_PACKAGES=linux-image-amd64,acpid,sudo
# https://cdimage.debian.org/cdimage/unofficial/non-free/cd-including-firmware/current-live/amd64/iso-hybrid/debian-live-11.0.0-amd64-kde+nonfree.log
FIRMWARE_PKGS=arm-trusted-firmware-tools dns323-firmware-tools firmware-ath9k-htc firmware-linux-free firmware-microbit-micropython firmware-microbit-micropython-doc firmware-tomu gnome-firmware grub-firmware-qemu hdmi2usb-fx2-firmware sigrok-firmware-fx2lafw ubertooth-firmware ubertooth-firmware-source amd64-microcode atmel-firmware bluez-firmware dahdi-firmware-nonfree firmware-amd-graphics firmware-atheros firmware-bnx2 firmware-bnx2x firmware-brcm80211 firmware-cavium firmware-intel-sound firmware-intelwimax firmware-ipw2x00 firmware-ivtv firmware-iwlwifi firmware-libertas firmware-linux firmware-linux-nonfree firmware-misc-nonfree firmware-myricom firmware-netronome firmware-netxen firmware-qcom-media firmware-qcom-soc firmware-qlogic firmware-realtek firmware-samsung firmware-siano firmware-sof-signed firmware-ti-connectivity firmware-zd1211 intel-microcode midisport-firmware
IMAGE_SIZE_MB=10000
MAIN_VOL_MOUNT_POINT=/mnt/installer
DEB_CACHE=/mnt/btrfs1/image_installer/deb_cache
DEBIAN_MIRROR=http://ftp.sk.debian.org/debian/

if [ ! -f "$IMAGE" ]; then
	dd if=/dev/zero "of=$IMAGE" bs=1MB count=$IMAGE_SIZE_MB
fi

LOOP_DEV=$(losetup -j "$IMAGE" | cut -d: -f1)

if [ -z "$LOOP_DEV" ]; then
	LOOP_DEV=$(losetup --find --show "$IMAGE")
fi

echo "Loop device: $LOOP_DEV"

MSG=$(mkfs.btrfs "$LOOP_DEV" 2>&1)

if [ "$?" -ne 0 ]; then
	echo "$MSG" | grep --quiet "existing filesystem"
	if [ "$?" -eq 0 ]; then
		echo "Filesystem already existing"
	else
		echo "$MSG"
		exit 1
	fi
else
	echo "Created btrfs filesystem"
fi

findmnt $LOOP_DEV >/dev/null
if [ "$?" -ne 0 ]; then
	mount -o compress=LZO "$LOOP_DEV" "$MAIN_VOL_MOUNT_POINT"
else
	echo "$LOOP_DEV already mounted"
fi

if [ ! -d "$MAIN_VOL_MOUNT_POINT/@" ]; then
	btrfs subvolume create "$MAIN_VOL_MOUNT_POINT/@"
else
	echo "Root subvolume already existing"
fi

debootstrap "--include=$DEBOOTSTRAP_PACKAGES" "--cache-dir=$DEB_CACHE" --components=main,contrib,non-free \
	"$DEBIAN_SUITE" "$MAIN_VOL_MOUNT_POINT/@" "$DEBIAN_MIRROR"

cd $MAIN_VOL_MOUNT_POINT/@
mount -t proc /proc proc/
mount --rbind /sys sys/
mount --rbind /dev dev/
cp /etc/resolv.conf etc/resolv.conf

chroot . env DEBIAN_FRONTEND=noninteractive apt -y install task-kde-desktop
chroot . env DEBIAN_FRONTEND=noninteractive apt -y install "$FIRMWARE_PKGS"

# cleanup
cd $MAIN_VOL_MOUNT_POINT/@
umount proc
umount sys
umount dev

umount $LOOP_DEV
losetup -d $LOOP_DEV

