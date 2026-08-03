# WTF Linux

A minimal amd64 Linux distribution based on Debian 13 (Trixie). Installs from a bootable ISO with a standard interactive Debian installer, pre-filled with sensible defaults. Ships with OpenSSH server, all ethernet drivers, full filesystem support, and DNS utilities out of the box.

## Specifications

| Property | Value |
|----------|-------|
| Base | Debian 13 (Trixie) |
| Architecture | amd64 |
| Installer | Interactive Debian installer with pre-filled defaults |
| Boot modes | BIOS (ISOLINUX) and UEFI (GRUB) |
| Default user | `wtf` (user sets password during install) |
| Root login | Disabled (sudo) |
| SSH | openssh-server, enabled on boot, port 22 |
| Package manager | APT (main, contrib, non-free, non-free-firmware) |
| Desktop | None (server/minimal) |

## Boot Menu

When booting the ISO, the installer presents:

```
WTF Linux 1.2 Installer

  Graphical install          <-- graphical Debian installer
  Install                    <-- text-mode Debian installer (default)
  Advanced options ...
    Expert install           <-- full manual control
    Rescue mode              <-- recovery shell
    Automated install        <-- unattended, no prompts
```

The **Graphical install** and **Install** options walk through the standard Debian installation screens (language, disk, user account, etc.) with WTF Linux defaults pre-selected. The user can accept or change each setting.

## Included Packages

### Core

openssh-server, sudo, curl, wget, vim, htop, less, man-db, bash-completion, ca-certificates, gnupg, lsb-release, apt-transport-https, net-tools, iputils-ping, ufw

### Ethernet Drivers and Firmware

All major NIC vendors are covered:

| Package | Coverage |
|---------|----------|
| firmware-linux | Metapackage (all free + non-free firmware) |
| firmware-realtek | RTL8111/8168/8169, USB NICs |
| firmware-intel-misc | Intel NIC microcode |
| firmware-bnx2 | Broadcom NetXtreme II (1GbE) |
| firmware-bnx2x | Broadcom NetXtreme II (10GbE) |
| firmware-netronome | Netronome SmartNICs |
| firmware-qlogic | QLogic converged/Fibre Channel |
| firmware-cavium | Cavium/Marvell LiquidIO, ThunderX |
| firmware-myricom | Myricom Myri-10G |
| firmware-misc-nonfree | Catch-all for remaining drivers |

Hardware diagnostics: ethtool, pciutils, usbutils

### Filesystems

| Package | Filesystem |
|---------|-----------|
| xfsprogs, xfsdump, xfslibs-dev | XFS (full suite) |
| e2fsprogs | ext2/ext3/ext4 |
| btrfs-progs | Btrfs |
| dosfstools | FAT/VFAT |
| ntfs-3g | NTFS (read/write) |
| exfatprogs | exFAT |
| f2fs-tools | F2FS |
| jfsutils | JFS |
| reiserfsprogs | ReiserFS |
| hfsprogs, hfsplus, hfsutils | HFS/HFS+ |
| nilfs-tools | NILFS2 |
| udftools | UDF |
| squashfs-tools | SquashFS |
| erofs-utils | EROFS |

Storage management: lvm2, mdadm, cryptsetup, dmsetup, multipath-tools

Network filesystems: nfs-common, cifs-utils, sshfs, fuse3

Partitioning: parted, gdisk, fdisk

### DNS Utilities

dnsutils (dig, nslookup, nsupdate), bind9-host, bind9-dnsutils, whois, dnstracer, dns-root-data, ldnsutils (drill), libidn2-0, resolvconf, systemd-resolved

## Building the ISO

### Prerequisites

A Debian or Ubuntu build host with root access. Build dependencies (xorriso, isolinux, syslinux-utils, cpio, gzip, wget, file) are installed automatically if missing.

### Build

```bash
# Downloads Debian 13 netinst automatically on first run
sudo ./scripts/build-iso.sh

# Or use a local Debian ISO
sudo ./scripts/build-iso.sh --source /path/to/debian-13.6.0-amd64-netinst.iso
```

Output: `output/wtf-linux-1.2-amd64.iso`

### Validate the preseed

```bash
./scripts/validate-preseed.sh
```

## Writing to USB

```bash
sudo dd if=output/wtf-linux-1.2-amd64.iso of=/dev/sdX bs=4M status=progress
```

## Testing in QEMU

```bash
# Graphical
./scripts/test-iso.sh

# Headless (serial console)
./scripts/test-iso.sh --headless

# Custom resources
./scripts/test-iso.sh --memory 4096 --disk 20G
```

SSH into the VM after installation completes:

```bash
ssh -p 2222 wtf@localhost
```

## Repository Structure

```
wtf-linux/
  preseed/
    wtf-linux.preseed          # Debian preseed with WTF defaults
  scripts/
    build-iso.sh               # ISO build script (run as root)
    validate-preseed.sh        # Preseed linter
    test-iso.sh                # QEMU test launcher
  config/
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

## License

This project remasters the official Debian installer. Debian is a registered trademark of Software in the Public Interest, Inc. WTF Linux is not affiliated with or endorsed by the Debian project.
