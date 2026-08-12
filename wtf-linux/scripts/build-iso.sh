#!/usr/bin/env bash
# =============================================================================
# WTF Linux ISO Builder
# Remaster an Ubuntu 24.04 LTS (Noble Numbat) live server ISO into a
# WTF Linux installer ISO with autoinstall configuration.
#
# Requirements (installed automatically if missing):
#   xorriso, p7zip-full, wget, file, imagemagick, fdisk
#
# Usage:
#   sudo ./scripts/build-iso.sh [--source /path/to/ubuntu.iso]
#
# If --source is not provided the script downloads the latest Ubuntu 24.04
# LTS Server amd64 ISO automatically.
# =============================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[WTF-BUILD] $*"; }
die()  { echo "[WTF-BUILD] ERROR: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CACHE_DIR="${PROJECT_DIR}/cache"
OUTPUT_DIR="${PROJECT_DIR}/output"
WORK_DIR="${PROJECT_DIR}/isowork"
MOUNT_DIR="${PROJECT_DIR}/isomount"
AUTOINSTALL_DIR="${PROJECT_DIR}/autoinstall"

UBUNTU_VERSION="24.04.4"
UBUNTU_CODENAME="noble"
UBUNTU_RELEASE="24.04"
UBUNTU_ARCH="amd64"
UBUNTU_MIRROR="https://releases.ubuntu.com/${UBUNTU_RELEASE}"
UBUNTU_ISO_NAME="ubuntu-${UBUNTU_VERSION}-live-server-${UBUNTU_ARCH}.iso"
UBUNTU_ISO_URL="${UBUNTU_MIRROR}/${UBUNTU_ISO_NAME}"

VERSION_FILE="${PROJECT_DIR}/config/version"
WTF_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [[ ! "$WTF_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    die "Invalid version '${WTF_VERSION}' in ${VERSION_FILE} (expected X.Y or X.Y.Z)"
fi
WTF_ISO_NAME="wtf-linux-${WTF_VERSION}-${UBUNTU_ARCH}.iso"
WTF_ISO_LABEL="WTF_Linux_${WTF_VERSION}"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root (sudo)."
    fi
}

install_deps() {
    log "Checking build dependencies..."
    local deps=(xorriso p7zip-full wget file imagemagick fdisk)
    local missing=()
    for pkg in "${deps[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null; then
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

# --- Download Ubuntu ISO if needed ---
if [[ -z "$SOURCE_ISO" ]]; then
    SOURCE_ISO="${CACHE_DIR}/${UBUNTU_ISO_NAME}"
    if [[ ! -f "$SOURCE_ISO" ]]; then
        log "Downloading Ubuntu ${UBUNTU_VERSION} live server ISO..."
        log "URL: ${UBUNTU_ISO_URL}"
        wget --no-verbose --show-progress -O "$SOURCE_ISO" "$UBUNTU_ISO_URL" || \
            die "Failed to download Ubuntu ISO. You can manually download it and pass --source /path/to/iso"
    else
        log "Using cached Ubuntu ISO: ${SOURCE_ISO}"
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

# --- Inject autoinstall configuration ---
log "Injecting WTF Linux autoinstall configuration..."
mkdir -p "$WORK_DIR/autoinstall"

# Template the version placeholder (@WTF_VERSION@) in user-data
sed "s|@WTF_VERSION@|${WTF_VERSION}|g" "$AUTOINSTALL_DIR/user-data" > "$WORK_DIR/autoinstall/user-data"
cp "$AUTOINSTALL_DIR/meta-data" "$WORK_DIR/autoinstall/meta-data"

# --- Inject branding and config files into autoinstall directory ---
# These are copied to the target system by autoinstall late-commands
log "Adding WTF Linux branding and configuration files..."
sed -e "s|@WTF_VERSION@|${WTF_VERSION}|g" \
    -e "s|@UBUNTU_RELEASE@|${UBUNTU_RELEASE}|g" \
    -e "s|@UBUNTU_CODENAME@|${UBUNTU_CODENAME^}|g" \
    "${PROJECT_DIR}/branding/motd" > "$WORK_DIR/autoinstall/motd"
cp "${PROJECT_DIR}/config/apt/sources.list" "$WORK_DIR/autoinstall/sources.list"
cp "${PROJECT_DIR}/config/ssh/sshd_config.d/wtf-linux.conf" "$WORK_DIR/autoinstall/sshd-wtf-linux.conf"

# --- Modify GRUB boot menu to include autoinstall parameters ---
log "Configuring GRUB boot menu..."

if [[ -f "$WORK_DIR/boot/grub/grub.cfg" ]]; then
    cat > "$WORK_DIR/boot/grub/grub.cfg" <<'GRUB_CFG'
# WTF Linux GRUB configuration (Ubuntu 24.04 LTS interactive install)

set default=0
set timeout=30

if loadfont /boot/grub/font.pf2 ; then
    set gfxmode=800x600
    set gfxpayload=keep
    insmod efi_gop
    insmod efi_uga
    insmod video_bochs
    insmod video_cirrus
    insmod gfxterm
    insmod png
    terminal_output gfxterm
fi

set menu_color_normal=cyan/blue
set menu_color_highlight=white/blue

menuentry "Install WTF Linux" {
    set gfxpayload=keep
    linux /casper/vmlinuz autoinstall ds=nocloud\;s=/cdrom/autoinstall/ ---
    initrd /casper/initrd
}

menuentry "Install WTF Linux (manual, no defaults)" {
    set gfxpayload=keep
    linux /casper/vmlinuz ---
    initrd /casper/initrd
}

menuentry "Try Ubuntu without installing" {
    set gfxpayload=keep
    linux /casper/vmlinuz boot=casper ---
    initrd /casper/initrd
}

menuentry "Boot from first hard disk" {
    set root=(hd0)
    chainloader +1
}
GRUB_CFG
fi

# Also update the UEFI GRUB config if it exists in a different location
if [[ -f "$WORK_DIR/boot/grub/loopback.cfg" ]]; then
    cat > "$WORK_DIR/boot/grub/loopback.cfg" <<'LOOPBACK_CFG'
menuentry "Install WTF Linux" {
    set gfxpayload=keep
    linux /casper/vmlinuz autoinstall ds=nocloud\;s=/cdrom/autoinstall/ ---
    initrd /casper/initrd
}
LOOPBACK_CFG
fi

# --- Boot splash message ---
log "Installing boot splash text..."
mkdir -p "$WORK_DIR/isolinux" 2>/dev/null || true
cat > "$WORK_DIR/isolinux/boot.msg" <<BOOTMSG

 __        _______ _____   _     _
 \ \      / /_   _|  ___| | |   (_)_ __  _   ___  __
  \ \ /\ / /  | | | |_    | |   | | '_ \| | | \ \/ /
   \ V  V /   | | |  _|   | |___| | | | | |_| |>  <
    \_/\_/    |_| |_|     |_____|_|_| |_|\__,_/_/\_\\

  WTF Linux ${WTF_VERSION} Installer
  Based on Ubuntu ${UBUNTU_RELEASE} LTS (${UBUNTU_CODENAME^}) - amd64

BOOTMSG

# --- Update ISOLINUX/syslinux if present (BIOS boot) ---
if [[ -f "$WORK_DIR/isolinux/isolinux.cfg" ]] || [[ -f "$WORK_DIR/isolinux/txt.cfg" ]]; then
    log "Configuring ISOLINUX boot menu..."

    if [[ -f "$WORK_DIR/isolinux/txt.cfg" ]]; then
        cat > "$WORK_DIR/isolinux/txt.cfg" <<TXTCFG
default wtfinstall
label wtfinstall
  menu label ^Install WTF Linux
  kernel /casper/vmlinuz
  append initrd=/casper/initrd autoinstall ds=nocloud;s=/cdrom/autoinstall/ ---
label manual
  menu label ^Install WTF Linux (manual, no defaults)
  kernel /casper/vmlinuz
  append initrd=/casper/initrd ---
TXTCFG
    fi

    if [[ -f "$WORK_DIR/isolinux/isolinux.cfg" ]]; then
        cat > "$WORK_DIR/isolinux/isolinux.cfg" <<'ISOLINUX_CFG'
# WTF Linux ISOLINUX configuration
default vesamenu.c32
timeout 300
prompt 0

include txt.cfg
ISOLINUX_CFG
    fi
fi

# --- Regenerate md5sums ---
log "Regenerating MD5 checksums..."
MD5_TMP="$(mktemp "${PROJECT_DIR}/md5sum.XXXXXX")"
(cd "$WORK_DIR" && find . -type f -not -name md5sum.txt -not -path './isolinux/*' -print0 | xargs -0 md5sum > "$MD5_TMP")
mv "$MD5_TMP" "$WORK_DIR/md5sum.txt"

# --- Build the new ISO ---
log "Building WTF Linux ISO..."

# Extract the exact El-Torito / GPT boot parameters from the source ISO.
# xorriso -report_el_torito as_mkisofs prints the flags needed to reproduce
# the same boot layout.  We need two values:
#   1) The --interval for -append_partition 2  (EFI system partition image)
#   2) The -e argument for the second El-Torito entry (appended partition ref)
log "Extracting boot parameters from source ISO..."
ELTORITO_OUTPUT="$(xorriso -indev "$SOURCE_ISO" -report_el_torito as_mkisofs 2>&1)"

# Grab the EFI partition interval  (e.g. 6640484d-6650643d)
EFI_APPEND_INTERVAL="$(echo "$ELTORITO_OUTPUT" | grep -- '-append_partition 2' | sed "s/.*--interval:local_fs:\([^:]*\)::.*/\1/")"
if [[ -z "$EFI_APPEND_INTERVAL" ]]; then
    die "Could not extract EFI partition interval from source ISO"
fi

# Grab the -e flag for the EFI El-Torito entry
# (e.g. --interval:appended_partition_2_start_1660121s_size_10160d:all::)
EFI_ELTORITO_E="$(echo "$ELTORITO_OUTPUT" | grep "^-e " | sed "s/^-e '//;s/'$//")"
if [[ -z "$EFI_ELTORITO_E" ]]; then
    die "Could not extract EFI El-Torito entry from source ISO"
fi

# Grab the -boot-load-size for the EFI entry (e.g. 10160)
EFI_BOOT_LOAD_SIZE="$(echo "$ELTORITO_OUTPUT" | grep -A2 "^-e " | grep 'boot-load-size' | sed 's/.*-boot-load-size //')"
if [[ -z "$EFI_BOOT_LOAD_SIZE" ]]; then
    EFI_BOOT_LOAD_SIZE="10160"
fi

log "EFI partition interval: ${EFI_APPEND_INTERVAL}"
log "EFI El-Torito entry:    ${EFI_ELTORITO_E}"
log "EFI boot-load-size:     ${EFI_BOOT_LOAD_SIZE}"

# Build ISO with xorriso -- Ubuntu live server ISO structure
xorriso -as mkisofs \
    -r -J \
    -V "$WTF_ISO_LABEL" \
    -o "${OUTPUT_DIR}/${WTF_ISO_NAME}" \
    --grub2-mbr "--interval:local_fs:0s-15s:zero_mbrpt,zero_gpt:${SOURCE_ISO}" \
    --protective-msdos-label \
    -partition_cyl_align off \
    -partition_offset 16 \
    --mbr-force-bootable \
    -append_partition 2 28732ac11ff8d211ba4b00a0c93ec93b \
        "--interval:local_fs:${EFI_APPEND_INTERVAL}::${SOURCE_ISO}" \
    -appended_part_as_gpt \
    -iso_mbr_part_type a2a0d0ebe5b9334487c068b6b72699c7 \
    -c '/boot.catalog' \
    -b '/boot/grub/i386-pc/eltorito.img' \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    --grub2-boot-info \
    -eltorito-alt-boot \
    -e "${EFI_ELTORITO_E}" \
    -no-emul-boot \
    -boot-load-size "$EFI_BOOT_LOAD_SIZE" \
    "$WORK_DIR"

log "============================================="
log "WTF Linux ISO built successfully!"
log "Output: ${OUTPUT_DIR}/${WTF_ISO_NAME}"
log "Size: $(du -h "${OUTPUT_DIR}/${WTF_ISO_NAME}" | cut -f1)"
log "============================================="
log ""
log "To test in QEMU:  ./scripts/test-iso.sh"
log "To test headless:  ./scripts/test-iso.sh --headless"
