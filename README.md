# Opinionated Debian Installer

This tool can be used to create a modern installation of Debian. Our opinions of what a modern installation of Debian should look like in 2022 are as follows:

 - Backports and non-free enabled
 - Firmware installed
 - Installed on btrfs subvolumes
 - Full disk encryption using luks2, unlocked by TPM (if available)
  
## Current limitations

 - **The installer will take over your whole disk**
 - Bullseye (debian 11) amd64 only

## Instructions
 
 1. Download a live ISO - the [debian non-free DVD](https://cdimage.debian.org/cdimage/unofficial/non-free/cd-including-firmware/current-live/amd64/iso-hybrid/) is recommended
 2. Boot the live ISO
 3. Connect to the internet
 4. Open a root shell
 5. Download the installer using `wget -O installer.sh https://odin.lamac.cc`
 6. Edit the file - especially the `DISK` variable containing name of the disk drive you want to install to
 7. Execute the installer using `bash ./installer.sh`
 8. You will be interactively prompted for LUKS passphrase, root password and user password
 9. The installer will inform you before each step and ask to confirm by pressing Enter. Press Ctrl+C if you are unsure and re-start the script after you investigate. It should pick up roughly where it left off. 
 10. Store the generated file `luks.key` in a safe place - you can use it to recover the data if decryption by TPM or passphrase fails for some reason.
 11. Reboot and enjoy

## Details

- 2 GPT disk partitions are created on the designated disk drive: UEFI ESP partition (200MB) and a [LUKS](https://cryptsetup-team.pages.debian.net/cryptsetup/README.Debian.html) device (rest of the drive)
- Btrfs subvolumes will be called `@` for `/` and `@home` for `/home`, the top-level subvolume will be mounted to `/root/btrfs1`
- Base system is installed using [debootstrap](https://wiki.debian.org/Debootstrap)
- The rest of the system is installed using [tasksel](https://wiki.debian.org/tasksel),
- Dracut is used instead of initramfs-tools
- Systemd-boot is used instead of grub
- Network-manager is used for networking
- Systemd-cryptenroll is used to unlock the disk, using TPM (if available)
