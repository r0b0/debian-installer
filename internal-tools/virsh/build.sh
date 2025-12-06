#!/bin/sh

VM=debian2025

virsh -c qemu:///system detach-device ${VM} --current --file image_as_usb.xml
virsh -c qemu:///system detach-device ${VM} --current --file disk_a_as_virtio.xml

virsh -c qemu:///system attach-device ${VM} --current --file build.xml
virsh -c qemu:///system attach-device ${VM} --current --file image_as_virtio.xml

virsh -c qemu:///system start ${VM}
