# ARCH LINUX INSTALLATION GUIDE

## [A] PRE-INSTALLATION PHASE

### A01-A05: Initial Setup
- ISO verification ensures authenticity and prevents corrupted installations
- Keyboard/font configuration provides comfortable working environment
- These steps establish baseline trust and usability

### A06: Boot Mode Verification
- **STRATEGY-VALIDATION-01**: Hardware compatibility verification
- UEFI mode is required for modern boot features
- Script exits if BIOS mode detected, preventing incompatible installation
- UEFI enables Secure Boot, TPM2, and faster boot times

### A07-A09: Network and Time Setup
- Network connectivity essential for package downloads
- NTP synchronization prevents certificate and package signature errors
- Accurate time critical for encryption operations

### A10: Tool Availability Check
- Pre-flight verification prevents mid-installation failures
- Reflector ensures fastest mirrors for package downloads
- Screen allows session recovery if connection drops

### A11: TPM2 Detection
- **STRATEGY-ENCRYPTION-02**: TPM2 hardware detection and conditional enrollment
- **STRATEGY-RISK-01**: TPM2 failure → passphrase fallback strategy
- Early detection allows adaptive installation path
- Maintains compatibility with both TPM and non-TPM systems

### A12-A13: Planning and Tooling
- Size planning prevents insufficient space errors
- Installing encryption tools before use avoids dependency issues

## [B] DISK PREPARATION PHASE

### B00: Disk Confirmation
- **STRATEGY-RISK-07**: Lockout prevention through validation
- Shows current data before destruction
- Requires explicit "YES" confirmation
- Prevents accidental data loss on wrong disk

### B01-B04: Disk Validation
- **STRATEGY-STORAGE-01**: GPT partitioning with 1 MiB alignment
- Checks for mounted partitions to prevent corruption
- Verifies minimum 20GB size requirement
- 1 MiB alignment ensures compatibility with all sector sizes (512/4096)

### B05-B06: GPT Creation
- **STRATEGY-STORAGE-01**: GPT partitioning with 1 MiB alignment
- Wipes old signatures preventing boot conflicts
- Creates fresh GPT with proper alignment
- 2048 sector start = 1 MiB alignment for optimal SSD performance

### B07-B09: Partition Layout
- **STRATEGY-STORAGE-02**: Three-partition layout
- 1GB ESP sufficient for multiple kernels + initramfs
- Root gets bulk of space (disk size - 32GB - 20GB)
- 12GB swap supports hibernation for systems with 8-16GB RAM

### B10-B11: Over-provisioning and Backup
- **STRATEGY-STORAGE-03**: NVMe over-provisioning reservation
- **STRATEGY-STORAGE-04**: GPT backup creation
- 20GB unallocated improves SSD lifespan and performance
- GPT backup enables disaster recovery

### TEST01-TEST03: Storage Verification
- **STRATEGY-VALIDATION-02**: Storage verification
- Confirms 512-byte logical / 4096-byte physical sectors
- Validates all partitions aligned to 1 MiB boundaries
- Verifies partition sizes match specifications

## [C] ENCRYPTION PHASE

### C01: LUKS Container Creation
- **STRATEGY-ENCRYPTION-01**: LUKS2 with tuned PBKDF
- **STRATEGY-ENCRYPTION-06**: AES-XTS-Plain64 with 512-bit keys
- Root uses 1500ms iteration time for stronger security
- Swap uses 800ms for faster boot (less critical data)
- Argon2id resistant to GPU/ASIC attacks

### C02-C04: Passphrase Setup
- **STRATEGY-ENCRYPTION-03**: Passphrase reuse strategy
- Single passphrase for both volumes improves usability
- User enters passphrase twice during setup (once per volume)

### C05: Volume Opening
- Verifies encryption working before filesystem creation
- Creates /dev/mapper/ entries for next phase

### C06-C07: UUID Storage
- **STRATEGY-ENCRYPTION-05**: Crypttab.initramfs UUID-based generation
- UUIDs ensure boot configuration survives disk reordering
- Stored for later boot configuration

### TEST04-TEST06: Encryption Verification
- **STRATEGY-VALIDATION-03**: Encryption verification
- Confirms LUKS2 format and cipher specifications
- Validates key slots properly configured
- Checks PBKDF timing meets security requirements

## [D] FILESYSTEM PHASE

### D01: ESP Formatting
- FAT32 required by UEFI specification
- Label "ESP" for easy identification

### D02: Root Filesystem
- **STRATEGY-STORAGE-07**: zstd:3 compression
- Btrfs chosen for snapshot and subvolume features
- Metadata duplication (-m dup) for reliability

### D03: Swap Initialization
- **STRATEGY-ENCRYPTION-04**: Separate encrypted swap
- Encrypted swap protects sensitive data in memory dumps
- Label for easy identification

