#!/usr/bin/env bash
# =============================================================================
# Validate WTF Linux preseed file for common errors
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PRESEED_FILE="${PROJECT_DIR}/preseed/wtf-linux.preseed"

echo "[VALIDATE] Checking preseed file: ${PRESEED_FILE}"

if [[ ! -f "$PRESEED_FILE" ]]; then
    echo "[VALIDATE] ERROR: Preseed file not found!"
    exit 1
fi

errors=0

# Check for required directives
required_directives=(
    "d-i debian-installer/locale"
    "d-i netcfg/choose_interface"
    "d-i mirror/http/hostname"
    "d-i partman-auto/method"
    "d-i passwd/username"
    "d-i grub-installer/only_debian"
    "d-i pkgsel/include"
    "tasksel tasksel/first"
)

for directive in "${required_directives[@]}"; do
    if ! grep -q "^${directive}" "$PRESEED_FILE"; then
        echo "[VALIDATE] WARNING: Missing directive: ${directive}"
        ((errors++))
    fi
done

# Check that openssh-server is in pkgsel/include
if ! grep -q "openssh-server" "$PRESEED_FILE"; then
    echo "[VALIDATE] ERROR: openssh-server not found in package selection!"
    ((errors++))
fi

# Check that ssh-server task is selected
if ! grep -q "ssh-server" "$PRESEED_FILE"; then
    echo "[VALIDATE] ERROR: ssh-server task not selected!"
    ((errors++))
fi

# Check for trixie/debian 13
if ! grep -q "trixie" "$PRESEED_FILE"; then
    echo "[VALIDATE] WARNING: No reference to 'trixie' (Debian 13) found"
    ((errors++))
fi

if [[ $errors -eq 0 ]]; then
    echo "[VALIDATE] Preseed file looks good! No issues found."
else
    echo "[VALIDATE] Found ${errors} issue(s). Review the warnings above."
fi

exit $errors
