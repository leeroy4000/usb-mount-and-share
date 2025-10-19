#!/bin/bash

# Fail fast, safer word splitting
set -euo pipefail
IFS=$'\n\t'

# --- Sanity / privileges check ---
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "This script must be run as root. Re-run with sudo or as root."
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
  echo "Device $DEVICE does not exist or is not a block device. Please check and try again."
  exit 1
fi

UUID=$(lsblk -no UUID "$DEVICE" || true)
FSTYPE=$(lsblk -no FSTYPE "$DEVICE" || true)

if [ -z "$UUID" ] || [ -z "$FSTYPE" ]; then
  echo "Failed to detect UUID or filesystem type. Here is device info for debugging:"
  lsblk -o NAME,UUID,FSTYPE,SIZE,MOUNTPOINT "$DEVICE" || true
  exit 1
fi

read -p "Enter a short name for the mount point (e.g., media): " MOUNT_NAME
if [ -z "$MOUNT_NAME" ]; then
  echo "Mount name cannot be empty."
  exit 1
fi
MOUNT_PATH="/mnt/$MOUNT_NAME"

echo "Creating mount point at $MOUNT_PATH..."
mkdir -p -- "$MOUNT_PATH"

# Backup fstab with timestamp and avoid duplicate entries
TS=$(date -u +%Y%m%d%H%M%S)
FSTAB_BACKUP="/etc/fstab.bak.$TS"

FSTAB_LINE="UUID=$UUID $MOUNT_PATH $FSTYPE defaults,uid=1000,gid=1000 0 0"

if grep -qF "UUID=$UUID" /etc/fstab || grep -qF "$MOUNT_PATH" /etc/fstab; then
  echo "An fstab entry for this device or mount path already exists; skipping fstab modification."
else
  echo "Backing up /etc/fstab to $FSTAB_BACKUP..."
  cp /etc/fstab "$FSTAB_BACKUP"
  echo "Adding to /etc/fstab: $FSTAB_LINE"
  echo "$FSTAB_LINE" >> /etc/fstab
fi

echo "Mounting..."
mount -a

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
read -p "Enter the Linux username to grant access (e.g., user1): " SAMBA_USER

if ! id -u "$SAMBA_USER" >/dev/null 2>&1; then
  echo "Linux user $SAMBA_USER does not exist. Create the user first or choose another user."
  exit 1
fi

echo "Adding Samba share to /etc/samba/smb.conf..."
cat >> /etc/samba/smb.conf <<EOF

[$SHARE_NAME]
   path = $MOUNT_PATH
   available = yes
   valid users = $SAMBA_USER
   read only = no
   browsable = yes
   public = yes
   writable = yes
   directory mask = 0775
EOF

echo "Setting Samba password for user $SAMBA_USER..."
smbpasswd -a "$SAMBA_USER"

echo "Restarting Samba..."
systemctl restart smbd

echo "Samba share [$SHARE_NAME] is now active."
echo "Access it from the client using: \\your-server-ip\$SHARE_NAME"
