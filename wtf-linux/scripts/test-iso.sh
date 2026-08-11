#!/usr/bin/env bash
# =============================================================================
# Test WTF Linux ISO in QEMU (headless or with display)
#
# Usage:
#   ./scripts/test-iso.sh [--headless] [--memory 2048] [--disk 10G]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_DIR}/output"
VERSION_FILE="${PROJECT_DIR}/config/version"
DISK_FILE="${OUTPUT_DIR}/wtf-linux-test.qcow2"

MEMORY="2048"
DISK_SIZE="10G"
HEADLESS=false

# Locate the latest built WTF Linux ISO (prefer the version in config/version)
ISO_FILE=""
WTF_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE" 2>/dev/null || true)"
if [[ -n "$WTF_VERSION" && -f "${OUTPUT_DIR}/wtf-linux-${WTF_VERSION}-amd64.iso" ]]; then
    ISO_FILE="${OUTPUT_DIR}/wtf-linux-${WTF_VERSION}-amd64.iso"
else
    ISO_FILE="$(find "$OUTPUT_DIR" -maxdepth 1 -name 'wtf-linux-*-amd64.iso' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2-)"
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --headless) HEADLESS=true; shift ;;
        --memory)   MEMORY="$2"; shift 2 ;;
        --disk)     DISK_SIZE="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ -z "$ISO_FILE" || ! -f "$ISO_FILE" ]]; then
    echo "ERROR: No WTF Linux ISO found in ${OUTPUT_DIR}"
    echo "Run 'sudo ./scripts/build-iso.sh' first."
    exit 1
fi

# Check for QEMU
if ! command -v qemu-system-x86_64 &>/dev/null; then
    echo "ERROR: qemu-system-x86_64 not found. Install with:"
    echo "  sudo apt-get install qemu-system-x86"
    exit 1
fi

# Create test disk if it doesn't exist
if [[ ! -f "$DISK_FILE" ]]; then
    echo "Creating test disk: ${DISK_FILE} (${DISK_SIZE})"
    qemu-img create -f qcow2 "$DISK_FILE" "$DISK_SIZE"
fi

echo "Starting WTF Linux test VM..."
echo "  ISO:    ${ISO_FILE}"
echo "  Disk:   ${DISK_FILE}"
echo "  Memory: ${MEMORY}MB"

# shellcheck disable=SC2054  # QEMU's -netdev syntax legitimately uses commas
QEMU_ARGS=(
    -m "$MEMORY"
    -cdrom "$ISO_FILE"
    -hda "$DISK_FILE"
    -boot d
    -device virtio-net-pci,netdev=net0
    -netdev user,id=net0,hostfwd=tcp::2222-:22
    -cpu host
    -enable-kvm
    -vga cirrus
)

if $HEADLESS; then
    QEMU_ARGS+=(-nographic -serial mon:stdio)
    echo "  Mode:   Headless (serial console)"
else
    echo "  Mode:   Graphical (QEMU display)"
fi
echo "  SSH:    ssh -p 2222 <user>@localhost (after install completes)"

qemu-system-x86_64 "${QEMU_ARGS[@]}"