### D04: Subvolume Structure
- **STRATEGY-STORAGE-06**: Btrfs subvolume structure
- **STRATEGY-DEVELOPMENT-01**: Git-like branching model
- @main: primary root subvolume
- @main-home: user data isolation
- @var, @log, @cache: system data organization
- @tmp: temporary files isolation
- @shared: shared data between environments
- @user-local: custom software installations

### D05-D06: Mount Options
- **STRATEGY-STORAGE-07**: zstd:3 compression with noatime
- compress=zstd:3: balanced compression ratio vs speed
- noatime: reduces unnecessary writes, extends SSD life
- commit=120: less frequent commits, better performance
- discard=async: background TRIM for SSD optimization
- space_cache=v2: improved metadata performance
- autodefrag: prevents fragmentation on COW filesystem

### TEST07-TEST11: Filesystem Verification
- **STRATEGY-VALIDATION-02**: Storage verification
- **STRATEGY-STORAGE-05**: Multi-tool validation
- UUID consistency across layers
- Btrfs health and subvolume structure
- Mount options properly applied
- Partition math validates no space lost

## [E] SYSTEM INSTALLATION PHASE

### E01-E02: Mirror Optimization
- Fresh keyring prevents signature errors
- Reflector selects fastest mirrors
- HTTPS protocol for secure downloads
- US mirrors for geographic optimization

### E03-E08: Package Installation
- **STRATEGY-BOOT-02**: Quad-kernel strategy
- Base system + development tools
- Both standard and LTS kernels for reliability
- Intel microcode for CPU bug fixes
- TPM2 tools for secure unlock
- Graphics drivers for Intel iGPU
- Audio firmware for modern sound cards
- Plymouth for graphical boot
- uwsm for Wayland session management

### TEST22-TEST23: Package Verification
- **STRATEGY-VALIDATION-05**: Configuration verification
- Confirms critical packages installed
- Validates microcode properly deployed

## [F] MOUNT CONFIGURATION PHASE

### F01-F05: Fstab Generation
- genfstab creates UUID-based mount configuration
- Preserves all mount options from installation

### F06: Subvolid Check
- **STRATEGY-RISK-07**: Lockout prevention
- Subvolid entries break if subvolume recreated
- Script exits if dangerous entries detected

### TEST12: UUID Consistency
- **STRATEGY-VALIDATION-02**: Storage verification
- Ensures fstab and crypttab reference same UUIDs

## [G] SYSTEM CONFIGURATION PHASE

### G01-G06: Basic Configuration
- Timezone for correct timestamps
- Hardware clock synchronization
- UTF-8 locale for international support
- US keymap persistence
- Console font configuration

### G07-G09: Network Identity
- Hostname identifies system on network
- Hosts file for local name resolution
- NetworkManager for automatic connectivity

### TEST24: Configuration Verification
- **STRATEGY-VALIDATION-05**: Configuration verification
- Validates all system settings applied correctly

## [H] BOOT CONFIGURATION PHASE

### H01: Initramfs Hooks
- **STRATEGY-BOOT-06**: mkinitcpio systemd hooks
- **STRATEGY-ENCRYPTION-07**: PCR 0+7 TPM2 binding
- systemd hooks for modern init
- sd-encrypt for LUKS unlock
- resume for hibernation support
- TPM2 auto-enrollment if available

### H02: Initramfs Generation
- Builds initial ramdisk with all drivers
- Both standard and fallback images

### H03-H04: systemd-boot Setup
- **STRATEGY-BOOT-01**: systemd-boot replacing GRUB
- **STRATEGY-BOOT-03**: Multi-subvolume boot entries
- Simpler than GRUB, native UEFI
- Automatic boot entries for all combinations

### H05-H08: Boot Entries
- **STRATEGY-BOOT-02**: Quad-kernel strategy
- **STRATEGY-DEVELOPMENT-03**: @sandbox snapshot
- **STRATEGY-OPERATION-01**: Early swap unlock
- Main/sandbox × standard/LTS × normal/fallback
- Resume parameter for hibernation
- Intel microcode loaded first

### TEST13-TEST16: Boot Verification
- **STRATEGY-VALIDATION-04**: Boot verification
- **STRATEGY-BOOT-07**: UUID consistency validation
- systemd-boot properly installed
- All kernels and initramfs present
- Boot entries syntactically correct
- UUIDs consistent across configuration

### TEST25-TEST27: Advanced Boot Checks
- Hooks properly configured
- Kernel parameters complete
- Compression settings active

## [I] SECURITY CONFIGURATION PHASE

### I01: Root Password
- Essential for system recovery
- Should be strong and memorable

### I02-I05: Secure Boot Preparation
- **STRATEGY-FUTURE-02**: Secure Boot path
- Infrastructure for future UKI implementation
- Currently prepared but not enforced

