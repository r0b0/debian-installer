# Opinionated Debian Installer

This tool can be used to create a modern installation of Debian. Our opinions of what a modern installation of Debian should look like in 2023 are as follows:

 - Backports and non-free enabled
 - Firmware installed
 - Installed on btrfs subvolumes
 - Full disk encryption using luks2, unlocked by TPM (if available)
 - Fast installation using an image
 - Browser-based installer
  
## Limitations

 - **The installer will take over your whole disk**
 - Bookworm (debian 12) amd64 only
 - The installer is in english only
 - At the moment, only KDE Plasma installer is available.

## Instructions
 
 1. Download our live image
 2. Write the image to a USB flash drive and boot it
 3. Start the installer icon from the desktop and fill in the form in the browser and press the big _Install_ button
 4. Store the generated file `luks.key` in a safe place - you can use it to recover the data if decryption by TPM or passphrase fails for some reason. **TODO download the file**
 5. Reboot and enjoy

## Details

- 2 GPT disk partitions are created on the designated disk drive: UEFI ESP partition (1GB) and a [LUKS](https://cryptsetup-team.pages.debian.net/cryptsetup/README.Debian.html) device (rest of the drive)
- GPT root partition is [auto-discoverable](https://www.freedesktop.org/software/systemd/man/systemd-gpt-auto-generator.html)
- Btrfs subvolumes will be called `@` for `/` and `@home` for `/home`, the top-level subvolume will be mounted to `/root/btrfs1`
- The system is installed using an image from the live iso. This will speed up the installation significantly.
- [Dracut](https://github.com/dracutdevs/dracut/wiki/) is used instead of initramfs-tools
- [Systemd-boot](https://www.freedesktop.org/wiki/Software/systemd/systemd-boot/) is used instead of grub
- [Network-manager](https://wiki.debian.org/NetworkManager) is used for networking
- [Systemd-cryptenroll](https://www.freedesktop.org/software/systemd/man/systemd-cryptenroll.html#--tpm2-device=PATH) is used to unlock the disk, using TPM (if available)

## Hacking

### Creating Your Own Installer Image

 1. Insert a blank storage device
 2. Edit the **DISK** variable at the top of files `make_image_*.sh`
 3. Execute the `make_image_*.sh` files as root

In the first stage of image generation, you will get a _tasksel_ prompt where you can select a different set of packages for your image.

### Installer Image Structure

There are 3 GPT partitions on the installer image:

 1. EFI boot partition
 2. Base Image - Btrfs partition with maximum zstd compression. When the live system is running, this is used as a [read-only lower device for overlayfs](https://docs.kernel.org/filesystems/overlayfs.html). The installer will copy this to the target system, mount it read-write, resize to expand to the whole partition and continue with the system installation.
 3. Top Overlay - upper and work device for the overlayfs for the live system. The changes you make while the live system is running are persisted here.

## Comparison

The following table contains comparison of features between our opinionated debian installer and official debian installers.

* Netinstall - https://www.debian.org/devel/debian-installer/
* Calamares - ?

|Feature |ODIN|Netinstall|Calamares|
|--|--| -- | -- |
|Installer l10n|N|Y| |
|Mirror selection|N|Y| |
|HTTP proxy support|N|Y| |
|Manual disk partitioning, LVM, filesystem selection|N[4]|Y| |
|Btrfs subvolumes|Y[2]|Y[3]| |
|LUKS|**Y**|Y[1]| |
|Image-based installation|**Y**|N| |
|Non-free and backports|**Y**|N| |
|Browser-based installer|Y|N| |

[1] /boot needs a separate unencrypted partition

[2] @ and @home - [timeshift](https://github.com/teejee2008/timeshift#supported-system-configurations) compatible

[3] @rootfs

[4] Fixed partitioning (see Details above), LVM is automatic, BTRFS is used as filesystem
