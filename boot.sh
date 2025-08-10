#!/bin/bash

# ARCH LINUX BOOTSTRAP
# ====================

# [A] PRE-INSTALLATION PHASE
# --------------------------

# .A01: ISO acquisition and verification
pacman-key -v archlinux-*.iso.sig

# .A02: Installation medium preparation
dd bs=4M if=archlinux.iso of=/dev/sdX status=progress oflag=sync

# .A03: Boot into live environment
echo "Please reboot into your firmware settings (UEFI/BIOS) and disable Secure Boot before proceeding."

# .A04: Console keyboard layout configuration
# .A05: Console font configuration

# .A06: Boot mode verification (UEFI/BIOS)
ls /sys/firmware/efi/efivars >/dev/null 2>&1 && echo "UEFI mode confirmed" || { echo "ERROR: BIOS mode detected, UEFI required"; exit 1; }

# .A07: Network interface setup

# .A08: Internet connection establishment
iwctl adapter phy0 set-property Powered on
iwctl station wlan0 connect <SSID>
ping -c3 archlinux.org || { echo "ERROR: No internet connectivity"; exit 1; }

# .A09: System clock synchronization
timedatectl set-ntp true
timedatectl status

# .A10: Pre-flight tool availability check
mkdir -p /mnt/tools 2>/dev/null || true
mount /dev/sda2 /mnt/tools
pacman -Sy --noconfirm git screen reflector
pacman-key --init && pacman-key --populate archlinux

# .A11: Encryption mode selection (TPM2/passphrase) / TPM2 availability check
echo "Checking TPM2 availability..."
if [ -d /sys/class/tpm ] && [ -c /dev/tpm0 ]; then
    echo "TPM2 hardware detected"
    TPM2_AVAILABLE=true
else
    echo "No TPM2 hardware found - will use passphrase only"
    TPM2_AVAILABLE=false
fi

# .A12: Partition size planning
# .A13: Install tooling
pacman -Sy --needed sgdisk cryptsetup btrfs-progs dosfstools util-linux gptfdisk


# [B] DISK PREPARATION PHASE
# --------------------------

# .B00: Confirm target disk and ensure it's not mounted
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT /dev/nvme0n1
lsblk -nrpo MOUNTPOINT /dev/nvme0n1 | grep -q . && echo "[!] Something on /dev/nvme0n1 is mounted. Unmount first." && exit 1
blockdev --getsize64 /dev/nvme0n1
cat /sys/block/nvme0n1/device/model 2>/dev/null || echo "?"
echo ""
echo "WARNING: This will DESTROY ALL DATA on /dev/nvme0n1"
echo "Current partition table:"
sgdisk --print /dev/nvme0n1 2>/dev/null || echo "No existing partition table found"
echo ""
read -p "Type 'YES' to continue with disk destruction: " confirm
[ "$confirm" = "YES" ] || { echo "Aborted by user"; exit 1; }

# .B01: Block device identification
# .B02: Existing partition detection
umount /dev/nvme0n1* 2>/dev/null || true
swapoff /dev/nvme0n1* 2>/dev/null || true

# .B03: Disk controller mode verification
# .B04: Sector size optimization check
# Check available disk space
DISK_SIZE=$(lsblk -bno SIZE /dev/nvme0n1 | head -1)
MIN_SIZE=$((20*1024*1024*1024))  # 20GB minimum
[ "$DISK_SIZE" -lt "$MIN_SIZE" ] && { echo "ERROR: Disk too small (minimum 20GB)"; exit 1; }

# .B05: Partition table creation
echo "[*] Wiping old signatures & creating new aligned GPT"
sudo wipefs -a /dev/nvme0n1
sudo sgdisk -Z /dev/nvme0n1
sudo sgdisk -a 2048 -o /dev/nvme0n1   # 1 MiB alignment

# .B06: Partition alignment configuration
# .B07: ESP partition creation
# ESP 1 GiB starting at 1 MiB
sudo sgdisk -n 1:2048:+1G -t 1:EF00 -c 1:"ESP" /dev/nvme0n1

# .B08: Root partition creation
sudo sgdisk -n 2:0:-32G -t 2:8309 -c 2:"cryptroot" /dev/nvme0n1

# .B09: Swap partition creation
sudo sgdisk -n 3:0:-20G -t 3:8309 -c 3:"cryptswap" /dev/nvme0n1

# .B10: Over-provisioning space allocation
# .B11: GPT backup creation
sudo sgdisk -p /dev/nvme0n1
sudo sgdisk --backup=gpt-nvme0n1-backup.bin /dev/nvme0n1
sudo sgdisk --load-backup=gpt-nvme0n1-backup.bin /dev/nvme0n1
sudo sgdisk -e /dev/nvme0n1
sudo partprobe /dev/nvme0n1

