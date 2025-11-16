# Opinionated Debian Installer

This tool can be used to create a modern installation of Debian. 
Our opinions of what a modern installation of Debian should look like in 2025 are:

 - Debian 13 (Trixie)
 - Backports and non-free enabled
 - Firmware installed
 - Installed on btrfs subvolumes
 - Full disk encryption, unlocked by TPM
 - Authenticated boot with self-generated Machine Owner Keys
 - Fast installation using an image
 - Browser-based installer
 - One-click installation of a swap file, nvidia drivers or flathub
  
## Limitations

 - **The installer will take over your whole disk**
 - Amd64 with UEFI only
 - The installer is in English only

## Downloads

| Desktop environment | Date     | Size  | Download                                                                                                                                                                                                                                                                                                         | SHA-256 Checksum                                                        |
|---------------------|----------|-------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------|
| KDE Plasma          | 20251102 | 5.1GB | [torrent](https://objectstorage.eu-frankfurt-1.oraclecloud.com/n/fr2rf1wke5iq/b/public/o/opinionated-debian-installer-trixie-kde-plasma-20251102a.torrent) / [slow](https://objectstorage.eu-frankfurt-1.oraclecloud.com/n/fr2rf1wke5iq/b/public/o/opinionated-debian-installer-trixie-kde-plasma-20251102a.img) | 717a41ff 2a5c68e0 d7505c07 f6ebf070 efda746d a0f542fb dcae5bfc 76f26364 |
| Gnome               | 20251019 | 4.3GB | [torrent](https://objectstorage.eu-frankfurt-1.oraclecloud.com/n/fr2rf1wke5iq/b/public/o/opinionated-debian-installer-trixie-gnome-20251019a.torrent) / [slow](https://objectstorage.eu-frankfurt-1.oraclecloud.com/n/fr2rf1wke5iq/b/public/o/opinionated-debian-installer-trixie-gnome-20251019a.img)           | 836d6cd3 0e20372c 3246c535 cf8143be ebe85499 f2504557 080d75a3 e57874be |
| Server              | 20251116 | 2.0GB | [torrent](https://objectstorage.eu-frankfurt-1.oraclecloud.com/n/fr2rf1wke5iq/b/public/o/opinionated-debian-installer-trixie-server-20251116a.torrent) / [slow](https://objectstorage.eu-frankfurt-1.oraclecloud.com/n/fr2rf1wke5iq/b/public/o/opinionated-debian-installer-trixie-server-20251116a.img)         | d9494702 f50e45cd e3e30c2f d6865566 b4cac031 7da736d8 b3d9a193 175bd4af |

## Instructions

1. Download one of the live image files from the table above
2. Write the image file to a USB flash drive. **Do not use ventoy** or similar "clever" tools - they are not compatible with these images. If you need a GUI, use [etcher](https://github.com/balena-io/etcher/releases) or [win32DiskImager](https://sourceforge.net/projects/win32diskimager/files/Archive/) or just use dd - `dd if=opinionated-debian-installer*.img of=/dev/sdX bs=256M oflag=dsync status=progress` where sdX is your USB flash drive 
3. Boot from the USB flash drive
4. Start the installer icon from the desktop/dash, fill in the form in the browser and press the big _Install_ button
5. (If you are using the fully authenticated boot mode: Reboot, enroll your MOK and reboot again)
6. Shutdown, remove the USB drive, boot debian and enjoy!

## Screencast & Screenshot

Screenshot of the full installer GUI:

![gui screenshot](readme-files/gui.png)

Video of installation of Debian with KDE Plasma (Bookworm version):

[![Watch the video](https://img.youtube.com/vi/sbnKvGMcagI/maxresdefault.jpg)](https://youtu.be/sbnKvGMcagI?si=W9NvZygB8Z7-LCT8&t=92)

## FAQ

**I have started to be asked for disk encryption password.
Can I have my passwordless boot back?**

You need to re-enroll the TPM to decrypt your drive.
Find the path to the underlying device (with `lsblk` or similar) and use the following command (replacing /dev/vda2 with your device):

    sudo systemd-cryptenroll --tpm2-pcrs=secure-boot-policy+shim-policy \
        --tpm2-device=auto --tpm2-pcrlock= --wipe-slot=tpm2 /dev/vda2

**The installer is very slow to start up or does not start at all**

You need fast USB storage.
USB3 is strongly recommended, including any hubs, converters or extension cables you might be using.
On slow storage, some systemd services might time out and the boot of the installer will not be successful.

**How to set keyboard layout**

Use the default debian method:

    sudo dpkg-reconfigure keyboard-configuration
    sudo setupcon

## SecureBoot

There are two options in regard to SecureBoot: simple or full.

The **simple mode** will just use shim, systemd-boot and kernel signed by Microsoft and Debian.
Your initrd file will not be signed.

If you Select the option **Enable MOK-signed UKI** in the installer, the **full mode** will apply.
This is the most secure option.
The installer will generate your Machine Owner Key (MOK) and configure the system to use Unified Kernel Image (UKI) which contains both the kernel and initrd. 
The MOK will be used to sign the UKI so that all the files involved in the boot process are authenticated.

After the installation, on the next boot, you will be asked to enroll your MOK.
Use the password you provided in the installer.
See the screenshots of the process below:
<details>
<summary>Screenshots of the MOK enrollment process</summary>

![mok enroll screenshot 1](readme-files/Screenshot_mok_import_01.png)
![mok enroll screenshot 2](readme-files/Screenshot_mok_import_02.png)
![mok enroll screenshot 3](readme-files/Screenshot_mok_import_03.png)
![mok enroll screenshot 4](readme-files/Screenshot_mok_import_04.png)
![mok enroll screenshot 5](readme-files/Screenshot_mok_import_05.png)
![mok enroll screenshot 6](readme-files/Screenshot_mok_import_06.png)

</details>

We also recommend re-enrolling the TPM device to decrypt your drive with PCRs 7 (secure-boot-policy) and 14 (shim-policy) after the installation.
Identify your underlying boot device (with `lsblk`) and use the following command (replacing /dev/vda2 with your device):

    sudo systemd-cryptenroll --tpm2-pcrs=secure-boot-policy+shim-policy \
        --tpm2-device=auto --tpm2-pcrlock= --wipe-slot=tpm2 /dev/vda2

This will prevent auto-decryption of your drive if SecureBoot is disabled or keys are tampered with.

## Details

- GPT disk partitions are created on the designated disk drive: 
  - UEFI ESP partition
  - Root partition - [LUKS](https://cryptsetup-team.pages.debian.net/cryptsetup/README.Debian.html) encrypted (rest of the drive)
- GPT root partition is [auto-discoverable](https://www.freedesktop.org/software/systemd/man/systemd-gpt-auto-generator.html)
- Btrfs subvolumes will be called `@` for `/`, `@home` for `/home` and `@swap` for swap (compatible with [timeshift](https://github.com/teejee2008/timeshift#supported-system-configurations)); the top-level subvolume will be mounted to `/root/btrfs1`
- The system is installed using an image from the live iso. This will speed up the installation significantly and allow off-line installation.
- [Dracut](https://github.com/dracutdevs/dracut/wiki/) is used instead of initramfs-tools
- [Systemd-boot](https://www.freedesktop.org/wiki/Software/systemd/systemd-boot/) is used instead of grub
- [Network-manager](https://wiki.debian.org/NetworkManager) is used for networking
- [Systemd-cryptenroll](https://www.freedesktop.org/software/systemd/man/systemd-cryptenroll.html#--tpm2-device=PATH) is used to unlock the disk, using TPM (if available)
- [Sudo](https://wiki.debian.org/sudo) is installed and configured for the created user 

## (Optional) Configuration, Automatic Installation

Edit [installer.ini](installer-files/boot/efi/installer.ini) on the first (vfat) partition of the installer image.
It will allow you to pre-seed and automate the installation.

If you edit it directly in the booted installer image, it is /boot/efi/installer.ini
Reboot after editing the file for the new values to take effect.

## Headless Installation

You can use the installer for server installation.

As a start, edit the configuration file installer.ini (see above), set the option BACK_END_IP_ADDRESS to 0.0.0.0 and reboot the installer.
**There is no encryption or authentication in the communication, so only do this on a trusted network.**

You have several options to access the installer. 
Assuming the IP address of the installed machine is 192.168.1.29, and you can reach it from your PC:

* Use the web interface in a browser on a PC - open `http://192.168.1.29:5000/`
* Use the text mode interface - start `opinionated-installer tui -baseUrl http://192.168.1.29:5000`
* Use curl - again, see the [installer.ini](installer-files/boot/efi/installer.ini) file for a list of all options for the form data in -F parameters:

      curl -v -F "DISK=/dev/vda" -F "USER_PASSWORD=hunter2" \
        -F "ROOT_PASSWORD=changeme" -F "LUKS_PASSWORD=luke" \ 
        http://192.168.1.29:5000/install

* Use curl to prompt for logs:

      curl http://192.168.1.29:5000/download_log

## Testing

If you are testing in a virtual machine, attaching the downloaded image file as a virtual disk, you need to extend it first.
The image file that you downloaded is shrunk, there is no free space left in the filesystems.
Use `truncate -s +500M opinionated*.img` to add 500MB to the virtual disk before you attach it to a virtual machine.
The installer will expand the partitions and filesystem to fill the device.

### Libvirt

To test with [libvirt](https://libvirt.org/), make sure to create the VM with UEFI:

1. Select the _Customize configuration before install_ option at the end of the new VM dialog
2. In the VM configuration window, _Overview_ tab, _Hypervisor Details_ section, select _Firmware_: _UEFI_

![virt-manager uefi screenshot](readme-files/virt-manager-uefi.png)

To add a TPM module, you need to install the [swtpm-tools](https://packages.debian.org/trixie/swtpm-tools) package.

Attach the downloaded installer image file as _Device type: Disk device_, not ~~CD-ROM device~~.

### Hyper-V

To test with the MS hyper-v virtualization, make sure to create your VM with [Generation 2](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/plan/Should-I-create-a-generation-1-or-2-virtual-machine-in-Hyper-V). 
This will enable UEFI.
TPM can be enabled in the Security tab of the Hyper-V settings.

You will also need to convert the installer image to VHDx format and make the file not sparse.
You can use [qemu-img](https://www.qemu.org/docs/master/tools/qemu-img.html) ([windows download](https://qemu.weilnetz.de/w64/)) and fsutil like this:

    qemu-img convert -f raw -O vhdx opinionated-debian-installer-*.img odin.vhdx
    fsutil sparse setflag odin.vhdx 0

Attach the generated VHDx file as a disk, not as a ~~CD~~.

## Hacking

Alternatively to running the whole browser-based GUI, you can run the `installer.sh` script manually from a root shell.
The end result will be exactly the same.
Just don't forget to edit the configuration options (especially the `DISK` variable) before running it.

### Creating Your Own Installer Image

 1. Insert a blank storage device
 2. Edit the **DISK** and other variables at the top of `make_image.sh`
 3. Execute  `make_image.sh` as root

In the first stage of image generation, you will get a _tasksel_ prompt where you can select a different set of packages for your image.

### Installer Image Structure

There are two GPT partitions on the installer image: EFI boot partition and a Btrfs partition.  
The Btrfs filesystem is created in two phases.

In the first phase, a basic, neutral debian installation is created by debootstrap, tasksel.
At this point, a snapshot called **opinionated_installer_bootstrap** is created.
When installing the target system, the installer will detect the snapshot and copy its contents to the target root subvolume using btrfs send/receive.

In the second phase, all the installer-specific files are added to the installer Btrfs filesystem.
Obviously, these are not part of the target installed system.

### Building the Frontend

The frontend is a [vue](https://vuejs.org/) application. 
You need [npm](https://www.npmjs.com/) to build it.
Run the following commands to build it:

    cd frontend
    npm run build

### Building the HTTP Backend and the Text-User-Interface Frontend

The HTTP backend and TUI frontend is a [go](https://go.dev/) application.
Run the following commands to build it:

    cd backend
    go build -o opinionated-installer

### Configuration Flow

```mermaid
flowchart LR
    A[installer.ini] -->|EnvironmentFile| B(installer_backend.service)
    B -->|ExecStart| C[backend]
    D(Web Frontend) --->|HTTP POST| C
    E(TUI Frontend) --->|HTTP POST| C
    G(curl) --->|HTTP POST| C
    C -->|environment| F[installer.sh]
```

### Output Flow

```mermaid
flowchart RL
    C[backend] -->|stdout| B(installer_backend.service)
    C --->|websocket| D(Web Frontend)
    C --->|websocket| E(TUI Frontend)
    C --->|HTTP GET| G(curl)
    F[installer.sh] -->|stdout| C
```

## Comparison

The following table contains a comparison of features between our opinionated debian installer and official debian installers.

| Feature                                             | ODIN  | [Netinstall](https://www.debian.org/CD/netinst/) | [Calamares](https://get.debian.org/debian-cd/current-live/amd64/iso-hybrid/) |
|-----------------------------------------------------|-------|--------------------------------------------------|------------------------------------------------------------------------------|
| Installer internationalization                      | N     | Y                                                | Y                                                                            |
| Mirror selection, HTTP proxy support                | N     | Y                                                | N                                                                            |
| Manual disk partitioning, LVM, filesystem selection | N[4]  | Y                                                | Y                                                                            |
| Btrfs subvolumes                                    | Y[2]  | Y[3]                                             | Y[2]                                                                         |
| Full drive encryption                               | **Y** | Y[1]                                             | Y                                                                            |
| Passwordless unlock (TPM)                           | **Y** | N                                                | N                                                                            |
| Fully authenticated boot (UKI+MOK)                  | **Y** | N                                                | N                                                                            |
| Image-based installation                            | **Y** | N                                                | N                                                                            |
| Non-free and backports                              | **Y** | N                                                | N                                                                            |
| Browser-based installer                             | **Y** | N                                                | N                                                                            |

[1] `/boot` needs a separate unencrypted partition

[2] `@` and `@home` ([timeshift](https://github.com/linuxmint/timeshift#supported-system-configurations) compatible)

[3] `@rootfs`

[4] Fixed partitioning (see Details above), LUKS is automatic, BTRFS is used as filesystem

## Support The Project

### Seed The Torrents

Please set up your torrent client to follow the RSS feed below and seed all new images:

[feed.xml](https://objectstorage.eu-frankfurt-1.oraclecloud.com/n/fr2rf1wke5iq/b/public/o/feed.xml)

### Spread The Word

Tell your friends about the installer.
If you are active on social media, please share!