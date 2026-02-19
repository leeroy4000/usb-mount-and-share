# Block Device Mount & Samba Share Script

A robust Bash script that automates mounting any block device (USB drive, secondary disk, LVM volume) on Linux and sharing it over the network via Samba. Built for homelab use — specifically to quickly expose storage from a Proxmox host to other VMs and clients on the network.

Handles edge cases, validates configurations, creates timestamped backups before any changes, and provides clear cross-platform connection instructions.

## Why I Built This

## Why I Built This

Managing fstab entries and Samba shares by hand is tedious and error-prone, especially when dealing with multiple filesystems (ext4, vfat, ntfs) that each have different valid mount options. I built this to make the process repeatable and safe on any Linux system — no more editing config files by hand or hoping you remembered the right mount flags.
## What It Does

1. **Lists available drives** using `lsblk` with detailed information
2. **Checks for existing mounts** and offers to unmount if necessary
3. **Detects filesystem type** and applies appropriate mount options
4. **Creates mount point** and updates `/etc/fstab` for persistent mounting across reboots
5. **Handles duplicate entries** intelligently:
   - Detects and removes invalid options (e.g., uid/gid on ext4)
   - Offers to update existing entries instead of failing
   - Creates timestamped backups before any changes
6. **Manages permissions** for ext4/xfs/btrfs filesystems:
   - Checks ownership of the mount point
   - Offers to set proper ownership for the Samba user
7. **Installs Samba** if not already present
8. **Configures Samba share** with proper authentication
9. **Validates configuration** using `testparm` before applying changes
10. **Provides connection details** for Windows, Linux, and Mac clients with actual server IP addresses

## Features

- **Error recovery** — validates Samba config and rolls back on failure
- **Interactive** — prompts for confirmation on destructive operations
- **Safe** — creates timestamped backups of `/etc/fstab` and `smb.conf`
- **Smart** — detects filesystem types and applies correct mount options
- **Colored output** — errors in red, warnings in yellow, success in green

## Requirements

- Linux system with `bash`, `lsblk`, `mount`, and `sed`
- `sudo` or root privileges
- Internet access (for Samba installation, if not already present)

## Usage

Make the script executable and run it with sudo:
```bash
chmod +x usb_mount_and_share.sh
sudo ./usb_mount_and_share.sh
```

Follow the interactive prompts:

1. **Select the device** (e.g., `sdb1` or `/dev/sdb1`)
2. **Provide a mount point name** (e.g., `media`, `backup`, `data`)
3. **Answer prompts** about existing configurations (if any)
4. **Set permissions** for ext4/xfs/btrfs filesystems (if needed)
5. **Choose a Samba share name** (what appears on the network)
6. **Enter the Linux username** to grant access
7. **Set a Samba password** for that user

## Sample Output
```
Available drives:
NAME   SIZE FSTYPE LABEL  MOUNTPOINT
sda    120G
sda1   120G ext4          /
sdb    500G
sdb1   500G ext4   backup

Enter the device name to mount (e.g., sdb1 or /dev/sdb1): sdb1
Enter a short name for the mount point (e.g., media): backup
Creating mount point at /mnt/backup...
Adding to /etc/fstab: UUID=a1b2c3d4-... /mnt/backup ext4 defaults 0 0
Reloading systemd daemon...
Mounting...
Samba is already installed.

Enter a name for the Samba share (e.g., media): backup
Enter the Linux username to grant access (e.g., jdoe): jdoe
Ownership is already correct.
Adding Samba share to /etc/samba/smb.conf...
Testing Samba configuration...
Samba configuration is valid.
Setting Samba password for user jdoe...
Restarting Samba...

============================================
SUCCESS! Setup complete.
============================================
Mount point: /mnt/backup
Samba share: [backup]

Access from other computers:

Windows (File Explorer):
  \\192.168.1.7\backup

Linux/Mac (File Manager or Terminal):
  smb://192.168.1.7/backup

Username: jdoe
Password: (the one you just set)
============================================
```

## Accessing the Share

### Windows
Open File Explorer, type the path in the address bar, and enter your credentials.

### Linux/Mac
Use your file manager's "Connect to Server" feature, or mount from the terminal:
```bash
# Mount temporarily
sudo mount -t cifs //192.168.1.7/backup /mnt/share -o username="jdoe"

# Or access via file manager
nautilus smb://192.168.1.7/backup
```

## Important Notes

- **Verify the device** carefully before proceeding — selecting the wrong device could cause data loss
- **System files modified** by this script:
  - `/etc/fstab` (persists mount across reboots)
  - `/etc/samba/smb.conf` (adds network share)
- **Automatic backups** are created with timestamps before any changes:
  - `/etc/fstab.bak.YYYYMMDDHHMMSS`
  - `/etc/samba/smb.conf.bak.YYYYMMDDHHMMSS`
- **Production systems** — review the script and test on non-critical systems first

## License

MIT — see [LICENSE](LICENSE) for details.