# .TEST01: Sector size consistency verification
echo "TEST01: Sector size verification"
blockdev --getss /dev/nvme0n1     # Should be 512
blockdev --getpbsz /dev/nvme0n1   # Should be 4096
fdisk -l /dev/nvme0n1 | grep "Sector size"

# .TEST02: Partition alignment verification  
echo "TEST02: Partition alignment verification"
sgdisk -A 1 /dev/nvme0n1    # ESP alignment check
sgdisk -A 2 /dev/nvme0n1    # Root alignment check
sgdisk -A 3 /dev/nvme0n1    # Swap alignment check
parted /dev/nvme0n1 align-check optimal 1
parted /dev/nvme0n1 align-check optimal 2
parted /dev/nvme0n1 align-check optimal 3

# .TEST03: Size verification (multiple tools)
echo "TEST03: Partition size verification"
lsblk -bno SIZE /dev/nvme0n1p1    # ESP size in bytes
blockdev --getsize64 /dev/nvme0n1p1
sgdisk -i 1 /dev/nvme0n1 | grep "size"
lsblk -bno SIZE /dev/nvme0n1p2    # Root size in bytes
lsblk -bno SIZE /dev/nvme0n1p3    # Swap size in bytes


# [C] ENCRYPTION PHASE
# --------------------

# .C01: LUKS container creation
# LUKS2 format root (partition 2) with stronger PBKDF
sudo cryptsetup luksFormat /dev/nvme0n1p2 \
  --type luks2 --pbkdf argon2id --iter-time 1500 \
  --cipher aes-xts-plain64 --key-size 512 --hash sha256 --label cryptroot
# LUKS2 format swap (partition 3) with lighter PBKDF
sudo cryptsetup luksFormat /dev/nvme0n1p3 \
  --type luks2 --pbkdf argon2id --iter-time 800 \
  --cipher aes-xts-plain64 --key-size 512 --hash sha256 --label cryptswap

# .C02: PBKDF parameter tuning
# .C03: TPM2 enrollment
# .C04: Passphrase configuration
# .C05: LUKS volume opening
# Open LUKS volumes (will prompt twice for passphrase)
sudo cryptsetup open /dev/nvme0n1p2 cryptroot
sudo cryptsetup open /dev/nvme0n1p3 cryptswap
[ -b /dev/mapper/cryptroot ] || { echo "ERROR: Failed to open LUKS volume"; exit 1; }

# .C06: Crypttab.initramfs creation (TPM2 auto-unlock)
# Write crypttab.initramfs (passphrase mode, luks only)
sudo mkdir -p /mnt/stage/etc
sudo tee /mnt/stage/etc/crypttab.initramfs >/dev/null <<'EOF'
cryptroot UUID=$(blkid -s UUID -o value /dev/nvme0n1p2) none luks
cryptswap UUID=$(blkid -s UUID -o value /dev/nvme0n1p3) none luks
EOF

# .C07: Store LUKS UUID for later use
LUKS_UUID=$(blkid -s UUID -o value /dev/nvme0n1p2)
[ -z "$LUKS_UUID" ] && { echo "ERROR: Could not determine LUKS UUID"; exit 1; }
echo "LUKS UUID: $LUKS_UUID"

# .TEST04: LUKS headers verification
echo "TEST04: LUKS configuration verification"
cryptsetup luksDump /dev/nvme0n1p2 | grep -E "(Version|Cipher|Hash|PBKDF)"
cryptsetup luksDump /dev/nvme0n1p3 | grep -E "(Version|Cipher|Hash|PBKDF)"

# .TEST05: Key slot verification
echo "TEST05: LUKS key slot verification"
cryptsetup luksDump /dev/nvme0n1p2 | grep -A5 "Keyslots"
cryptsetup luksDump /dev/nvme0n1p3 | grep -A5 "Keyslots"

# .TEST06: Encryption strength verification
echo "TEST06: PBKDF timing verification"
cryptsetup luksDump /dev/nvme0n1p2 | grep "Iteration time"
cryptsetup luksDump /dev/nvme0n1p3 | grep "Iteration time"


# [D] FILESYSTEM PHASE
# --------------------

# .D01: ESP formatting (FAT32)
sudo mkfs.vfat -F32 -n ESP /dev/nvme0n1p1
# Verify ESP filesystem
fsck.fat -v /dev/nvme0n1p1 || { echo "ERROR: ESP filesystem verification failed"; exit 1; }

# .D02: Root filesystem creation
sudo mkfs.btrfs -L archroot -m dup /dev/mapper/cryptroot

