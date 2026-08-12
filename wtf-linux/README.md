# WTF Linux

A minimal amd64 Linux distribution based on Ubuntu 24.04 LTS (Noble Numbat) for physical servers, workstations, and virtual machines. Installs from a bootable ISO using Ubuntu's Subiquity installer in interactive mode with sensible pre-filled defaults. The installer prompts for username, password, hostname, disk selection, and network configuration while automatically installing all WTF Linux packages, OpenSSH server, hardware firmware, hypervisor guest agents, serial console, full filesystem support, and DNS utilities.

## Specifications

| Property | Value |
|----------|-------|
| Base | Ubuntu 24.04 LTS (Noble Numbat) |
| Architecture | amd64 |
| Target | Physical x86_64 hardware and virtual machines (QEMU/KVM, Proxmox, VMware, Hyper-V) |
| Installer | Interactive (Subiquity with autoinstall defaults) |
| Boot modes | BIOS (ISOLINUX) and UEFI (GRUB), both with serial console |
| Default user | Set during install (pre-filled default: `wtf`) |
| Root login | Disabled (sudo) |
| SSH | openssh-server, enabled on boot, port 22 |
| Serial console | ttyS0 @ 115200 baud (installer and installed system) |
| Package manager | APT (main, restricted, universe, multiverse) |
| Desktop | None (server/minimal) |

## Boot Menu

When booting the ISO, the installer presents:

```
WTF Linux 2.0 Installer

  Install WTF Linux                      <-- interactive install with WTF defaults (default)
  Install WTF Linux (manual, no defaults) <-- standard Ubuntu installer, no autoinstall
  Try Ubuntu without installing
  Boot from first hard disk
```

The **Install WTF Linux** option launches the Subiquity installer in interactive mode. The user is prompted for identity (hostname, username, password), disk/storage selection, and network configuration. All values are pre-filled with sensible WTF Linux defaults. Packages, SSH configuration, branding, and late-commands are applied automatically after the interactive sections complete.

The **Install WTF Linux (manual, no defaults)** option launches the standard Ubuntu Server installer without any autoinstall configuration for full manual control.

### Interactive Installer Prompts

During the **Install WTF Linux** flow, the installer prompts for:

| Section | What the user configures | Default |
|---------|-------------------------|---------|
| Identity | Hostname, username, password | `wtf-linux` / `wtf` |
| Storage | Disk selection and partitioning | Entire disk, single partition |
| Network | Interface configuration | DHCP on all ethernet interfaces |

All other sections (locale, keyboard, timezone, packages, SSH, branding) are applied automatically without prompts.

## Included Packages

### Core

openssh-server, sudo, curl, wget, vim, htop, less, man-db, bash-completion, ca-certificates, gnupg, lsb-release, apt-transport-https, net-tools, iputils-ping, ufw

### VM Guest Agents

| Package | Hypervisor |
|---------|-----------|
| qemu-guest-agent | QEMU/KVM, Proxmox VE |
| open-vm-tools | VMware ESXi/Workstation |
| spice-vdagent | SPICE protocol (Proxmox, virt-manager) |
| acpid | Graceful shutdown/reboot from any hypervisor |

### Hardware Firmware

| Package | Hardware |
|---------|----------|
| linux-firmware | Metapackage for all firmware (Intel, Realtek, Broadcom, etc.) |

Note: Ubuntu uses the `linux-firmware` metapackage which bundles all firmware blobs (Intel, Realtek, Broadcom, Atheros, etc.) into a single package, unlike Debian which splits them into separate `firmware-*` packages.

### Filesystems

| Package | Filesystem |
|---------|-----------|
| xfsprogs, xfsdump | XFS |
| e2fsprogs | ext2/ext3/ext4 |
| btrfs-progs | Btrfs |
| dosfstools | FAT/VFAT |
| ntfs-3g | NTFS |
| exfatprogs | exFAT |
| f2fs-tools | F2FS |
| jfsutils | JFS |
| reiserfsprogs | ReiserFS |
| hfsplus, hfsutils | HFS/HFS+ |
| nilfs-tools | NILFS2 |
| udftools | UDF |
| squashfs-tools | SquashFS |
| erofs-utils | EROFS |
| mtools | DOS/FAT without mounting |

Storage management: lvm2, mdadm, cryptsetup, dmsetup, multipath-tools