### I06: TPM2 Enrollment
- **STRATEGY-ENCRYPTION-02**: TPM2 conditional enrollment
- **STRATEGY-ENCRYPTION-07**: PCR 0+7 binding
- PCR0: firmware measurements
- PCR7: Secure Boot state
- Automatic unlock if system unmodified

### TEST17: TPM2 Verification
- **STRATEGY-VALIDATION-06**: Security verification
- Confirms TPM2 token in LUKS header
- Validates enrollment successful

## [J] SYSTEM OPTIMIZATION PHASE

### J01-J03: Performance Tuning
- **STRATEGY-OPERATION-02**: System tuning
- vm.swappiness=10: prefer RAM over swap
- fstrim.timer: weekly SSD optimization
- timesyncd: accurate time keeping

### J04-J06: Hardware Optimization
- TLP for laptop power management
- Intel PSR disabled (causes issues)
- Performance mount options active

### J07: User Creation
- **STRATEGY-OPERATION-07**: User account with sudo
- Non-root user for daily operations
- wheel group for administrative access

### J08-J10: Snapshot Management
- **STRATEGY-OPERATION-06**: Snapper for root/home/var
- **STRATEGY-DEVELOPMENT-01**: Git-like branching
- Automatic snapshot on package changes
- Baseline snapshots for recovery

### J11: Sandbox Creation
- **STRATEGY-DEVELOPMENT-02**: @main stable environment
- **STRATEGY-DEVELOPMENT-03**: @sandbox experimentation
- Snapshot of @main for safe testing
- Separate home to isolate changes

### J12-J14: Autologin Setup
- **STRATEGY-OPERATION-05**: uwsm + autologin
- getty override for automatic login
- .bash_profile starts Wayland session
- Seamless boot to desktop

### TEST28-TEST33: System Verification
- **STRATEGY-VALIDATION-05**: Configuration verification
- **STRATEGY-VALIDATION-08**: 39-point testing framework
- All optimizations active
- Services properly enabled
- User account functional
- Snapshots operational
- Autologin configured

## [K] PRE-REBOOT VERIFICATION PHASE

### K01-K06: Final Checks
- **STRATEGY-VALIDATION-08**: Comprehensive testing
- **STRATEGY-RISK-07**: Lockout prevention
- UUID consistency across all configs
- Bootloader entries valid
- ESP has sufficient space
- All filesystems mounted
- Critical services enabled

### TEST18-TEST19: Security and State
- **STRATEGY-VALIDATION-06**: Security verification
- File permissions correct
- System state comprehensive summary

### TEST34-TEST39: Recovery Readiness
- **STRATEGY-VALIDATION-07**: Recovery verification
- **STRATEGY-STORAGE-04**: GPT backup available
- **STRATEGY-STORAGE-03**: Over-provisioning confirmed
- **STRATEGY-FUTURE-02**: Secure Boot readiness
- Graphics, network, audio subsystems verified
- All hardware properly detected

## [L] REBOOT PHASE

### L01-L04: Clean Shutdown
- **STRATEGY-RISK-08**: Live ISO recovery procedures
- Sync ensures all data written
- Unmount prevents corruption
- LUKS volumes properly closed
- Graceful system restart

## [M] POST-INSTALLATION PHASE

### M01-M06: First Boot Validation
- **STRATEGY-OPERATION-01**: Hibernation support
- Suspend/resume functionality
- Network connectivity
- Service health checks

### M07-M10: System Completion
- GUI installation for desktop
- Mirror updates for speed
- Full system upgrade

## [N] MAINTENANCE & RECOVERY PHASE

### N01-N08: Ongoing Procedures
- **STRATEGY-RISK-04**: Snapshot restoration
- **STRATEGY-RISK-05**: Multiple recovery options
- **STRATEGY-FUTURE-06**: Btrfs maintenance
- GPT restore from backup
- Bootloader recovery procedures
- UUID mismatch resolution
- Kernel update management
- Btrfs scrub and balance
- SSD health monitoring
- Backup strategy implementation
- Performance monitoring

## KEY INSIGHTS

**Why This Approach Works:**
- Multiple validation points prevent silent failures
- Redundant recovery mechanisms ensure system resilience
- Development workflow mimics familiar Git patterns
- Hardware features (TPM2) used when available, not required
- Performance optimizations balanced with reliability
- Security implemented in layers, not single points
- User experience prioritized without sacrificing control

**Critical Success Factors:**
- 39 test points catch issues before they become problems
- UUID-based configuration survives hardware changes
- Subvolume structure enables atomic system changes
- Multiple kernel/boot options prevent complete failure
- Comprehensive backup points enable recovery
- Clear separation between stable and experimental environments
