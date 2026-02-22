#!/usr/bin/env bash

set -e

echo "==== Ubuntu Password + 2FA Setup ===="
echo

# --- ask which user to configure ---
read -rp "Enter the username to secure: " TARGET_USER

if ! id "$TARGET_USER" &>/dev/null; then
    echo "User does not exist."
    exit 1
fi

echo
echo "Changing password for $TARGET_USER"
sudo passwd "$TARGET_USER"

echo
echo "Installing Google Authenticator PAM module..."
sudo apt update
sudo apt install -y libpam-google-authenticator

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

if ! grep -q "pam_google_authenticator.so" "$PAM_SSHD"; then
    echo "auth required pam_google_authenticator.so" | sudo tee -a "$PAM_SSHD"
fi

echo
echo "Updating sshd_config..."

SSHD_CONFIG="/etc/ssh/sshd_config"

sudo sed -i 's/^#\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/' "$SSHD_CONFIG"
sudo sed -i 's/^#\?UsePAM.*/UsePAM yes/' "$SSHD_CONFIG"
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"

echo
echo "Restarting SSH service..."
sudo systemctl restart ssh

echo
echo "Configuring sudo to require 2FA..."

SUDO_PAM="/etc/pam.d/sudo"

if ! grep -q "pam_google_authenticator.so" "$SUDO_PAM"; then
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