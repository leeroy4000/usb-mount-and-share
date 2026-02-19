#!/bin/bash
# =============================================================================
# usb_mount_and_share.sh
# Description: Mounts a USB/block device and shares it over the network
#              via Samba. Handles fstab, permissions, and config validation.
# Usage:       sudo ./usb_mount_and_share.sh
# =============================================================================

# Fail fast, safer word splitting
set -euo pipefail
IFS=$'\n\t'

# --- Colors ---
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

err()  { echo -e "${RED}ERROR: $*${NC}" >&2; }
warn() { echo -e "${YELLOW}WARNING: $*${NC}"; }
ok()   { echo -e "${GREEN}$*${NC}"; }

# --- Sanity / privileges check ---
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  err "This script must be run as root. Re-run with sudo or as root."
  exit 1
fi

# --- MOUNT SETUP ---

echo "Available drives:"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
echo

read -p "Enter the device name to mount (e.g., sdb1 or /dev/sdb1): " DEVICE_NAME

# Accept either 'sdb1' or '/dev/sdb1' from the user
if [[ "$DEVICE_NAME" == /dev/* ]]; then
  DEVICE="$DEVICE_NAME"
else
  DEVICE="/dev/$DEVICE_NAME"
fi

# Verify the device exists and is a block device
if [ ! -b "$DEVICE" ]; then
  err "Device $DEVICE does not exist or is not a block device. Please check and try again."
  exit 1
fi

# Check if device is already mounted elsewhere
CURRENT_MOUNT=$(lsblk -no MOUNTPOINT "$DEVICE" || true)
if [ -n "$CURRENT_MOUNT" ]; then
  warn "$DEVICE is already mounted at $CURRENT_MOUNT"
  read -p "Do you want to unmount it first? (y/n): " UNMOUNT_CHOICE
  if [[ "$UNMOUNT_CHOICE" =~ ^[Yy]$ ]]; then
    echo "Unmounting $CURRENT_MOUNT..."
    umount "$CURRENT_MOUNT"
    ok "Unmounted successfully."
  else
    err "Cannot proceed with device already mounted. Exiting."
    exit 1
  fi
fi

# Get UUID and FSTYPE
UUID=$(lsblk -no UUID "$DEVICE" || true)
FSTYPE=$(lsblk -no FSTYPE "$DEVICE" || true)

if [ -z "$UUID" ] || [ -z "$FSTYPE" ]; then
  err "Failed to detect UUID or filesystem type. Here is device info for debugging:"
  lsblk -o NAME,UUID,FSTYPE,SIZE,MOUNTPOINT "$DEVICE" || true
  exit 1
fi

# Determine mount options based on filesystem type
MOUNT_OPTS="defaults"
case "$FSTYPE" in
  vfat|exfat|ntfs)
    # These filesystems support uid/gid
    MOUNT_OPTS="defaults,uid=1000,gid=1000"
    ;;
  *)
    # ext4, xfs, btrfs, etc. do not support uid/gid mount options
    MOUNT_OPTS="defaults"
    ;;
esac

read -p "Enter a short name for the mount point (e.g., media): " MOUNT_NAME
if [ -z "$MOUNT_NAME" ]; then
  err "Mount name cannot be empty."
  exit 1
fi
MOUNT_PATH="/mnt/$MOUNT_NAME"

echo "Creating mount point at $MOUNT_PATH..."
mkdir -p -- "$MOUNT_PATH"

# Backup fstab with timestamp
TS=$(date -u +%Y%m%d%H%M%S)
FSTAB_BACKUP="/etc/fstab.bak.$TS"

# Compose fstab line
FSTAB_LINE="UUID=$UUID $MOUNT_PATH $FSTYPE $MOUNT_OPTS 0 0"

# Check for duplicate fstab entries (by UUID and mount path)
FSTAB_MODIFIED=false
if grep -qE "^UUID=$UUID[[:space:]]+$MOUNT_PATH[[:space:]]" /etc/fstab; then
  echo "An fstab entry for this device and mount path already exists."

  # Check if it has invalid options for the filesystem type
  if [[ "$FSTYPE" =~ ^(ext4|xfs|btrfs)$ ]]; then
    if grep -E "^UUID=$UUID[[:space:]]+$MOUNT_PATH[[:space:]]" /etc/fstab | grep -q "uid=\|gid="; then
      warn "Found invalid uid/gid options for $FSTYPE filesystem."
      read -p "Update the entry to remove invalid options? (y/n): " UPDATE_CHOICE
      if [[ "$UPDATE_CHOICE" =~ ^[Yy]$ ]]; then
        echo "Backing up /etc/fstab to $FSTAB_BACKUP..."
        cp /etc/fstab "$FSTAB_BACKUP"
        ESCAPED_MOUNT_PATH=$(echo "$MOUNT_PATH" | sed 's/[\/&]/\\&/g')
        sed -i "/^UUID=$UUID[[:space:]]\+$ESCAPED_MOUNT_PATH[[:space:]]\+$FSTYPE[[:space:]]/s/,\?uid=[0-9]\+//g; /^UUID=$UUID[[:space:]]\+$ESCAPED_MOUNT_PATH[[:space:]]\+$FSTYPE[[:space:]]/s/,\?gid=[0-9]\+//g" /etc/fstab
        ok "Cleaned up invalid uid/gid options in /etc/fstab."
        FSTAB_MODIFIED=true
      fi
    else
      echo "Entry looks correct. Using existing entry."
    fi
  else
    echo "Entry looks correct. Using existing entry."
  fi
elif grep -qE "^UUID=$UUID[[:space:]]" /etc/fstab; then
  warn "A fstab entry for this device exists with a different mount path."
  grep -E "^UUID=$UUID[[:space:]]" /etc/fstab
  read -p "Do you want to update it to use $MOUNT_PATH instead? (y/n): " UPDATE_CHOICE
  if [[ "$UPDATE_CHOICE" =~ ^[Yy]$ ]]; then
    echo "Backing up /etc/fstab to $FSTAB_BACKUP..."
    cp /etc/fstab "$FSTAB_BACKUP"
    sed -i "/^UUID=$UUID[[:space:]]/c\\$FSTAB_LINE" /etc/fstab
    ok "Updated fstab entry to use $MOUNT_PATH."
    FSTAB_MODIFIED=true
  else
    err "Please resolve the conflict manually in /etc/fstab. Exiting."
    exit 1
  fi
elif grep -qE "^[^#]*[[:space:]]+$MOUNT_PATH[[:space:]]" /etc/fstab; then
  warn "A fstab entry for this mount path exists with a different device."
  grep -E "^[^#]*[[:space:]]+$MOUNT_PATH[[:space:]]" /etc/fstab
  read -p "Do you want to replace it with the new device? (y/n): " UPDATE_CHOICE
  if [[ "$UPDATE_CHOICE" =~ ^[Yy]$ ]]; then
    echo "Backing up /etc/fstab to $FSTAB_BACKUP..."
    cp /etc/fstab "$FSTAB_BACKUP"
    sed -i "\|[[:space:]]\+$MOUNT_PATH[[:space:]]|c\\$FSTAB_LINE" /etc/fstab
    ok "Updated fstab entry for $MOUNT_PATH."
    FSTAB_MODIFIED=true
  else
    err "Please resolve the conflict manually in /etc/fstab. Exiting."
    exit 1
  fi
else
  echo "Backing up /etc/fstab to $FSTAB_BACKUP..."
  cp /etc/fstab "$FSTAB_BACKUP"
  echo "Adding to /etc/fstab: $FSTAB_LINE"
  echo "$FSTAB_LINE" >> /etc/fstab
  FSTAB_MODIFIED=true
fi

# Reload systemd if fstab was modified
if [ "$FSTAB_MODIFIED" = true ]; then
  echo "Reloading systemd daemon..."
  systemctl daemon-reload
fi

# Only attempt to mount if not already mounted
if mount | grep -q "on $MOUNT_PATH "; then
  echo "$MOUNT_PATH is already mounted."
else
  echo "Mounting..."
  if ! mount "$MOUNT_PATH" 2>&1; then
    err "Mount failed. Please check the error above."
    exit 1
  fi
fi

echo "Mount status:"
mount | grep -- "$MOUNT_PATH" || echo "Mount point $MOUNT_PATH not found in mount output."

# --- SAMBA INSTALLATION CHECK ---

if ! command -v smbd >/dev/null 2>&1; then
  echo "Samba is not installed. Installing..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y samba
else
  echo "Samba is already installed."
fi

# --- SAMBA CONFIGURATION ---

read -p "Enter a name for the Samba share (e.g., media): " SHARE_NAME
read -p "Enter the Linux username to grant access (e.g., jdoe): " SAMBA_USER

if ! id -u "$SAMBA_USER" >/dev/null 2>&1; then
  err "Linux user '$SAMBA_USER' does not exist. Create the user first or choose another user."
  exit 1
fi

# Handle permissions for ext4/xfs/btrfs filesystems
if [[ "$FSTYPE" =~ ^(ext4|xfs|btrfs)$ ]]; then
  echo "Detected $FSTYPE filesystem. Checking ownership of $MOUNT_PATH..."
  CURRENT_OWNER=$(stat -c '%U' "$MOUNT_PATH")
  if [ "$CURRENT_OWNER" != "$SAMBA_USER" ]; then
    echo "Current owner is $CURRENT_OWNER."
    read -p "Set ownership of $MOUNT_PATH to $SAMBA_USER? (y/n): " CHOWN_CHOICE
    if [[ "$CHOWN_CHOICE" =~ ^[Yy]$ ]]; then
      echo "Setting ownership..."
      chown -R "$SAMBA_USER:$SAMBA_USER" "$MOUNT_PATH"
      chmod -R 775 "$MOUNT_PATH"
      ok "Ownership updated."
    else
      warn "You may need to manually adjust permissions for Samba to work correctly."
    fi
  else
    ok "Ownership is already correct."
  fi
fi

# Avoid duplicate Samba share entries
if grep -q "^\[$SHARE_NAME\]" /etc/samba/smb.conf; then
  warn "A Samba share named [$SHARE_NAME] already exists in smb.conf."
  read -p "Do you want to update it? (y/n): " UPDATE_SAMBA
  if [[ "$UPDATE_SAMBA" =~ ^[Yy]$ ]]; then
    echo "Backing up smb.conf..."
    cp /etc/samba/smb.conf "/etc/samba/smb.conf.bak.$TS"
    # Remove the existing share section
    sed -i "/^\[$SHARE_NAME\]/,/^$/d" /etc/samba/smb.conf
    echo "Removed old [$SHARE_NAME] entry."
  else
    err "Please choose a different share name or edit /etc/samba/smb.conf manually. Exiting."
    exit 1
  fi
fi

echo "Adding Samba share to /etc/samba/smb.conf..."
cat >> /etc/samba/smb.conf <<EOF

[$SHARE_NAME]
  path = $MOUNT_PATH
  available = yes
  valid users = $SAMBA_USER
  read only = no
  browsable = yes
  writable = yes
  directory mask = 0775
  create mask = 0664
EOF

# Test Samba configuration
echo "Testing Samba configuration..."
if ! testparm -s /etc/samba/smb.conf >/dev/null 2>&1; then
  err "Samba configuration is invalid. Rolling back..."
  if [ -f "/etc/samba/smb.conf.bak.$TS" ]; then
    mv "/etc/samba/smb.conf.bak.$TS" /etc/samba/smb.conf
  fi
  err "Configuration rolled back. Please check your settings."
  exit 1
fi
ok "Samba configuration is valid."

echo "Setting Samba password for user $SAMBA_USER..."
smbpasswd -a "$SAMBA_USER"

echo "Restarting Samba..."
if ! systemctl restart smbd; then
  err "Failed to restart Samba. Check 'systemctl status smbd' for details."
  exit 1
fi

echo ""
echo "============================================"
ok "SUCCESS! Setup complete."
echo "============================================"
echo "Mount point: $MOUNT_PATH"
echo "Samba share: [$SHARE_NAME]"
echo ""
echo "Access from other computers:"
echo ""
# Get all non-loopback IP addresses
IPS=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.')
if [ -n "$IPS" ]; then
  echo "Windows (File Explorer):"
  while IFS= read -r IP; do
    echo "  \\\\$IP\\$SHARE_NAME"
  done <<< "$IPS"
  echo ""
  echo "Linux/Mac (File Manager or Terminal):"
  while IFS= read -r IP; do
    echo "  smb://$IP/$SHARE_NAME"
  done <<< "$IPS"
else
  echo "Windows: \\\\<server-ip>\\$SHARE_NAME"
  echo "Linux/Mac: smb://<server-ip>/$SHARE_NAME"
  warn "Could not detect IP address automatically."
fi
echo ""
echo "Username: $SAMBA_USER"
echo "Password: (the one you just set)"
echo "============================================"
