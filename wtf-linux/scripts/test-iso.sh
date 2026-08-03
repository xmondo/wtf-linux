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
ISO_FILE="${OUTPUT_DIR}/wtf-linux-1.0-amd64.iso"
DISK_FILE="${OUTPUT_DIR}/wtf-linux-test.qcow2"

MEMORY="2048"
DISK_SIZE="10G"
HEADLESS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --headless) HEADLESS=true; shift ;;
        --memory)   MEMORY="$2"; shift 2 ;;
        --disk)     DISK_SIZE="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

if [[ ! -f "$ISO_FILE" ]]; then
    echo "ERROR: ISO not found at ${ISO_FILE}"
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

QEMU_ARGS=(
    -m "$MEMORY"
    -cdrom "$ISO_FILE"
    -hda "$DISK_FILE"
    -boot d
    -net nic -net user,hostfwd=tcp::2222-:22
    -cpu host
    -enable-kvm
)

if $HEADLESS; then
    QEMU_ARGS+=(-nographic -serial mon:stdio)
    echo "  Mode:   Headless (serial console)"
    echo "  SSH:    ssh -p 2222 wtf@localhost (after install completes)"
else
    echo "  Mode:   Graphical"
    echo "  SSH:    ssh -p 2222 wtf@localhost (after install completes)"
fi

qemu-system-x86_64 "${QEMU_ARGS[@]}"
