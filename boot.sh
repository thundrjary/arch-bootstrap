# ### Pre-Installation Phase
# - Disable Secure Boot (ISO is not signed for SB)
echo "Please reboot into your firmware settings (UEFI/BIOS) and disable Secure Boot before proceeding."
# - ISO acquisition and verification
pacman-key -v archlinux-*.iso.sig || { echo "ISO verification failed"; exit 1; }
# - Installation medium preparation
dd bs=4M if=archlinux.iso of=/dev/sdX status=progress oflag=sync || { echo "Failed to write ISO to USB"; exit 1; }
# - Boot into live environment
# - Console keyboard layout configuration
# - Console font configuration
# - Boot mode verification (UEFI/BIOS)
ls /sys/firmware/efi/efivars >/dev/null 2>&1 || { echo "System not booted in UEFI mode"; exit 1; }
# - Network interface setup
# - Internet connection establishment (Wi-Fi)
iwctl adapter phy0 set-property Powered on || { echo "Failed to power on Wi-Fi adapter"; exit 1; }
iwctl station wlan0 connect <SSID> || { echo "Failed to connect to Wi-Fi"; exit 1; }
ping -c3 archlinux.org || { echo "Network connectivity test failed"; exit 1; }
# - System clock synchronization
timedatectl set-ntp true || { echo "Failed to enable NTP"; exit 1; }
# - Pre-flight tool availability check
mkdir -p /mnt/tools || { echo "Failed to create /mnt/tools"; exit 1; }
mount /dev/sda2 /mnt/tools || { echo "Failed to mount /dev/sda2 to /mnt/tools"; exit 1; }
# - Temporary packages for install process in ISO environment
pacman -Sy --noconfirm git screen || { echo "Failed to install temporary packages (git, screen)"; exit 1; }
# - Encryption mode selection (TPM2/passphrase)
# - Partition size planning
# - Import Arch master keys
pacman-key --init && pacman-key --populate archlinux || { echo "Failed to import Arch master keys"; exit 1; }

# ### Disk Preparation Phase
# - Block device identification
# - Existing partition detection
# - Disk controller mode verification
# - Sector size optimization check
# - Partition table creation
sgdisk --zap-all /dev/nvme0n1 || { echo "Failed to wipe partition table on /dev/nvme0n1"; exit 1; }
# - Partition alignment configuration
# - ESP partition creation
sudo sgdisk --new=1:0:+512M --typecode=1:EF00 /dev/nvme0n1 || { echo "Failed to create ESP partition"; exit 1; }
# - Root partition creation
sudo sgdisk --new=2:0:0 --typecode=3:8300 /dev/nvme0n1 || { echo "Failed to create root partition"; exit 1; }
# - Swap partition creation
# - Over-provisioning space allocation
# - GPT backup creation
sudo sgdisk --print /dev/nvme0n1 || { echo "Failed to print partition table"; exit 1; }

# ### Encryption Phase
# - LUKS container creation
# - PBKDF parameter tuning
# - TPM2 enrollment
# - Passphrase configuration
# - LUKS volume opening
# - Crypttab.initramfs creation

# ### Filesystem Phase
# - ESP formatting (FAT32)
mkfs.fat -F32 /dev/nvme0n1p1 || { echo "Failed to format ESP partition"; exit 1; }
# - Root filesystem creation
mkfs.btrfs -f /dev/nvme0n1p2 || { echo "Failed to format root partition with Btrfs"; exit 1; }
# - Btrfs subvolume creation
mount /dev/nvme0n1p2 /mnt/stage || { echo "Failed to mount root partition"; exit 1; }
btrfs subvolume create /mnt/stage/@main || { echo "Failed to create subvolume @main"; exit 1; }
btrfs subvolume create /mnt/stage/@main-home || { echo "Failed to create subvolume @main-home"; exit 1; }
btrfs subvolume create /mnt/stage/@sandbox || { echo "Failed to create subvolume @sandbox"; exit 1; }
btrfs subvolume create /mnt/stage/@sandbox-home || { echo "Failed to create subvolume @sandbox-home"; exit 1; }
btrfs subvolume create /mnt/stage/@var || { echo "Failed to create subvolume @var"; exit 1; }
btrfs subvolume create /mnt/stage/@log || { echo "Failed to create subvolume @log"; exit 1; }
btrfs subvolume create /mnt/stage/@cache || { echo "Failed to create subvolume @cache"; exit 1; }
btrfs subvolume create /mnt/stage/@tmp || { echo "Failed to create subvolume @tmp"; exit 1; }
btrfs subvolume create /mnt/stage/@shared || { echo "Failed to create subvolume @shared"; exit 1; }
btrfs subvolume create /mnt/stage/@user-local || { echo "Failed to create subvolume @user-local"; exit 1; }
umount /mnt/stage || { echo "Failed to unmount /mnt/stage"; exit 1; }
# - Mount option configuration
mount -o compress=zstd:3,noatime,commit=120,ssd,discard=async,space_cache=v2,autodefrag,subvol=@main /dev/nvme0n1p2 /mnt/stage || { echo "Failed to mount @main"; exit 1; }
mkdir -p /mnt/stage/{efi,home,.snapshots,var,tmp} || { echo "Failed to create directories"; exit 1; }
mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@main-home /dev/nvme0n1p2 /mnt/stage/home || { echo "Failed to mount @main-home"; exit 1; }
mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@sandbox /dev/nvme0n1p2 /mnt/stage/.snapshots || { echo "Failed to mount @sandbox"; exit 1; }
mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@var /dev/nvme0n1p2 /mnt/stage/var || { echo "Failed to mount @var"; exit 1; }
mkdir -p /mnt/stage/var/{log,cache} || { echo "Failed to create /mnt/stage/var subdirectories"; exit 1; }
mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@log /dev/nvme0n1p2 /mnt/stage/var/log || { echo "Failed to mount @log"; exit 1; }
mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@cache /dev/nvme0n1p2 /mnt/stage/var/cache || { echo "Failed to mount @cache"; exit 1; }
mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@tmp /dev/nvme0n1p2 /mnt/stage/tmp || { echo "Failed to mount @tmp"; exit 1; }
mount /dev/nvme0n1p1 /mnt/stage/efi || { echo "Failed to mount ESP at /mnt/stage/efi"; exit 1; }