# .D03: Swap space initialization
# Make swap
sudo mkswap -L swap /dev/mapper/cryptswap
# .D04: Btrfs subvolume creation
# Create subvolumes
sudo mount /dev/mapper/cryptroot /mnt/stage
sudo btrfs subvolume create /mnt/stage/@main
sudo btrfs subvolume create /mnt/stage/@main-home
sudo btrfs subvolume create /mnt/stage/@var
sudo btrfs subvolume create /mnt/stage/@log
sudo btrfs subvolume create /mnt/stage/@cache
sudo btrfs subvolume create /mnt/stage/@tmp
sudo btrfs subvolume create /mnt/stage/@shared
sudo btrfs subvolume create /mnt/stage/@user-local
sudo umount /mnt/stage

# .D05: Compression configuration
# .D06: Mount option configuration
sudo mount -o compress=zstd:3,noatime,commit=120,ssd,discard=async,space_cache=v2,autodefrag,subvol=@main /dev/mapper/cryptroot /mnt/stage
sudo mkdir -p /mnt/stage/{efi,home,var,tmp,shared,usr/local}
sudo mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@main-home   /dev/mapper/cryptroot /mnt/stage/home
sudo mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@var         /dev/mapper/cryptroot /mnt/stage/var
sudo mkdir -p /mnt/stage/var/{log,cache}
sudo mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@log         /dev/mapper/cryptroot /mnt/stage/var/log
sudo mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@cache       /dev/mapper/cryptroot /mnt/stage/var/cache
sudo mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@tmp         /dev/mapper/cryptroot /mnt/stage/tmp
sudo mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@shared      /dev/mapper/cryptroot /mnt/stage/shared
sudo mount -o noatime,compress=zstd:3,space_cache=v2,autodefrag,discard=async,subvol=@user-local  /dev/mapper/cryptroot /mnt/stage/usr/local
sudo mount /dev/nvme0n1p1 /mnt/stage/efi

# Verify all mounts are successful
for mount_point in /mnt/stage /mnt/stage/efi /mnt/stage/home /mnt/stage/var /mnt/stage/var/log /mnt/stage/var/cache; do
    mountpoint -q "$mount_point" || { echo "ERROR: $mount_point not mounted"; exit 1; }
done
echo "All mounts successful"

# .TEST07: UUID cross-verification
echo "TEST07: UUID consistency verification"
blkid /dev/nvme0n1p1   # ESP UUID
blkid /dev/nvme0n1p2   # LUKS root UUID  
blkid /dev/nvme0n1p3   # LUKS swap UUID
blkid /dev/mapper/cryptroot   # Btrfs UUID
blkid /dev/mapper/cryptswap   # Swap UUID

# .TEST08: Btrfs filesystem verification
echo "TEST08: Btrfs verification"
btrfs filesystem show /dev/mapper/cryptroot
btrfs subvolume list /mnt/stage
btrfs filesystem usage /mnt/stage

# .TEST09: Mount options verification
echo "TEST09: Mount options verification"
mount | grep /mnt/stage
findmnt /mnt/stage -o SOURCE,TARGET,FSTYPE,OPTIONS

# .TEST10: ESP filesystem check
echo "TEST10: ESP filesystem verification"
fsck.fat -v /dev/nvme0n1p1

# .TEST11: Size accounting verification
echo "TEST11: Partition size math verification"
TOTAL=$(blockdev --getsize64 /dev/nvme0n1)
ESP=$(blockdev --getsize64 /dev/nvme0n1p1) 
ROOT=$(blockdev --getsize64 /dev/nvme0n1p2)
SWAP=$(blockdev --getsize64 /dev/nvme0n1p3)
echo "Total: $TOTAL, Used: $((ESP + ROOT + SWAP)), Free: $((TOTAL - ESP - ROOT - SWAP))"
echo "OP space: $((TOTAL - ESP - ROOT - SWAP)) bytes = $(((TOTAL - ESP - ROOT - SWAP) / 1024 / 1024 / 1024)) GiB"

# .TEST20: Hardware compatibility verification
echo "TEST20: Hardware compatibility verification"
lscpu | grep -E "(Vendor ID|Model name|Flags.*aes)"
lsmod | grep -E "(aes|crypto)"
cat /proc/meminfo | grep MemTotal
dmesg | grep -i "nvme\|ssd" | head -5

# .TEST21: Memory/swap ratio verification
echo "TEST21: Memory/swap ratio verification"
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_GB=$((TOTAL_RAM_KB / 1024 / 1024))
SWAP_SIZE_GB=$(((SWAP) / 1024 / 1024 / 1024))
echo "RAM: ${TOTAL_RAM_GB}GB, Swap: ${SWAP_SIZE_GB}GB, Ratio: $(echo "scale=2; $SWAP_SIZE_GB / $TOTAL_RAM_GB" | bc)"

