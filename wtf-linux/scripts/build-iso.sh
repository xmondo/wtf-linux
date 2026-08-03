#!/usr/bin/env bash
# =============================================================================
# WTF Linux ISO Builder
# Remaster a Debian 13 (Trixie) netinst ISO into a WTF Linux installer ISO.
#
# Requirements (installed automatically if missing):
#   xorriso, isolinux, syslinux-utils, cpio, gzip, wget, file
#
# Usage:
#   sudo ./scripts/build-iso.sh [--source /path/to/debian.iso]
#
# If --source is not provided the script downloads the latest Debian 13
# netinst amd64 ISO automatically.
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CACHE_DIR="${PROJECT_DIR}/cache"
OUTPUT_DIR="${PROJECT_DIR}/output"
WORK_DIR="${PROJECT_DIR}/isowork"
MOUNT_DIR="${PROJECT_DIR}/isomount"
PRESEED_FILE="${PROJECT_DIR}/preseed/wtf-linux.preseed"

DEBIAN_VERSION="13"
DEBIAN_CODENAME="trixie"
DEBIAN_ARCH="amd64"
DEBIAN_MIRROR="https://cdimage.debian.org/cdimage/release/${DEBIAN_VERSION}.0"
DEBIAN_ISO_NAME="debian-${DEBIAN_VERSION}.0-${DEBIAN_ARCH}-netinst.iso"
DEBIAN_ISO_URL="${DEBIAN_MIRROR}/${DEBIAN_ARCH}/iso-cd/${DEBIAN_ISO_NAME}"

WTF_VERSION="1.0"
WTF_ISO_NAME="wtf-linux-${WTF_VERSION}-${DEBIAN_ARCH}.iso"
WTF_ISO_LABEL="WTF_Linux_${WTF_VERSION}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[WTF-BUILD] $*"; }
die()  { echo "[WTF-BUILD] ERROR: $*" >&2; exit 1; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root (sudo)."
    fi
}

install_deps() {
    log "Checking build dependencies..."
    local deps=(xorriso isolinux syslinux-utils cpio gzip wget file)
    local missing=()
    for pkg in "${deps[@]}"; do
        if ! dpkg -l "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log "Installing missing packages: ${missing[*]}"
        apt-get update -qq
        apt-get install -y -qq "${missing[@]}"
    fi
    log "All dependencies satisfied."
}

cleanup() {
    log "Cleaning up..."
    umount "$MOUNT_DIR" 2>/dev/null || true
    rm -rf "$WORK_DIR" "$MOUNT_DIR"
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
SOURCE_ISO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --source) SOURCE_ISO="$2"; shift 2 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
check_root
trap cleanup EXIT

install_deps

mkdir -p "$CACHE_DIR" "$OUTPUT_DIR"

# --- Download Debian ISO if needed ---
if [[ -z "$SOURCE_ISO" ]]; then
    SOURCE_ISO="${CACHE_DIR}/${DEBIAN_ISO_NAME}"
    if [[ ! -f "$SOURCE_ISO" ]]; then
        log "Downloading Debian ${DEBIAN_VERSION} netinst ISO..."
        log "URL: ${DEBIAN_ISO_URL}"
        wget --no-verbose --show-progress -O "$SOURCE_ISO" "$DEBIAN_ISO_URL" || \
            die "Failed to download Debian ISO. You can manually download it and pass --source /path/to/iso"
    else
        log "Using cached Debian ISO: ${SOURCE_ISO}"
    fi
fi

[[ -f "$SOURCE_ISO" ]] || die "Source ISO not found: ${SOURCE_ISO}"

# --- Extract the ISO ---
log "Extracting source ISO..."
rm -rf "$WORK_DIR" "$MOUNT_DIR"
mkdir -p "$MOUNT_DIR" "$WORK_DIR"

mount -o loop,ro "$SOURCE_ISO" "$MOUNT_DIR"
cp -a "$MOUNT_DIR"/. "$WORK_DIR"/
umount "$MOUNT_DIR"
rmdir "$MOUNT_DIR"

# Make the extracted tree writable
chmod -R u+w "$WORK_DIR"

# --- Inject preseed ---
log "Injecting WTF Linux preseed configuration..."
cp "$PRESEED_FILE" "$WORK_DIR/preseed.cfg"

# --- Modify ISOLINUX boot menu for automated install ---
log "Configuring boot menu for automated install..."

# BIOS boot (isolinux)
if [[ -f "$WORK_DIR/isolinux/isolinux.cfg" ]]; then
    cat > "$WORK_DIR/isolinux/isolinux.cfg" <<'ISOLINUX_CFG'
# WTF Linux ISOLINUX configuration
default wtf-install
timeout 50
prompt 1

display boot.msg

label wtf-install
    menu label ^Install WTF Linux
    kernel /install.amd/vmlinuz
    append auto=true priority=critical preseed/file=/cdrom/preseed.cfg initrd=/install.amd/initrd.gz --- quiet

