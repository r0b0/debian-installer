#!/bin/sh
# This is a module for dracut to enable rootfs on overlayfs comprised by explicitly configured filesystems
# Kernel command line parameters: rd.overlay.lower, rd.overlay.upper, rd.overlay.work

type getarg > /dev/null 2>&1 || . /lib/dracut-lib.sh
type wait_for_mount > /dev/null 2>&1 || . /lib/dracut-lib.sh

lower=$(getarg rd.overlay.lower)
upper=$(getarg rd.overlay.upper)
work=$(getarg rd.overlay.work)

sleep 2

mount -t overlay overlay -o "lowerdir=${lower},upperdir=${upper},workdir=${work}" "${NEWROOT}"