# Reminder for base install
echo "pacstrap /mnt base linux linux-headers linux-lts linux-lts-headers \\"
echo "               linux-firmware mkinitcpio btrfs-progs cryptsetup \\"
echo "               networkmanager dosfstools util-linux gptfdisk \\"
echo "               intel-ucode   # or amd-ucode depending on CPU"


# [E] SYSTEM INSTALLATION PHASE
# -----------------------------

# E01: Update keys & package database
pacman-key --refresh-keys
pacman -Sy archlinux-keyring

# E02: Mirror selection & ranking
pacman -Sy --needed reflector
reflector --country US --latest 50 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# E03–E08: All base system, tools, drivers, firmware, and extras
pacstrap -K /mnt/stage \
    base base-devel btrfs-progs \             # .E03 Base system + filesystem tools
    linux linux-headers linux-lts linux-lts-headers linux-firmware intel-ucode \        # .E03 Kernel + firmware + microcode
    vim nano sudo man-db man-pages texinfo \       # .E04 Essential system tools + editors
    efibootmgr \                              # .E05 EFI boot management tools
    tpm2-tss tpm2-tools \                     # .E06 Security & TPM support
    networkmanager bluez bluez-utils \        # .E07 Networking & Bluetooth
    mesa vulkan-intel intel-media-driver \    # .E08 Graphics & video drivers
    libinput iio-sensor-proxy \               # .E08 Input & sensor drivers
    tlp tlp-rdw pipewire wireplumber pipewire-pulse pipewire-alsa \ # .E08 Power & audio system
    sof-firmware linux-firmware-marvell \         # .E08 Intel audio firmware + additional wifi
    plymouth \
    uwsm \
    git wget curl

# Verify critical packages were installed
echo "Verifying package installation..."
arch-chroot /mnt/stage pacman -Qqe > /tmp/installed-packages.txt
echo "Installed $(wc -l < /tmp/installed-packages.txt) packages"
for pkg in base linux linux-lts networkmanager; do
    arch-chroot /mnt/stage pacman -Qi $pkg >/dev/null || { echo "ERROR: Critical package $pkg not installed"; exit 1; }
done
echo "Critical packages verified"

# .TEST22: Package dependency verification
echo "TEST22: Package dependency verification"
arch-chroot /mnt/stage pacman -Qi linux | grep "Required By"
arch-chroot /mnt/stage pacman -Qi linux-lts | grep "Required By"
arch-chroot /mnt/stage pacman -Qi intel-ucode | grep "Install Date"

# .TEST23: Microcode verification
echo "TEST23: Microcode verification"
arch-chroot /mnt/stage ls -la /boot/intel-ucode.img
arch-chroot /mnt/stage file /boot/intel-ucode.img


# [F] MOUNT CONFIGURATION PHASE
# -----------------------------

# .F01: Root volume mounting
# .F02: Boot partition mounting
# .F03: Additional mountpoint creation
# .F04: Swap activation
# .F05: Fstab generation
sudo genfstab -U /mnt/stage | sudo tee -a /mnt/stage/etc/fstab

# .F06: Mount option verification
grep -q 'subvolid=' /mnt/stage/etc/fstab && { echo "CRITICAL: fstab contains subvolid entries!"; exit 1; }

# .TEST12: fstab and crypttab UUID consistency
echo "TEST12: Configuration file UUID verification"
grep UUID /mnt/stage/etc/fstab
grep UUID /mnt/stage/etc/crypttab.initramfs


# [G] SYSTEM CONFIGURATION PHASE
# ------------------------------

# .G01: Chroot entry
arch-chroot /mnt/stage /bin/bash <<'CHROOT_EOF'

# .G02: Timezone configuration
ln -sf /usr/share/zoneinfo/US/Mountain /etc/localtime

# .G03: Hardware clock setup
hwclock --systohc

# .G04: Locale generation
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen

# .G05: Language configuration
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# .G06: Console configuration persistence
echo "KEYMAP=us" > /etc/vconsole.conf

# .G07: Hostname configuration
echo "lollypop" > /etc/hostname

# .G08: Network configuration
systemctl enable NetworkManager

# .G09: Hosts file setup
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   lollypop.localdomain lollypop
EOF

# .TEST24: System configuration verification
echo "TEST24: System configuration verification"
ls -la /etc/localtime
locale | grep LANG
cat /etc/vconsole.conf
cat /etc/hostname
getent hosts lollypop


# [H] BOOT CONFIGURATION PHASE
# ----------------------------

# .H01: Initramfs hook configuration
LUKS_UUID=$(blkid -s UUID -o value /dev/nvme0n1p2)
printf 'cryptroot UUID=%s - tpm2-device=auto\n' "$LUKS_UUID" > /etc/crypttab.initramfs

# Install intel-ucode
pacman -Sy --noconfirm intel-ucode

