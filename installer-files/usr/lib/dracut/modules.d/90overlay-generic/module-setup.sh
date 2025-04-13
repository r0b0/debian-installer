#!/bin/bash
# This is a module for dracut to enable rootfs on overlayfs comprised by explicitly configured filesystems
# Kernel command line parameters: rd.overlay.lower, rd.overlay.upper, rd.overlay.work

check() {
    return 0
}

depends() {
    echo base
}

installkernel() {
    instmods overlay
}

install() {
    inst_hook mount 99 "$moddir/mount-overlayfs.sh"
}