Network filesystems: nfs-common, cifs-utils, sshfs, fuse3

Partitioning: parted, gdisk, fdisk

Hardware diagnostics: ethtool, pciutils, usbutils

### DNS Utilities

bind9-host, bind9-dnsutils (dig, nslookup, nsupdate), whois, dnstracer, dns-root-data, ldnsutils (drill), libidn2-0, systemd-resolved

## Building the ISO

### Prerequisites

A Debian or Ubuntu build host with root access. Build dependencies (xorriso, p7zip-full, wget, file, imagemagick) are installed automatically if missing.

### Build

```bash
# Downloads Ubuntu 24.04 LTS server ISO automatically on first run
sudo ./scripts/build-iso.sh

# Or use a local Ubuntu ISO
sudo ./scripts/build-iso.sh --source /path/to/ubuntu-24.04.2-live-server-amd64.iso
```

Output: `output/wtf-linux-2.0-amd64.iso`

### Validate the autoinstall

```bash
./scripts/validate-autoinstall.sh
```

## Testing in QEMU

The test script launches a QEMU VM with virtio disk and virtio-net:

```bash
# Graphical (serial output on stdout)
./scripts/test-iso.sh

# Headless (serial console only, no GUI window)
./scripts/test-iso.sh --headless

# Custom resources
./scripts/test-iso.sh --memory 4096 --disk 20G
```

SSH into the VM after installation completes:

```bash
ssh -p 2222 wtf@localhost
```

## VM Deployment

### Proxmox VE

1. Upload the ISO to a Proxmox storage (local, NFS, etc.)
2. Create a VM: VirtIO SCSI disk, VirtIO NIC, OVMF (UEFI) or SeaBIOS
3. Attach the ISO as CD/DVD and boot
4. After install, `qemu-guest-agent` reports IP/status to Proxmox automatically

### VMware ESXi

1. Upload the ISO to a datastore
2. Create a VM with Guest OS = Ubuntu 64-bit
3. Boot and install; `open-vm-tools` starts automatically

### Generic QEMU/KVM

```bash
qemu-img create -f qcow2 wtf-linux.qcow2 20G
qemu-system-x86_64 -m 2048 -enable-kvm -cpu host \
    -drive file=wtf-linux.qcow2,if=virtio,format=qcow2 \
    -device virtio-net-pci,netdev=n0 \
    -netdev user,id=n0,hostfwd=tcp::2222-:22 \
    -cdrom output/wtf-linux-2.0-amd64.iso -boot d \
    -serial mon:stdio
```

## Repository Structure

```
wtf-linux/
  autoinstall/
    user-data                  # Ubuntu autoinstall configuration (cloud-init)
    meta-data                  # Cloud-init meta-data (empty, required)
  preseed/
    wtf-linux.preseed          # Legacy Debian preseed (kept for reference)
  scripts/
    build-iso.sh               # ISO build script (run as root)
    validate-autoinstall.sh    # Autoinstall YAML validator
    validate-preseed.sh        # Legacy preseed linter (Debian)
    test-iso.sh                # QEMU test launcher (virtio)
  config/
    version                    # WTF Linux version (single source of truth)
    apt/sources.list           # APT sources (Ubuntu 24.04 Noble Numbat)
    ssh/sshd_config.d/
      wtf-linux.conf           # OpenSSH server defaults
  branding/
    motd                       # Login banner
  output/                      # Built ISOs (gitignored)
  cache/                       # Downloaded source ISOs (gitignored)
```

## Customization

**Add or remove packages:** Edit the `packages:` list in `autoinstall/user-data`, then rebuild.

**Change SSH defaults:** Edit `config/ssh/sshd_config.d/wtf-linux.conf`, then rebuild.

**Change branding:** Edit files in `branding/`, then rebuild.

**Change installer defaults:** Edit the autoinstall directives (locale, timezone, storage, identity, etc.) in `autoinstall/user-data`, then rebuild. The `interactive-sections` list controls which sections prompt the user interactively.

**Bump the version:** Edit `config/version` (format `X.Y` or `X.Y.Z`). The build script, boot menus, autoinstall `late-commands`, and `test-iso.sh` all read it, so there is no other version number to update.

## License

This project remasters the official Ubuntu Server installer. Ubuntu is a registered trademark of Canonical Ltd. WTF Linux is not affiliated with or endorsed by Canonical.