# ### System Installation Phase
# - Mirror selection and ranking
#   # (optional) Example: reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist || { echo "Mirror ranking failed"; exit 1; }
# - Base package installation (aggregate core + microcode)
pacstrap -K /mnt/stage base linux linux-firmware btrfs-progs intel-ucode || { echo "Pacstrap base+kernel+firmware+microcode failed"; exit 1; }
# - Essential tools installation (recommended)
pacstrap -K /mnt/stage networkmanager vim sudo man-db || { echo "Pacstrap essentials failed"; exit 1; }
# - Bootloader tools installation (prepare for later config)
pacstrap -K /mnt/stage grub efibootmgr || { echo "Pacstrap bootloader tools failed"; exit 1; }
# - Kernel installation (single/dual)
# - Firmware installation
# - Microcode installation
# - Network tools installation

# ### Mount Configuration Phase
# - Root volume mounting
# - Boot partition mounting
# - Additional mountpoint creation
# - Swap activation
# - Fstab generation
genfstab -U /mnt/stage >> /mnt/stage/etc/fstab || { echo "Failed to generate fstab"; exit 1; }
# - Mount option verification
grep -q 'subvolid=' /mnt/stage/etc/fstab && { echo "CRITICAL: fstab contains subvolid entries!"; exit 1; }

# ### System Configuration Phase
# - Chroot entry
arch-chroot /mnt/stage || { echo "Failed to chroot into /mnt/stage"; exit 1; }
# - Timezone configuration
ln -sf /usr/share/zoneinfo/US/Mountain /etc/localtime || { echo "Failed to set timezone"; exit 1; }
# - Hardware clock setup
hwclock --systohc || { echo "Failed to set hardware clock"; exit 1; }
# - Locale generation
# - Language configuration
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen || { echo "Failed to uncomment en_US.UTF-8 in locale.gen"; exit 1; }
locale-gen || { echo "Failed to generate locale"; exit 1; }
# - Console configuration persistence
# - Hostname configuration
# - Network configuration
# - Hosts file setup

# ### Boot Configuration Phase
# - Initramfs hook configuration
# - Initramfs generation
# - Bootloader installation
# - Boot entry creation
# - Fallback entry creation
# - Microcode loading setup
# - Kernel parameter configuration
# - Resume/hibernation setup

# ### Security Configuration Phase
# - Root password setup
# - Secure Boot key generation
# - Key enrollment
# - Kernel signing
# - UKI creation (optional)
# - TPM2 configuration

# ### System Optimization Phase
# - Swappiness tuning
# - TRIM timer enablement
# - Time synchronization service
# - Performance mount options
# - Compression settings

# ### Pre-Reboot Verification Phase
# - Configuration file review
# - UUID verification
# - Bootloader entry validation
# - ESP space check
# - Mount hierarchy verification
# - Service enablement check

# ### Reboot Phase
# - Chroot exit
# - Partition unmounting
# - System restart
# - Installation medium removal

# ### Post-Installation Phase
# - First boot verification
# - Suspend/resume testing
# - Hibernation testing
# - Network connectivity check
# - Service status verification
# - User account creation
# - GUI installation
# - Additional software setup

# ### Maintenance & Recovery Phase
# - GPT restore procedures
# - Bootloader recovery
# - UUID mismatch fixes
# - Kernel update procedures
# - Btrfs maintenance
# - SSD health monitoring
# - System backup strategy
# - Performance monitoring
