# A  PRE-INSTALLATION PHASE
### .A01  ISO acquisition and verification

**Purpose**
- Acquire the official Arch Linux installation image and verify its authenticity and integrity before use.
- Ensure the installation medium is free from corruption and tampering for a secure and reproducible deployment.

**Related Strategy References:**
- STRATEGY-VALIDATION-06: Security verification (permissions, Secure Boot readiness)
- STRATEGY-VALIDATION-09: Multi-tool redundant validation methodology
- STRATEGY-RISK-08: Live ISO recovery procedures and verification

**Process Overview**
- Download the ISO from an official Arch Linux mirror using HTTPS or a trusted mirror network.
- Download the `.iso.sig` signature file corresponding to the ISO.
- Run `pacman-key -v archlinux-*.iso.sig` to validate the GPG signature against Arch's official master keys.
- Optionally verify integrity with `.sha256` or `.sha1` checksum files using `sha256sum -c` or `sha1sum -c`.

**Tolerances & Acceptable Ranges**
- Cryptographic verification must pass without warnings or key mismatches.
- Checksum verification must match exactly; any difference indicates corruption.
- Download speed is non-critical, but persistent slow speeds may indicate a bad mirror.

**Failure Modes**
- Invalid signature: Could indicate tampering, compromised mirror, or outdated GPG keyring.
  - Mitigation: Refresh keyring (`pacman-key --refresh-keys`), retry from a different mirror.
- Checksum mismatch: Indicates corruption or incomplete download.
  - Mitigation: Re-download from a reliable source, ensure stable connection and storage integrity.
- GPG key missing: Local keyring lacks Arch master keys.
  - Mitigation: Initialize and populate keyring (`pacman-key --init && pacman-key --populate archlinux`).

**Security Implications**
- Installing from an unverified ISO risks compromised OS with potential backdoors.
- A compromised boot medium can alter partitioning or encryption setup silently.
- Supports maintaining a trusted computing base from the first boot.

**Extended Considerations**
- For high-security or air-gapped installs, download and verify on a trusted system offline.
- Keep a local archive of verified ISOs for reproducibility.
- Store SHA256 hashes of known-good ISOs in version control for provenance tracking.

### .A02  Installation medium preparation

**Purpose**
- Write the verified Arch Linux ISO to a bootable medium (USB, SSD, or other).
- Ensure the medium is properly formatted and written with sector alignment for reliable booting.
- Maintain the integrity of the ISO’s boot structure during transfer.

**Related Strategy References**
- STRATEGY-STORAGE-01: GPT partitioning with 1 MiB alignment for sector compatibility
- STRATEGY-VALIDATION-02: Storage verification (alignment, sizes, UUIDs)
- STRATEGY-RISK-08: Live ISO recovery procedures and verification

**Process Overview**
- Use `dd bs=4M if=archlinux.iso of=/dev/sdX status=progress oflag=sync` to write the ISO directly to the target device.
- Replace `/dev/sdX` with the correct device path (verify via `lsblk` or `fdisk -l`).
- `bs=4M` improves write performance without overloading I/O buffers.
- `oflag=sync` ensures data is physically written before the command completes.

**Tolerances & Acceptable Ranges**
- Write process must complete without I/O errors.
- Device capacity must be greater than the ISO size (typically >1 GB for Arch).
- Target device must not be mounted during writing.
- Acceptable verification: post-write `sha256sum` comparison between ISO and device image read-back.

**Failure Modes**
- Wrong target device specified, resulting in data loss.
  - Mitigation: Double-check with `lsblk` and device labels before executing `dd`.
- Incomplete write or I/O errors due to bad sectors.
  - Mitigation: Test medium (`badblocks`, `f3probe`) before use; replace failing media.
- USB boot failure after write.
  - Mitigation: Ensure firmware supports USB boot, check boot order, retry on another port.

**Security Implications**
- Writing to the wrong device could destroy critical data.
- Using untested or faulty media risks boot instability or installation failure.
- This phase must preserve the verified ISO’s authenticity — no transformation of its filesystem or boot loader.

**Extended Considerations**
- For speed and reliability, use USB 3.0 or NVMe-based boot media where possible.
- Avoid tools that “enhance” the ISO by modifying boot menus (can break Secure Boot or verification).
- For repeated deployments, maintain a dedicated, tested USB stick labeled for Arch ISO use.
- Post-write verification via `cmp` or `sha256sum` on `/dev/sdX` is recommended in high-reliability workflows.

### .A03  Boot into live environment

**Purpose**
- Transition from the system’s firmware interface (UEFI/BIOS) into the Arch Linux live ISO environment.
- Provide a controlled, minimal Linux environment for executing the installation workflow.
- Ensure hardware initialization under known-good kernel and drivers before proceeding with disk operations.

**Related Strategy References**
- STRATEGY-BOOT-01: systemd-boot installation replacing GRUB
- STRATEGY-VALIDATION-01: Hardware compatibility verification (CPU, memory, NVMe)
- STRATEGY-RISK-08: Live ISO recovery procedures and verification

**Process Overview**
- Insert the prepared installation medium into the target machine.
- Power on and access firmware setup (often `F2`, `F12`, `DEL`, or `ESC` during boot).
- Disable Secure Boot (Arch Linux ISO is not signed for Secure Boot by default).
- Set boot mode to UEFI (required for this strategy; BIOS/Legacy mode is unsupported here).
- Select the installation medium as the primary boot device or use the firmware’s boot menu to launch it.
- From the ISO boot menu, choose the default “Arch Linux install medium (x86_64, UEFI)” entry.

**Tolerances & Acceptable Ranges**
- Secure Boot must be disabled unless Secure Boot + custom key enrollment is planned (future enhancement).
- Boot mode must be confirmed as UEFI; BIOS/Legacy boot is outside operational tolerances for this guide.
- Live environment must load successfully to a root shell prompt with no kernel panics or driver lockups.

**Failure Modes**
- Medium not detected in firmware boot menu.
  - Mitigation: Recreate the boot medium, try another USB port, verify firmware USB boot support.
- Boots into BIOS/Legacy mode instead of UEFI.
  - Mitigation: Enable UEFI mode in firmware, disable CSM (Compatibility Support Module).
- Secure Boot enabled, preventing boot.
  - Mitigation: Disable Secure Boot or enroll custom keys after building UKI in a later phase.
- Kernel panic or driver errors during boot.
  - Mitigation: Test with different kernel parameters (e.g., `nomodeset`), try alternate hardware or media.

**Security Implications**
- UEFI boot mode ensures compatibility with GPT partitioning and systemd-boot (core to STRATEGY-BOOT-01).
- Disabling Secure Boot temporarily reduces boot-time verification; long-term remediation planned in STRATEGY-FUTURE-02.
- Booting from unverified media risks firmware-level persistence attacks; mitigated by earlier verification steps.

**Extended Considerations**
- Document firmware settings changes (e.g., disable Secure Boot, enable UEFI, disable Fast Boot) for reproducibility.
- For remote or headless systems, ensure IPMI/KVM or similar remote console access is available before reboot.
- On multi-boot systems, confirm that changing boot order doesn’t disrupt other OS boot entries.

# .A04  Console keyboard layout configuration

**Purpose**
- Configure the keyboard layout in the live environment to match the user’s preferred or physical keyboard.
- Prevent command input errors due to mismatched key mappings, especially for symbols used in passwords or commands.
- Ensure consistent input behavior during all installation phases.

**Related Strategy References**
- STRATEGY-OPERATION-07: User account creation with sudo privileges (keyboard layout must match expected login input)
- STRATEGY-VALIDATION-05: Configuration verification (ensuring persistent layout in system configs)

**Process Overview**
- List available keyboard layouts: `localectl list-keymaps` or `ls /usr/share/kbd/keymaps/**/*.map.gz`.
- Load desired layout: `loadkeys <layout>` (e.g., `loadkeys us`, `loadkeys de-latin1`, `loadkeys fr`).
- Verify layout correctness by typing test strings containing special characters (e.g., `!@#$%^&*()`).
- This setting only persists for the current live session — permanent configuration occurs in `.G06`.

**Tolerances & Acceptable Ranges**
- Layout selection must match the physical keyboard’s intended mapping.
- Response to `loadkeys` must indicate successful load with no errors.
- Keypress verification must confirm correct mapping for all required symbols in passwords, encryption keys, and commands.

**Failure Modes**
- Incorrect layout chosen, leading to mistyped commands or passwords.
  - Mitigation: Immediately reload the correct layout; verify before entering sensitive inputs.
- Layout unavailable in live environment.
  - Mitigation: Choose the closest supported layout; custom layouts can be added post-installation.
- Layout resets after reboot into live environment.
  - Mitigation: Reapply `loadkeys` each time until persistent configuration is set in installed system.

**Security Implications**
- Incorrect layout can lead to passphrase entry failures for LUKS encryption, potentially locking the installer out of the system.
- Reduces risk of introducing unintended characters into commands that may damage partitions or overwrite data.

**Extended Considerations**
- For multilingual systems, note all required layouts and plan for configuration of input switching in desktop environment later.
- Consider using ASCII-only passphrases during installation if layout uncertainty exists.
- For remote installs over serial or SSH, ensure terminal emulator and remote host agree on layout and encoding.

  .A05  Console font configuration
# .A06  Boot mode verification (UEFI/BIOS)

**Purpose**
- Confirm that the live environment is running in UEFI mode rather than legacy BIOS.
- Ensure compatibility with GPT partitioning, systemd-boot, and Secure Boot integration as defined in the strategy.
- Prevent installation in an unsupported firmware mode, which would break later boot configuration phases.

**Related Strategy References**
- STRATEGY-BOOT-01: systemd-boot installation replacing GRUB
- STRATEGY-VALIDATION-04: Boot verification (systemd-boot, entries, parameters)
- STRATEGY-RISK-05: Boot failure → multiple entry combination recovery

**Process Overview**
- Check for UEFI-specific filesystem:  
  `ls /sys/firmware/efi/efivars`
  - If directory exists and is accessible, system is in UEFI mode.
  - If absent, system is in legacy BIOS mode.
- Script implementation:  
  `ls /sys/firmware/efi/efivars >/dev/null 2>&1 && echo "UEFI mode confirmed" || { echo "ERROR: BIOS mode detected, UEFI required"; exit 1; }`
- Abort installation if UEFI is not detected.

**Tolerances & Acceptable Ranges**
- Only UEFI mode is acceptable for this strategy.
- Secure Boot state (enabled/disabled) is recorded but not validated in this phase.
- efivars directory must be present and readable without kernel errors.

**Failure Modes**
- System boots in BIOS mode despite UEFI capability.
  - Mitigation: Enable UEFI in firmware settings, disable CSM/Legacy Support, retry boot.
- efivars missing due to kernel or firmware bug.
  - Mitigation: Update firmware, test with newer ISO kernel, check boot parameters.
- Incorrect detection caused by chroot into BIOS-installed environment.
  - Mitigation: Always check from the live environment before proceeding with disk preparation.

**Security Implications**
- BIOS mode lacks Secure Boot support and restricts bootloader options.
- BIOS + MBR installs have no GPT partition backup header (affects STRATEGY-STORAGE-04 recovery procedures).
- UEFI is required for planned Secure Boot + TPM2 measured boot in STRATEGY-FUTURE-02 and STRATEGY-ENCRYPTION-07.

**Extended Considerations**
- On some hardware, enabling UEFI may disable certain legacy peripheral support; verify all needed devices before continuing.
- Multi-boot systems should have consistent boot mode across all OSes to avoid firmware boot menu confusion.
- In virtualized installs, ensure the VM firmware is set to UEFI mode in hypervisor settings.

  .A07  Network interface setup
  .A08  Internet connection establishment

### .A09 – System Clock Synchronization

**Purpose**
- Ensure the system clock is accurate before package installation and key verification.
- Prevent issues with TLS/SSL certificates, GPG signatures, and time-sensitive operations during the installation.
- Establish NTP-based time synchronization to keep the clock accurate throughout the install process.

**Related Strategy References**
- STRATEGY-VALIDATION-05: Configuration verification (fstab, crypttab, services)
- STRATEGY-VALIDATION-08: 39-point comprehensive testing framework
- STRATEGY-RISK-07: Lockout prevention through validation and testing

**Process Overview**
- Enable NTP time synchronization:
  - `timedatectl set-ntp true`
- Verify synchronization status:
  - `timedatectl status` (look for "System clock synchronized: yes" and "NTP service: active")
- If using a restricted or offline environment:
  - Set time manually with `timedatectl set-time "YYYY-MM-DD HH:MM:SS"`
- Synchronization ensures that GPG key validation and secure connections to mirrors will not fail due to clock skew.

**Tolerances & Acceptable Ranges**
- Time offset should be within ±5 seconds for general installations.
- For security-sensitive installations, a tolerance of ±1 second is preferred.
- Timezone accuracy is not critical at this phase; UTC or local time can be set later in `.G02`.

**Failure Modes**
- NTP servers unreachable due to lack of internet.
  - Mitigation: Check network connectivity (from `.A07` and `.A08`), switch to manual time setting.
- Clock drifts significantly during installation.
  - Mitigation: Re-run `timedatectl set-ntp true` or manually correct before finalizing system configuration.
- Hardware clock failure (CMOS battery dead).
  - Mitigation: Rely on network time until battery replacement; ensure service is enabled post-install.

**Security Implications**
- Incorrect system time can cause GPG signature verification failures, halting package installation.
- Large time discrepancies may trigger mirror or keyserver security mechanisms, blocking downloads.
- Accurate time is essential for future logs, auditing, and systemd journal integrity.

**Extended Considerations**
- In virtual machines, verify that the hypervisor’s clock synchronization feature is enabled to reduce drift.
- For installations in secure or offline networks, consider setting up an internal NTP server.
- Time synchronization also benefits LUKS operations with TPM2 (time-based sealing in advanced configurations).

### .A10  Pre-flight tool availability check

**Purpose**
- Confirm that essential installation and troubleshooting tools are present in the live environment before proceeding.
- Prevent mid-installation interruptions due to missing utilities.
- Prepare the working environment for both normal installation and potential recovery scenarios.

**Related Strategy References**
- STRATEGY-VALIDATION-08: 39-point comprehensive testing framework
- STRATEGY-RISK-08: Live ISO recovery procedures and verification
- STRATEGY-STORAGE-04: GPT backup creation and restoration procedures

**Process Overview**
- Create a dedicated mount point for staging tools:
  - `mkdir -p /mnt/tools`
- Mount a temporary storage location for tool installation if needed.
- Install critical packages:
  - `pacman -Sy --noconfirm git screen reflector`
    - `git` – source retrieval for scripts/configs
    - `screen` – persistent shell sessions during long operations
    - `reflector` – mirror ranking and selection
- Initialize and populate Arch Linux keyring:
  - `pacman-key --init`
  - `pacman-key --populate archlinux`
- This step ensures keyring freshness for package verification.

**Tolerances & Acceptable Ranges**
- All tools must install without package conflict or missing dependency errors.
- Keyring initialization must complete without GPG import failures.
- Mirror list updates should finish within reasonable time (<60 seconds typical on a good connection).

**Failure Modes**
- `pacman` database lock or sync failure.
  - Mitigation: Remove stale lock (`/var/lib/pacman/db.lck`), retry.
- Keyring population fails due to unreachable keyservers.
  - Mitigation: Check network connectivity, change keyserver in `/etc/pacman.d/gnupg/gpg.conf`.
- Mirror ranking fails because `reflector` is missing or cannot connect.
  - Mitigation: Install from ISO if available, manually edit `/etc/pacman.d/mirrorlist`.

**Security Implications**
- Without a valid keyring, package authenticity verification fails, creating a supply chain security risk.
- Missing utilities can prevent recovery from mid-installation failures.
- Reliable mirror selection improves installation security by reducing exposure to compromised or stale mirrors.

