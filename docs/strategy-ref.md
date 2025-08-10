**Arch Linux Installation Strategy - Atomic Component IDs**

---

**STORAGE LAYER**
- **STRATEGY-STORAGE-01**: GPT partitioning with 1 MiB alignment for sector compatibility
- **STRATEGY-STORAGE-02**: Three-partition layout (1G ESP, encrypted root, 12G encrypted swap)
- **STRATEGY-STORAGE-03**: NVMe over-provisioning reservation (~20GB unallocated)
- **STRATEGY-STORAGE-04**: GPT backup creation and restoration procedures
- **STRATEGY-STORAGE-05**: Multi-tool partition size validation and byte accounting
- **STRATEGY-STORAGE-06**: Btrfs subvolume structure (@main, @main-home, @var, @log, @cache, @tmp, @shared, @user-local)
- **STRATEGY-STORAGE-07**: zstd:3 compression with noatime mount optimization

**ENCRYPTION LAYER**
- **STRATEGY-ENCRYPTION-01**: LUKS2 container creation with tuned PBKDF (1500ms root, 800ms swap)
- **STRATEGY-ENCRYPTION-02**: TPM2 hardware detection and conditional enrollment
- **STRATEGY-ENCRYPTION-03**: Passphrase reuse strategy (single prompt, dual unlock)
- **STRATEGY-ENCRYPTION-04**: Separate encrypted swap container for hibernation
- **STRATEGY-ENCRYPTION-05**: Crypttab.initramfs UUID-based generation
- **STRATEGY-ENCRYPTION-06**: AES-XTS-Plain64 cipher with 512-bit keys and SHA256
- **STRATEGY-ENCRYPTION-07**: PCR 0+7 TPM2 binding for Secure Boot integration

**BOOT LAYER**
- **STRATEGY-BOOT-01**: systemd-boot installation replacing GRUB
- **STRATEGY-BOOT-02**: Quad-kernel strategy (linux + linux-lts, normal + fallback)
- **STRATEGY-BOOT-03**: Multi-subvolume boot entry generation
- **STRATEGY-BOOT-04**: Intel microcode integration with dedicated initrd
- **STRATEGY-BOOT-05**: Hibernation resume parameter configuration
- **STRATEGY-BOOT-06**: mkinitcpio systemd hooks (sd-encrypt, resume, filesystems)
- **STRATEGY-BOOT-07**: Boot entry UUID consistency validation

**DEVELOPMENT WORKFLOW**
- **STRATEGY-DEVELOPMENT-01**: Git-like branching model using Btrfs snapshots
- **STRATEGY-DEVELOPMENT-02**: @main stable production environment maintenance
- **STRATEGY-DEVELOPMENT-03**: @sandbox static snapshot for safe experimentation
- **STRATEGY-DEVELOPMENT-04**: @feat-* feature branch creation and management
- **STRATEGY-DEVELOPMENT-05**: Change isolation and testing methodology
- **STRATEGY-DEVELOPMENT-06**: Feature branch boot entry auto-generation
- **STRATEGY-DEVELOPMENT-07**: Rollback and promotion procedures
- **STRATEGY-DEVELOPMENT-08**: Failed experiment cleanup and disposal

**SYSTEM OPERATION**
- **STRATEGY-OPERATION-01**: Early swap unlock for hibernation support
- **STRATEGY-OPERATION-02**: System tuning (swappiness=10, fstrim.timer)
- **STRATEGY-OPERATION-03**: NetworkManager and Bluetooth service enablement
- **STRATEGY-OPERATION-04**: Plymouth graphical unlock integration
- **STRATEGY-OPERATION-05**: uwsm + autologin seamless desktop transition
- **STRATEGY-OPERATION-06**: Snapper snapshot management for root/home/var
- **STRATEGY-OPERATION-07**: User account creation with sudo privileges
- **STRATEGY-OPERATION-08**: Service configuration and enablement verification

