#!/bin/bash

# --- MOUNT SETUP ---

echo "Available drives:"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
echo

read -p "Enter the device name to mount (e.g., sdb1): " DEVICE_NAME
DEVICE="/dev/$DEVICE_NAME"

UUID=$(blkid -s UUID -o value "$DEVICE")
FSTYPE=$(blkid -s TYPE -o value "$DEVICE")

if [ -z "$UUID" ] || [ -z "$FSTYPE" ]; then
  echo "Failed to detect UUID or filesystem type. Please check the device and try again."
  exit 1
fi

read -p "Enter a short name for the mount point (e.g., media): " MOUNT_NAME
MOUNT_PATH="/mnt/$MOUNT_NAME"

echo "Creating mount point at $MOUNT_PATH..."
sudo mkdir -p "$MOUNT_PATH"

echo "Backing up /etc/fstab to /etc/fstab.bak..."
sudo cp /etc/fstab /etc/fstab.bak

FSTAB_LINE="UUID=$UUID $MOUNT_PATH $FSTYPE defaults,uid=1000,gid=1000 0 0"
echo "Adding to /etc/fstab: $FSTAB_LINE"
echo "$FSTAB_LINE" | sudo tee -a /etc/fstab

echo "Mounting..."
sudo mount -a

echo "Mount status:"
mount | grep "$MOUNT_PATH"

# --- SAMBA INSTALLATION CHECK ---

if ! command -v smbd &> /dev/null; then
  echo "Samba is not installed. Installing..."
  sudo apt-get update
  sudo apt-get install -y samba
else
  echo "Samba is already installed."
fi

# --- SAMBA CONFIGURATION ---

read -p "Enter a name for the Samba share (e.g., media): " SHARE_NAME
read -p "Enter the Linux username to grant access (e.g., user1): " SAMBA_USER

echo "Adding Samba share to /etc/samba/smb.conf..."
sudo bash -c "cat >> /etc/samba/smb.conf <<EOF

[$SHARE_NAME]
   path = $MOUNT_PATH
   available = yes
   valid users = $SAMBA_USER
   read only = no
   browsable = yes
   public = yes
   writable = yes
   directory mask = 0775
EOF"

echo "Setting Samba password for user $SAMBA_USER..."
sudo smbpasswd -a "$SAMBA_USER"

echo "Restarting Samba..."
sudo systemctl restart smbd

echo "Samba share [$SHARE_NAME] is now active."
echo "Access it from Windows using: \\your-server-ip\$SHARE_NAME"