**Extended Considerations**
- For air-gapped installs, tools and keyring should be preloaded onto the installation medium.
- Consider adding additional diagnostic tools (`htop`, `smartmontools`, `btrfs-progs`) early for troubleshooting.
- Maintain a reproducible tool list so every installation starts with the same verified utilities.

### .A11  Encryption mode selection / TPM2 availability check

**Purpose**
- Determine whether the system supports Trusted Platform Module 2.0 (TPM2) for disk encryption key storage and automatic unlocking.
- Select the encryption unlock method based on hardware capabilities and security requirements.
- Decide between TPM2-backed auto-unlock or passphrase-only mode.

**Related Strategy References**
- STRATEGY-ENCRYPTION-02: TPM2 hardware detection and conditional enrollment
- STRATEGY-ENCRYPTION-03: Passphrase reuse strategy (single prompt, dual unlock)
- STRATEGY-ENCRYPTION-07: PCR 0+7 TPM2 binding for Secure Boot integration
- STRATEGY-RISK-01: TPM2 failure → passphrase fallback strategy

**Process Overview**
- Check TPM2 device presence:
  - `[ -d /sys/class/tpm ] && [ -c /dev/tpm0 ]`
  - If present, set `TPM2_AVAILABLE=true`; else `TPM2_AVAILABLE=false`.
- If TPM2 is available:
  - Plan to enroll encryption keys to TPM2 for auto-unlock during boot.
- If TPM2 is not available:
  - Proceed with passphrase-only encryption mode, requiring manual entry at boot.
- Log result for reference in later encryption and boot configuration phases.

**Tolerances & Acceptable Ranges**
- A valid TPM2 device should appear as `/dev/tpm0` and be functional (`tpm2_getrandom` test possible).
- PCR selection tolerance: PCR 0+7 as per strategy; must be adjustable in case of firmware-specific constraints.
- TPM2 is optional for installation but affects unlock convenience and integration with Secure Boot.

**Failure Modes**
- TPM2 present but inaccessible due to BIOS/UEFI settings.
  - Mitigation: Enable TPM in firmware settings, ensure OS-level driver is loaded.
- TPM2 detected but fails during key enrollment.
  - Mitigation: Switch to passphrase-only mode; plan for TPM reconfiguration post-install.
- PCR mismatch after firmware update, causing auto-unlock failure.
  - Mitigation: Re-enroll keys to TPM or temporarily fall back to passphrase.

**Security Implications**
- TPM2 auto-unlock can protect against offline attacks but may allow an attacker with physical access to boot the machine if not paired with Secure Boot (STRATEGY-FUTURE-02).
- Passphrase-only mode increases security against theft but requires manual unlock at every boot.
- Using both TPM2 and passphrase provides two-factor unlock but increases complexity.

**Extended Considerations**
- For maximum security, bind TPM2 key sealing to both PCR values and Secure Boot state.
- In passphrase mode, ensure the chosen passphrase meets entropy and complexity requirements to resist brute force attacks.
- TPM2 hardware verification should be repeated post-install to confirm driver and kernel module stability.

### .A12  Partition size planning

**Purpose**
- Define the exact partition sizes and layout before disk operations begin.
- Ensure that storage is allocated according to performance, capacity, and over-provisioning strategies.
- Avoid installation failures caused by undersized partitions or poor space distribution.

**Related Strategy References**
- STRATEGY-STORAGE-02: Three-partition layout (1G ESP, encrypted root, 12G encrypted swap)
- STRATEGY-STORAGE-03: NVMe over-provisioning reservation (~20GB unallocated)
- STRATEGY-STORAGE-05: Multi-tool partition size validation and byte accounting
- STRATEGY-RISK-04: Root corruption → sandbox and snapshot restoration

**Process Overview**
- Review total disk size using `lsblk -bno SIZE /dev/<disk>` or `blockdev --getsize64`.
- Apply partitioning scheme:
  - **ESP**: 1 GiB FAT32, aligned at 1 MiB boundary for UEFI boot (STRATEGY-STORAGE-01).
  - **Root**: Largest contiguous partition possible minus reserved swap and OP space.
  - **Swap**: 12 GiB encrypted partition to support hibernation.
  - **OP Space**: ~20 GiB unallocated for NVMe over-provisioning.
- Validate planned sizes with manual calculation before applying partitioning tools.

**Tolerances & Acceptable Ranges**
- ESP: ≥512 MiB minimum; 1 GiB target for compatibility and extra bootloader storage.
- Root: ≥20 GiB minimum usable space; preferred size ≥80% of remaining capacity after swap and OP reservation.
- Swap: At least equal to RAM size for hibernation; in this plan fixed at 12 GiB unless RAM is significantly larger.
- OP Space: ~7–10% of total disk capacity; in this plan 20 GiB fixed target.

**Failure Modes**
- Miscalculation resulting in insufficient space for root filesystem.
  - Mitigation: Recalculate before commit; adjust OP space or swap size if necessary.
- Oversized ESP wasting disk space.
  - Mitigation: Keep within target size unless firmware requires larger.
- Forgetting OP space reservation, leading to reduced SSD lifespan.
  - Mitigation: Explicitly leave final sectors unpartitioned in partitioning tool.

**Security Implications**
- Correct sizing of encrypted swap is critical for reliable hibernation with encryption (STRATEGY-ENCRYPTION-04).
- Allocating excessive swap can slow resume from hibernation due to increased read/write volume.
- OP space reservation improves SSD performance and wear-leveling longevity.

**Extended Considerations**
- For multi-boot setups, adjust ESP size to accommodate multiple OS bootloaders.
- For servers or workstations with large storage, consider separating `/home` into its own partition or subvolume.
- Document all size choices in installation logs for reproducibility and future maintenance.

**1. High-Level Partition Layout (Top-to-Bottom Disk View)**
```
|---------------------------------------------------------------|
|       1 GiB ESP (EFI System Partition)   [FAT32, UEFI Boot]   |
|---------------------------------------------------------------|
|        ~XX GiB Encrypted Root (Btrfs @main + subvolumes)      |
|---------------------------------------------------------------|
|       12 GiB Encrypted Swap  (for hibernation)                |
|---------------------------------------------------------------|
|       ~20 GiB Unallocated Space (Over-Provisioning)           |
|---------------------------------------------------------------|
```
- ESP at the start ensures UEFI bootloader compatibility.
- Root occupies the majority of the disk after ESP.
- Swap placed after root for sequential block alignment.
- OP space at the end improves NVMe wear leveling.

**2. Root Subvolume Layout (Btrfs Organization Inside Encrypted Root)**
```
Encrypted Root (cryptroot)
└── Btrfs Filesystem
    ├── @main            → Mounted as /
    ├── @main-home       → Mounted as /home
    ├── @var             → Mounted as /var
    ├── @log             → Mounted as /var/log
    ├── @cache           → Mounted as /var/cache
    ├── @tmp             → Mounted as /tmp
    ├── @shared          → Mounted as /shared
    └── @user-local      → Mounted as /usr/local
```
- Modular structure supports snapshots and selective restores.
- Aligns with STRATEGY-STORAGE-06 and STRATEGY-DEVELOPMENT-01.

**3. Sector Alignment Concept (1 MiB Alignment)**
```
[ Sector 0 ] ----> [ 1 MiB boundary ] | Partition 1 starts
[ Partition N end ] ----> [ Next 1 MiB boundary ] | Next partition starts
```
- Prevents misaligned writes that can slow down SSD/NVMe.
- Matches STRATEGY-STORAGE-01 for performance optimization.

**4. Disk Size Calculation Flow**
```
Total Disk Size: X GiB
  - ESP: 1 GiB
  - Swap: 12 GiB
  - Over-Provisioning: 20 GiB
--------------------------------
Remaining = Root Partition Size
```
- Helps verify before running sgdisk or parted commands.

**5. Process**
```
STEP-BY-STEP “CUTAWAY” — FROM EMPTY DISK TO FINAL LAYOUT
(Target disk example: /dev/nvme0n1)

-------------------------------------------------------------------------------
STEP 0  | STARTING POINT — EMPTY DISK (NO PARTITIONS)
Action  | wipe signatures, new GPT, 1 MiB alignment baseline
Cmds    | wipefs -a /dev/nvme0n1
        | sgdisk -Z /dev/nvme0n1
        | sgdisk -a 2048 -o /dev/nvme0n1

View    | [ Protective MBR ][ Primary GPT hdr ][ (free space ... ) ][ Backup GPT ]
Cutaway | |----LBA0----|----LBA1----|=========================|----Last LBAs----|

Notes   | - Alignment (-a 2048) => partitions start on 2048-sector boundaries (~1 MiB)
        | - This maximizes NVMe performance and avoids RMW penalties.


-------------------------------------------------------------------------------
STEP 1  | CREATE ESP (EFI SYSTEM PARTITION)
Action  | 1 GiB FAT32, starts at 1 MiB boundary
Cmds    | sgdisk -n 1:2048:+1G -t 1:EF00 -c 1:"ESP" /dev/nvme0n1

Cutaway | [ ESP 1GiB ][                FREE/UNALLOCATED SPACE                 ][ GPT ]
        | |----1 MiB----1 GiB----|============================================|====|

Notes   | - ESP first improves firmware compatibility.
        | - Leaves the remainder for root, swap, and OP reservation.


-------------------------------------------------------------------------------
STEP 2  | CREATE ENCRYPTED ROOT
Action  | consume everything except space reserved for swap and OP
Cmds    | sgdisk -n 2:0:-32G -t 2:8309 -c 2:"cryptroot" /dev/nvme0n1
        |   (here “-32G” = 12G swap + ~20G OP reservation)

Cutaway | [ ESP 1GiB ][         ROOT (cryptroot)          ][ 12G SWAP + 20G OP + GPT ]
        | |--1G--|--------------------(X GiB)---------------------|-------|-----|==|

Notes   | - Type 8309 (Linux LUKS) as a strong hint of intended encryption usage.
        | - Root size = Total - 1G (ESP) - 12G (swap) - 20G (OP).


-------------------------------------------------------------------------------
STEP 3  | CREATE ENCRYPTED SWAP
Action  | 12 GiB LUKS swap partition
Cmds    | sgdisk -n 3:0:-20G -t 3:8309 -c 3:"cryptswap" /dev/nvme0n1

Cutaway | [ ESP 1GiB ][           ROOT (cryptroot)           ][ SWAP 12G ][ OP ~20G ][ GPT ]
        | |--1G--|----------------------(X GiB)----------------------|---12G---|--~20G--|==|

Notes   | - Keeps a fixed 20 GiB unallocated tail for NVMe over-provisioning.
        | - Swap after root maintains sequential block layout.


-------------------------------------------------------------------------------
STEP 4  | WRITE & VALIDATE PARTITION TABLE
Action  | print/backup/rehydrate/expand GPT, notify kernel
Cmds    | sgdisk -p /dev/nvme0n1
        | sgdisk --backup=gpt-nvme0n1-backup.bin /dev/nvme0n1
        | sgdisk --load-backup=gpt-nvme0n1-backup.bin /dev/nvme0n1
        | sgdisk -e /dev/nvme0n1
        | partprobe /dev/nvme0n1

Expected|
Table   | Number  Start (1MiB-aligned)  Size      Type   Name
        | -----   ---------------------  --------  -----  -------------
        | 1       1 MiB                 1 GiB     EF00   ESP
        | 2       (next 1 MiB boundary) X GiB     8309   cryptroot
        | 3       (next 1 MiB boundary) 12 GiB    8309   cryptswap
        | Tail    (unallocated)         ~20 GiB   ----   Over-Provisioning

Notes   | - Backup file is your “get-out-of-jail” for GPT recovery.
        | - -e rewrites/expands backup GPT header to end-of-disk if needed.


-------------------------------------------------------------------------------
STEP 5  | ALIGNMENT & SANITY CHECKS
Action  | verify sectors, alignment, sizes
Cmds    | blockdev --getss /dev/nvme0n1        # logical sector (expected 512)
        | blockdev --getpbsz /dev/nvme0n1      # physical (often 4096)
        | fdisk -l /dev/nvme0n1 | grep "Sector size"
        | parted /dev/nvme0n1 align-check optimal 1
        | parted /dev/nvme0n1 align-check optimal 2
        | parted /dev/nvme0n1 align-check optimal 3
        | lsblk -bno SIZE /dev/nvme0n1p1
        | lsblk -bno SIZE /dev/nvme0n1p2
        | lsblk -bno SIZE /dev/nvme0n1p3

Cutaway | [ 1MiB aligned starts for p1, p2, p3 ]  →  “optimal” = aligned
        | p1: ESP (FAT32)
        | p2: cryptroot (to be LUKS + Btrfs with subvolumes)
        | p3: cryptswap (to be LUKS + swap)

Notes   | - All “align-check optimal” should report: aligned.
        | - Byte math for TOTAL ≈ ESP + ROOT + SWAP + OP (unallocated) must hold.


-------------------------------------------------------------------------------
STEP 6  | RESULTING “CUTAWAY” — FINAL TARGET SHAPE (BEFORE LUKS/BTRFS)
Diagram | ┌───────────────────────────────────────────────────────────────────────┐
        | │  ESP (1 GiB, EF00)  │      ROOT (cryptroot, X GiB, 8309)     │ SWAP │
        | │  [ /dev/nvme0n1p1 ] │      [ /dev/nvme0n1p2 ]                │ 12G  │
        | │  Start @ 1 MiB      │      1 MiB-aligned                      │(p3)  │
        | └───────────────────────────────────────────────────────────────────────┘
        |                         └─────── Unallocated ~20 GiB (OP) ───────┘

Next    | - LUKS format p2 & p3 → map as /dev/mapper/cryptroot, /dev/mapper/cryptswap
        | - mkfs.btrfs on cryptroot; create subvolumes (@main, @main-home, @var, …)
        | - mkswap on cryptswap; later add resume=UUID to boot entries


-------------------------------------------------------------------------------
QUICK CHECKLIST (BEFORE MOVING TO ENCRYPTION)
[ ] ESP = 1 GiB, FAT32 target, partition type EF00
[ ] Root size = Total - (1G + 12G + ~20G), partition type 8309
[ ] Swap = 12 GiB, partition type 8309
[ ] ~20 GiB unallocated tail preserved for OP
[ ] All partitions 1 MiB aligned (parted align-check = “aligned”)
[ ] GPT backup file saved (gpt-nvme0n1-backup.bin)
[ ] Byte math verified with lsblk/blockdev (no hidden usage at tail)
```

### .A13  Install tooling

**Purpose**
- Add essential utilities to the live environment to streamline installation, diagnostics, and recovery.
- Ensure all required commands are available before starting irreversible operations like partitioning, encryption, or base system install.
- Provide redundancy in case certain operations must be retried without network access.

**Related Strategy References**
- STRATEGY-VALIDATION-08: 39-point comprehensive testing framework
- STRATEGY-RISK-08: Live ISO recovery procedures and verification
- STRATEGY-STORAGE-05: Multi-tool partition size validation and byte accounting

**Process Overview**
- Synchronize package databases:
  - `pacman -Sy`
- Install key base utilities:
  - `pacman -Sy --noconfirm git vim nano screen reflector btrfs-progs cryptsetup smartmontools`
    - **git** – fetch and version control install scripts/configs
    - **vim / nano** – text editing in different preference styles
    - **screen** – persistent terminal sessions for long operations
    - **reflector** – automated Arch mirror ranking
    - **btrfs-progs** – required for Btrfs filesystem creation and management
    - **cryptsetup** – required for LUKS encryption setup
    - **smartmontools** – NVMe/SATA health checks
