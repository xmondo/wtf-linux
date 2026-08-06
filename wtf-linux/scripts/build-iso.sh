#!/usr/bin/env bash
# =============================================================================
# WTF Linux ISO Builder
# Remaster a Debian 13 (Trixie) netinst ISO into a WTF Linux installer ISO.
#
# Requirements (installed automatically if missing):
#   xorriso, isolinux, syslinux-utils, cpio, gzip, wget, file, imagemagick
#
# Usage:
#   sudo ./scripts/build-iso.sh [--source /path/to/debian.iso]
#
# If --source is not provided the script downloads the latest Debian 13
# netinst amd64 ISO automatically.
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
PRESEED_FILE="${PROJECT_DIR}/preseed/wtf-linux.preseed"

DEBIAN_VERSION="13.6.0"
DEBIAN_CODENAME="trixie"
DEBIAN_MAJOR="${DEBIAN_VERSION%%.*}"
DEBIAN_ARCH="amd64"
DEBIAN_MIRROR="https://cdimage.debian.org/cdimage/release/${DEBIAN_VERSION}"
DEBIAN_ISO_NAME="debian-${DEBIAN_VERSION}-${DEBIAN_ARCH}-netinst.iso"
DEBIAN_ISO_URL="${DEBIAN_MIRROR}/${DEBIAN_ARCH}/iso-cd/${DEBIAN_ISO_NAME}"

