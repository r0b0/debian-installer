#!/bin/bash
VERSION=$(uname -r)
/etc/kernel/postinst.d/dracut "${VERSION}" "/boot/vmlinuz-${VERSION}"

# no need - done by the above
# /etc/kernel/postinst.d/zz-systemd-boot  "${VERSION}" "/boot/vmlinuz-${VERSION}"
