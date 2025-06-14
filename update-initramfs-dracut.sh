#/bin/bash
VERSION=$(uname -r)
/etc/kernel/postinst.d/dracut "${VERSION}" "/boot/vmlinuz-${VERSION}"
/etc/kernel/postinst.d/zz-systemd-boot  "${VERSION}" "/boot/vmlinuz-${VERSION}"