- Refresh Arch keyring:
  - `pacman-key --init`
  - `pacman-key --populate archlinux`
- Optional but recommended:
  - `htop` – process monitoring
  - `parted` and `gdisk` – alternate partitioning tools
  - `neofetch` – system info summary for logging

**Tolerances & Acceptable Ranges**
- All tool installs should complete without dependency conflicts or signature verification errors.
- Installation time should remain minimal (<2 minutes on typical broadband).
- Keyring initialization must succeed without expired or revoked key errors.

**Failure Modes**
- Package signature verification fails.
  - Mitigation: Update keyring first (`pacman-key --refresh-keys`) before reattempting install.
- Network dropout during installation.
  - Mitigation: Reconnect network (`.A07` and `.A08`), rerun `pacman -Sy`.
- Missing package in repo due to mirror lag.
  - Mitigation: Use `reflector` to select the most up-to-date mirrors.

**Security Implications**
- Fresh keyring ensures package authenticity, preventing man-in-the-middle package injection.
- Installing extra diagnostic tools early ensures safer recovery in case of install failure.
- Keeping tooling installs minimal reduces the live environment’s attack surface.

**Extended Considerations**
- For air-gapped installs, pre-load packages into `/mnt/tools` or use a local repo mirror.
- For high-availability installs, maintain a list of required packages and versions for reproducibility.
- Consider saving the package list to a file with:
  - `pacman -Qqe > /mnt/tools/liveenv-tooling-list.txt`

##  DISK PREPARATION PHASE
### .B00  Confirm target disk and ensure it's not mounted

**Purpose**
- Identify the exact storage device intended for installation.
- Prevent accidental data loss by ensuring the target disk is correct and not currently mounted or in use.
- Establish a verified baseline before destructive operations such as partitioning or encryption.

**Related Strategy References**
- STRATEGY-STORAGE-01: GPT partitioning with 1 MiB alignment
- STRATEGY-VALIDATION-02: Storage verification (alignment, sizes, UUIDs)
- STRATEGY-RISK-06: Complete system failure → documented reinstall procedures

**Process Overview**
- List all block devices:
  - `lsblk -d -o NAME,SIZE,MODEL`
  - Example output:
    ```
    NAME   SIZE   MODEL
    nvme0n1 476G  Samsung SSD 970 EVO
    sda     931G  WDC WD10EZEX-00
    ```
- Verify device path (`/dev/nvme0n1`, `/dev/sda`, etc.) matches intended target.
- Double-check capacity, model, and serial number:
  - `udevadm info --query=all --name=/dev/<disk> | grep -E 'ID_MODEL=|ID_SERIAL='`
- Ensure disk is not mounted:
  - `lsblk /dev/<disk>` – verify no mountpoints are listed for any partitions.
  - If any partitions are mounted, unmount them:
    - `umount -R /mnt/<mountpoint>` (repeat as necessary)
- Optional: wipe old filesystem signatures to avoid confusion in later steps:
  - `wipefs -n /dev/<disk>` (dry-run to see existing signatures)
  - If safe to proceed: `wipefs -a /dev/<disk>` (destructive)

**Tolerances & Acceptable Ranges**
- Disk must match documented size within ±0.1% (small variations due to manufacturer rounding are normal).
- No partitions on target disk should be mounted or in use.
- Device name should remain stable between boots (NVMe drives usually consistent; USB drives can shift if ports change).

**Failure Modes**
- Wrong disk selected, leading to catastrophic data loss.
  - Mitigation: Require double confirmation of disk identity, including size and serial.
- Target disk busy due to swap or system mounts.
  - Mitigation: Swapoff (`swapoff /dev/<partition>`) and unmount all mounts before proceeding.
- Removable drive letter changes between reboots.
  - Mitigation: Always verify `lsblk` output before running destructive commands.

**Security Implications**
- Accidentally selecting a disk with sensitive data could result in irrecoverable loss and possible security breach.
- Ensuring the correct disk prevents contamination of other operating systems or storage pools.

**Extended Considerations**
- For multi-disk systems, label target disk physically before starting.
- In virtualized environments, confirm VM virtual disk mapping matches host settings.
- If disk is part of a RAID array or LVM volume, ensure it is removed from the set before continuing.

Here are a few **plaintext diagrams** to visually reinforce **.B00 – Confirm Target Disk and Ensure It’s Not Mounted**.

---

**1. System View of Disks** (example: one NVMe SSD for install, one HDD for storage)

```
+-------------------------------+     +----------------------------------+
| /dev/nvme0n1                   |     | /dev/sda                         |
|  Size: 476G                    |     |  Size: 931G                       |
|  Model: Samsung SSD 970 EVO    |     |  Model: WDC WD10EZEX-00WN4A0       |
|  Serial: S3ESNX0M123456X        |     |  Serial: WD-WCC6Y0K12345           |
|  STATUS: TARGET (will install) |     |  STATUS: PRESERVE (do not touch)   |
+--------------------------------+     +-----------------------------------+
```

* Use size + model + serial for positive identification.
* Only the **TARGET** disk will be wiped.

---

**2. Mountpoint Check Flow**

```
   [List devices with lsblk]
             |
             v
   +---------------------+
   | Disk has partitions?|
   +---------------------+
         |        |
       Yes       No
       |          \
       v           \
+------------------+ \
| Check mountpoints|  \
+------------------+   \
       |             +--------------------+
   Mounted?          | No partitions = OK |
       |             +--------------------+
    Yes | No
       v   \
+--------------+ \
| Unmount all  |  \
| with umount  |   \
+--------------+    \
       |             v
       +------> [Safe to Proceed]
```

* This helps avoid proceeding with an in-use device.

---

**3. Pre-Destruction Verification Checklist**

```
[ ] Disk name matches documented target (e.g., /dev/nvme0n1)
[ ] Capacity matches expected value
[ ] Model and serial match verified hardware
[ ] No partitions mounted
[ ] No active swap on target device
[ ] Backup of important data confirmed (if any)
```

* Treat this like an airplane preflight — nothing “flies” until all boxes are checked.

---

**4. Visual “Danger Zone” Concept**

```
           *********************************************
           *  WARNING: THIS OPERATION IS DESTRUCTIVE   *
           *********************************************
               \ 
                \  Target Disk: /dev/nvme0n1
                 \  Model: Samsung SSD 970 EVO
                  \  Size: 476 GiB
                   \  STATUS: Verified OK for wipe
```

* Helps reinforce the seriousness of double-checking before continuing.

Here’s the **ASCII `lsblk` snapshot diagram** for **.B00 – Confirm Target Disk and Ensure It’s Not Mounted**.

---

**Before** (Target disk still has mounted partitions)

```
NAME        MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINTS
nvme0n1     259:0    0 476.9G  0 disk  
├─nvme0n1p1 259:1    0   512M  0 part  /mnt/boot
├─nvme0n1p2 259:2    0   300G  0 part  /mnt
└─nvme0n1p3 259:3    0  176.4G 0 part  /mnt/data
sda           8:0    0 931.5G  0 disk  
└─sda1        8:1    0 931.5G  0 part  /mnt/storage
```

⚠ **Problem:** `/dev/nvme0n1` partitions are mounted. Proceeding now would risk wiping an active filesystem.

---

**After** (Target disk unmounted and ready)

```
NAME        MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINTS
nvme0n1     259:0    0 476.9G  0 disk  
├─nvme0n1p1 259:1    0   512M  0 part  
├─nvme0n1p2 259:2    0   300G  0 part  
└─nvme0n1p3 259:3    0  176.4G 0 part  
sda           8:0    0 931.5G  0 disk  
└─sda1        8:1    0 931.5G  0 part  /mnt/storage
```

✅ **Safe:** No partitions on `/dev/nvme0n1` are mounted.

---

**Unmounting Commands Used**

```
umount -R /mnt/boot
umount -R /mnt/data
umount -R /mnt
```

(Repeat for all mounted partitions on the target disk.)

---

Here’s the **extended ASCII `lsblk` snapshot diagram** for **.B00 – Confirm Target Disk and Ensure It’s Not Mounted**, now including **swapoff example**.

---

**Before** (Target disk has mounted partitions **and** active swap)

```
NAME        MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINTS
nvme0n1     259:0    0 476.9G  0 disk  
├─nvme0n1p1 259:1    0   512M  0 part  /mnt/boot
├─nvme0n1p2 259:2    0   300G  0 part  /mnt
└─nvme0n1p3 259:3    0  176.4G 0 part  [SWAP]
sda           8:0    0 931.5G  0 disk  
└─sda1        8:1    0 931.5G  0 part  /mnt/storage
```

⚠ **Problems Detected:**

* `/dev/nvme0n1p1` and `/dev/nvme0n1p2` are mounted.
* `/dev/nvme0n1p3` is active swap.

---

**Unmount and Swapoff Commands Used**

```
umount -R /mnt/boot
umount -R /mnt
swapoff /dev/nvme0n1p3
```

* `umount -R` ensures recursive unmount of any nested mountpoints.
* `swapoff` disables swap usage on the target partition, freeing the device for modification.

---

**After** (Target disk unmounted and swap disabled — safe to proceed)

```
NAME        MAJ:MIN RM   SIZE RO TYPE  MOUNTPOINTS
nvme0n1     259:0    0 476.9G  0 disk  
├─nvme0n1p1 259:1    0   512M  0 part  
├─nvme0n1p2 259:2    0   300G  0 part  
└─nvme0n1p3 259:3    0  176.4G 0 part  
sda           8:0    0 931.5G  0 disk  
└─sda1        8:1    0 931.5G  0 part  /mnt/storage
```

✅ **Safe:** No partitions on `/dev/nvme0n1` are mounted or used as swap.

---

**Mini Safety Checklist**

```
[ ] All target partitions unmounted
[ ] swapoff run for any swap on target disk
[ ] Disk identity confirmed via size, model, serial
[ ] No critical data present (or backed up)
```

---

```
                ┌───────────────────────────────┐
                │ Identify target disk (lsblk)  │
                └───────────────┬───────────────┘
                                │
                                v
                ┌───────────────────────────────┐
                │ Verify size/model/serial match│
                └───────────────┬───────────────┘
                                │
                        No match│ Yes match
                                │
                    ┌───────────▼───────────┐
                    │  STOP – wrong device  │
                    └───────────────────────┘
                                │
                                v
                ┌───────────────────────────────┐
                │ Any partitions mounted?        │
                └───────────────┬───────────────┘
                                │
                        Yes     │ No
                                │
             ┌──────────────────▼──────────────────┐
             │ Unmount all with umount -R /mnt/... │
             └──────────────────┬──────────────────┘
                                │
                                v
                ┌───────────────────────────────┐
                │ Any active swap on this disk?  │
                └───────────────┬───────────────┘
                                │
                        Yes     │ No
                                │
         ┌──────────────────────▼──────────────────────┐
         │ Disable swap: swapoff /dev/<swap_partition> │
         └──────────────────────┬──────────────────────┘
                                │
                                v
                ┌───────────────────────────────┐
                │    SAFE TO PROCEED (WIPE)      │
                └───────────────────────────────┘
```


### .B01  Block device identification

**Purpose**
- Enumerate all storage devices currently connected to the system.
- Accurately map Linux device names (/dev/nvme0n1, /dev/sda, etc.) to their physical counterparts.
- Lay the groundwork for selecting the correct target disk in later phases.

**Related Strategy References**
- STRATEGY-VALIDATION-02: Storage verification (alignment, sizes, UUIDs)
- STRATEGY-RISK-06: Complete system failure → documented reinstall procedures
- STRATEGY-STORAGE-05: Multi-tool partition size validation and byte accounting

**Process Overview**
- Use `lsblk` for a tree view of devices, partitions, sizes, and mountpoints:
  - `lsblk -o NAME,SIZE,TYPE,MODEL,SERIAL,MOUNTPOINT`
- Verify disk details with `udevadm`:
  - `udevadm info --query=all --name=/dev/<disk> | grep -E 'ID_MODEL=|ID_SERIAL='`
- Show detailed partition table with:
  - `fdisk -l /dev/<disk>` or `parted /dev/<disk> print`
- For NVMe devices, check namespace info:
  - `nvme list`
- Record each device’s:
  - Device node (e.g., `/dev/nvme0n1`)
  - Model
  - Serial number
  - Capacity
  - Connection type (SATA, NVMe, USB)

**Tolerances & Acceptable Ranges**
- Reported sizes should match manufacturer specs within ±0.1%.
- Model and serial numbers must exactly match labels on the physical drive or vendor documentation.
- Device naming (e.g., `nvme0n1`, `sda`) is consistent across boot sessions unless hardware changes occur.

**Failure Modes**
- Misidentifying the target device:
  - Mitigation: Cross-check model, serial, and size using multiple tools.
- Hot-plugging devices after identification, causing name changes:
  - Mitigation: Identify and lock target disk *immediately before* destructive steps.
- Multiple identical drives of the same model:
  - Mitigation: Use serial number and `by-id` symlinks (`/dev/disk/by-id/`) to differentiate.

**Security Implications**
- Accurate device identification prevents accidental overwrites of drives containing sensitive data.
- Using `/dev/disk/by-id/` symlinks in scripts can reduce risk of device name changes causing unintended actions.

**Extended Considerations**
- In multi-boot or dual-disk setups, explicitly note which drives should be excluded from the installation process.
- For remote installs or headless systems, consider logging all `lsblk` and `udevadm` output to a remote server for audit purposes.
- If system contains drives in RAID or LVM, identify their underlying block devices before proceeding.

Here are some **plaintext diagrams** you can use for **.B01 – Block Device Identification**.

---

**1. Logical Device Tree (lsblk view)**

```
nvme0n1   476.9G  disk   Samsung SSD 970 EVO  (Serial: S3ESNX0M123456X)
├─nvme0n1p1  512M  part   EFI System Partition
├─nvme0n1p2  300G  part   Linux filesystem
└─nvme0n1p3  176.4G part   Linux swap

sda        931.5G  disk   WDC WD10EZEX-00WN4A0 (Serial: WD-WCC6Y0K12345)
└─sda1     931.5G  part   NTFS Data Volume
```

* Shows hierarchy from physical device → partitions → mountpoints.
* Use size, model, and serial for verification.

---

