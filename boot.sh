# ## Complete Installation Step Categories
# 
# ### [A] Pre-Installation Phase
# - A01: ISO acquisition and verification
pacman-key -v archlinux-*.iso.sig || { echo "ISO verification failed"; exit 1; }
# - A02: Installation medium preparation
dd bs=4M if=archlinux.iso of=/dev/sdX status=progress oflag=sync || { echo "Failed to write ISO to USB"; exit 1; }
# - A03: Boot into live environment
echo "Please reboot into your firmware settings (UEFI/BIOS) and disable Secure Boot before proceeding."
# - A04: Console keyboard layout configuration
# - A05: Console font configuration
# - A06: Boot mode verification (UEFI/BIOS)
ls /sys/firmware/efi/efivars >/dev/null 2>&1 || { echo "System not booted in UEFI mode"; exit 1; }
# - A07: Network interface setup
# - A08: Internet connection establishment
iwctl adapter phy0 set-property Powered on || { echo "Failed to power on Wi-Fi adapter"; exit 1; }
iwctl station wlan0 connect <SSID> || { echo "Failed to connect to Wi-Fi"; exit 1; }
ping -c3 archlinux.org || { echo "Network connectivity test failed"; exit 1; }
# - A09: System clock synchronization
timedatectl set-ntp true || { echo "Failed to enable NTP"; exit 1; }
# - A10: Pre-flight tool availability check
mkdir -p /mnt/tools || { echo "Failed to create /mnt/tools"; exit 1; }
mount /dev/sda2 /mnt/tools || { echo "Failed to mount /dev/sda2 to /mnt/tools"; exit 1; }
pacman -Sy --noconfirm git screen || { echo "Failed to install temporary packages (git, screen)"; exit 1; }
pacman-key --init && pacman-key --populate archlinux || { echo "Failed to import Arch master keys"; exit 1; }
# - A11: Encryption mode selection (TPM2/passphrase)
# - A12: Partition size planning
# 
# ### [B] Disk Preparation Phase
# - B01: Block device identification
# - B02: Existing partition detection
# - B03: Disk controller mode verification
# - B04: Sector size optimization check
# - B05: Partition table creation
sgdisk --zap-all /dev/nvme0n1 || { echo "Failed to wipe partition table on /dev/nvme0n1"; exit 1; }
# - B06: Partition alignment configuration
# - B07: ESP partition creation
sudo sgdisk --new=1:0:+512M --typecode=1:EF00 /dev/nvme0n1 || { echo "Failed to create ESP partition"; exit 1; }
# - B08: Root partition creation
sudo sgdisk --new=2:0:0 --typecode=3:8300 /dev/nvme0n1 || { echo "Failed to create root partition"; exit 1; }
# - B09: Swap partition creation
# - B10: Over-provisioning space allocation
# - B11: GPT backup creation
sudo sgdisk --print /dev/nvme0n1 || { echo "Failed to print partition table"; exit 1; }
# 
# ### [C] Encryption Phase
# - C01: LUKS container creation
cryptsetup luksFormat --type luks2 /dev/nvme0n1p2
# - C02: PBKDF parameter tuning
# - C03: TPM2 enrollment
# - C04: Passphrase configuration
# - C05: LUKS volume opening
cryptsetup open /dev/nvme0n1p2 cryptroot || { echo "Failed to open LUKS container"; exit 1; }
[ -b /dev/mapper/cryptroot ] || { echo "ERROR: Encrypted device /dev/mapper/cryptroot not available"; exit 1; }
# - C06: Crypttab.initramfs creation
# 
# ### [D] Filesystem Phase
# - D01: ESP formatting (FAT32)
mkfs.fat -F32 /dev/nvme0n1p1 || { echo "Failed to format ESP partition"; exit 1; }
# - D02: Root filesystem creation
# OLD: mkfs.btrfs -f /dev/nvme0n1p2 || { echo "Failed to format root partition with Btrfs"; exit 1; }
mkfs.btrfs -f /dev/mapper/cryptroot || { echo "Failed to format encrypted root partition with Btrfs"; exit 1; }
# - D03: Swap space initialization
# - D04: Btrfs subvolume creation
# OLD mount /dev/nvme0n1p2 /mnt/stage || { echo "Failed to mount root partition"; exit 1; }
mount /dev/mapper/cryptroot /mnt/stage || { echo "Failed to mount encrypted root partition"; exit 1; }
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
# - D05: Compression configuration
# - D06: Mount option configuration
mount -o compress=zstd:3,noatime,commit=120,ssd,discard=async,space_cache=v2,autodefrag,subvol=@main /dev/mapper/cryptroot /mnt/stage || { echo "Failed to mount @main"; exit 1; }
mkdir -p /mnt/stage/{efi,home,var,tmp} || { echo "Failed to create directories"; exit 1; }
mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@main-home /dev/mapper/cryptroot /mnt/stage/home || { echo "Failed to mount @main-home"; exit 1; }
mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@sandbox /dev/mapper/cryptroot /mnt/stage/ || { echo "Failed to mount @sandbox"; exit 1; }
mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@var /dev/mapper/cryptroot /mnt/stage/var || { echo "Failed to mount @var"; exit 1; }
mkdir -p /mnt/stage/var/{log,cache} || { echo "Failed to create /mnt/stage/var subdirectories"; exit 1; }
mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@log /dev/mapper/cryptroot /mnt/stage/var/log || { echo "Failed to mount @log"; exit 1; }
mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@cache /dev/mapper/cryptroot /mnt/stage/var/cache || { echo "Failed to mount @cache"; exit 1; }
mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@tmp /dev/mapper/cryptroot /mnt/stage/tmp || { echo "Failed to mount @tmp"; exit 1; }
mount /dev/nvme0n1p1 /mnt/stage/efi || { echo "Failed to mount ESP at /mnt/stage/efi"; exit 1; }
# 
# ### [E] System Installation Phase
# - E01: Mirror selection and ranking
# # (optional) Example: reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist || { echo "Mirror ranking failed"; exit 1; }
# - E02: Base package installation
pacstrap -K /mnt/stage base linux linux-firmware btrfs-progs intel-ucode || { echo "Pacstrap base+kernel+firmware+microcode failed"; exit 1; }
# - E03: Kernel installation (single/dual)
# - E04: Firmware installation
# - E05: Microcode installation
# - E06: Essential tools installation
pacstrap -K /mnt/stage networkmanager vim sudo man-db || { echo "Pacstrap essentials failed"; exit 1; }
pacstrap -K /mnt/stage grub efibootmgr || { echo "Pacstrap bootloader tools failed"; exit 1; }
pacstrap -K /mnt/stage tpm2-tss tpm2-tools
# - E07: Network tools installation
# 
# ### [F] Mount Configuration Phase
# - F01: Root volume mounting
# - F02: Boot partition mounting
# - F03: Additional mountpoint creation
# - F04: Swap activation
# - F05: Fstab generation
genfstab -U /mnt/stage >> /mnt/stage/etc/fstab || { echo "Failed to generate fstab"; exit 1; }
# - F06: Mount option verification
grep -q 'subvolid=' /mnt/stage/etc/fstab && { echo "CRITICAL: fstab contains subvolid entries!"; exit 1; }
# 
# ### [G] System Configuration Phase
# - G01: Chroot entry
arch-chroot /mnt/stage || { echo "Failed to chroot into /mnt/stage"; exit 1; }
# - G02: Timezone configuration
ln -sf /usr/share/zoneinfo/US/Mountain /etc/localtime || { echo "Failed to set timezone"; exit 1; }
# - G03: Hardware clock setup
hwclock --systohc || { echo "Failed to set hardware clock"; exit 1; }
# - G04: Locale generation
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen || { echo "Failed to uncomment en_US.UTF-8 in locale.gen"; exit 1; }
locale-gen || { echo "Failed to generate locale"; exit 1; }
# - G05: Language configuration
echo "LANG=en_US.UTF-8" > /etc/locale.conf || { echo "Failed to configure /etc/locale.conf"; exit 1; }
# - G06: Console configuration persistence
echo "KEYMAP=us" > /etc/vconsole.conf || { echo "Failed to configure /etc/vconsole.conf"; exit 1; }
# - G07: Hostname configuration
echo "lollypop" > /etc/hostname || { echo "Failed to set hostname"; exit 1; }
# - G08: Network configuration
# - G09: Hosts file setup
echo "127.0.1.1 lollypop.localdomain lollypop" >> /etc/hosts || { echo "Failed to configure /etc/hosts"; exit 1; }
# 
# ### [H] Boot Configuration Phase
# - H01: Initramfs hook configuration
#   -- Base mkinitcpio config with optional LUKS+TPM2 path. Toggle by exporting LUKS_TPM2=1 before running.
LUKS_UUID=$(blkid -s UUID -o value /dev/nvme0n1p2) || { echo "Failed to get LUKS UUID"; exit 1; }
[ -z "$LUKS_UUID" ] && { echo "ERROR: Could not determine LUKS UUID"; exit 1; }
printf 'cryptroot UUID=%s - tpm2-device=auto\n' "$LUKS_UUID" > /etc/crypttab.initramfs || { echo "Failed to create crypttab.initramfs"; exit 1; }
#   -- Use zstd compression
sed -i 's/^#*COMPRESSION=.*/COMPRESSION="zstd"/' /etc/mkinitcpio.conf
#   -- Ensure required modules (add btrfs for root FS)
sed -i 's/^MODULES=.*/MODULES=(btrfs)/' /etc/mkinitcpio.conf
echo 'MODULES=(btrfs)' >> /etc/mkinitcpio.conf
#   -- Set HOOKS depending on encryption choice
# -- systemd-based initramfs with sd-encrypt and resume
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt resume filesystems fsck)/' /etc/mkinitcpio.conf
# -- Prepare crypttab for TPM2 auto-unlock (run after luksFormat so UUID exists)
blkid -s UUID -o value "$ROOT_PART"
printf 'cryptroot UUID=%s - tpm2-device=auto\n' "$LUKS_UUID" > /etc/crypttab.initramfs
# -- classic udev-based initramfs without encryption
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)/' /etc/mkinitcpio.conf
# - H02: Initramfs generation
mkinitcpio -P || { echo "mkinitcpio failed"; exit 1; }
# H03: Bootloader installation
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB || { echo "Failed to install GRUB bootloader"; exit 1; }
grub-mkconfig -o /boot/grub/grub.cfg || { echo "Failed to generate GRUB config"; exit 1; }
[ -f /boot/grub/grub.cfg ] || { echo "ERROR: GRUB config file not created"; exit 1; }
# - H04: Boot entry creation
# - H05: Fallback entry creation
# - H06: Microcode loading setup
# H07: Kernel parameter configuration
LUKS_UUID=$(blkid -s UUID -o value /dev/nvme0n1p2) || { echo "Failed to get LUKS UUID for kernel params"; exit 1; }
[ -z "$LUKS_UUID" ] && { echo "ERROR: Could not determine LUKS UUID for kernel params"; exit 1; }
cp /etc/default/grub /etc/default/grub.bak || { echo "Failed to backup GRUB config"; exit 1; }
sed -i "s/^GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"rd.luks.name=${LUKS_UUID}=cryptroot root=\/dev\/mapper\/cryptroot /" /etc/default/grub || { echo "Failed to add kernel parameters to GRUB"; exit 1; }
grep -q "rd.luks.name=" /etc/default/grub || { echo "ERROR: Kernel parameters not added to GRUB config"; exit 1; }
#   If using LUKS+TPM2, remember to add kernel params later (e.g., 'rd.luks.name=<UUID>=cryptroot resume=UUID=<swap-uuid>' or 'resume_offset=...').
# - H08: Resume/hibernation setup
# 
# 
# ### [I] Security Configuration Phase
# - I01: Root password setup
passwd || { echo "Failed to set root password"; exit 1; }
# - I02: Secure Boot key generation
# - I03: Key enrollment
# - I04: Kernel signing
# - I05: UKI creation (optional)
# I06: TPM2 configuration
# -- Check TPM2 availability first
systemd-cryptenroll --tpm2-device=list > /dev/null 2>&1 || { echo "WARNING: No TPM2 device found, skipping enrollment"; }
if systemd-cryptenroll --tpm2-device=list > /dev/null 2>&1; then
    systemd-cryptenroll /dev/nvme0n1p2 --tpm2-device=auto --tpm2-pcrs=0+7 || { echo "Failed to enroll TPM2 for LUKS"; exit 1; }
    echo "TPM2 enrollment successful"
