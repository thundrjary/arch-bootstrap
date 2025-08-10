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
    linux linux-firmware intel-ucode \        # .E03 Kernel + firmware + microcode
    vim nano sudo man-db man-pages texinfo \       # .E04 Essential system tools + editors
    grub efibootmgr \                         # .E05 Bootloader & EFI tools
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
for pkg in base linux grub networkmanager; do
    arch-chroot /mnt/stage pacman -Qi $pkg >/dev/null || { echo "ERROR: Critical package $pkg not installed"; exit 1; }
done
echo "Critical packages verified"


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


# [H] BOOT CONFIGURATION PHASE
# ----------------------------

# .H01: Initramfs hook configuration
LUKS_UUID=$(blkid -s UUID -o value /dev/nvme0n1p2)
printf 'cryptroot UUID=%s - tpm2-device=auto\n' "$LUKS_UUID" > /etc/crypttab.initramfs
sed -i \
  -e 's/^#\?COMPRESSION=.*/COMPRESSION="zstd"/' \
  -e 's/^MODULES=.*/MODULES=(btrfs)/' \
  -e 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt plymouth filesystems fsck)/' \
  /etc/mkinitcpio.conf

# .H02: Initramfs generation
mkinitcpio -P

# .H03: Bootloader installation
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB --recheck
[ -f /efi/EFI/GRUB/grubx64.efi ] || { echo "ERROR: GRUB installation failed"; exit 1; }

# .H04: Boot entry creation
# .H05: Fallback entry creation
# .H06: Microcode loading setup
# .H07: Kernel parameter configuration
cp /etc/default/grub /etc/default/grub.bak
sed -i "s/^GRUB_CMDLINE_LINUX=\"/GRUB_CMDLINE_LINUX=\"rd.luks.name=${LUKS_UUID}=cryptroot root=\/dev\/mapper\/cryptroot rootflags=subvol=@main quiet splash /" /etc/default/grub
grep -q "rd.systemd.show_status" /etc/default/grub || \
  sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="rd.systemd.show_status=auto /' /etc/default/grub

# Verify LUKS UUID consistency before generating config
LUKS_UUID_GRUB=$(grep "rd.luks.name=" /etc/default/grub | sed 's/.*rd.luks.name=\([^=]*\)=.*/\1/')
LUKS_UUID_ACTUAL=$(blkid -s UUID -o value /dev/nvme0n1p2)
[ "$LUKS_UUID_GRUB" = "$LUKS_UUID_ACTUAL" ] || { 
    echo "ERROR: LUKS UUID mismatch - GRUB: $LUKS_UUID_GRUB, Actual: $LUKS_UUID_ACTUAL"
    exit 1
}

grub-mkconfig -o /boot/grub/grub.cfg

# .H08: Resume/hibernation setup


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
else
    echo "Using passphrase-only unlock"
fi


# [J] SYSTEM OPTIMIZATION PHASE
# -----------------------------

# .J01: Swappiness tuning
echo "vm.swappiness=10" > /etc/sysctl.d/99-swappiness.conf

# .J02: TRIM timer enablement
systemctl enable fstrim.timer

# .J03: Time synchronization service
systemctl enable systemd-timesyncd 

# .J04: Performance mount options

# .J05: TLP enablement
systemctl enable tlp tlp-sleep

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
pacman -S --needed --noconfirm snapper snapper-support snap-pac grub-btrfs
snapper -c root create-config /
snapper -c home create-config /home
snapper -c var create-config /var
systemctl enable grub-btrfs.path

# .J09: Bluetooth setup
systemctl enable bluetooth

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

# .J12: Get username for system configuration
USERNAME=$(arch-chroot /mnt/stage getent passwd | awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' | head -1)

# .J13: Add sandbox boot entry and autologin setup
arch-chroot /mnt/stage /bin/bash <<CHROOT_EOF3
# Add sandbox grub entry
LUKS_UUID=\$(blkid -s UUID -o value /dev/nvme0n1p2)
ROOT_UUID=\$(blkid -s UUID -o value /dev/mapper/cryptroot)

cat >> /etc/grub.d/40_custom <<EOF
menuentry 'Arch Linux (sandbox)' --class arch --class gnu-linux --class gnu --class os {
    insmod gzio
    insmod part_gpt
    insmod btrfs
    search --no-floppy --fs-uuid --set=root \$ROOT_UUID
    linux   /vmlinuz-linux rd.luks.name=\$LUKS_UUID=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@sandbox quiet splash
    initrd  /initramfs-linux.img
}
EOF
grub-mkconfig -o /boot/grub/grub.cfg
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


# [K] PRE-REBOOT VERIFICATION PHASE
# ---------------------------------

# .K01: Configuration file review
# .K02: UUID verification
LUKS_UUID_CHECK=$(blkid -s UUID -o value /dev/nvme0n1p2)
grep -q "$LUKS_UUID_CHECK" /mnt/stage/etc/default/grub || { echo "ERROR: LUKS UUID mismatch in GRUB config"; exit 1; }

# .K03: Bootloader entry validation
[ -f /mnt/stage/boot/grub/grub.cfg ] || { echo "ERROR: GRUB config not found"; exit 1; }
grep -q "Arch Linux" /mnt/stage/boot/grub/grub.cfg || { echo "ERROR: No Arch Linux entries in GRUB config"; exit 1; }

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
# sgdisk --load-backup=/tmp/gpt-backup.txt /dev/nvme0n1

# .N02: Bootloader recovery
# arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB --recheck

# .N03: UUID mismatch fixes
# .N04: Kernel update procedures
# .N05: Btrfs maintenance
# btrfs scrub start /
# btrfs balance start -dusage=50 /

# .N06: SSD health monitoring
# smartctl -a /dev/nvme0n1

# .N07: System backup strategy
# .N08: Performance monitoring