# Tuning: prefer RAM over swap, enable TRIM, enable time sync
printf "vm.swappiness=10\n" > /etc/sysctl.d/99-sysctl.conf
systemctl enable --now fstrim.timer
systemctl enable systemd-timesyncd

# mkinitcpio hooks for systemd initramfs with sd-encrypt + resume
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect modconf kms keyboard sd-vconsole block sd-encrypt resume filesystems fsck)/' /etc/mkinitcpio.conf

# .TEST25: mkinitcpio configuration verification
echo "TEST25: mkinitcpio configuration verification"
grep "^HOOKS=" /etc/mkinitcpio.conf
grep "sd-encrypt" /etc/mkinitcpio.conf
grep "resume" /etc/mkinitcpio.conf
grep "systemd" /etc/mkinitcpio.conf

# .H02: Initramfs generation
mkinitcpio -P

# .H03: Bootloader installation - systemd-boot instead of GRUB
bootctl install

# .H04: Boot entry creation
# UUIDs for cryptswap (resume) — adjust if different
SWAP_UUID=$(blkid -s UUID -o value /dev/mapper/cryptswap)

# Loader config
cat >/boot/loader/loader.conf <<'EOF'
default  arch-main.conf
timeout  3
editor   no
EOF

# Main entries (@main)
cat >/boot/loader/entries/arch-main.conf <<EOF
title   Arch Linux (@main)
linux   /vmlinuz-linux
initrd  /intel-ucode.img       # or /amd-ucode.img
initrd  /initramfs-linux.img
options root=/dev/mapper/cryptroot rootflags=subvol=@main rw resume=UUID=${SWAP_UUID} loglevel=3
EOF

cat >/boot/loader/entries/arch-lts.conf <<EOF
title   Arch Linux LTS (@main)
linux   /vmlinuz-linux-lts
initrd  /intel-ucode.img       # or /amd-ucode.img
initrd  /initramfs-linux-lts.img
options root=/dev/mapper/cryptroot rootflags=subvol=@main rw resume=UUID=${SWAP_UUID} loglevel=3
EOF

# .H05: Fallback entry creation
# Sandbox entries (@sandbox)
cat >/boot/loader/entries/arch-sandbox.conf <<EOF
title   Arch Linux (@sandbox)
linux   /vmlinuz-linux
initrd  /intel-ucode.img       # or /amd-ucode.img
initrd  /initramfs-linux.img
options root=/dev/mapper/cryptroot rootflags=subvol=@sandbox rw resume=UUID=${SWAP_UUID} loglevel=3
EOF

cat >/boot/loader/entries/arch-sandbox-lts.conf <<EOF
title   Arch Linux LTS (@sandbox)
linux   /vmlinuz-linux-lts
initrd  /intel-ucode.img       # or /amd-ucode.img
initrd  /initramfs-linux-lts.img
options root=/dev/mapper/cryptroot rootflags=subvol=@sandbox rw resume=UUID=${SWAP_UUID} loglevel=3
EOF

# Fallback entries
cat >/boot/loader/entries/arch-linux-fallback.conf <<EOF
title   Arch Linux (fallback)
linux   /vmlinuz-linux
initrd  /intel-ucode.img       # or /amd-ucode.img
initrd  /initramfs-linux-fallback.img
options root=/dev/mapper/cryptroot rootflags=subvol=@main rw resume=UUID=${SWAP_UUID}
EOF

cat >/boot/loader/entries/arch-linux-lts-fallback.conf <<EOF
title   Arch Linux LTS (fallback)
linux   /vmlinuz-linux-lts
initrd  /intel-ucode.img       # or /amd-ucode.img
initrd  /initramfs-linux-lts-fallback.img
options root=/dev/mapper/cryptroot rootflags=subvol=@main rw resume=UUID=${SWAP_UUID}
EOF

# .H06: Microcode loading setup
# .H07: Kernel parameter configuration
# .H08: Resume/hibernation setup
# (Handled above in boot entries with resume=UUID)

# .TEST13: systemd-boot installation verification
echo "TEST13: systemd-boot installation verification"
test -f /mnt/stage/boot/EFI/systemd/systemd-bootx64.efi && echo "systemd-boot: OK"
test -f /mnt/stage/boot/loader/loader.conf && echo "loader.conf: OK"

# .TEST14: Kernel/initrd presence verification
echo "TEST14: Boot file presence verification"
ls -la /mnt/stage/boot/{vmlinuz-*,initramfs-*,intel-ucode.img}

