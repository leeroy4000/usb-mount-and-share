# USB Mount and Share Script

This is a simple Bash script to help mount a USB drive on a Linux system and share it with Windows machines using Samba.

## 🔧 What It Does

1. Lists all available drives using `lsblk`.
2. Prompts you to select a device and specify a mount point name.
3. Automatically gathers UUID and filesystem info using `blkid`.
4. Creates the mount directory and updates `/etc/fstab`.
5. Mounts the drive immediately.
6. Checks if Samba is installed; installs it if missing.
7. Prompts for a Samba share name and user.
8. Appends a new share definition to `smb.conf`.
9. Sets the Samba password and restarts the Samba service.

## 📝 Requirements

- Linux system with `bash`, `blkid`, `lsblk`, and `mount`
- `sudo` privileges
- Internet access (for Samba installation, if needed)

## 🚀 Usage

Make the script executable and run it:

```bash
chmod +x usb_mount_and_share.sh
./usb_mount_and_share.sh
```

Follow the on-screen prompts:
- Select the device name (e.g., `sdb1`)
- Provide a mount point name (e.g., `media`)
- Choose a Samba share name
- Enter the Linux user to assign Samba access
- Set a Samba password for that user

## 🛑 Notes

- Be careful when selecting a device—ensure it's the correct USB drive.
- This script modifies system files:
  - `/etc/fstab` is updated to persist the mount
  - `/etc/samba/smb.conf` is updated with a new share
- A backup of `/etc/fstab` is automatically created at `/etc/fstab.bak`
- Use caution on production systems or servers with existing Samba configurations.