**VALIDATION FRAMEWORK**
- **STRATEGY-VALIDATION-01**: Hardware compatibility verification (CPU, memory, NVMe)
- **STRATEGY-VALIDATION-02**: Storage verification (alignment, sizes, UUIDs)
- **STRATEGY-VALIDATION-03**: Encryption verification (LUKS headers, key slots, PBKDF)
- **STRATEGY-VALIDATION-04**: Boot verification (systemd-boot, entries, parameters)
- **STRATEGY-VALIDATION-05**: Configuration verification (fstab, crypttab, services)
- **STRATEGY-VALIDATION-06**: Security verification (permissions, Secure Boot readiness)
- **STRATEGY-VALIDATION-07**: Recovery verification (backups, over-provisioning)
- **STRATEGY-VALIDATION-08**: 39-point comprehensive testing framework
- **STRATEGY-VALIDATION-09**: Multi-tool redundant validation methodology

**RISK MITIGATION**
- **STRATEGY-RISK-01**: TPM2 failure → passphrase fallback strategy
- **STRATEGY-RISK-02**: Kernel failure → LTS and fallback initramfs options
- **STRATEGY-RISK-03**: Update failure → feature branch isolation and rollback
- **STRATEGY-RISK-04**: Root corruption → sandbox and snapshot restoration
- **STRATEGY-RISK-05**: Boot failure → multiple entry combination recovery
- **STRATEGY-RISK-06**: Complete system failure → documented reinstall procedures
- **STRATEGY-RISK-07**: Lockout prevention through validation and testing
- **STRATEGY-RISK-08**: Live ISO recovery procedures and verification

**FUTURE ENHANCEMENT**
- **STRATEGY-FUTURE-01**: Interactive decision framework (disk, size, unlock mode)
- **STRATEGY-FUTURE-02**: Secure Boot + UKI implementation path
- **STRATEGY-FUTURE-03**: Unified Kernel Images for measured boot
- **STRATEGY-FUTURE-04**: Custom key enrollment and signature management
- **STRATEGY-FUTURE-05**: Automated feature branch lifecycle management
- **STRATEGY-FUTURE-06**: Advanced Btrfs maintenance and monitoring
- **STRATEGY-FUTURE-07**: NVMe health monitoring and alerting

---

**Component Dependencies**
- **Storage Foundation**: STRATEGY-STORAGE-01→STRATEGY-STORAGE-02→STRATEGY-STORAGE-03→STRATEGY-STORAGE-04→STRATEGY-STORAGE-05
- **Encryption Chain**: STRATEGY-ENCRYPTION-01→STRATEGY-ENCRYPTION-02→STRATEGY-ENCRYPTION-03→STRATEGY-ENCRYPTION-04→STRATEGY-ENCRYPTION-05
- **Boot Stack**: STRATEGY-BOOT-01→STRATEGY-BOOT-02→STRATEGY-BOOT-03→STRATEGY-BOOT-04→STRATEGY-BOOT-05→STRATEGY-BOOT-06
- **Development Flow**: STRATEGY-DEVELOPMENT-01→STRATEGY-DEVELOPMENT-02→STRATEGY-DEVELOPMENT-03→STRATEGY-DEVELOPMENT-04→STRATEGY-DEVELOPMENT-05
- **Validation Pipeline**: STRATEGY-VALIDATION-01→STRATEGY-VALIDATION-02→STRATEGY-VALIDATION-03→STRATEGY-VALIDATION-04→STRATEGY-VALIDATION-05→STRATEGY-VALIDATION-06→STRATEGY-VALIDATION-07→STRATEGY-VALIDATION-08

**Critical Path**: STRATEGY-STORAGE-01→STRATEGY-STORAGE-02→STRATEGY-ENCRYPTION-01→STRATEGY-ENCRYPTION-03→STRATEGY-BOOT-01→STRATEGY-BOOT-02→STRATEGY-DEVELOPMENT-01→STRATEGY-VALIDATION-08→STRATEGY-RISK-07

This atomic breakdown enables precise tracking, testing, and modification of individual strategy components while maintaining clear dependency relationships and hierarchical organization.
