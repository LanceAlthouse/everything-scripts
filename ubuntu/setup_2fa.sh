#!/usr/bin/env bash

set -euo pipefail

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "Missing required command: $1"
        exit 1
    }
}

ensure_line_in_file() {
    local line="$1"
    local file="$2"

    if ! grep -Eq "^[[:space:]]*${line//./\\.}[[:space:]]*$" "$file"; then
        echo "$line" | sudo tee -a "$file" >/dev/null
        return 0
    fi

    return 1
}

ensure_sshd_option() {
    local key="$1"
    local value="$2"
    local file="$3"

    if grep -Eq "^[[:space:]]*${key}[[:space:]]+${value}[[:space:]]*$" "$file"; then
        return 1
    fi

    if grep -Eq "^[[:space:]#]*${key}[[:space:]]+" "$file"; then
        sudo sed -i -E "s|^[[:space:]#]*${key}[[:space:]]+.*|${key} ${value}|" "$file"
    else
        echo "${key} ${value}" | sudo tee -a "$file" >/dev/null
    fi

    return 0
}

require_cmd id
require_cmd sudo
require_cmd grep
require_cmd sed
require_cmd apt
require_cmd dpkg

echo "==== Ubuntu Password + 2FA Setup ===="
echo

# --- ask which user to configure ---
read -rp "Enter the username to secure: " TARGET_USER

TARGET_USER="${TARGET_USER// /}"

if [[ -z "$TARGET_USER" ]]; then
    echo "Username cannot be empty."
    exit 1
fi

if ! id "$TARGET_USER" &>/dev/null; then
    echo "User does not exist."
    exit 1
fi

echo
echo "Changing password for $TARGET_USER"
sudo passwd "$TARGET_USER"

echo
echo "Installing Google Authenticator PAM module..."
if ! dpkg -s libpam-google-authenticator >/dev/null 2>&1; then
    sudo apt update
    sudo apt install -y libpam-google-authenticator
else
    echo "libpam-google-authenticator is already installed."
fi

echo
echo "========================================"
echo "Now we will generate the 2FA secret."
echo "Follow the prompts carefully."
echo "Recommended answers:"
echo "  - Time-based tokens: yes"
echo "  - Update file: yes"
echo "  - Disallow reuse: yes"
echo "  - Enable rate limiting: yes"
echo "========================================"
echo

sudo -u "$TARGET_USER" google-authenticator

echo
echo "Configuring PAM for SSH..."

PAM_SSHD="/etc/pam.d/sshd"

ssh_pam_changed=0
if ensure_line_in_file "auth required pam_google_authenticator.so" "$PAM_SSHD"; then
    ssh_pam_changed=1
fi

echo
echo "Updating sshd_config..."

SSHD_CONFIG="/etc/ssh/sshd_config"

sshd_changed=0

if ensure_sshd_option "ChallengeResponseAuthentication" "yes" "$SSHD_CONFIG"; then
    sshd_changed=1
fi

# Newer OpenSSH uses KbdInteractiveAuthentication; keep both for compatibility.
if ensure_sshd_option "KbdInteractiveAuthentication" "yes" "$SSHD_CONFIG"; then
    sshd_changed=1
fi

if ensure_sshd_option "UsePAM" "yes" "$SSHD_CONFIG"; then
    sshd_changed=1
fi

if ensure_sshd_option "PasswordAuthentication" "yes" "$SSHD_CONFIG"; then
    sshd_changed=1
fi

echo
echo "Restarting SSH service..."
if (( ssh_pam_changed == 1 || sshd_changed == 1 )); then
    sudo systemctl restart ssh
else
    echo "No SSH config changes detected; restart not required."
fi

echo
echo "Configuring sudo to require 2FA..."

SUDO_PAM="/etc/pam.d/sudo"

if ! grep -Eq '^[[:space:]]*auth[[:space:]]+required[[:space:]]+pam_google_authenticator\.so([[:space:]]+.*)?$' "$SUDO_PAM"; then
    sudo sed -i '1iauth required pam_google_authenticator.so' "$SUDO_PAM"
fi

echo
echo "========================================"
echo "SETUP COMPLETE"
echo "========================================"
echo
echo "IMPORTANT:"
echo "1) Open a NEW terminal and test SSH login"
echo "2) Confirm you get a verification code prompt"
echo "3) Do NOT close your current session until verified"
echo
echo "If login fails, revert changes using your current session."
echo