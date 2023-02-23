# Opinionated Debian Installer

This tool can be used to create a modern installation of Debian. Our opinions of what a modern installation of Debian should look like in 2023 are as follows:

 - Backports and non-free enabled
 - Firmware installed
 - Installed on btrfs subvolumes
 - Full disk encryption using luks2, unlocked by TPM (if available)
 - Fast installation using an image
  
## Limitations

 - **The installer will take over your whole disk**
 - Bookworm (debian 12) amd64 only
 - The installer is in english only
 - Currently, only KDE Plasma installer ISO is available.

## Instructions
 
 1. Download our live ISO
 2. Boot the live ISO and login as live with password live
 3. **Edit the file /installer.sh - especially the `DISK` variable containing name of the disk drive you want to install to**
 4. Start the installer from the desktop and follow the prompts
 8. You will be interactively prompted for LUKS passphrase, root password and user password
 9. The installer will inform you before each step and ask to confirm by pressing Enter. Press Ctrl+C if you are unsure and re-start the script after you investigate. It should pick up roughly where it left off. 
 11. Store the generated file `luks.key` in a safe place - you can use it to recover the data if decryption by TPM or passphrase fails for some reason.
 12. Reboot and enjoy

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

### Creating Your Own ISO

 1. Insert a blank storage device
 2. Edit the **DISK** variable at the top of files `make_image_*.sh`
 3. Execute the `make_image_*.sh` files as root

In the first stage of image generation, you will get a _tasksel_ prompt where you can select a different set of packages for your image.

### Installer ISO Structure

There are 3 GPT partitions on the installer ISO:

 1. EFI boot partition
 2. Base Image - Btrfs partition with maximum zstd compression. When the live system is running, this is used as a [read-only lower device for overlayfs](https://docs.kernel.org/filesystems/overlayfs.html). The installer will copy this to the target system, mount it read-write, resize to expand to the whole partition and continue with the system installation.
 3. Top Overlay - upper and work device for the overlayfs for the live system. The changes you make while the live system is running are persisted here.

## Comparison

The following table contains comparison of features between our opinionated debian installer and official debian installers.

* Netinstall - https://www.debian.org/devel/debian-installer/
* Calamares - ?

|Feature |ODIN|Netinstall|Calamares|
|--|--| -- | -- |
|Installer l10n |N|Y| |
|Timezone setup|N|Y| |
|Locales setup|N|Y| |
|Console keyboard|N|Y |
|Hostname setup|N|Y| |
|Root password|Y|Y |
|Regular user and password|Y|Y| |
|Mirror selection|N|Y| |
|HTTP proxy support|N|Y| |
|Manual disk partitioning, LVM, filesystem selection|N|Y| |
|Btrfs subvolumes|Y[2]|Y[3]| |
|LUKS|**Y**|Y[1]| |
|Image-based installation|**Y**|N| |
|Non-free and backports|**Y**|N| |

[1] /boot needs a separate unencrypted partition
[2] @ and @home
[3] @rootfs
