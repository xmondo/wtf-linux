#!/usr/bin/env bash
# =============================================================================
# Validate WTF Linux autoinstall (cloud-init) user-data for common errors
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
USERDATA_FILE="${PROJECT_DIR}/autoinstall/user-data"
METADATA_FILE="${PROJECT_DIR}/autoinstall/meta-data"

echo "[VALIDATE] Checking autoinstall files..."

errors=0
warnings=0

# --- Check that user-data exists ---
if [[ ! -f "$USERDATA_FILE" ]]; then
    echo "[VALIDATE] ERROR: user-data file not found: ${USERDATA_FILE}"
    exit 1
fi
echo "[VALIDATE] Found user-data: ${USERDATA_FILE}"

# --- Check that meta-data exists ---
if [[ ! -f "$METADATA_FILE" ]]; then
    echo "[VALIDATE] ERROR: meta-data file not found: ${METADATA_FILE}"
    ((errors++))
else
    echo "[VALIDATE] Found meta-data: ${METADATA_FILE}"
fi

# --- Validate YAML syntax ---
echo "[VALIDATE] Checking YAML syntax..."
if command -v python3 &>/dev/null; then
    yaml_error=$(python3 -c "
import yaml, sys
try:
    with open('${USERDATA_FILE}', 'r') as f:
        data = yaml.safe_load(f)
    if data is None:
        print('ERROR: user-data is empty or not valid YAML')
        sys.exit(1)
    print('OK: YAML syntax is valid')
except yaml.YAMLError as e:
        print(f'ERROR: YAML parse error: {e}')
        sys.exit(1)
" 2>&1) || {
        echo "[VALIDATE] ${yaml_error}"
        ((errors++))
    }
    if [[ $errors -eq 0 ]]; then
        echo "[VALIDATE] ${yaml_error}"
    fi
else
    echo "[VALIDATE] WARNING: python3 not found, skipping YAML syntax check"
    ((warnings++))
fi

# --- Check for #cloud-config header ---
first_line=$(head -1 "$USERDATA_FILE")
if [[ "$first_line" != "#cloud-config" ]]; then
    echo "[VALIDATE] ERROR: user-data must start with '#cloud-config' (found: '${first_line}')"
    ((errors++))
fi

# --- Check for required autoinstall keys ---
echo "[VALIDATE] Checking required autoinstall directives..."

required_keys=(
    "version:"
    "locale:"
    "keyboard:"
    "storage:"
    "identity:"
    "ssh:"
    "packages:"
    "late-commands:"
)

for key in "${required_keys[@]}"; do
    if ! grep -q "^  ${key}\|^${key}" "$USERDATA_FILE"; then
        echo "[VALIDATE] ERROR: Missing required key: ${key}"
        ((errors++))
    fi
done

# --- Check that openssh-server is in the packages list ---
if ! grep -q "openssh-server" "$USERDATA_FILE"; then
    echo "[VALIDATE] ERROR: openssh-server not found in packages list!"
    ((errors++))
fi

# --- Check that SSH server installation is enabled ---
if ! grep -q "install-server: true" "$USERDATA_FILE"; then
    echo "[VALIDATE] ERROR: SSH server install not enabled (install-server: true)"
    ((errors++))
fi

# --- Check for autoinstall version ---
if ! grep -q "version: 1" "$USERDATA_FILE"; then
    echo "[VALIDATE] WARNING: autoinstall version should be 1 for Ubuntu 24.04"
    ((warnings++))
fi

# --- Validate required packages are present ---
echo "[VALIDATE] Checking critical packages..."
critical_packages=(
    "openssh-server"
    "sudo"
    "curl"
    "wget"
    "vim"
    "linux-firmware"
)

for pkg in "${critical_packages[@]}"; do
    if ! grep -q -- "- ${pkg}" "$USERDATA_FILE"; then
        echo "[VALIDATE] WARNING: Expected package not found: ${pkg}"
        ((warnings++))
    fi
done

# --- Summary ---
if [[ $errors -eq 0 ]]; then
    if [[ $warnings -eq 0 ]]; then
        echo "[VALIDATE] Autoinstall configuration looks good! No issues found."
    else
        echo "[VALIDATE] No errors. ${warnings} warning(s)."
    fi
else
    echo "[VALIDATE] Found ${errors} error(s) and ${warnings} warning(s). Review the output above."
fi

exit $errors