VERSION_FILE="${PROJECT_DIR}/config/version"
WTF_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [[ ! "$WTF_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "Invalid version '${WTF_VERSION}' in ${VERSION_FILE} (expected X.Y.Z)"
fi
WTF_ISO_NAME="wtf-linux-${WTF_VERSION}-${DEBIAN_ARCH}.iso"
WTF_ISO_LABEL="WTF_Linux_${WTF_VERSION}"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root (sudo)."
    fi
}

install_deps() {
    log "Checking build dependencies..."
    local deps=(xorriso isolinux syslinux-utils cpio gzip wget file imagemagick)
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
    [[ -n "${MD5_TMP:-}" ]] && rm -f "$MD5_TMP"
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
# Template the version placeholder (@WTF_VERSION@) from config/version
sed "s|@WTF_VERSION@|${WTF_VERSION}|g" "$PRESEED_FILE" > "$WORK_DIR/preseed.cfg"

# --- Replace installer splash text in initrd ---
log "Replacing Debian installer splash with WTF Linux branding..."
INITRD_WORK=$(mktemp -d "${WORK_DIR}/initrd.XXXXXX")

# Extract initrd
(cd "$INITRD_WORK" && gzip -dc "$WORK_DIR/install.amd/initrd.gz" | cpio -id --quiet 2>/dev/null)

# Replace the installer splash/banner text if present
# The Debian installer uses /usr/share/graphics/logo_debian.png for graphical
# installs and displays version info from various places.
# For text-mode installs the key branding is in the preseed and boot menu,
# but we can also replace the installer's internal banner strings.

# Create a WTF Linux text banner for the installer
if [[ -d "$INITRD_WORK/usr/share/debian-installer" ]]; then
    echo "WTF Linux ${WTF_VERSION} Installer" > "$INITRD_WORK/usr/share/debian-installer/build-id" 2>/dev/null || true
fi

# Replace the Debian logo with the WTF Linux splash image
if [[ -d "$INITRD_WORK/usr/share/graphics" ]]; then
    log "Converting branding/desolate_city.jpg to PNG and replacing logo_debian.png in initrd..."
    convert "${PROJECT_DIR}/branding/desolate_city.jpg" "$INITRD_WORK/usr/share/graphics/logo_debian.png"
    log "Installer splash image replaced with desolate_city.jpg."
fi

# Inject the preseed into the initrd as well (belt and suspenders --
# the preseed is also on /cdrom but having it in the initrd ensures
# it is found during early installer stages)
sed "s|@WTF_VERSION@|${WTF_VERSION}|g" "$PRESEED_FILE" > "$INITRD_WORK/preseed.cfg"

# Repack initrd
(cd "$INITRD_WORK" && find . | cpio -H newc -o --quiet | gzip -9 > "$WORK_DIR/install.amd/initrd.gz")
rm -rf "$INITRD_WORK"
log "Initrd repacked with WTF Linux branding and preseed."

# --- Modify ISOLINUX boot menu for interactive install ---
log "Configuring boot menu for interactive install with WTF defaults..."

# Generate ISOLINUX splash image (640x480 PNG for vesamenu.c32)
log "Converting branding/desolate_city.jpg to 640x480 PNG for ISOLINUX splash..."
convert "${PROJECT_DIR}/branding/desolate_city.jpg" -resize 640x480! "$WORK_DIR/isolinux/splash.png"
log "ISOLINUX splash image installed."

# BIOS boot (isolinux)
if [[ -f "$WORK_DIR/isolinux/isolinux.cfg" ]]; then
    cat > "$WORK_DIR/isolinux/isolinux.cfg" <<'ISOLINUX_CFG'
# WTF Linux ISOLINUX configuration
default vesamenu.c32
timeout 0
prompt 0
display boot.msg

include menu.cfg
ISOLINUX_CFG

    # Create the menu configuration
    cat > "$WORK_DIR/isolinux/menu.cfg" <<MENUCFG
menu hshift 0
menu width 82

menu title WTF Linux ${WTF_VERSION} Installer
include stdmenu.cfg
include wtf.cfg

menu begin advanced
    menu title Advanced options
    include stdmenu.cfg

    label expert
        menu label ^Expert install
        kernel /install.amd/vmlinuz
        append priority=low initrd=/install.amd/initrd.gz ---

    label rescue
        menu label ^Rescue mode
        kernel /install.amd/vmlinuz
        append rescue/enable=true priority=low initrd=/install.amd/initrd.gz ---

    label auto
        menu label ^Automated install (unattended)
        kernel /install.amd/vmlinuz
        append auto=true priority=critical preseed/file=/cdrom/preseed.cfg initrd=/install.amd/initrd.gz ---

    menu end
MENUCFG

    # Create the WTF Linux menu entries
    cat > "$WORK_DIR/isolinux/wtf.cfg" <<'WTFCFG'
label install
    menu label ^Install
    menu default
    kernel /install.amd/vmlinuz
    append preseed/file=/cdrom/preseed.cfg initrd=/install.amd/initrd.gz ---
WTFCFG

    # Always overwrite stdmenu.cfg -- the Debian source ISO ships its own
    # version which may include directives that pull in graphical-installer
    # menu entries (gtk.cfg, etc.).  We must replace it unconditionally.
    cat > "$WORK_DIR/isolinux/stdmenu.cfg" <<'STDMENU'
menu background splash.png
menu color title    * #FFFFFFFF *
menu color border   * #00000000 #00000000 none
menu color sel      * #ffffffff #76a1d0ff *
menu color hotsel   1;7;37;40 #ffffffff #76a1d0ff *
menu color tabmsg   * #ffffffff #00000000 *
menu color help     37;40 #ffdddd00 #00000000 none
menu vshift 12
menu rows 10
menu helpmsgrow 15
menu cmdlinerow 16
menu timeoutrow 16
menu tabmsgrow 18
menu tabmsg Press ENTER to boot or TAB to edit a menu entry
STDMENU

    # Remove ALL leftover Debian .cfg files from isolinux/ except the four
    # we explicitly generate (isolinux.cfg, menu.cfg, wtf.cfg, stdmenu.cfg).
    # Previous builds used a hardcoded list of stale filenames, but Debian
    # point releases can introduce new .cfg files (gtk.cfg, adgtk.cfg,
    # spkgtk.cfg, txt.cfg, drk.cfg, spk.cfg, etc.) that sneak graphical-
    # installer or other unwanted menu entries back into the boot menu.
    log "Removing ALL leftover Debian .cfg files from isolinux/..."
    keep_cfgs="isolinux.cfg|menu.cfg|wtf.cfg|stdmenu.cfg"
    find "$WORK_DIR/isolinux" -maxdepth 1 -name '*.cfg' \
        | grep -Ev "/($keep_cfgs)$" \
        | while read -r stale; do
            log "  removing $(basename "$stale")"
            rm -f "$stale"
        done
fi

# Boot splash message
cat > "$WORK_DIR/isolinux/boot.msg" <<BOOTMSG

 __        _______ _____   _     _
 \ \      / /_   _|  ___| | |   (_)_ __  _   ___  __
  \ \ /\ / /  | | | |_    | |   | | '_ \| | | \ \/ /
   \ V  V /   | | |  _|   | |___| | | | | |_| |>  <
    \_/\_/    |_| |_|     |_____|_|_| |_|\__,_/_/\_\

  WTF Linux ${WTF_VERSION} Installer
  Based on Debian ${DEBIAN_MAJOR} (${DEBIAN_CODENAME^}) - amd64

BOOTMSG

# Generate GRUB splash image
log "Copying splash image for GRUB (UEFI) boot menu..."
convert "${PROJECT_DIR}/branding/desolate_city.jpg" "$WORK_DIR/boot/grub/splash.png"
log "GRUB splash image installed."

# UEFI boot (GRUB)
if [[ -f "$WORK_DIR/boot/grub/grub.cfg" ]]; then
    cat > "$WORK_DIR/boot/grub/grub.cfg" <<'GRUB_CFG'
# WTF Linux GRUB configuration (UEFI)

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
    background_image /boot/grub/splash.png
fi

set menu_color_normal=cyan/blue
set menu_color_highlight=white/blue
set timeout=-1

menuentry --hotkey=i "Install" {
    linux /install.amd/vmlinuz preseed/file=/cdrom/preseed.cfg ---
    initrd /install.amd/initrd.gz
}

submenu --hotkey=a "Advanced options ..." {

    menuentry "Expert install" {
        linux /install.amd/vmlinuz priority=low ---
        initrd /install.amd/initrd.gz
    }

    menuentry "Rescue mode" {
        linux /install.amd/vmlinuz rescue/enable=true priority=low ---
        initrd /install.amd/initrd.gz
    }

    menuentry "Automated install (unattended)" {
        linux /install.amd/vmlinuz auto=true priority=critical preseed/file=/cdrom/preseed.cfg ---
        initrd /install.amd/initrd.gz
    }
}
GRUB_CFG
fi

# --- Inject branding files into the ISO for late_command to copy ---
log "Adding WTF Linux branding..."
mkdir -p "$WORK_DIR/wtf-linux"
sed -e "s|@WTF_VERSION@|${WTF_VERSION}|g" \
    -e "s|@DEBIAN_MAJOR@|${DEBIAN_MAJOR}|g" \
    -e "s|@DEBIAN_CODENAME@|${DEBIAN_CODENAME^}|g" \
    "${PROJECT_DIR}/branding/motd" > "$WORK_DIR/wtf-linux/motd"
cp "${PROJECT_DIR}/config/apt/sources.list" "$WORK_DIR/wtf-linux/sources.list"
cp "${PROJECT_DIR}/config/ssh/sshd_config.d/wtf-linux.conf" "$WORK_DIR/wtf-linux/sshd-wtf-linux.conf"

# --- Regenerate md5sums ---
# Hash into a temp file outside $WORK_DIR so the checksum file itself is
# never walked by find, then move it into place.
log "Regenerating MD5 checksums..."
MD5_TMP="$(mktemp "${PROJECT_DIR}/md5sum.XXXXXX")"
(cd "$WORK_DIR" && find . -not -path './isolinux/*' -not -name md5sum.txt -type f -print0 | xargs -0 md5sum > "$MD5_TMP")
mv "$MD5_TMP" "$WORK_DIR/md5sum.txt"
MD5_TMP=""

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
