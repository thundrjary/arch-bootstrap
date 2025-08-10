# ## Complete Installation Step Categories
# 
# ### [A] Pre-Installation Phase
# - A01: ISO acquisition and verification
pacman-key -v archlinux-*.iso.sig
# - A02: Installation medium preparation
dd bs=4M if=archlinux.iso of=/dev/sdX status=progress oflag=sync
# - A03: Boot into live environment
echo "Please reboot into your firmware settings (UEFI/BIOS) and disable Secure Boot before proceeding."
# - A04: Console keyboard layout configuration
# - A05: Console font configuration
# - A06: Boot mode verification (UEFI/BIOS)
ls /sys/firmware/efi/efivars >/dev/null 2>&1
# - A07: Network interface setup
# - A08: Internet connection establishment
iwctl adapter phy0 set-property Powered on
iwctl station wlan0 connect <SSID>
ping -c3 archlinux.org
# - A09: System clock synchronization
timedatectl set-ntp true
# - A10: Pre-flight tool availability check
mkdir -p /mnt/tools
mount /dev/sda2 /mnt/tools
pacman -Sy --noconfirm git screen
pacman-key --init && pacman-key --populate archlinux
# - A11: Encryption mode selection (TPM2/passphrase)
# - A12: Partition size planning
# 
# ### [B] Disk Preparation Phase
# - B01: Block device identification
# - B02: Existing partition detection
# - B03: Disk controller mode verification
# - B04: Sector size optimization check
# - B05: Partition table creation
sgdisk --zap-all /dev/nvme0n1
# - B06: Partition alignment configuration
# - B07: ESP partition creation
sudo sgdisk --new=1:0:+512M --typecode=1:EF00 /dev/nvme0n1
# - B08: Root partition creation
sudo sgdisk --new=2:0:0 --typecode=3:8300 /dev/nvme0n1
# - B09: Swap partition creation
# - B10: Over-provisioning space allocation
# - B11: GPT backup creation
sudo sgdisk --print /dev/nvme0n1
# 
# ### [C] Encryption Phase
# - C01: LUKS container creation
cryptsetup luksFormat --type luks2 /dev/nvme0n1p2
# - C02: PBKDF parameter tuning
# - C03: TPM2 enrollment
# - C04: Passphrase configuration
# - C05: LUKS volume opening
cryptsetup open /dev/nvme0n1p2 cryptroot
[ -b /dev/mapper/cryptroot ]
# - C06: Crypttab.initramfs creation
# 
# ### [D] Filesystem Phase
# - D01: ESP formatting (FAT32)
mkfs.fat -F32 /dev/nvme0n1p1
# - D02: Root filesystem creation
# OLD: mkfs.btrfs -f /dev/nvme0n1p2
mkfs.btrfs -f /dev/mapper/cryptroot
# - D03: Swap space initialization
# - D04: Btrfs subvolume creation
# OLD mount /dev/nvme0n1p2 /mnt/stage
mount /dev/mapper/cryptroot /mnt/stage
btrfs subvolume create /mnt/stage/@main
btrfs subvolume create /mnt/stage/@main-home
btrfs subvolume create /mnt/stage/@sandbox
btrfs subvolume create /mnt/stage/@sandbox-home
btrfs subvolume create /mnt/stage/@var
btrfs subvolume create /mnt/stage/@log
btrfs subvolume create /mnt/stage/@cache
btrfs subvolume create /mnt/stage/@tmp
btrfs subvolume create /mnt/stage/@shared
btrfs subvolume create /mnt/stage/@user-local
umount /mnt/stage
# - D05: Compression configuration
# - D06: Mount option configuration
mount -o compress=zstd:3,noatime,commit=120,ssd,discard=async,space_cache=v2,autodefrag,subvol=@main /dev/mapper/cryptroot /mnt/stage
mkdir -p /mnt/stage/{efi,home,var,tmp}
mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@main-home /dev/mapper/cryptroot /mnt/stage/home
mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@sandbox /dev/mapper/cryptroot /mnt/stage/
mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@var /dev/mapper/cryptroot /mnt/stage/var
mkdir -p /mnt/stage/var/{log,cache}
mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@log /dev/mapper/cryptroot /mnt/stage/var/log
mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@cache /dev/mapper/cryptroot /mnt/stage/var/cache
mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@tmp /dev/mapper/cryptroot /mnt/stage/tmp
mount /dev/nvme0n1p1 /mnt/stage/efi
# 
# ### [E] System Installation Phase
# - E01: Mirror selection and ranking
# # (optional) Example: reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
# - E02: Base package installation
pacstrap -K /mnt/stage base linux linux-firmware btrfs-progs intel-ucode
# - E03: Kernel installation (single/dual)
# - E04: Firmware installation
# - E05: Microcode installation
# - E06: Essential tools installation
pacstrap -K /mnt/stage networkmanager vim sudo man-db
pacstrap -K /mnt/stage grub efibootmgr
pacstrap -K /mnt/stage tpm2-tss tpm2-tools
# - E07: Network tools installation
# 
# ### [F] Mount Configuration Phase
# - F01: Root volume mounting
# - F02: Boot partition mounting
# - F03: Additional mountpoint creation
# - F04: Swap activation
# - F05: Fstab generation
genfstab -U /mnt/stage >> /mnt/stage/etc/fstab
# - F06: Mount option verification
grep -q 'subvolid=' /mnt/stage/etc/fstab && { echo "CRITICAL: fstab contains subvolid entries!"; exit 1; }
# 
# ### [G] System Configuration Phase
# - G01: Chroot entry
arch-chroot /mnt/stage
# - G02: Timezone configuration
ln -sf /usr/share/zoneinfo/US/Mountain /etc/localtime
# - G03: Hardware clock setup
hwclock --systohc
# - G04: Locale generation
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
# - G05: Language configuration
echo "LANG=en_US.UTF-8" > /etc/locale.conf
# - G06: Console configuration persistence
echo "KEYMAP=us" > /etc/vconsole.conf
# - G07: Hostname configuration
echo "lollypop" > /etc/hostname
# - G08: Network configuration
# - G09: Hosts file setup
echo "127.0.1.1 lollypop.localdomain lollypop" >> /etc/hosts
# 
# ### [H] Boot Configuration Phase
# - H01: Initramfs hook configuration
#   -- Base mkinitcpio config with optional LUKS+TPM2 path. Toggle by exporting LUKS_TPM2=1 before running.
LUKS_UUID=$(blkid -s UUID -o value /dev/nvme0n1p2)
[ -z "$LUKS_UUID" ] && { echo "ERROR: Could not determine LUKS UUID"; exit 1; }
printf 'cryptroot UUID=%s - tpm2-device=auto\n' "$LUKS_UUID" > /etc/crypttab.initramfs
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
mkinitcpio -P
# H03: Bootloader installation
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
[ -f /boot/grub/grub.cfg ]
# - H04: Boot entry creation
# - H05: Fallback entry creation
# - H06: Microcode loading setup
# H07: Kernel parameter configuration
LUKS_UUID=$(blkid -s UUID -o value /dev/nvme0n1p2)
[ -z "$LUKS_UUID" ] && { echo "ERROR: Could not determine LUKS UUID for kernel params"; exit 1; }
cp /etc/default/grub /etc/default/grub.bak
sed -i "s/^GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"rd.luks.name=${LUKS_UUID}=cryptroot root=\/dev\/mapper\/cryptroot /" /etc/default/grub
grep -q "rd.luks.name=" /etc/default/grub
#   If using LUKS+TPM2, remember to add kernel params later (e.g., 'rd.luks.name=<UUID>=cryptroot resume=UUID=<swap-uuid>' or 'resume_offset=...').
# - H08: Resume/hibernation setup
# 
# 
# ### [I] Security Configuration Phase
# - I01: Root password setup
passwd
# - I02: Secure Boot key generation
# - I03: Key enrollment
# - I04: Kernel signing
# - I05: UKI creation (optional)
# I06: TPM2 configuration
# -- Check TPM2 availability first
systemd-cryptenroll --tpm2-device=list > /dev/null 2>&1
if systemd-cryptenroll --tpm2-device=list > /dev/null 2>&1; then
    systemd-cryptenroll /dev/nvme0n1p2 --tpm2-device=auto --tpm2-pcrs=0+7
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
useradd -mG wheel <user>
passwd <user>
EDITOR=vim visudo
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
