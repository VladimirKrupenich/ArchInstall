#!/bin/bash

debug=1
echo "-------- | DISK SETUP | --------"

# ---- | INSTALL STATUS CHECK | ----
InstallStatus() {
    if [ $? -ne 0 ]; then
        echo "[ ERROR ] - $1 failed!"
        echo "error: $?"
        exit 1
    else
        if [ $debug -eq 1 ]; then
            echo "[ SUCCESS ] - $1 successufully "
        fi
    fi
}

# ---- | SETUP | ----
SSD=$(lsblk -o PATH,MODEL | grep -i 'ssd' | awk '{print $1}' | head -n1)
HDD=$(lsblk -o PATH,MODEL | grep -i 'tosh' | awk '{print $1}' | head -n1)

[ -z "$SSD" ] && SSD="/dev/sda"     # fallback
[ -z "$HDD" ] && HDD="/dev/sdb"     # fallback

# ---- | CHECKS | ----
# -- | SSD | --
if [ ! -e "$SSD" ]; then
    echo "[ ERROR ] - $SSD not found!"
    exit 1
fi

# -- | HDD | --
if [ ! -e "$HDD" ]; then
    echo "[ ERROR ] - $HDD not found!"
    exit 1
fi

# -- | FREE SPACE | --
if  [ $(df --output=avail -BG / | tail -1 | tr -d 'G') -lt 10 ]; then
    echo "[ ERROR ] - Not enough free space for installation!"
    exit 1
fi


# ---- | WARNING | ----
echo "[ WARNING ] This script will erase all data on $SSD and $HDD!"
read -p "Continue? (y/N): " confirm
if [ "$confirm" != "y" ]; then
    echo "[ INFO ] Installation canceled"
    exit 1
fi

# ---- | WIPING | ----
wipefs --all "$SSD"                                                                                     && InstallStatus "Wipe $SSD"
wipefs --all "$HDD"                                                                                     && InstallStatus "Wipe $HDD"

# ---- | PARTITIONING | ----
parted -s "$SSD" mklabel gpt                                                                            && InstallStatus "Create GPT label on $SSD"
parted -s "$SSD" mkpart "EFI" fat32 1MiB 512MiB                                                         && InstallStatus "Create EFI partition"
parted -s "$SSD" set 1 esp on                                                                           && InstallStatus "Set ESP flag"
parted -s "$SSD" mkpart "root" btrfs 512MiB 100%                                                        && InstallStatus "Create root partition"

parted -s "$HDD" mklabel gpt                                                                            && InstallStatus "Create GPT label on $HDD"
parted -s "$HDD" mkpart "data" btrfs 1MiB 100%                                                          && InstallStatus "Create data partition"

# ---- | FILESYSTEM | ----
mkfs.fat -F32 "${SSD}1"                                                                                 && InstallStatus "Format EFI partition"
mkfs.btrfs -f "${SSD}2"                                                                                 && InstallStatus "Format root partition"
mkfs.btrfs -f "${HDD}1"                                                                                 && InstallStatus "Format data partition"

# ---- | MOUNTING | ----
mount "${SSD}2" /mnt                                                                                    && InstallStatus "Mount root partition"
mkdir -p /mnt/boot                                                                                      && InstallStatus "Mount boot partition"
mount "${SSD}1" /mnt/boot                                                                               && InstallStatus "Mount EFI partition"

# ---- | SUBVOLUMES | ----
btrfs subvolume create /mnt/@                                                                           && InstallStatus "Create @subvolume"
btrfs subvolume create /mnt/@home                                                                       && InstallStatus "Create @home subvolume"
btrfs subvolume create /mnt/@snapshots                                                                  && InstallStatus "Create @snapshots subvolume"
btrfs subvolume create /mnt/@var_log                                                                    && InstallStatus "Create @var_log subvolume"
btrfs subvolume create /mnt/@swap                                                                       && InstallStatus "Create @swap subvolume"

umount /mnt                                                                                             && InstallStatus "Unmount root partition"

mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=@ "${SSD}2" /mnt                     && InstallStatus "Remount root with subvolume"
mkdir -p /mnt/{home,.snapshots,var/log,swap,boot}                                                       && InstallStatus "Create directory structure"
mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=@home "${SSD}2" /mnt/home            && InstallStatus "Mount home subvolume"
mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=@snapshots "${SSD}2" /mnt/.snapshots && InstallStatus "Mount snapshots subvolume"
mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=@var_log "${SSD}2" /mnt/var/log      && InstallStatus "Mount var_log subvolume"
mount -o noatime,compress=zstd,space_cache=v2,discard=async,subvol=@swap "${SSD}2" /mnt/swap            && InstallStatus "Mount swap subvolume"

mkdir -p /mnt/mnt/data                                                                                  && InstallStatus "Create data partition"
mount "${HDD}1" /mnt/mnt/data                                                                           && InstallStatus "Mount data partition"


# ---- | SWAP | ----
dd if=/dev/zero of /mnt/swap/swapfile bs=1M count=$((8*1024)) status=progress                           && InstallStatus "Create swap file"
chmod 600 /mnt/swap/swapfile                                                                            && InstallStatus "Set swap file permission"
mkswap /mnt/swap/swapfile                                                                               && InstallStatus "Initialize swap"
swapon /mnt/swap/swapfile                                                                               && InstallStatus "Activate swap"

echo "-------- | DISK SETUP SUCCESSFULLY COMPLETED | --------"