**2. Device Mapping with /dev/disk/by-id/**

```
/dev/disk/by-id/
  ├── nvme-Samsung_SSD_970_EVO_500GB_S3ESNX0M123456X -> ../../nvme0n1
  ├── ata-WDC_WD10EZEX-00WN4A0_WD-WCC6Y0K12345      -> ../../sda
```

* More reliable than `/dev/nvme0n1` or `/dev/sda` because these names persist even if Linux device order changes.

---

**3. Identification Cross-Check Flow**

```
[ lsblk output ] ----\
                      +--> [ Confirm size matches expected capacity ]
[ udevadm output ] ---/      [ Confirm model & serial match physical drive ]
                             [ Record device node and by-id link ]
```

* Ensures each piece of device info is confirmed from multiple tools before proceeding.

---

**4. Multi-Drive Risk Illustration**

```
+-------------------+       +-------------------+
| /dev/nvme0n1      |       | /dev/nvme1n1      |
| 500 GB SSD        |       | 500 GB SSD        |
| Serial: ...123456 |       | Serial: ...789012 |
+-------------------+       +-------------------+
         ↑                          ↑
   TARGET DRIVE               NON-TARGET DRIVE
```

* Shows why identical model drives require serial number checking.
```
BEFORE vs AFTER — Block Device Identification (B01)

┌────────────────────────────── BEFORE: Identification-Only ──────────────────────────────┐
│ Goal: Enumerate devices; NO target chosen yet                                           │
│                                                                                         │
│ lsblk -o NAME,SIZE,TYPE,MODEL,SERIAL,MOUNTPOINT                                         │
│                                                                                         │
│ nvme0n1    476.9G disk  Samsung SSD 970 EVO     SERIAL=S3ESNX0M123456X                  │
│ ├─nvme0n1p1 512M  part  EFI System Partition                                             │
│ ├─nvme0n1p2 300G  part  Linux filesystem                                                │
│ └─nvme0n1p3 176.4G part  Linux swap                                                     │
│                                                                                         │
│ sda         931.5G disk  WDC WD10EZEX-00WN4A0   SERIAL=WD-WCC6Y0K12345                  │
│ └─sda1      931.5G part  NTFS Data Volume                                               │
│                                                                                         │
│ /dev/disk/by-id/                                                                        │
│   nvme-Samsung_SSD_970_EVO_500GB_S3ESNX0M123456X  -> ../../nvme0n1                      │
│   ata-WDC_WD10EZEX-00WN4A0_WD-WCC6Y0K12345        -> ../../sda                          │
└─────────────────────────────────────────────────────────────────────────────────────────┘


┌────────────────────────────── AFTER: Target Marked & Logged ─────────────────────────────┐
│ Goal: Positively mark the install target; record all identifiers                         │
│                                                                                          │
│ TARGET DISK: /dev/nvme0n1                                                                │
│   Size  : 476.9G                                                                         │
│   Model : Samsung SSD 970 EVO                                                            │
│   Serial: S3ESNX0M123456X                                                                │
│   By-ID : /dev/disk/by-id/nvme-Samsung_SSD_970_EVO_500GB_S3ESNX0M123456X                │
│                                                                                          │
│ NON-TARGET: /dev/sda (Preserve)                                                          │
│   Size  : 931.5G                                                                         │
│   Model : WDC WD10EZEX-00WN4A0                                                           │
│   Serial: WD-WCC6Y0K12345                                                                │
│   By-ID : /dev/disk/by-id/ata-WDC_WD10EZEX-00WN4A0_WD-WCC6Y0K12345                       │
│                                                                                          │
│ Suggested annotations in your notes/log:                                                 │
│  - [TARGET] /dev/nvme0n1  (Samsung 970 EVO, S/N S3ESNX0M123456X)                         │
│  - [KEEP  ] /dev/sda      (WDC WD10EZEX, S/N WD-WCC6Y0K12345)                            │
└──────────────────────────────────────────────────────────────────────────────────────────┘


LEGEND & MINI-CHECKS
- Use size + model + serial + /dev/disk/by-id/ link to positively identify each drive.
- Mark exactly ONE device as [TARGET]; mark all others as [KEEP].
- Re-run lsblk just before any destructive step to ensure device names didn’t change.

OPTIONAL QUICK COMMANDS
- Record details:  lsblk -o NAME,SIZE,TYPE,MODEL,SERIAL,MOUNTPOINT | tee /root/lsblk.txt
- By-id map:       ls -l /dev/disk/by-id/ | tee /root/by-id.txt
- Udev facts:      udevadm info --query=all --name=/dev/nvme0n1 | tee /root/nvme0n1.txt
```

---

### .B02  Existing partition detection

**Purpose**
- Detect and document any existing partitions on the target disk before wiping or repartitioning.
- Identify any residual data, boot loaders, or filesystem signatures that could interfere with the new installation.
- Provide a pre-wipe record for audit, rollback, or forensic purposes.

**Related Strategy References**
- STRATEGY-VALIDATION-02: Storage verification (alignment, sizes, UUIDs)
- STRATEGY-STORAGE-04: GPT backup creation and restoration procedures
- STRATEGY-RISK-06: Complete system failure → documented reinstall procedures

**Process Overview**
- Display current partition layout:
  - `lsblk -o NAME,SIZE,TYPE,FSTYPE,PARTLABEL,UUID,MOUNTPOINT /dev/<disk>`
- Show detailed partition table from GPT/MBR:
  - `sgdisk -p /dev/<disk>` or `parted /dev/<disk> print`
- Detect filesystem signatures (even if partitions aren’t mounted):
  - `wipefs -n /dev/<disk>`  # Non-destructive “dry-run” mode
- Optionally run a sector scan to identify boot loaders or remnants:
  - `hexdump -C /dev/<disk> | less` (only for deep inspection)
- Record output for reference:
  - `lsblk -o NAME,SIZE,TYPE,FSTYPE,UUID,PARTLABEL /dev/<disk> | tee /root/prewipe-partitions.txt`
  - `sgdisk -p /dev/<disk> | tee /root/prewipe-gpt.txt`

**Tolerances & Acceptable Ranges**
- Any number of partitions may exist; the key is to fully document them before removal.
- Some drives may have leftover boot sectors or partial GPT data; note and prepare to overwrite.
- Inconsistent partition tables (protective MBR + damaged GPT) must be resolved before proceeding.

**Failure Modes**
- Skipping detection, leading to accidental overwriting of critical data.
- Misreading output, mistaking non-target partitions for safe-to-wipe areas.
- GPT and MBR data mismatch causing installation tools to fail or misalign partitions.
  - Mitigation: Re-initialize GPT (`sgdisk -Z`) after confirming target.

**Security Implications**
- Leftover partitions may contain sensitive data; document and securely wipe if required.
- Old boot loaders or EFI entries could interfere with the new system boot order.

**Extended Considerations**
- For multi-boot systems, clearly identify which partitions belong to which OS.
- If keeping any partition (e.g., shared data), explicitly mark them in documentation.
- Consider taking a full image (`dd if=/dev/<disk> of=/mnt/backup/disk.img`) if forensic preservation is required.

Here are some **plaintext diagram** ideas for **.B02 – Existing Partition Detection** that make it easier to visualize what’s on the target disk before wiping.

---

**1. Pre-Wipe Partition Map (lsblk-style)**

```
/dev/nvme0n1   476.9G  disk  Samsung SSD 970 EVO
├─nvme0n1p1    300M    part  vfat       EFI System
├─nvme0n1p2    200G    part  ext4       Arch Linux Root
├─nvme0n1p3    50G     part  ext4       Arch Linux Home
├─nvme0n1p4    12G     part  swap       Linux Swap
└─nvme0n1p5    214.6G  part  ntfs       Windows Data
```

* Each partition’s **size**, **filesystem type**, and **label** visible at a glance.
* Makes it obvious what will be destroyed if the disk is wiped.

---

**2. Timeline of Past Partitioning (hypothetical)**

```
[ | ESP | Arch Linux Root | Arch Linux Home | Swap | Windows Data | ]
 ^   300M      200G         50G       12G        214G
```

* Shows physical ordering from start to end of disk.
* Useful for detecting misalignment or space wastage between partitions.

---

**3. Detection Workflow Flowchart**

```
[Run lsblk on target disk]
           |
           v
[Run sgdisk/parted to read partition table]
           |
           v
[Run wipefs -n to detect FS signatures]
           |
           v
[Log outputs to /root/prewipe-*]
           |
           v
  [Decision: Keep or Destroy Each Partition?]
```

* Ensures consistent process before any destructive step.

---

**4. GPT & MBR Mismatch Risk**

```
    Protective MBR  <==>  Damaged GPT Header
        |                     |
    /dev/nvme0n1         sgdisk -v shows mismatch
```

* Highlights why reading both structures matters — some tools only see one table.

Here’s the **side-by-side “Before and After Wipe” ASCII map** linking **.B02 – Existing Partition Detection** directly to **.B05 – Partition Creation** for traceability.

---

```
┌────────────────────────────── BEFORE WIPE ──────────────────────────────┐
│ /dev/nvme0n1   476.9G  disk  Samsung SSD 970 EVO                         │
│ ├─nvme0n1p1    300M    part  vfat        EFI System (old)                │
│ ├─nvme0n1p2    200G    part  ext4        Arch Linux Root                 │
│ ├─nvme0n1p3    50G     part  ext4        Arch Linux Home                 │
│ ├─nvme0n1p4    12G     part  swap        Linux Swap                      │
│ └─nvme0n1p5    214.6G  part  ntfs        Windows Data                    │
└──────────────────────────────────────────────────────────────────────────┘
  ↑
  │  All partitions documented via `lsblk`, `sgdisk -p`, `wipefs -n`
  │  Decide: NONE preserved for clean Arch install
  v

┌────────────────────────────── AFTER WIPE ───────────────────────────────┐
│ /dev/nvme0n1   476.9G  disk  Samsung SSD 970 EVO                         │
│ ├─nvme0n1p1    1G      part  vfat        EFI System (new)                │
│ ├─nvme0n1p2    ~443.9G part  crypto_LUKS Encrypted Root (Btrfs inside)   │
│ │    ├── @main            → /                                             │
│ │    ├── @main-home       → /home                                         │
│ │    ├── @var             → /var                                          │
│ │    ├── @log             → /var/log                                      │
│ │    ├── @cache           → /var/cache                                    │
│ │    ├── @tmp             → /tmp                                          │
│ │    ├── @shared          → /shared                                       │
│ │    └── @user-local      → /usr/local                                    │
│ └─nvme0n1p3    12G     part  crypto_LUKS Encrypted Swap                   │
│ (Last ~20G left unallocated for NVMe over-provisioning)                   │
└──────────────────────────────────────────────────────────────────────────┘
```

---

**Traceability Notes:**

* **B02 output** is saved as pre-wipe reference (`/root/prewipe-partitions.txt`).
* **B05 plan** references this baseline to ensure complete overwrite of old structures.
* Any partitions kept (in a mixed setup) would be visually **unchanged** between maps.

---
Here’s the **triple-column layout** for `.B02 – Existing Partition Detection` → `.B05 – Partition Creation` traceability, showing **Before → Planned → After** states.

---

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                BEFORE (.B02)        │      PLANNED (.B05)        │      AFTER (Post-B05)│
├─────────────────────────────────────┼────────────────────────────┼─────────────────────┤
│ nvme0n1p1  300M  vfat   EFI (old)    │ 1G  vfat   EFI (new)       │ 1G  vfat   EFI (new) │
│ nvme0n1p2  200G  ext4   Arch Linux Root  │ ~443.9G LUKS2 Encrypted    │ LUKS2 Encrypted      │
│ nvme0n1p3   50G  ext4   Arch Linux Home  │   (Btrfs subvolumes)       │   Btrfs subvolumes   │
│ nvme0n1p4   12G  swap   Linux Swap   │ 12G LUKS2 Encrypted Swap   │ LUKS2 Encrypted Swap │
│ nvme0n1p5  214G  ntfs   Windows Data │ — (unallocated/removed)    │ — (absent)           │
│ —           —     —     —            │ ~20G Unallocated (OPR)     │ ~20G Unallocated     │
└─────────────────────────────────────┴────────────────────────────┴─────────────────────┘
```

---

**Legend & Key Points**

* **Before:** Detected via `lsblk`, `sgdisk -p`, `wipefs -n`.
* **Planned:** Matches **atomic strategy** (see STRATEGY-STORAGE-02 & STRATEGY-STORAGE-03).
* **After:** Verified via `lsblk` & `sgdisk` after `.B05` partition creation.

Here’s the **condensed vertical “change log” format** for `.B02 → .B05` execution, using `KEEP`, `MODIFY`, and `REMOVE` annotations.

---

```
CHANGE LOG — Existing Partition Detection → Partition Creation

Disk: /dev/nvme0n1  (Samsung SSD 970 EVO, 476.9G)
-----------------------------------------------------------------
[REMOVE] nvme0n1p1   300M   vfat     EFI (old) → Replace with 1G EFI (new)
[REMOVE] nvme0n1p2   200G   ext4     Arch Linux Root → Merge into new LUKS2 Root
[REMOVE] nvme0n1p3    50G   ext4     Arch Linux Home → Merge into new LUKS2 Root
[REMOVE] nvme0n1p4    12G   swap     Linux Swap → Replace with LUKS2 Swap
[REMOVE] nvme0n1p5   214G   ntfs     Windows Data → Discard (no preservation)
[CREATE] nvme0n1p1     1G   vfat     EFI System Partition (UEFI boot)
[CREATE] nvme0n1p2 ~443.9G LUKS2     Encrypted Root (Btrfs subvolumes)
[CREATE] nvme0n1p3    12G   LUKS2    Encrypted Swap (hibernation support)
[RESERVE] ~20G Unallocated (NVMe over-provisioning)
-----------------------------------------------------------------

LEGEND
- REMOVE = Destroy existing partition
- CREATE = Make new partition from free space
- MODIFY = Adjust existing partition without full removal (N/A in this case)
- RESERVE = Space intentionally left unallocated
```

---

**Usage Flow**

1. Run `.B02` and fill this log directly from detected partitions.
2. Apply KEEP / MODIFY / REMOVE decisions for each.
3. Add CREATE / RESERVE lines from `.B05` plan.
4. This final list becomes your **exact execution order** for partitioning commands.

Here’s the **ASCII “wipe and rebuild” timeline** showing the **physical disk transformation** from `.B02` (detection) → wipe → `.B05` (new layout).

---

```
PHYSICAL DISK TRANSFORMATION — /dev/nvme0n1 (476.9G)

STEP 1 — Before Wipe (.B02)
[ ESP 300M | Arch Linux Root 200G | Arch Linux Home 50G | Swap 12G | Windows Data 214G ]

STEP 2 — Wipe Action
[ ************************************************************ ]
  ^ Entire disk zeroed, old GPT removed, filesystem signatures erased

STEP 3 — New Partition Layout (.B05)
[ EFI 1G | Encrypted Root ~443.9G | Encrypted Swap 12G | (20G Unallocated) ]

SUBVOLUME LAYOUT INSIDE ENCRYPTED ROOT
  @main         → /
  @main-home    → /home
  @var          → /var
  @log          → /var/log
  @cache        → /var/cache
  @tmp          → /tmp
  @shared       → /shared
  @user-local   → /usr/local
```

---

**Why this is useful:**

* **Step 1** is a snapshot of what’s being destroyed — helps confirm before wiping.
* **Step 2** emphasizes that **everything is gone** — no partial re-use.
* **Step 3** directly matches the strategy plan (**STRATEGY-STORAGE-02**, **STRATEGY-STORAGE-06**).

### .B03  Disk Controller Mode Verification

- **Purpose**  
  - Ensure the system’s storage controller is operating in the intended mode (e.g., AHCI) before installation.  
  - Prevent performance degradation, boot issues, or incompatibility with Arch Linux’s kernel drivers.  
  - Required step before proceeding to destructive operations — changing the controller mode after OS install can break boot.

- **Insights**  
  - Many consumer motherboards default to RAID/Intel RST mode, which can cause Linux boot/initramfs problems without extra drivers.  
  - AHCI is preferred for single-disk setups to enable NCQ, TRIM, and full SMART monitoring.  
  - NVMe drives typically bypass SATA controller settings, but BIOS/UEFI may still present a compatibility/legacy toggle affecting enumeration.

- **Explanations**  
  - In UEFI firmware, SATA/NVMe mode is found under *Storage Configuration* or *Advanced → PCH Storage*.  
  - For SATA drives: “AHCI” mode is optimal; “IDE” is legacy and should be avoided unless recovering very old hardware.  
  - For NVMe: confirm PCIe mode (x4 Gen3/Gen4) and disable compatibility/legacy mapping where possible.

- **Tolerances**  
  - Mode should be stable and match expected kernel modules (e.g., `ahci` or `nvme`).  
  - Switching modes after partitioning may require `mkinitcpio` regeneration and bootloader reconfiguration — to be avoided.

- **Strategy Reference**  
  - **STRATEGY-STORAGE-01** (sector alignment) indirectly depends on correct controller mode for consistent reported geometry.  
  - **STRATEGY-VALIDATION-01** (hardware verification) includes controller mode checks.

- **Failure Modes**  
  - Mode set to RAID/Intel RST without drivers → disk invisible to Arch installer.  
  - Mode switched post-install → kernel panic / root device not found.  
  - Compatibility mode throttling NVMe to SATA speeds → massive performance loss.

- **Verification Procedure**  
  1. Enter UEFI/BIOS setup.  
  2. For SATA: confirm “AHCI” mode is enabled (not RAID/IDE).  
  3. For NVMe: confirm PCIe lane allocation and disable “Compatibility” or “Legacy” mappings.  
  4. Boot into Arch ISO and run:
     ```
     lsblk -d -o NAME,ROTA,TRAN
     lspci | grep -i storage
     ```
     Verify expected transport type (SATA/NVMe) and driver.

- **Pre-flight Actions**  
  - If mode change is needed, do it now before partitioning.  
  - Save screenshots of BIOS settings for documentation and disaster recovery.

### .B04  Sector size optimization check

- **Purpose**  
  - Confirm that the disk’s reported logical and physical sector sizes match expectations for optimal alignment and performance.  
  - Prevent misaligned partitions, which can reduce throughput and increase write amplification — especially important for SSDs/NVMe in Arch Linux installs.  
  - Ensure compatibility with **STRATEGY-STORAGE-01** (1 MiB alignment).

- **Insights**  
  - Modern SSDs/NVMe drives typically have 512-byte logical sectors and 4096-byte physical sectors (512e format).  
  - Some drives present 4K logical sectors (4Kn) — performance impact can occur if not accounted for during partition creation.  
  - Misaligned partitions can cause read/write operations to span multiple physical sectors unnecessarily.

- **Explanations**  
  - **Logical sector size** = smallest addressable block from OS perspective.  
  - **Physical sector size** = actual block size on the disk media.  
  - GPT partitioning tools (e.g., `parted`, `sgdisk`) handle alignment automatically if instructed to start partitions on 1 MiB boundaries.

- **Tolerances**  
  - Logical = 512 bytes or 4096 bytes.  
  - Physical = 4096 bytes (typical SSD/NVMe) or larger for specialized enterprise media.  
  - 1 MiB alignment ensures compatibility with any sector size ≥ 512 bytes.

- **Strategy Reference**  
  - **STRATEGY-STORAGE-01**: GPT partitioning with 1 MiB alignment.  
  - **STRATEGY-STORAGE-05**: Multi-tool partition size validation and byte accounting.

- **Failure Modes**  
  - Using legacy tools without proper alignment → degraded performance, increased wear.  
  - Filesystem performance anomalies (especially with random writes).  
  - On RAID arrays, stripe size misalignment can multiply inefficiencies.

- **Verification Procedure**  
  1. Boot Arch ISO.  
  2. Run:
     ```
     lsblk -o NAME,PHY-SeC,LOG-SeC
     cat /sys/block/<disk>/queue/physical_block_size
     cat /sys/block/<disk>/queue/logical_block_size
     ```
  3. Ensure physical sector size ≥ logical sector size.  
  4. Confirm partitioning plan starts all partitions at sector numbers divisible by `(1 MiB / logical_sector_size)`.

- **Pre-flight Actions**  
  - Adjust partition creation commands if using non-standard sector sizes.  
  - Document drive’s sector information in pre-install log (`/root/preflight-disk-info.txt`) for future reference.

### .B05  Partition table creation

- **Purpose**  
  - Establish a clean GPT partition table matching the Arch Linux atomic install strategy.  
  - Implement layout from planning phase (.A12) and reference detection results (.B02).  
  - Guarantee correct sizing, order, and alignment for all partitions, ensuring optimal performance and maintainability.

- **Insights**  
  - GPT is mandatory for UEFI boot per Arch standards; offers redundancy and CRC32 protection of partition data.  
  - Partition creation here is destructive — this step should only occur after `.B00` confirmation and `.B02` documentation.  
  - Each partition’s start sector should be 1 MiB aligned to satisfy **STRATEGY-STORAGE-01** and sector size checks from `.B04`.  
  - The unallocated ~20 GiB at the end of disk supports **STRATEGY-STORAGE-03** (NVMe over-provisioning).

- **Explanations**  
  - EFI System Partition (ESP) → FAT32, 1 GiB, type EF00, mounted at `/boot`.  
  - Encrypted root partition → LUKS2 container holding Btrfs subvolumes per **STRATEGY-STORAGE-06**.  
  - Encrypted swap partition → LUKS2 container sized to 12 GiB per **STRATEGY-ENCRYPTION-04**.  
  - Remaining ~20 GiB unallocated → extends SSD life, improves wear leveling.

- **Tolerances**  
  - Partition sizes must be within ±1 MiB of planned spec to ensure predictable byte accounting (**STRATEGY-STORAGE-05**).  
  - Alignment: start sectors divisible by `(1 MiB / logical_sector_size)`.  
  - Partition type GUIDs must match spec (e.g., EF00 for ESP, 8300 for Linux data if unencrypted, 8200 for swap if unencrypted).

- **Strategy Reference**  
  - **STRATEGY-STORAGE-01** → Alignment rules.  
  - **STRATEGY-STORAGE-02** → Three-partition layout.  
  - **STRATEGY-STORAGE-03** → Over-provisioning.  
  - **STRATEGY-STORAGE-05** → Size validation.  
  - **STRATEGY-ENCRYPTION-04** → Separate encrypted swap.

- **Failure Modes**  
  - Mis-typed device name → wrong disk destroyed.  
  - Incorrect type codes → bootloader or kernel fails to detect partition.  
  - Misalignment → degraded performance / increased wear.  
  - Swap size too small for hibernation → resume failures.

- **Verification Procedure**  
  1. Run `sgdisk --zap-all /dev/<disk>` to wipe GPT/MBR.  
  2. Create partitions in order:  
     - ESP: start at 1 MiB, size 1 GiB, type EF00.  
     - Root: start at 2 GiB, size ~443.9 GiB, type 8300 (to be encrypted).  
     - Swap: size 12 GiB, type 8200 (to be encrypted).  
  3. Leave final ~20 GiB unallocated.  
  4. Verify layout with:
     ```
     sgdisk -p /dev/<disk>
     lsblk -o NAME,SIZE,TYPE
     ```
  5. Compare to `.B02` pre-wipe log and `.A12` plan.

- **Pre-flight Actions**  
  - Save final `sgdisk -p` output to `/root/post-partition-table.txt`.  
  - Cross-check against triple-column change log (Before → Planned → After).


### .B06  Partition alignment configuration
**.B06  Partition Alignment Configuration**

- **Purpose**  
  - Ensure all partitions are aligned to 1 MiB boundaries for maximum performance, compatibility, and SSD/NVMe lifespan.  
  - Avoid misaligned writes that span multiple physical sectors, causing extra read-modify-write cycles.  
  - This is a foundational requirement for **STRATEGY-STORAGE-01** (GPT partitioning with 1 MiB alignment).

- **Insights**  
  - Modern SSDs and NVMe drives usually have 4K physical sectors, but many still present 512-byte logical sectors (512e).  
  - 1 MiB = 2048 sectors (512-byte) or 256 sectors (4K-byte), making it a universal alignment standard across sector sizes.  
  - Most modern partitioning tools (e.g., `parted`, `sgdisk`) align to 1 MiB by default, but explicit verification prevents silent misalignments.  
  - Alignment affects both start and end of partitions — important for back-to-back allocations without gaps.

- **Explanations**  
  - Misalignment can reduce throughput by up to 50% and increase wear on NAND flash.  
  - Btrfs benefits from aligned partitions to maintain predictable extents and compression performance (**STRATEGY-STORAGE-07**).  
  - Arch Linux install scripts assume modern alignment standards; mismatched offsets can confuse recovery tools.

- **Tolerances**  
  - Start sector must be divisible by `(1 MiB / logical_sector_size)`.  
  - End sector alignment should leave no partial physical sectors.  
  - Deviations from 1 MiB alignment only acceptable for embedded/legacy constraints (not applicable here).

- **Strategy Reference**  
  - **STRATEGY-STORAGE-01** → Primary alignment rule.  
  - **STRATEGY-STORAGE-05** → Size and alignment validation.  
  - **STRATEGY-VALIDATION-02** → Storage verification.

- **Failure Modes**  
  - Using old partitioning tools (MBR default 63-sector start) → misaligned root filesystem.  
  - RAID setups with stripe sizes misaligned → compounded performance penalty.  
  - NVMe over-provisioning space incorrectly aligned → wasted blocks, reduced endurance.

- **Verification Procedure**  
  1. During `.B05` creation, specify start points as multiples of 1 MiB in `sgdisk` or `parted`. Example:
     ```
     sgdisk -n 1:1MiB:+1GiB -t 1:EF00 /dev/<disk>
     ```
  2. After creation, verify with:
     ```
     lsblk -o NAME,START,SIZE,ALIGNMENT
     ```
     Ensure ALIGNMENT column shows `0` (fully aligned).  
  3. Cross-check sector math:
     ```
     echo "<start_sector> % (1MiB/<logical_sector_size>)" | bc
     ```
     Result should be `0`.

- **Pre-flight Actions**  
  - Capture final partition start/end offsets in `/root/partition-alignment.txt`.  
  - Document in install log for reproducibility and post-install validation.

### .B07  ESP partition creation
**.B07  ESP (EFI System Partition) Creation**

- **Purpose**  
  - Create a dedicated EFI System Partition for UEFI firmware to store bootloaders and associated data.  
  - Required for Arch Linux UEFI boot via `systemd-boot` (**STRATEGY-BOOT-01**).  
  - Ensures a clean, standards-compliant environment for boot entries and kernel images.

- **Insights**  
  - FAT32 format is required by the UEFI specification for the ESP.  
  - The partition must be marked with the EFI System Partition type GUID (EF00 in `sgdisk`).  
  - **STRATEGY-STORAGE-02** specifies an ESP size of **1 GiB** to accommodate multiple kernels, initramfs images, and microcode updates without space constraints.  
  - While many distros use 512 MiB, larger size ensures future flexibility (multi-kernel strategy per **STRATEGY-BOOT-02**).

- **Explanations**  
  - The ESP acts as a firmware-readable filesystem mounted at `/boot` (for `systemd-boot`).  
  - All kernel images, initramfs files, and `systemd-boot` loader entries will be stored here.  
  - This partition is shared across OS installations if multi-booting (not applicable here since this is a clean Arch install).

- **Tolerances**  
  - Size: 1 GiB ± 1 MiB tolerance.  
  - Filesystem: FAT32 only; cluster size auto-selected by `mkfs.fat`.  
  - Partition type: EF00 GUID; must be flagged as bootable in UEFI.

- **Strategy Reference**  
  - **STRATEGY-STORAGE-02** → ESP allocation in 3-part layout.  
  - **STRATEGY-BOOT-01** → systemd-boot installation.  
  - **STRATEGY-BOOT-02** → Quad-kernel strategy support.

- **Failure Modes**  
  - Wrong type code → UEFI firmware ignores partition.  
  - Too small ESP → future kernel updates fail due to insufficient space.  
  - Wrong filesystem format → firmware cannot load bootloader.  
  - ESP not mounted or mounted incorrectly during installation → bootloader install fails.

- **Verification Procedure**  
  1. Create ESP using `sgdisk`:
     ```
     sgdisk -n 1:1MiB:+1GiB -t 1:EF00 /dev/<disk>
     ```
  2. Format:
     ```
     mkfs.fat -F32 -n EFI /dev/<disk>p1
     ```
  3. Verify:
     ```
     lsblk -o NAME,SIZE,FSTYPE,PARTTYPE /dev/<disk>
     ```
     Confirm FAT32 filesystem and EF00 type GUID.

- **Pre-flight Actions**  
  - Record ESP creation details in `/root/esp-info.txt`.  
  - Mount at `/mnt/boot` immediately after creation to prevent misplacement of boot files during later steps.

### .B08  Root partition creation
**.B08  Root Partition Creation**

- **Purpose**  
  - Allocate and define the primary Linux root partition according to the Arch Linux atomic install plan.  
  - Provide an encrypted container (LUKS2) to hold the Btrfs filesystem and its subvolume hierarchy (**STRATEGY-STORAGE-06**).  
  - Size calculated to maximize available space while leaving reserved swap and NVMe over-provisioning area.

- **Insights**  
  - Per **STRATEGY-STORAGE-02**, the root partition will consume all remaining space after ESP (1 GiB), swap (12 GiB), and ~20 GiB reserved for over-provisioning (**STRATEGY-STORAGE-03**).  
  - Alignment rules from **STRATEGY-STORAGE-01** apply — partition starts on a 1 MiB boundary.  
  - Root is encrypted separately to ensure TPM2/Passphrase dual unlock strategy (**STRATEGY-ENCRYPTION-03**).  
  - Btrfs is selected for snapshotting, subvolume isolation, and development workflow branching (**STRATEGY-DEVELOPMENT-01** through **STRATEGY-DEVELOPMENT-08**).

- **Explanations**  
  - LUKS2 container on the root partition provides confidentiality and supports hibernation resume through coordinated key management with swap.  
  - Btrfs subvolumes (`@main`, `@main-home`, `@var`, etc.) allow targeted snapshotting and recovery without affecting unrelated areas.  
  - Large contiguous root space improves fragmentation resistance and snapshot efficiency.

- **Tolerances**  
  - Size: ~443.9 GiB ± 1 MiB.  
  - Start sector: must be divisible by `(1 MiB / logical_sector_size)`.  
  - Type code: 8300 (Linux filesystem) pre-encryption; will be replaced with crypt type on unlock mapping.

- **Strategy Reference**  
  - **STRATEGY-STORAGE-01** → Alignment rules.  
  - **STRATEGY-STORAGE-02** → Partition size/location in 3-part layout.  
  - **STRATEGY-STORAGE-06** → Btrfs subvolume design.  
  - **STRATEGY-ENCRYPTION-01** → LUKS2 setup.  
  - **STRATEGY-DEVELOPMENT-01** → Snapshot branching workflow.

- **Failure Modes**  
  - Incorrect size → swap or over-provisioning area encroached.  
  - Misalignment → reduced SSD/NVMe performance and lifespan.  
  - Wrong type GUID → installer may fail to detect during encryption setup.  
  - Insufficient space for future expansion → may require repartitioning.

- **Verification Procedure**  
  1. Create partition with `sgdisk`:
     ```
     sgdisk -n 2:<start>:+443.9GiB -t 2:8300 /dev/<disk>
     ```
     `<start>` = 1 GiB + alignment offset.
  2. Confirm:
     ```
     lsblk -o NAME,SIZE,TYPE,PARTTYPE /dev/<disk>
     ```
  3. Validate sector alignment with:
     ```
     cat /sys/block/<disk>/queue/optimal_io_size
     lsblk -o NAME,ALIGNMENT
     ```

- **Pre-flight Actions**  
  - Save layout to `/root/root-partition-info.txt`.  
  - Double-check `.A12` plan and `.B05` execution match exactly before encryption begins.

### .B09  Swap partition creation

- **Purpose**  
  - Allocate a dedicated encrypted swap partition to support system swapping and hibernation.  
  - Ensure swap is isolated from the root container to maintain independent lifecycle and encryption settings.  
  - Match swap size to system RAM for reliable hibernation resume.

- **Insights**  
  - Per **STRATEGY-STORAGE-02**, swap size is fixed at **12 GiB**.  
  - Per **STRATEGY-ENCRYPTION-04**, swap will be encrypted in its own LUKS2 container, enabling hibernation support while protecting memory dump contents.  
  - Keeping swap separate from root avoids data fragmentation in the main filesystem and simplifies swap key management.  
  - Swap partition location is immediately after root, before the unallocated NVMe over-provisioning space (**STRATEGY-STORAGE-03**).

- **Explanations**  
  - Encrypted swap ensures that sensitive data paged to disk is not accessible if the device is removed.  
  - Swap size of 12 GiB accommodates systems with up to ~12 GiB RAM for hibernation (resume requires swap >= RAM).  
  - Separate LUKS header allows a shorter PBKDF time (800 ms) for faster resume while keeping root’s PBKDF time higher for brute-force resistance.

- **Tolerances**  
  - Size: 12 GiB ± 1 MiB.  
  - Start sector: aligned to 1 MiB boundary (**STRATEGY-STORAGE-01**).  
  - Type GUID: 8200 (Linux swap) pre-encryption.

- **Strategy Reference**  
  - **STRATEGY-STORAGE-02** → Partition location and sizing.  
  - **STRATEGY-STORAGE-03** → Over-provisioning area reservation.  
  - **STRATEGY-ENCRYPTION-04** → Separate encrypted swap container.  
  - **STRATEGY-ENCRYPTION-05** → UUID-based `crypttab.initramfs` generation.  
  - **STRATEGY-ENCRYPTION-03** → Passphrase reuse strategy.

- **Failure Modes**  
  - Size too small for hibernation → resume failures or truncated memory image.  
  - Misalignment → degraded write performance.  
  - Swap not encrypted → hibernation data leakage.  
  - Placed after over-provisioning space → disrupts wear leveling strategy.

- **Verification Procedure**  
  1. Create partition:
     ```
     sgdisk -n 3:<start>:+12GiB -t 3:8200 /dev/<disk>
     ```
     `<start>` = end of root partition + alignment offset.
  2. Confirm layout:
     ```
     lsblk -o NAME,SIZE,TYPE,PARTTYPE /dev/<disk>
     ```
  3. Validate alignment:
     ```
     lsblk -o NAME,START,ALIGNMENT /dev/<disk>
     ```

- **Pre-flight Actions**  
  - Save details to `/root/swap-partition-info.txt`.  
  - Cross-check RAM size to ensure swap is adequate for hibernation use case.  
  - Keep PBKDF parameters documented for resume tuning.

### .B10  Over-provisioning space allocation
**.B10  Over-Provisioning Space Allocation**

- **Purpose**  
  - Reserve unallocated space at the end of the NVMe device to extend SSD lifespan, improve performance stability, and assist in wear leveling.  
  - Provide a safety buffer for unexpected growth in metadata or filesystem structures.  
  - Fulfill **STRATEGY-STORAGE-03** by keeping ~20 GiB unpartitioned and invisible to the OS.

- **Insights**  
  - NVMe controllers use unallocated space as an extension of their internal spare blocks pool, which improves write performance consistency under heavy workloads.  
  - Over-provisioning reduces write amplification and can significantly extend NAND endurance.  
  - Most consumer drives have some factory OP, but reserving additional space benefits sustained write workloads and snapshot-heavy Btrfs setups (**STRATEGY-STORAGE-06**).  
  - Unallocated space should be physically contiguous at the end of the drive for maximum effectiveness.

- **Explanations**  
  - The OS cannot use this area, but the drive’s firmware will still see it and treat it as part of its wear leveling pool.  
  - Leaving space inside a filesystem (e.g., 95% full) is not the same as true over-provisioning — the latter is invisible to the OS.  
  - Amount chosen (~20 GiB) balances endurance benefits with usable capacity needs.

- **Tolerances**  
  - Size: 20 GiB ± 1 GiB.  
  - Location: last segment of the disk, directly after the swap partition.  
  - Must remain fully unallocated — no partition table entry.

- **Strategy Reference**  
  - **STRATEGY-STORAGE-03** → Over-provisioning space reservation.  
  - **STRATEGY-STORAGE-05** → Size validation and byte accounting.  
  - **STRATEGY-VALIDATION-02** → Storage verification.

- **Failure Modes**  
  - Accidental allocation → eliminates OP benefits and may impact drive longevity.  
  - Misplacement (not contiguous at disk end) → firmware may not treat it as spare pool.  
  - Inconsistent size → reduced endurance or wasted capacity.

- **Verification Procedure**  
  1. After creating ESP, root, and swap partitions, check remaining free space:
     ```
     lsblk -o NAME,SIZE,TYPE /dev/<disk>
     ```
  2. Ensure the final free segment is ~20 GiB.  
  3. Validate with `sgdisk`:
     ```
     sgdisk -p /dev/<disk>
     ```
     Confirm last partition’s end sector is 20 GiB before disk’s total sector count.

- **Pre-flight Actions**  
  - Document OP size and location in `/root/overprovisioning-info.txt`.  
  - Recheck after installation to ensure no future expansion overwrites OP area.

### .B11  GPT backup creation
**.B11  GPT Backup Creation**

- **Purpose**  
  - Create a backup of the freshly created GPT partition table to allow rapid restoration in case of corruption, accidental deletion, or firmware issues.  
  - Ensure a recoverable baseline before any encryption, formatting, or data write operations begin.  
  - Satisfies **STRATEGY-STORAGE-04** (GPT backup creation and restoration procedures).

- **Insights**  
  - GPT stores two headers: one at the start of the disk (primary) and one at the end (secondary). If either becomes corrupted, recovery is possible if a valid backup exists.  
  - Arch install process often overwrites partition structures when experimenting — a binary GPT backup saves hours of manual re-entry.  
  - `sgdisk` allows creating a compact binary dump of the partition table, which can be restored byte-for-byte.

- **Explanations**  
  - GPT corruption can occur due to misconfigured partitioning tools, firmware bugs, or partial disk cloning.  
  - A backup file can be stored on the live ISO environment, external USB, or remote system.  
  - This step is done after **.B05–.B10** so the backup reflects the final partition plan.

- **Tolerances**  
  - Backup must be created immediately after confirming `.B10` free space allocation.  
  - File must be saved outside of the target disk to avoid overwriting during install.

- **Strategy Reference**  
  - **STRATEGY-STORAGE-04** → GPT backup creation/restoration procedures.  
  - **STRATEGY-VALIDATION-02** → Partition verification prior to backup.

- **Failure Modes**  
  - No backup → manual recreation needed in case of GPT corruption.  
  - Backup stored on target disk → overwritten during installation.  
  - Backup not matching actual layout → restoring leads to inconsistent or invalid partition table.

- **Verification Procedure**  
  1. Save GPT to external storage:
     ```
     sgdisk --backup=/mnt/external/gpt-backup-$(date +%Y%m%d).bin /dev/<disk>
     ```
  2. Confirm file exists and is non-zero:
     ```
     ls -lh /mnt/external/gpt-backup-*.bin
     ```
  3. Optionally test restore (to a different disk or loop device):
     ```
     sgdisk --load-backup=gpt-backup-YYYYMMDD.bin /dev/testdisk
     sgdisk -p /dev/testdisk
     ```

- **Pre-flight Actions**  
  - Store backup in at least two locations (e.g., USB stick + network share).  
  - Record SHA256 checksum for integrity verification:
     ```
     sha256sum gpt-backup-*.bin > gpt-backup-*.sha256
     ```
  - Document restore command in install notes for quick access during emergencies.

## C  ENCRYPTION PHASE
### .C01  LUKS container creation
**.C01  LUKS Container Creation**

- **Purpose**  
  - Create encrypted containers for both the root and swap partitions according to the Arch Linux atomic install plan.  
  - Protect all at-rest data (including hibernation images) from unauthorized access.  
  - Implement PBKDF timings and cipher parameters per **STRATEGY-ENCRYPTION-01** and **STRATEGY-ENCRYPTION-04**.

- **Insights**  
  - **Root LUKS2 container**: higher PBKDF target (~1500 ms) for brute-force resistance.  
  - **Swap LUKS2 container**: lower PBKDF target (~800 ms) for faster hibernation resume.  
  - AES-XTS-Plain64 with 512-bit keys ensures strong encryption without measurable performance bottlenecks on modern CPUs with AES-NI support (**STRATEGY-ENCRYPTION-06**).  
  - TPM2 binding (PCR 0+7) is optional and conditional per **STRATEGY-ENCRYPTION-02**, but passphrase fallback is always configured (**STRATEGY-RISK-01**).

- **Explanations**  
  - LUKS2 headers store encryption metadata, keyslots, and PBKDF settings.  
  - UUIDs are generated for use in `/etc/crypttab` and `initramfs` embedding (**STRATEGY-ENCRYPTION-05**).  
  - Passphrase reuse strategy (**STRATEGY-ENCRYPTION-03**) allows a single prompt to unlock both root and swap.

- **Tolerances**  
  - PBKDF target times:  
    - Root: 1500 ms ± 200 ms  
    - Swap: 800 ms ± 100 ms  
  - Cipher: AES-XTS-Plain64, key size = 512 bits, hash = SHA256.  
  - LUKS format version: 2 only (no LUKS1 fallback).

- **Strategy Reference**  
  - **STRATEGY-ENCRYPTION-01** → LUKS2 creation with tuned PBKDF.  
  - **STRATEGY-ENCRYPTION-02** → TPM2 hardware detection & enrollment.  
  - **STRATEGY-ENCRYPTION-03** → Passphrase reuse strategy.  
  - **STRATEGY-ENCRYPTION-04** → Separate swap container.  
  - **STRATEGY-ENCRYPTION-05** → UUID-based crypttab.  
  - **STRATEGY-ENCRYPTION-06** → Cipher parameters.

- **Failure Modes**  
  - Incorrect PBKDF settings → slow boot/resume or reduced security.  
  - Header corruption → complete data loss without backup.  
  - Swap left unencrypted → hibernation data leakage.  
  - TPM2 binding without fallback → lockout if PCR values change.

- **Verification Procedure**  
  1. Create root container:
     ```
     cryptsetup luksFormat /dev/<root-partition> \
       --type luks2 \
       --cipher aes-xts-plain64 \
       --key-size 512 \
       --hash sha256 \
       --iter-time 1500
     ```
  2. Create swap container:
     ```
     cryptsetup luksFormat /dev/<swap-partition> \
       --type luks2 \
       --cipher aes-xts-plain64 \
       --key-size 512 \
       --hash sha256 \
       --iter-time 800
     ```
  3. Open containers:
     ```
     cryptsetup open /dev/<root-partition> cryptroot
     cryptsetup open /dev/<swap-partition> cryptswap
     ```
  4. Verify:
     ```
     cryptsetup luksDump /dev/<root-partition>
     cryptsetup status cryptroot
     ```

- **Pre-flight Actions**  
  - Backup LUKS headers before filesystem creation:
     ```
     cryptsetup luksHeaderBackup /dev/<root-partition> --header-backup-file root-header.img
     cryptsetup luksHeaderBackup /dev/<swap-partition> --header-backup-file swap-header.img
     ```
  - Store header backups securely off-device.  
  - Document UUIDs and PBKDF timings in `/root/luks-info.txt`.

### .C02  PBKDF parameter tuning
**.C02  PBKDF Parameter Tuning**

- **Purpose**  
  - Adjust the Password-Based Key Derivation Function (PBKDF) iteration time for each LUKS2 container to balance security with boot/resume performance.  
  - Ensure root has maximum brute-force resistance, while swap is optimized for hibernation resume speed.  
  - Directly fulfills **STRATEGY-ENCRYPTION-01** (tuned PBKDF) and **STRATEGY-ENCRYPTION-04** (fast swap unlock).

- **Insights**  
  - PBKDF2 and Argon2id are the available KDFs in LUKS2; Arch defaults to Argon2id for better GPU resistance.  
  - `--iter-time` sets target computation time, not a fixed iteration count — cryptsetup auto-adjusts based on CPU speed.  
  - TPM2 unlock methods may bypass PBKDF entirely but a fallback passphrase slot still benefits from tuned timings.  
  - Passphrase reuse strategy (**STRATEGY-ENCRYPTION-03**) requires both containers to have compatible unlock prompt timings.

- **Explanations**  
  - Higher PBKDF times = stronger resistance against offline brute-force attacks, but slower unlock.  
  - For swap, overly high PBKDF times can cause multi-second delays when resuming from hibernation.  
  - Tuning is hardware-specific — a fast CPU can tolerate higher times without noticeable impact.

- **Tolerances**  
  - Root PBKDF target: 1500 ms ± 200 ms.  
  - Swap PBKDF target: 800 ms ± 100 ms.  
  - KDF: Argon2id (preferred), fallback to PBKDF2 only for compatibility scenarios.  
  - Parallelism: 4 (or CPU core count, whichever is lower).  
  - Memory cost: ≥ 128 MiB for root, ≥ 64 MiB for swap.

- **Strategy Reference**  
  - **STRATEGY-ENCRYPTION-01** → PBKDF tuning.  
  - **STRATEGY-ENCRYPTION-03** → Passphrase reuse.  
  - **STRATEGY-ENCRYPTION-04** → Swap hibernation optimization.

- **Failure Modes**  
  - PBKDF too low → reduces brute-force resistance.  
  - PBKDF too high → excessive boot/resume delays.  
  - Different passphrases for root/swap → extra prompts during boot.  
  - Inconsistent Argon2id parameters → unpredictable performance.

- **Verification Procedure**  
  1. Measure system baseline:
     ```
     cryptsetup benchmark
     ```
  2. Adjust root:
     ```
     cryptsetup luksChangeKey /dev/<root-partition> \
       --pbkdf argon2id \
       --iter-time 1500 \
       --pbkdf-memory 131072 \
       --pbkdf-parallel 4
     ```
  3. Adjust swap:
     ```
     cryptsetup luksChangeKey /dev/<swap-partition> \
       --pbkdf argon2id \
       --iter-time 800 \
       --pbkdf-memory 65536 \
       --pbkdf-parallel 4
     ```
  4. Verify settings:
     ```
     cryptsetup luksDump /dev/<root-partition> | grep -A4 'PBKDF'
     cryptsetup luksDump /dev/<swap-partition> | grep -A4 'PBKDF'
     ```

- **Pre-flight Actions**  
  - Record final PBKDF parameters in `/root/luks-pbkdf-info.txt`.  
  - Test boot and hibernation resume to confirm acceptable unlock times.  
  - Keep header backups after tuning in case parameters need to be restored.

### .C03  TPM2 enrollment
**.C03  TPM2 Enrollment**

- **Purpose**  
  - Integrate Trusted Platform Module 2.0 into the LUKS unlock process for root and swap partitions, enabling hardware-bound key storage.  
  - Allow automatic decryption when platform integrity matches expected state, reducing or eliminating passphrase prompts.  
  - Maintain a fallback passphrase path per **STRATEGY-RISK-01** to prevent lockouts.

- **Insights**  
  - TPM2 can bind keys to Platform Configuration Registers (PCRs), ensuring decryption only occurs when firmware, bootloader, and kernel integrity match.  
  - For Secure Boot workflows, binding to PCR 0+7 enforces that only signed, measured boot chains can decrypt data (**STRATEGY-ENCRYPTION-07**).  
  - Arch’s `systemd-cryptenroll` integrates TPM2 keys directly into LUKS2 metadata; this avoids manual keyfile management.  
  - TPM2 presence is not guaranteed — `.A11` checks determine if this step is executed.

- **Explanations**  
  - TPM2 enrollment stores an additional keyslot in the LUKS header, linked to the TPM device rather than a human passphrase.  
  - On boot, `systemd-cryptsetup` queries the TPM for the bound key; if PCR values match, unlock proceeds automatically.  
  - PCR binding adds an extra layer of tamper detection: modified boot chain or firmware resets PCRs and invalidates key.

- **Tolerances**  
  - TPM version: 2.0 only.  
  - Keyslot count: leave at least one free slot for recovery.  
  - PCR selection:  
    - PCR 0 → firmware & bootloader measurements.  
    - PCR 7 → Secure Boot policy state.  
  - Backup passphrase: mandatory.

- **Strategy Reference**  
  - **STRATEGY-ENCRYPTION-02** → TPM2 detection & enrollment.  
  - **STRATEGY-ENCRYPTION-07** → PCR binding with Secure Boot.  
  - **STRATEGY-RISK-01** → Passphrase fallback.

- **Failure Modes**  
  - PCRs change after firmware update → TPM key unusable until re-enrolled.  
  - TPM disabled in BIOS/UEFI → no auto-unlock.  
  - Lost passphrase → complete lockout if TPM key becomes invalid.  
  - TPM chip failure → must fall back to manual passphrase entry.

- **Verification Procedure**  
  1. Check TPM2 presence:
     ```
     systemd-cryptenroll --tpm2-device=list
     ```
  2. Enroll TPM2 key for root:
     ```
     systemd-cryptenroll /dev/<root-partition> \
       --tpm2-device=auto \
       --tpm2-pcrs=0+7
     ```
  3. Enroll TPM2 key for swap:
     ```
     systemd-cryptenroll /dev/<swap-partition> \
       --tpm2-device=auto \
       --tpm2-pcrs=0+7
     ```
  4. Verify enrollment:
     ```
     systemd-cryptenroll /dev/<root-partition> --dump
     ```

- **Pre-flight Actions**  
  - Document PCR bindings and keyslot assignments in `/root/tpm2-enrollment-info.txt`.  
  - Test auto-unlock by rebooting and ensuring no passphrase is prompted when system state is unchanged.  
  - Rehearse recovery procedure with passphrase to confirm fallback path works.

### .C04  Passphrase configuration
**.C04  Passphrase Configuration**

- **Purpose**  
  - Set and manage passphrases for the root and swap LUKS containers, ensuring a consistent and secure unlock process.  
  - Implement the single-passphrase strategy (**STRATEGY-ENCRYPTION-03**) to unlock both containers with one entry at boot.  
  - Maintain at least one offline-stored recovery passphrase for disaster scenarios.

- **Insights**  
  - A unified passphrase reduces boot complexity and human error while still allowing TPM2 auto-unlock as the primary path.  
  - Each LUKS container supports multiple keyslots — one can be TPM-bound, one the primary passphrase, and one a recovery key.  
  - Passphrases should be long (≥ 20 characters), high-entropy, and memorable enough to type without copy-paste in early boot.

- **Explanations**  
  - By adding the same passphrase to both root and swap, `systemd-cryptsetup` prompts only once during boot.  
  - Recovery passphrases can be longer and stored securely offline; these are only needed if TPM2 binding or main passphrase fails.  
  - Swapping passphrases between slots allows rotation without wiping encrypted data.

- **Tolerances**  
  - Minimum length: 20 characters (primary) / 32 characters (recovery).  
  - Maximum active passphrases: ≤ 3 per container to simplify management.  
  - Ensure keyslot count does not exceed container capacity.

- **Strategy Reference**  
  - **STRATEGY-ENCRYPTION-03** → Single prompt dual unlock.  
  - **STRATEGY-RISK-01** → Fallback access strategy.  
  - **STRATEGY-ENCRYPTION-05** → UUID-based mapping in `crypttab`.

- **Failure Modes**  
  - Different passphrases → two boot prompts, breaking automation flow.  
  - Lost recovery passphrase → lockout risk if TPM and primary both fail.  
  - Too-short or guessable passphrase → reduced brute-force resistance.  
  - Mis-assigned keyslot → passphrase doesn’t match intended container.

- **Verification Procedure**  
  1. Add unified passphrase to both containers:
     ```
     cryptsetup luksAddKey /dev/<root-partition>
     cryptsetup luksAddKey /dev/<swap-partition>
     ```
  2. Test unlock with single passphrase:
     ```
     cryptsetup open /dev/<root-partition> testroot
     cryptsetup open /dev/<swap-partition> testswap
     ```
  3. Add recovery passphrase:
     ```
     cryptsetup luksAddKey /dev/<root-partition> --key-slot 2
     cryptsetup luksAddKey /dev/<swap-partition> --key-slot 2
     ```
  4. Verify:
     ```
     cryptsetup luksDump /dev/<root-partition> | grep -A2 "Keyslots"
     ```

- **Pre-flight Actions**  
  - Store recovery passphrase in offline encrypted vault and in printed sealed copy.  
  - Document active keyslot assignments in `/root/luks-passphrase-info.txt`.  
  - Test boot sequence to confirm only one prompt is required with TPM disabled.

### .C05  LUKS volume opening
**.C05  LUKS Volume Opening**

- **Purpose**  
  - Open the encrypted LUKS containers for root and swap so that filesystems can be created and mounted.  
  - Establish consistent device-mapper names (`cryptroot`, `cryptswap`) for use in fstab, crypttab, and initramfs.  
  - Prepare volumes for subsequent filesystem creation and system installation.

- **Insights**  
  - Naming consistency is critical — using fixed mapper names avoids breakage if UUIDs or device paths change.  
  - This step validates passphrases, TPM2 auto-unlock configuration, and PBKDF tuning before committing to filesystem creation.  
  - Per **STRATEGY-ENCRYPTION-05**, `crypttab.initramfs` will be generated using UUIDs, but mapper names must be stable.

- **Explanations**  
  - When `cryptsetup open` is run, the kernel’s device-mapper framework creates a virtual block device (`/dev/mapper/<name>`) that exposes the decrypted view of the LUKS container.  
  - Root and swap will each have a mapped device — these are treated like raw block devices by mkfs and mkswap.  
  - Verifying successful opening now avoids wasted effort in later steps.

- **Tolerances**  
  - Mapper names: `cryptroot` and `cryptswap` only (no variation).  
  - Both containers must open without errors before proceeding.  
  - TPM2-bound unlock should work silently if enabled; otherwise passphrase prompt must succeed.

- **Strategy Reference**  
  - **STRATEGY-ENCRYPTION-03** → Unified passphrase unlock.  
  - **STRATEGY-ENCRYPTION-05** → UUID-based mapping in initramfs.  
  - **STRATEGY-RISK-01** → Fallback passphrase.

- **Failure Modes**  
  - Incorrect mapper name → fstab/crypttab mismatch at boot.  
  - Container fails to open → cannot create filesystem or swap.  
  - Opening swap first may cause systemd to auto-activate it unexpectedly — must be avoided.  
  - Wrong passphrase → lockout from container.

- **Verification Procedure**  
  1. Open root:
     ```
     cryptsetup open /dev/<root-partition> cryptroot
     ```
  2. Open swap:
     ```
     cryptsetup open /dev/<swap-partition> cryptswap
     ```
  3. Confirm devices exist:
     ```
     lsblk /dev/mapper/cryptroot
     lsblk /dev/mapper/cryptswap
     ```
  4. Verify mappings:
     ```
     dmsetup info
     ```

- **Pre-flight Actions**  
  - Ensure LUKS header backups exist before opening.  
  - Test both TPM2 auto-unlock and passphrase unlock paths.  
  - Record mapping info in `/root/luks-mapper-info.txt` for consistency in boot configuration.

### .C06  Crypttab.initramfs creation (TPM2 auto-unlock)
**.C06  Crypttab.initramfs Creation (TPM2 Auto-Unlock)**

- **Purpose**  
  - Generate a `crypttab.initramfs` file that embeds encrypted volume mapping information into the initramfs.  
  - Enable TPM2-based auto-unlock during early boot, eliminating manual passphrase entry when platform integrity is verified.  
  - Ensure both root and swap mappings are correctly defined for systemd-based early boot processing.

- **Insights**  
  - The standard `/etc/crypttab` is processed after the initramfs stage, but root needs to be unlocked *inside* the initramfs — hence `crypttab.initramfs`.  
  - Using UUIDs rather than device paths ensures consistent mapping even if disk order changes (**STRATEGY-ENCRYPTION-05**).  
  - When TPM2 binding is active (**STRATEGY-ENCRYPTION-02**, **STRATEGY-ENCRYPTION-07**), systemd can unlock without prompting for a passphrase.  
  - Swap must also be defined if hibernation is configured so the resume image can be accessed before pivot to root.

- **Explanations**  
  - `crypttab.initramfs` entries follow the format:
    ```
    <mapper-name> UUID=<uuid> none luks,discard
    ```
  - The `none` field indicates no keyfile or passphrase is stored — TPM2 unlock handles key retrieval.  
  - The `discard` option allows SSD TRIM operations to be passed through for performance and wear leveling.

- **Tolerances**  
  - Must use LUKS UUIDs from `blkid`, not partition UUIDs.  
  - Mapper names must match those used in `.C05` exactly.  
  - File must be located at `/etc/crypttab.initramfs` inside the target root before initramfs generation.

- **Strategy Reference**  
  - **STRATEGY-ENCRYPTION-02** → TPM2 detection/enrollment.  
  - **STRATEGY-ENCRYPTION-03** → Unified passphrase fallback.  
  - **STRATEGY-ENCRYPTION-05** → UUID-based mapping.  
  - **STRATEGY-ENCRYPTION-07** → PCR binding for Secure Boot.

- **Failure Modes**  
  - Wrong UUID → boot fails with “device not found” error.  
  - Wrong mapper name → initramfs unlock scripts fail.  
  - Missing swap entry → hibernation resume fails.  
  - Incorrect discard usage on unsupported hardware → errors during boot.

- **Verification Procedure**  
  1. Get UUIDs:
     ```
     blkid /dev/<root-partition>
     blkid /dev/<swap-partition>
     ```
  2. Create `/etc/crypttab.initramfs`:
     ```
     cryptroot UUID=<root-uuid> none luks,discard
     cryptswap UUID=<swap-uuid> none luks,discard
     ```
  3. Rebuild initramfs:
     ```
     mkinitcpio -P
     ```
  4. Inspect initramfs to confirm inclusion:
     ```
     lsinitcpio /boot/initramfs-linux.img | grep crypttab.initramfs
     ```

- **Pre-flight Actions**  
  - Backup the file to `/root/crypttab.initramfs.bak`.  
  - Test TPM2 auto-unlock by rebooting with Secure Boot and PCR values unchanged.  
  - Test fallback by disabling TPM2 in firmware and confirming passphrase prompt appears.

### .C07  Store LUKS UUID for later use
**.C07  Store LUKS UUID for Later Use**

- **Purpose**  
  - Record the LUKS container UUIDs for root and swap partitions for use in fstab, crypttab, mkinitcpio, and recovery procedures.  
  - Ensure that all configuration files reference immutable UUIDs rather than device paths, preventing boot failures from device name changes.

- **Insights**  
  - LUKS UUIDs are different from partition UUIDs — they are internal to the encrypted container and remain constant even if the partition table changes.  
  - UUID-based mapping is central to **STRATEGY-ENCRYPTION-05** for reliable automated unlocking in both TPM2 and passphrase scenarios.  
  - Keeping a secure, offline copy of these UUIDs allows for rapid rebuild of crypttab/initramfs after disaster recovery.

- **Explanations**  
  - During installation, LUKS UUIDs are extracted using `blkid` or `cryptsetup luksUUID`.  
  - These identifiers are used in `/etc/crypttab.initramfs` (for root/swap unlock) and sometimes in kernel parameters (e.g., `resume=UUID=<swap-uuid>` for hibernation).  
  - If LUKS headers are restored from backup, the UUIDs remain unchanged, simplifying reconfiguration.

- **Tolerances**  
  - Must store *both* root and swap LUKS UUIDs.  
  - File must be saved in at least two separate secure locations (local + external).  
  - Formatting must be clear and unambiguous — no truncation.

- **Strategy Reference**  
  - **STRATEGY-ENCRYPTION-05** → UUID-based mapping.  
  - **STRATEGY-VALIDATION-02** → Storage verification.  
  - **STRATEGY-RISK-07** → Lockout prevention.

- **Failure Modes**  
  - Using partition UUID instead of LUKS UUID → initramfs unlock scripts fail.  
  - Losing UUID record → longer recovery process, requiring live environment to re-probe.  
  - Storing UUIDs only on encrypted root → inaccessible in recovery.

- **Verification Procedure**  
  1. Get UUIDs:
     ```
     cryptsetup luksUUID /dev/<root-partition>
     cryptsetup luksUUID /dev/<swap-partition>
     ```
     or
     ```
     blkid /dev/<root-partition>
     blkid /dev/<swap-partition>
     ```
  2. Save to file:
     ```
     echo "ROOT_LUKS_UUID=<uuid>" >> /root/luks-uuids.txt
     echo "SWAP_LUKS_UUID=<uuid>" >> /root/luks-uuids.txt
     ```
  3. Copy to external media:
     ```
     cp /root/luks-uuids.txt /mnt/usb/
     ```

- **Pre-flight Actions**  
  - Create a printed copy for offline storage in sealed envelope.  
  - Store alongside LUKS header backups for complete recovery package.  
  - Verify UUID entries by cross-checking with live environment commands before finalizing configuration.

## D  FILESYSTEM PHASE
### .D01  ESP formatting (FAT32)
**.D01  ESP Formatting (FAT32)**

- **Purpose**  
  - Format the EFI System Partition (ESP) with FAT32 to ensure UEFI firmware compatibility for booting.  
  - Provide a dedicated, standards-compliant partition for the systemd-boot loader, kernels, and initramfs images.  
  - Satisfies **STRATEGY-BOOT-01** requirement for a clean systemd-boot installation environment.

- **Insights**  
  - UEFI specification mandates the ESP to be FAT32 for partitions > 512 MiB; FAT16 is only allowed for very small ESPs (≤ 512 MiB).  
  - The chosen size of 1 GiB (**STRATEGY-STORAGE-02**) ensures space for multiple kernels, fallback images, microcode updates, and UKI builds (**STRATEGY-FUTURE-03**).  
  - Labeling the ESP as `ESP` and setting the correct partition type GUID ensures detection by firmware and systemd tooling.

- **Explanations**  
  - Formatting is done *after* partition table creation and alignment checks (.B05–.B06) and before root filesystem creation.  
  - The `mkfs.fat` tool from `dosfstools` is standard in Arch ISO environments.  
  - The `-F 32` flag enforces FAT32 even on partitions small enough to be FAT16-eligible — prevents firmware edge-case incompatibilities.

- **Tolerances**  
  - Partition size: 1 GiB ± 10 MiB.  
  - Partition type GUID: `c12a7328-f81f-11d2-ba4b-00a0c93ec93b` (EFI System).  
  - Filesystem: FAT32 only, with allocation unit size default (no forced changes).

- **Strategy Reference**  
  - **STRATEGY-STORAGE-02** → ESP partition layout.  
  - **STRATEGY-BOOT-01** → systemd-boot installation.  
  - **STRATEGY-VALIDATION-04** → Boot verification.

- **Failure Modes**  
  - Wrong filesystem type → firmware may not detect ESP.  
  - Incorrect type GUID → OS tools fail to mount ESP automatically.  
  - Insufficient size → later kernel or initramfs updates fail due to space exhaustion.

- **Verification Procedure**  
  1. Format ESP:
     ```
     mkfs.fat -F 32 -n ESP /dev/<esp-partition>
     ```
  2. Verify filesystem type and label:
     ```
     lsblk -f /dev/<esp-partition>
     ```
  3. Confirm partition type GUID:
     ```
     blkid -p /dev/<esp-partition>
     ```
     or
     ```
     sgdisk -i <partition-number> /dev/<disk>
     ```

- **Pre-flight Actions**  
  - Ensure ESP is unmounted before formatting.  
  - Confirm no bootloader files exist that need preservation (for dual-boot scenarios).  
  - Document ESP partition device path and label in `/root/esp-info.txt` for boot configuration reference.

### .D02  Root filesystem creation
**.D02  Root Filesystem Creation**

- **Purpose**  
  - Create a Btrfs filesystem on the decrypted root LUKS container, enabling advanced subvolume management, snapshotting, and compression.  
  - Implement the predefined subvolume structure from **STRATEGY-STORAGE-06** for clean separation of system, user, and variable data.  
  - Prepare the root environment for a flexible, rollback-capable Arch installation.

- **Insights**  
  - Btrfs offers built-in features (compression, CoW, subvolumes) that align with **STRATEGY-DEVELOPMENT-01** through **STRATEGY-DEVELOPMENT-08**.  
  - The `-L` option assigns a filesystem label (e.g., `BTRFS_ROOT`) for easier identification during recovery.  
  - The initial format is performed on the raw decrypted device (`/dev/mapper/cryptroot`) before subvolumes are created.

- **Explanations**  
  - Using `mkfs.btrfs` with `-f` (force) ensures a clean filesystem even if residual metadata exists.  
  - Compression is not enabled at mkfs stage — instead, mount options will specify `compress=zstd:3 noatime` per **STRATEGY-STORAGE-07**.  
  - The base filesystem is mounted temporarily to create subvolumes, after which it is unmounted and remounted with optimized options.

- **Tolerances**  
  - Label: `BTRFS_ROOT` (all caps, no spaces) to match recovery scripts.  
  - Node size: default (no override).  
  - Metadata profile: `single` for single-device setups.  
  - Filesystem UUID: auto-generated, recorded for reference.

- **Strategy Reference**  
  - **STRATEGY-STORAGE-06** → Subvolume structure.  
  - **STRATEGY-STORAGE-07** → Compression and mount optimization.  
  - **STRATEGY-DEVELOPMENT-01** → Snapshot-based workflow.

- **Failure Modes**  
  - Formatting wrong device → catastrophic data loss.  
  - Skipping `-f` on reused partitions → mount errors from stale superblocks.  
  - Missing label → harder to identify during recovery.  
  - Omitting subvolumes → loss of rollback and snapshot granularity.

- **Verification Procedure**  
  1. Create Btrfs filesystem:
     ```
     mkfs.btrfs -f -L BTRFS_ROOT /dev/mapper/cryptroot
     ```
  2. Verify filesystem type and label:
     ```
     lsblk -f /dev/mapper/cryptroot
     ```
  3. Mount to create subvolumes:
     ```
     mount /dev/mapper/cryptroot /mnt
     btrfs subvolume create /mnt/@main
     btrfs subvolume create /mnt/@main-home
     btrfs subvolume create /mnt/@var
     btrfs subvolume create /mnt/@log
     btrfs subvolume create /mnt/@cache
     btrfs subvolume create /mnt/@tmp
     btrfs subvolume create /mnt/@shared
     btrfs subvolume create /mnt/@user-local
     umount /mnt
     ```

- **Pre-flight Actions**  
  - Triple-check `/dev/mapper/cryptroot` is correct before formatting.  
  - Record filesystem UUID:
     ```
     blkid /dev/mapper/cryptroot >> /root/fs-uuids.txt
     ```
  - Keep a diagram of subvolume layout for reference in mount configuration.

### .D03  Swap space initialization
**.D03  Swap Space Initialization**

- **Purpose**  
  - Create and activate an encrypted swap space within the decrypted swap LUKS container (`cryptswap`).  
  - Support hibernation by ensuring swap size is adequate to store the full system RAM image.  
  - Fulfill **STRATEGY-ENCRYPTION-04** requirement for separate encrypted swap.

- **Insights**  
  - Encrypted swap prevents leakage of sensitive data from RAM (including hibernation images).  
  - By placing swap in a dedicated LUKS container, PBKDF tuning from **.C02** ensures faster resume from hibernation without sacrificing security.  
  - The swap UUID will be referenced in `/etc/fstab` and kernel `resume=` parameter.

- **Explanations**  
  - `mkswap` writes swap-specific metadata, including a UUID, onto the decrypted block device.  
  - The `swapon` command is optional at install time but is useful for immediate testing of swap functionality.  
  - Hibernation requires swap space ≥ total installed RAM; otherwise resume will fail.

- **Tolerances**  
  - Swap size: ~12 GiB as per **STRATEGY-STORAGE-02**, but at least equal to installed RAM if hibernation is enabled.  
  - Label: `SWAP` (optional but recommended).  
  - Filesystem type: swap only — do not format with a traditional FS.

- **Strategy Reference**  
  - **STRATEGY-ENCRYPTION-04** → Separate encrypted swap container.  
  - **STRATEGY-VALIDATION-05** → Configuration verification.  
  - **STRATEGY-RISK-07** → Lockout prevention.

- **Failure Modes**  
  - Formatting wrong device → loss of data or root filesystem.  
  - Insufficient swap size → hibernation fails or crashes.  
  - Missing `resume=` kernel parameter → system boots fresh instead of resuming.  
  - Activating swap before encryption open → unencrypted swap exposure.

- **Verification Procedure**  
  1. Create swap on decrypted device:
     ```
     mkswap -L SWAP /dev/mapper/cryptswap
     ```
  2. Verify UUID:
     ```
     blkid /dev/mapper/cryptswap
     ```
  3. (Optional) Activate immediately:
     ```
     swapon /dev/mapper/cryptswap
     ```
  4. Confirm active swap:
     ```
     swapon --show
     free -h
     ```

- **Pre-flight Actions**  
  - Ensure `cryptswap` is open from **.C05**.  
  - Record swap UUID in `/root/swap-uuid.txt`.  
  - If hibernation planned, set kernel parameter:
     ```
     resume=UUID=<swap-uuid>
     ```
  - Test swap activation before proceeding to system installation.

### .D04  Btrfs subvolume creation
### .D05  Compression configuration
### .D06  Mount option configuration

E  SYSTEM INSTALLATION PHASE
### .E01  Update keys & package database
### .E02  Mirror selection & ranking
### .E03–.E08  Base system, tools, drivers, firmware, extras installation

F  MOUNT CONFIGURATION PHASE
### .F01  Root volume mounting
### .F02  Boot partition mounting
### .F03  Additional mountpoint creation
### .F04  Swap activation
### .F05  Fstab generation
### .F06  Mount option verification

G  SYSTEM CONFIGURATION PHASE
### .G01  Chroot entry
### .G02  Timezone configuration
### .G03  Hardware clock setup
### .G04  Locale generation
### .G05  Language configuration
### .G06  Console configuration persistence
### .G07  Hostname configuration
### .G08  Network configuration
### .G09  Hosts file setup

H  BOOT CONFIGURATION PHASE
### .H01  Initramfs hook configuration
### .H02  Initramfs generation
### .H03  Bootloader installation - systemd-boot
### .H04  Boot entry creation
### .H05  Fallback entry creation
### .H06  Microcode loading setup
### .H07  Kernel parameter configuration
### .H08  Resume/hibernation setup

I  SECURITY CONFIGURATION PHASE
### .I01  Root password setup
### .I02  Secure Boot key generation
### .I03  Key enrollment
### .I04  Kernel signing
### .I05  UKI creation (optional)
### .I06  TPM2 configuration

J  SYSTEM OPTIMIZATION PHASE
### .J01  Swappiness tuning
### .J02  TRIM timer enablement
### .J03  Time synchronization service
### .J04  Performance mount options
### .J05  TLP enablement
### .J06  Disable Intel PSR (i915)
### .J07  User account creation
### .J08  Snapper setup
### .J09  Bluetooth setup
### .J10  Create baseline snapshots
### .J11  Create sandbox snapshots
### .J12  Get username for system configuration
### .J13  Add sandbox boot entry
### .J14  Setup autologin

K  PRE-REBOOT VERIFICATION PHASE
### .K01  Configuration file review
### .K02  UUID verification
### .K03  Bootloader entry validation
### .K04  ESP space check
### .K05  Mount hierarchy verification
### .K06  Service enablement check

L  REBOOT PHASE
### .L01  Chroot exit
### .L02  Partition unmounting
### .L03  System restart
### .L04  Installation medium removal

M  POST-INSTALLATION PHASE
### .M01  First boot verification
### .M02  Suspend/resume testing
### .M03  Hibernation testing
### .M04  Network connectivity check
### .M05  Service status verification
### .M06  User account creation
### .M07  GUI installation
### .M08  Additional software setup
### .M09  Update mirrors
### .M10  System update

N  MAINTENANCE & RECOVERY PHASE
### .N01  GPT restore procedures
### .N02  Bootloader recovery
### .N03  UUID mismatch fixes
### .N04  Kernel update procedures
### .N05  Btrfs maintenance
### .N06  SSD health monitoring
### .N07  System backup strategy
### .N08  Performance monitoring


TESTS
### .TEST01  Sector size consistency verification
### .TEST02  Partition alignment verification
### .TEST03  Size verification (multiple tools)
### .TEST04  LUKS headers verification
### .TEST05  Key slot verification
### .TEST06  Encryption strength verification
### .TEST07  UUID cross-verification
### .TEST08  Btrfs filesystem verification
### .TEST09  Mount options verification
### .TEST10  ESP filesystem check
### .TEST11  Size accounting verification
### .TEST12  fstab and crypttab UUID consistency
### .TEST13  systemd-boot installation verification
### .TEST14  Kernel/initrd presence verification
### .TEST15  Boot entry syntax verification
### .TEST16  Boot entry UUID consistency
### .TEST17  TPM2 token verification
### .TEST18  Security file permissions verification
### .TEST19  Final comprehensive verification
### .TEST20  Hardware compatibility verification
### .TEST21  Memory/swap ratio verification
### .TEST22  Package dependency verification
### .TEST23  Microcode verification
### .TEST24  System configuration verification
### .TEST25  mkinitcpio configuration verification
### .TEST26  Kernel parameter verification
### .TEST27  Compression settings verification
### .TEST28  System tuning verification
### .TEST29  Service configuration verification
### .TEST30  User account verification
### .TEST31  Snapper configuration verification
### .TEST32  Sandbox subvolume verification
### .TEST33  Autologin configuration verification
### .TEST34  Recovery readiness verification
### .TEST35  Over-provisioning verification
### .TEST36  Secure Boot readiness verification
### .TEST37  Plymouth and graphics verification
### .TEST38  Network and connectivity verification
### .TEST39  Audio system verification


ARCH LINUX INSTALLATION STRATEGY – ATOMIC COMPONENT IDs
  STORAGE LAYER
    STRATEGY-STORAGE-01  GPT partitioning with 1 MiB alignment for sector compatibility
    STRATEGY-STORAGE-02  Three-partition layout (1G ESP, encrypted root, 12G encrypted swap)
    STRATEGY-STORAGE-03  NVMe over-provisioning reservation (~20GB unallocated)
    STRATEGY-STORAGE-04  GPT backup creation and restoration procedures
    STRATEGY-STORAGE-05  Multi-tool partition size validation and byte accounting
    STRATEGY-STORAGE-06  Btrfs subvolume structure (@main, @main-home, @var, @log, @cache, @tmp, @shared, @user-local)
    STRATEGY-STORAGE-07  zstd:3 compression with noatime mount optimization
  ENCRYPTION LAYER
    STRATEGY-ENCRYPTION-01  LUKS2 container creation with tuned PBKDF (1500ms root, 800ms swap)
    STRATEGY-ENCRYPTION-02  TPM2 hardware detection and conditional enrollment
    STRATEGY-ENCRYPTION-03  Passphrase reuse strategy (single prompt, dual unlock)
    STRATEGY-ENCRYPTION-04  Separate encrypted swap container for hibernation
    STRATEGY-ENCRYPTION-05  Crypttab.initramfs UUID-based generation
    STRATEGY-ENCRYPTION-06  AES-XTS-Plain64 cipher with 512-bit keys and SHA256
    STRATEGY-ENCRYPTION-07  PCR 0+7 TPM2 binding for Secure Boot integration
  BOOT LAYER
    STRATEGY-BOOT-01  systemd-boot installation replacing GRUB
    STRATEGY-BOOT-02  Quad-kernel strategy (linux + linux-lts, normal + fallback)
    STRATEGY-BOOT-03  Multi-subvolume boot entry generation
    STRATEGY-BOOT-04  Intel microcode integration with dedicated initrd
    STRATEGY-BOOT-05  Hibernation resume parameter configuration
    STRATEGY-BOOT-06  mkinitcpio systemd hooks (sd-encrypt, resume, filesystems)
    STRATEGY-BOOT-07  Boot entry UUID consistency validation
  DEVELOPMENT WORKFLOW
    STRATEGY-DEVELOPMENT-01  Git-like branching model using Btrfs snapshots
    STRATEGY-DEVELOPMENT-02  @main stable production environment maintenance
    STRATEGY-DEVELOPMENT-03  @sandbox static snapshot for safe experimentation
    STRATEGY-DEVELOPMENT-04  @feat-* feature branch creation and management
    STRATEGY-DEVELOPMENT-05  Change isolation and testing methodology
    STRATEGY-DEVELOPMENT-06  Feature branch boot entry auto-generation
    STRATEGY-DEVELOPMENT-07  Rollback and promotion procedures
    STRATEGY-DEVELOPMENT-08  Failed experiment cleanup and disposal
  SYSTEM OPERATION
    STRATEGY-OPERATION-01  Early swap unlock for hibernation support
    STRATEGY-OPERATION-02  System tuning (swappiness=10, fstrim.timer)
    STRATEGY-OPERATION-03  NetworkManager and Bluetooth service enablement
    STRATEGY-OPERATION-04  Plymouth graphical unlock integration
    STRATEGY-OPERATION-05  uwsm + autologin seamless desktop transition
    STRATEGY-OPERATION-06  Snapper snapshot management for root/home/var
    STRATEGY-OPERATION-07  User account creation with sudo privileges
    STRATEGY-OPERATION-08  Service configuration and enablement verification
  VALIDATION FRAMEWORK
    STRATEGY-VALIDATION-01  Hardware compatibility verification (CPU, memory, NVMe)
    STRATEGY-VALIDATION-02  Storage verification (alignment, sizes, UUIDs)
    STRATEGY-VALIDATION-03  Encryption verification (LUKS headers, key slots, PBKDF)
    STRATEGY-VALIDATION-04  Boot verification (systemd-boot, entries, parameters)
    STRATEGY-VALIDATION-05  Configuration verification (fstab, crypttab, services)
    STRATEGY-VALIDATION-06  Security verification (permissions, Secure Boot readiness)
    STRATEGY-VALIDATION-07  Recovery verification (backups, over-provisioning)
    STRATEGY-VALIDATION-08  39-point comprehensive testing framework
    STRATEGY-VALIDATION-09  Multi-tool redundant validation methodology
  RISK MITIGATION
    STRATEGY-RISK-01  TPM2 failure → passphrase fallback strategy
    STRATEGY-RISK-02  Kernel failure → LTS and fallback initramfs options
    STRATEGY-RISK-03  Update failure → feature branch isolation and rollback
    STRATEGY-RISK-04  Root corruption → sandbox and snapshot restoration
    STRATEGY-RISK-05  Boot failure → multiple entry combination recovery
    STRATEGY-RISK-06  Complete system failure → documented reinstall procedures
    STRATEGY-RISK-07  Lockout prevention through validation and testing
    STRATEGY-RISK-08  Live ISO recovery procedures and verification
  FUTURE ENHANCEMENT
    STRATEGY-FUTURE-01  Interactive decision framework (disk, size, unlock mode)
    STRATEGY-FUTURE-02  Secure Boot + UKI implementation path
    STRATEGY-FUTURE-03  Unified Kernel Images for measured boot
    STRATEGY-FUTURE-04  Custom key enrollment and signature management
    STRATEGY-FUTURE-05  Automated feature branch lifecycle management
    STRATEGY-FUTURE-06  Advanced Btrfs maintenance and monitoring
    STRATEGY-FUTURE-07  NVMe health monitoring and alerting
