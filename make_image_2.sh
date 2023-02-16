#!/bin/bash

# edit this:
DISK=/dev/vdb

DEBIAN_VERSION=bookworm
# TODO enable backports here when it becomes available for bookworm
DEBIAN_SOURCE=${DEBIAN_VERSION}
FSFLAGS="compress=zstd:9"

target=/target
root_device=${DISK}2
overlay_top_device=${DISK}3

echo shrinking the partition by ${DEVICE_SLACK}
read -p "Enter to continue"
echo ", -${DEVICE_SLACK}" | sfdisk ${DISK} -N 2

echo checking the filesystem after partition shrink
read -p "Enter to continue"
btrfs check ${DISK}2

echo creating the overlay top partition
read -p "Enter to continue"
echo ", +" | sfdisk ${DISK} --append
sfdisk --part-label ${DISK} 3 "Overlay Top"

if [ ! -f btrfs_top_created.txt ]; then
    echo create overlay top filesystem on ${overlay_top_device}
    read -p "Enter to continue"
    mkfs.btrfs -f ${overlay_top_device}
    touch btrfs_top_created.txt
fi

if grep -qs "/mnt/btrfs1" /proc/mounts ; then
    echo base image already mounted on /mnt/btrfs1
else
    echo mount base image read only on /mnt/btrfs1
    mkdir -p /mnt/btrfs1
    read -p "Enter to continue"
    mount ${root_device} /mnt/btrfs1 -o ${FSFLAGS},ro
fi

if grep -qs "/mnt/btrfs2" /proc/mounts ; then
    echo overlay top already mounted on /mnt/btrfs2
else
    echo mount overlay top on /mnt/btrfs2
    mkdir -p /mnt/btrfs2
    read -p "Enter to continue"
    mount ${overlay_top_device} /mnt/btrfs2 -o ${FSFLAGS}
    mkdir -p /mnt/btrfs2/upper
    mkdir -p /mnt/btrfs2/work
fi

if grep -qs "overlay on /target" /proc/mounts ; then
    echo overlay already mounted on /target
else
    echo mount overlay on /target
    mount -t overlay overlay -olowerdir=/mnt/btrfs1,upperdir=/mnt/btrfs2/upper,workdir=/mnt/btrfs2/work ${target}
fi

mkdir -p ${target}/var/cache/apt/archives
if grep -qs "${target}/var/cache/apt/archives" /proc/mounts ; then
    echo apt cache directory already bind mounted on target
else
    echo bind mounting apt cache directory to target
    mount /var/cache/apt/archives ${target}/var/cache/apt/archives -o bind
fi

if grep -qs "${target}/proc" /proc/mounts ; then
    echo bind mounts already set up on ${target}
else
    echo bind mount dev, proc, sys, run on ${target}
    read -p "Enter to continue"
    mount -t proc none ${target}/proc
    mount --make-rslave --rbind /sys ${target}/sys
    mount --make-rslave --rbind /dev ${target}/dev
    mount --make-rslave --rbind /run ${target}/run
fi

if grep -qs 'root:\$' ${target}/etc/shadow ; then
    echo root password already set up
else
    echo set up root password
    read -p "Enter to continue"
    chroot ${target}/ passwd
fi

if grep -qs "^${USERNAME}:" ${target}/etc/shadow ; then
    echo ${USERNAME} user already set up
else
    echo set up ${USERNAME} user
    chroot ${target}/ adduser ${USERNAME}
fi

echo install required packages on ${target}
cat <<EOF > ${target}/tmp/run1.sh
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -t ${DEBIAN_SOURCE} locales systemd systemd-boot dracut network-manager -y
bootctl install
EOF
read -p "Enter to continue"
chroot ${target}/ sh /tmp/run1.sh

echo install required packages on ${target}
cat <<EOF > ${target}/tmp/run1.sh
#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -t ${DEBIAN_SOURCE} linux-image-amd64 -y
bootctl install
EOF
read -p "Enter to continue"
chroot ${target}/ sh /tmp/run1.sh

echo umounting all filesystems
read -p "Enter to continue"
umount -R ${target}
umount -R /mnt/btrfs1
umount -R /mnt/btrfs2

echo "INSTALLATION FINISHED"