# .TEST15: Boot entry syntax verification
echo "TEST15: Boot entry configuration verification"
for entry in /mnt/stage/boot/loader/entries/*.conf; do
    echo "Checking $entry:"
    grep -E "^(title|linux|initrd|options)" "$entry"
done

# .TEST16: Boot entry UUID consistency
echo "TEST16: Boot entry UUID verification"
grep UUID /mnt/stage/boot/loader/entries/*.conf

# .TEST26: Kernel parameter verification
echo "TEST26: Kernel parameter verification"
grep "root=/dev/mapper/cryptroot" /mnt/stage/boot/loader/entries/*.conf
grep "rootflags=subvol=" /mnt/stage/boot/loader/entries/*.conf
grep "resume=UUID=" /mnt/stage/boot/loader/entries/*.conf
grep "loglevel=" /mnt/stage/boot/loader/entries/*.conf

# .TEST27: Compression settings verification
echo "TEST27: Btrfs compression verification"
mount | grep /mnt/stage | grep compress
btrfs property get /mnt/stage compression


# [I] SECURITY CONFIGURATION PHASE
# --------------------------------

# .I01: Root password setup
echo "Setting root password:"
passwd

# .I02: Secure Boot key generation
# .I03: Key enrollment
# .I04: Kernel signing
# .I05: UKI creation (optional)

# .I06: TPM2 configuration
CHROOT_EOF

# Pass TPM2_AVAILABLE into chroot
arch-chroot /mnt/stage /bin/bash <<CHROOT_EOF2
if [ "$TPM2_AVAILABLE" = true ] && systemd-cryptenroll --tpm2-device=list >/dev/null 2>&1; then
    systemd-cryptenroll /dev/nvme0n1p2 --tpm2-device=auto --tpm2-pcrs=0+7
    echo "TPM2 enrollment successful"
    cryptsetup luksDump /dev/nvme0n1p2 | grep -q "tpm2" && echo "TPM2 token verified in LUKS header" || echo "Warning: TPM2 token not found in LUKS header"
    
    # .TEST17: TPM2 token verification
    echo "TEST17: TPM2 token verification"
    cryptsetup luksDump /dev/nvme0n1p2 | grep -A10 "Tokens"
    systemd-cryptenroll /dev/nvme0n1p2 --list
else
    echo "Using passphrase-only unlock"
fi


# [J] SYSTEM OPTIMIZATION PHASE
# -----------------------------

# .J01: Swappiness tuning (moved to H)
# .J02: TRIM timer enablement (moved to H)
# .J03: Time synchronization service (moved to H)

# .J04: Performance mount options

# .J05: TLP enablement
systemctl enable tlp tlp-sleep

# .TEST28: System tuning verification
echo "TEST28: System tuning verification"
cat /etc/sysctl.d/99-sysctl.conf
systemctl is-enabled fstrim.timer
systemctl is-enabled systemd-timesyncd
systemctl is-enabled tlp

# .TEST29: Service configuration verification
echo "TEST29: Service configuration verification"
systemctl is-enabled NetworkManager
systemctl is-enabled bluetooth

# .J06: Disable Intel PSR (i915)
echo "options i915 enable_psr=0" > /etc/modprobe.d/i915.conf

# .J07: User account creation
echo "Creating user account:"
read -p "Enter username: " USERNAME
useradd -mG wheel "\$USERNAME"
echo "Setting password for \$USERNAME:"
passwd "\$USERNAME"
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel

# .J08: Snapper setup
pacman -S --needed --noconfirm snapper snapper-support snap-pac
snapper -c root create-config /
snapper -c home create-config /home
snapper -c var create-config /var

# .TEST31: Snapper configuration verification
echo "TEST31: Snapper configuration verification"
snapper -c root list
snapper -c home list  
snapper -c var list
ls -la /etc/snapper/configs/

# .J09: Bluetooth setup
systemctl enable bluetooth

# .TEST30: User account verification
echo "TEST30: User account verification"
getent passwd $USERNAME
groups $USERNAME
ls -la /home/$USERNAME/
cat /etc/sudoers.d/wheel

CHROOT_EOF2

# .J10: Create baseline snapshots (outside chroot)
arch-chroot /mnt/stage snapper -c root create --description "Baseline Root"
arch-chroot /mnt/stage snapper -c home create --description "Baseline Home"
arch-chroot /mnt/stage snapper -c var create --description "Baseline Var"

# .J11: Create snapshot from @main to @sandbox (outside chroot)
mkdir -p /mnt/.btrfs
mount -o subvolid=5 /dev/mapper/cryptroot /mnt/.btrfs
if [ ! -d /mnt/.btrfs/@sandbox ]; then
    btrfs subvolume snapshot /mnt/.btrfs/@main /mnt/.btrfs/@sandbox
    btrfs subvolume snapshot /mnt/.btrfs/@main-home /mnt/.btrfs/@sandbox-home
    echo "Sandbox subvolumes created"
else
    echo "Sandbox subvolumes already exist"
fi

# Modify sandbox fstab
mkdir -p /mnt/sbx
mount -o subvol=@sandbox /dev/mapper/cryptroot /mnt/sbx
if grep -qE "\s/home\s" /mnt/sbx/etc/fstab 2>/dev/null; then
    sed -i 's#subvol=@main-home#subvol=@sandbox-home#' /mnt/sbx/etc/fstab
else
    ROOT_UUID=$(blkid -s UUID -o value /dev/mapper/cryptroot)
    echo "UUID=$ROOT_UUID /home btrfs noatime,compress=zstd:3,space_cache=v2,autodefrag,ssd,discard=async,subvol=@sandbox-home 0 0" >> /mnt/sbx/etc/fstab
fi
umount /mnt/sbx /mnt/.btrfs

# .TEST32: Sandbox subvolume verification
echo "TEST32: Sandbox subvolume verification"
mount -o subvolid=5 /dev/mapper/cryptroot /mnt/.btrfs
btrfs subvolume list /mnt/.btrfs | grep sandbox
btrfs subvolume show /mnt/.btrfs/@sandbox
btrfs subvolume show /mnt/.btrfs/@sandbox-home
umount /mnt/.btrfs

# .J12: Get username for system configuration
USERNAME=$(arch-chroot /mnt/stage getent passwd | awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' | head -1)

# .J13: Add sandbox boot entry and autologin setup
arch-chroot /mnt/stage /bin/bash <<CHROOT_EOF3
# Sandbox boot entries are created in section H with systemd-boot
CHROOT_EOF3

# .J14: Setup autologin (outside chroot to avoid systemctl issues)
if [ -n "$USERNAME" ]; then
    echo "Setting up autologin for $USERNAME..."
    mkdir -p /mnt/stage/etc/systemd/system/getty@tty1.service.d
    cat > /mnt/stage/etc/systemd/system/getty@tty1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USERNAME --noclear %I \$TERM
EOF
    
    cat > /mnt/stage/home/$USERNAME/.bash_profile <<'EOF'
if [ -z "$DISPLAY" ] && [ "${XDG_VTNR:-0}" -eq 1 ]; then
    exec uwsm start
fi
EOF
    arch-chroot /mnt/stage chown $USERNAME:$USERNAME /home/$USERNAME/.bash_profile
    arch-chroot /mnt/stage systemctl enable getty@tty1
    echo "Autologin configured for $USERNAME"
fi

# .TEST33: Autologin configuration verification
echo "TEST33: Autologin configuration verification"
if [ -n "$USERNAME" ]; then
    cat /mnt/stage/etc/systemd/system/getty@tty1.service.d/override.conf
    cat /mnt/stage/home/$USERNAME/.bash_profile
    arch-chroot /mnt/stage systemctl is-enabled getty@tty1
fi


# [K] PRE-REBOOT VERIFICATION PHASE
# ---------------------------------

# .K01: Configuration file review
# .K02: UUID verification
LUKS_UUID_CHECK=$(blkid -s UUID -o value /dev/nvme0n1p2)
SWAP_UUID_CHECK=$(blkid -s UUID -o value /dev/mapper/cryptswap)
grep -q "resume=UUID=${SWAP_UUID_CHECK}" /mnt/stage/boot/loader/entries/arch-main.conf || { echo "ERROR: Swap UUID mismatch in systemd-boot config"; exit 1; }

# .K03: Bootloader entry validation
[ -f /mnt/stage/boot/loader/loader.conf ] || { echo "ERROR: systemd-boot config not found"; exit 1; }
[ -f /mnt/stage/boot/loader/entries/arch-main.conf ] || { echo "ERROR: No main boot entry found"; exit 1; }

# .K04: ESP space check
ESP_USAGE=$(df /mnt/stage/efi | awk 'NR==2 {print $5}' | tr -d '%')
[ "$ESP_USAGE" -gt 80 ] && echo "WARNING: ESP usage is ${ESP_USAGE}%"

# .K05: Mount hierarchy verification
for mount in /mnt/stage /mnt/stage/efi /mnt/stage/home /mnt/stage/var; do
    mountpoint -q "$mount" || { echo "ERROR: $mount not mounted"; exit 1; }
done

# .K06: Service enablement check
echo "Verifying enabled services:"
for service in NetworkManager fstrim.timer systemd-timesyncd tlp bluetooth getty@tty1; do
    if arch-chroot /mnt/stage systemctl is-enabled $service >/dev/null 2>&1; then
        echo "✓ $service enabled"
    else
        echo "✗ $service NOT enabled"
    fi
done

echo "Pre-reboot verification completed successfully"

# .TEST18: File permissions verification
echo "TEST18: Security file permissions verification"
ls -la /mnt/stage/etc/crypttab.initramfs
ls -la /mnt/stage/boot/loader/

# .TEST19: Final comprehensive verification
echo "TEST19: Final system state verification"
echo "=== Partition Summary ==="
lsblk /dev/nvme0n1
echo "=== Mount Summary ==="
findmnt | grep /mnt/stage
echo "=== LUKS Summary ==="
cryptsetup status cryptroot
cryptsetup status cryptswap
echo "=== Boot Files Summary ==="
ls -la /mnt/stage/boot/loader/entries/
echo "=== Subvolume Summary ==="
btrfs subvolume list /mnt/stage

# .TEST34: Recovery readiness verification
echo "TEST34: Recovery readiness verification"
ls -la gpt-nvme0n1-backup.bin
file gpt-nvme0n1-backup.bin
echo "GPT backup location: $(pwd)/gpt-nvme0n1-backup.bin"

# .TEST35: Over-provisioning verification
echo "TEST35: Over-provisioning verification"
DISK_MODEL=$(cat /sys/block/nvme0n1/device/model 2>/dev/null || echo "Unknown")
echo "Disk model: $DISK_MODEL"
echo "Total disk space: $((TOTAL / 1024 / 1024 / 1024)) GiB"
echo "Unallocated space: $(((TOTAL - ESP - ROOT - SWAP) / 1024 / 1024 / 1024)) GiB"
OP_PERCENT=$(echo "scale=2; ((($TOTAL - $ESP - $ROOT - $SWAP) * 100) / $TOTAL)" | bc)
echo "Over-provisioning percentage: ${OP_PERCENT}%"

# .TEST36: Secure Boot readiness verification
echo "TEST36: Secure Boot readiness verification"
efivar -l | grep -i secureboot || echo "No SecureBoot variables found"
ls -la /sys/firmware/efi/efivars/ | grep -i secureboot || echo "No SecureBoot EFI vars"
bootctl status 2>/dev/null | grep -i secure || echo "SecureBoot status unknown"

# .TEST37: Plymouth and graphics verification
echo "TEST37: Plymouth and graphics configuration verification"
arch-chroot /mnt/stage pacman -Qi plymouth | grep "Install Date"
arch-chroot /mnt/stage pacman -Qi mesa | grep "Install Date"
lspci | grep -i vga
lsmod | grep -i i915

# .TEST38: Network and connectivity verification
echo "TEST38: Network and connectivity readiness verification"
arch-chroot /mnt/stage pacman -Qi networkmanager | grep "Install Date"
ip link show
lspci | grep -i network
lsusb | grep -i wireless || echo "No USB wireless devices"

# .TEST39: Audio system verification
echo "TEST39: Audio system verification"
arch-chroot /mnt/stage pacman -Qi pipewire | grep "Install Date"
arch-chroot /mnt/stage pacman -Qi wireplumber | grep "Install Date"
lspci | grep -i audio
cat /proc/asound/cards 2>/dev/null || echo "No sound cards detected yet"


# [L] REBOOT PHASE
# ----------------

# .L01: Chroot exit (already handled)

# .L02: Partition unmounting
sync
umount -R /mnt/stage || { echo "WARNING: Some filesystems couldn't be unmounted cleanly"; }
cryptsetup close cryptroot || { echo "WARNING: Could not close LUKS volume"; }
cryptsetup close cryptswap || { echo "WARNING: Could not close swap volume"; }

# .L03: System restart
echo ""
echo "Installation completed successfully!"
echo "System will reboot in 10 seconds..."
echo "Please remove installation media when prompted."
echo ""
read -t 10 -p "Press Enter to reboot now, or wait 10 seconds... "
reboot

# .L04: Installation medium removal


# [M] POST-INSTALLATION PHASE
# ---------------------------

# .M01: First boot verification
# .M02: Suspend/resume testing
# .M03: Hibernation testing
# .M04: Network connectivity check
ping -c3 archlinux.org

# .M05: Service status verification
systemctl status NetworkManager bluetooth tlp

# .M06: User account creation (moved to J07)

# .M07: GUI installation
# TODO pacman -S sway foot # example (choose your compositor/DE)

# .M08: Additional software setup
# .M09: Update mirrors
sudo reflector --country US --latest 50 --protocol https --sort rate --save /etc/pacman.d/mirrorlist

# .M10: System update
sudo pacman -Syu


# [N] MAINTENANCE & RECOVERY PHASE
# --------------------------------

# .N01: GPT restore procedures
# sgdisk --load-backup=gpt-nvme0n1-backup.bin /dev/nvme0n1

# .N02: Bootloader recovery
# arch-chroot /mnt bootctl install

# .N03: UUID mismatch fixes
# .N04: Kernel update procedures
# .N05: Btrfs maintenance
# btrfs scrub start /
# btrfs balance start -dusage=50 /

# .N06: SSD health monitoring
# smartctl -a /dev/nvme0n1

# .N07: System backup strategy
# .N08: Performance monitoring