label expert
    menu label ^Expert Install
    kernel /install.amd/vmlinuz
    append priority=low initrd=/install.amd/initrd.gz ---
ISOLINUX_CFG
fi

# Boot splash message
cat > "$WORK_DIR/isolinux/boot.msg" <<'BOOTMSG'

 __        _______ _____   _     _
 \ \      / /_   _|  ___| | |   (_)_ __  _   ___  __
  \ \ /\ / /  | | | |_    | |   | | '_ \| | | \ \/ /
   \ V  V /   | | |  _|   | |___| | | | | |_| |>  <
    \_/\_/    |_| |_|     |_____|_|_| |_|\__,_/_/\_\

  WTF Linux 1.0 Installer
  Based on Debian 13 (Trixie) - amd64

  Press ENTER to start automated installation
  Type 'expert' for manual expert install

BOOTMSG

# UEFI boot (GRUB)
if [[ -f "$WORK_DIR/boot/grub/grub.cfg" ]]; then
    cat > "$WORK_DIR/boot/grub/grub.cfg" <<'GRUB_CFG'
# WTF Linux GRUB configuration (UEFI)
set default=0
set timeout=5

menuentry "Install WTF Linux" {
    linux /install.amd/vmlinuz auto=true priority=critical preseed/file=/cdrom/preseed.cfg --- quiet
    initrd /install.amd/initrd.gz
}

menuentry "Expert Install" {
    linux /install.amd/vmlinuz priority=low ---
    initrd /install.amd/initrd.gz
}
GRUB_CFG
fi

# --- Inject branding files into the ISO for late_command to copy ---
log "Adding WTF Linux branding..."
mkdir -p "$WORK_DIR/wtf-linux"
cp "${PROJECT_DIR}/branding/motd" "$WORK_DIR/wtf-linux/motd"
cp "${PROJECT_DIR}/config/apt/sources.list" "$WORK_DIR/wtf-linux/sources.list"
cp "${PROJECT_DIR}/config/ssh/sshd_config.d/wtf-linux.conf" "$WORK_DIR/wtf-linux/sshd-wtf-linux.conf"

# --- Update preseed late_command to copy branding from ISO ---
# Append copy commands to the preseed
cat >> "$WORK_DIR/preseed.cfg" <<'EXTRA_LATE'

# Additional late commands to install branding from ISO media
d-i preseed/late_command string \
    in-target systemctl enable ssh ; \
    cp /cdrom/wtf-linux/motd /target/etc/motd ; \
    cp /cdrom/wtf-linux/sources.list /target/etc/apt/sources.list ; \
    mkdir -p /target/etc/ssh/sshd_config.d ; \
    cp /cdrom/wtf-linux/sshd-wtf-linux.conf /target/etc/ssh/sshd_config.d/wtf-linux.conf ; \
    mkdir -p /target/etc/wtf-linux ; \
    echo 'WTF Linux 1.0 (based on Debian 13 Trixie)' > /target/etc/wtf-linux/version ; \
    echo 'wtf-linux' > /target/etc/hostname ; \
    printf 'WTF Linux 1.0 \\n \\l\n' > /target/etc/issue ; \
    echo 'Welcome to WTF Linux 1.0' > /target/etc/issue.net ; \
    printf 'PRETTY_NAME="WTF Linux 1.0"\nNAME="WTF Linux"\nVERSION="1.0"\nID=wtf-linux\nID_LIKE=debian\nHOME_URL="https://github.com/xmondo/wtf-linux"\nBUG_REPORT_URL="https://github.com/xmondo/wtf-linux/issues"\n' > /target/etc/wtf-release ;
EXTRA_LATE

# --- Regenerate md5sums ---
log "Regenerating MD5 checksums..."
(cd "$WORK_DIR" && find . -follow -type f ! -name md5sum.txt ! -path './isolinux/*' -print0 | xargs -0 md5sum > md5sum.txt)

# --- Build the new ISO ---
log "Building WTF Linux ISO..."
xorriso -as mkisofs \
    -r -J \
    -V "$WTF_ISO_LABEL" \
    -o "${OUTPUT_DIR}/${WTF_ISO_NAME}" \
    -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -boot-load-size 4 \
    -boot-info-table \
    -no-emul-boot \
    -eltorito-alt-boot \
    -e boot/grub/efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    "$WORK_DIR"

log "============================================="
log "WTF Linux ISO built successfully!"
log "Output: ${OUTPUT_DIR}/${WTF_ISO_NAME}"
log "Size: $(du -h "${OUTPUT_DIR}/${WTF_ISO_NAME}" | cut -f1)"
log "============================================="
log ""
log "To write to USB: sudo dd if=${OUTPUT_DIR}/${WTF_ISO_NAME} of=/dev/sdX bs=4M status=progress"
log "To test in VM:   qemu-system-x86_64 -m 2048 -cdrom ${OUTPUT_DIR}/${WTF_ISO_NAME} -boot d"
