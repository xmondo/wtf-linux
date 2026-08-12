# WTF Linux

A minimal amd64 Linux distribution based on Debian 13 (Trixie) for physical servers, workstations, and virtual machines. Installs from a bootable ISO with a fully interactive Debian installer, pre-filled with sensible defaults. Ships with OpenSSH server, hardware firmware (Intel, Realtek, Atheros), hypervisor guest agents, serial console, full filesystem support, and DNS utilities out of the box.

## Specifications

| Property | Value |
|----------|-------|
| Base | Debian 13 (Trixie) |
| Architecture | amd64 |
| Target | Physical x86_64 hardware and virtual machines (QEMU/KVM, Proxmox, VMware, Hyper-V) |
| Installer | Interactive Debian installer with pre-filled defaults |
| Boot modes | BIOS (ISOLINUX) and UEFI (GRUB), both with serial console |
| Default user | Set during install (user creates account interactively) |
| Root login | Disabled (sudo) |
| SSH | openssh-server, enabled on boot, port 22 |
| Serial console | ttyS0 @ 115200 baud (installer and installed system) |
| Package manager | APT (main, contrib, non-free, non-free-firmware) |
| Desktop | None (server/minimal) |

## Boot Menu

When booting the ISO, the installer presents (visible on both VGA and serial console):

```
WTF Linux 1.3.0 Installer

  Install                    <-- text-mode Debian installer (default)
  Advanced options ...
    Expert install           <-- full manual control
    Rescue mode              <-- recovery shell
    Automated install        <-- unattended, no prompts
```

The **Install** option walks through the standard Debian installation screens with WTF Linux defaults pre-selected. The installer prompts for ALL settings including hostname, network, DNS, and user account creation. The user can accept or change each setting.

## Included Packages

### Core

openssh-server, sudo, curl, wget, vim, htop, less, man-db, bash-completion, ca-certificates, gnupg, lsb-release, net-tools, iputils-ping, ufw

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
| firmware-linux | Metapackage for all free + non-free firmware |
| firmware-linux-nonfree | Non-free firmware blobs |
| firmware-linux-free | Free firmware blobs |
| firmware-realtek | Realtek NICs (RTL8111/8168/8169, USB) |
| firmware-iwlwifi | Intel Wireless (Wi-Fi 6/6E/7, AX/BE series) |
| firmware-atheros | Atheros/Qualcomm wireless adapters |
| firmware-misc-nonfree | Catch-all for remaining hardware drivers |

### Filesystems

| Package | Filesystem |
|---------|-----------|
| xfsprogs, xfsdump | XFS |
| e2fsprogs | ext2/ext3/ext4 |
| btrfs-progs | Btrfs |
| dosfstools | FAT/VFAT |

Storage management: lvm2, cryptsetup, dmsetup

Network filesystems: nfs-common, cifs-utils, sshfs, fuse3

Partitioning: parted, gdisk, fdisk

Hardware diagnostics: ethtool, pciutils

### DNS Utilities

bind9-host, bind9-dnsutils (dig, nslookup, nsupdate), whois, dnstracer, dns-root-data, ldnsutils (drill), libidn2-0, systemd-resolved

## Building the ISO

### Prerequisites

A Debian or Ubuntu build host with root access. Build dependencies (xorriso, isolinux, syslinux-utils, cpio, gzip, wget, file, imagemagick) are installed automatically if missing.

### Build

```bash
# Downloads Debian 13 netinst automatically on first run
sudo ./scripts/build-iso.sh

# Or use a local Debian ISO
sudo ./scripts/build-iso.sh --source /path/to/debian-13.6.0-amd64-netinst.iso
```

Output: `output/wtf-linux-1.3.0-amd64.iso`

### Validate the preseed

```bash
./scripts/validate-preseed.sh
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
ssh -p 2222 <user>@localhost
```

## VM Deployment

### Proxmox VE

1. Upload the ISO to a Proxmox storage (local, NFS, etc.)
2. Create a VM: VirtIO SCSI disk, VirtIO NIC, OVMF (UEFI) or SeaBIOS
3. Attach the ISO as CD/DVD and boot
4. After install, `qemu-guest-agent` reports IP/status to Proxmox automatically

### VMware ESXi

1. Upload the ISO to a datastore
2. Create a VM with Guest OS = Debian 13 (64-bit)
3. Boot and install; `open-vm-tools` starts automatically

### Generic QEMU/KVM

```bash
qemu-img create -f qcow2 wtf-linux.qcow2 20G
qemu-system-x86_64 -m 2048 -enable-kvm -cpu host \
    -drive file=wtf-linux.qcow2,if=virtio,format=qcow2 \
    -device virtio-net-pci,netdev=n0 \
    -netdev user,id=n0,hostfwd=tcp::2222-:22 \
    -cdrom output/wtf-linux-1.3.0-amd64.iso -boot d \
    -serial mon:stdio
```

## Repository Structure

```
wtf-linux/
  preseed/
    wtf-linux.preseed          # Debian preseed with WTF defaults
  scripts/
    build-iso.sh               # ISO build script (run as root)
    validate-preseed.sh        # Preseed linter
    test-iso.sh                # QEMU test launcher (virtio)
  config/
    version                    # WTF Linux version (single source of truth)
    apt/sources.list           # APT sources (Debian 13 Trixie)
    ssh/sshd_config.d/
      wtf-linux.conf           # OpenSSH server defaults
  branding/
    motd                       # Login banner
  output/                      # Built ISOs (gitignored)
  cache/                       # Downloaded source ISOs (gitignored)
```

## Customization

**Add or remove packages:** Edit the `d-i pkgsel/include` list in `preseed/wtf-linux.preseed`, then rebuild.

**Change SSH defaults:** Edit `config/ssh/sshd_config.d/wtf-linux.conf`, then rebuild.

**Change branding:** Edit files in `branding/`, then rebuild.

**Change installer defaults:** Edit the preseed directives (locale, timezone, mirror, hostname, etc.) in `preseed/wtf-linux.preseed`, then rebuild.

**Bump the version:** Edit `config/version` (format `X.Y.Z`). The build script, boot menus, preseed `late_command`, and `test-iso.sh` all read it, so there is no other version number to update.

## License

This project remasters the official Debian installer. Debian is a registered trademark of Software in the Public Interest, Inc. WTF Linux is not affiliated with or endorsed by the Debian project.