else
    echo "TPM2 not available - system will require passphrase at boot"
fi
# 
# ### [J] System Optimization Phase
# - J01: Swappiness tuning
# - J02: TRIM timer enablement
# - J03: Time synchronization service
# - J04: Performance mount options
# - J05: Compression settings
# 
# ### [K] Pre-Reboot Verification Phase
# - K01: Configuration file review
# - K02: UUID verification
# - K03: Bootloader entry validation
# - K04: ESP space check
# - K05: Mount hierarchy verification
# - K06: Service enablement check
# 
# ### [L] Reboot Phase
# - L01: Chroot exit
# - L02: Partition unmounting
# - L03: System restart
# - L04: Installation medium removal
# 
# ### [M] Post-Installation Phase
# - M01: First boot verification
# - M02: Suspend/resume testing
# - M03: Hibernation testing
# - M04: Network connectivity check
# - M05: Service status verification
# - M06: User account creation
useradd -mG wheel <user> || { echo "Failed to create user"; exit 1; }
passwd <user> || { echo "Failed to set user password"; exit 1; }
EDITOR=vim visudo || { echo "Failed to open visudo"; exit 1; }
# - M07: GUI installation
# - M08: Additional software setup
# 
# ### [N] Maintenance & Recovery Phase
# - N01: GPT restore procedures
# - N02: Bootloader recovery
# - N03: UUID mismatch fixes
# - N04: Kernel update procedures
# - N05: Btrfs maintenance
# - N06: SSD health monitoring
# - N07: System backup strategy
# - N08: Performance monitoring
