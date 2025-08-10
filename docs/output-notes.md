# BIOS Configuration and Security Check

## BIOS Settings
- TPM 2.0 Enabled
- Verified SMBIOS Enabled  
- Cleared Security Chip
- Cleared Factory Keys for Secure Boot
- Verified Secure Boot is Disabled (per Arch Install guide)

## TPM Detection and System Logs

### Command: TPM Detection via dmesg
**Command:**
```bash
dmesg | grep -i tpm
```

**Output:**
```
[    0.900563] tpm_tis NTC0702:00: 2.0 TPM (device-id 0xFC, rev-id 1)
[   85.467421] systemd[1]: systemd 257.7-1-arch running in system mode (+PAM +AUDIT -SELINUX -APPARMOR -IMA +IPE +SMACK +SECCOMP +GCRYPT +GNUTLS +OPENSSL +ACL +BLKID +CURL +ELFUTILS +FIDO2 +IDN2 -IDN +IPTC +KMOD +LIBCRYPTSETUP +LIBCRYPTSETUP_PLUGINS +LIBFDISK +PCRE2 +PWQUALITY +P11KIT +QRENCODE +TPM2 +BZIP2 +LZ4 +XZ +ZLIB +ZSTD +BPF_FRAMEWORK +BTF +XKBCOMMON +UTMP -SYSVINIT +LIBARCHIVE)
[   87.167238] systemd[1]: TPM PCR Measurements was skipped because of an unmet condition check (ConditionSecurity=measured-uki).
[   87.167255] systemd[1]: Make TPM PCR Policy was skipped because of an unmet condition check (ConditionSecurity=measured-uki).
[   87.382714] systemd[1]: TPM PCR Machine ID Measurement was skipped because of an unmet condition check (ConditionSecurity=measured-uki).
[   87.397082] systemd[1]: Early TPM SRK Setup was skipped because of an unmet condition check (ConditionSecurity=measured-uki).
[   87.624784] systemd[1]: TPM SRK Setup was skipped because of an unmet condition check (ConditionSecurity=measured-uki).
```

> **Note:** TPM 2.0 detected, but UKI (Unified Kernel Image) security measurements are not configured.

## Security Boot Status Check

### Command: Check Secure Boot State
**Command:**
```bash
mokutil --sb-state
```

**Output:**
```
SecureBoot disabled
```

> **Note:** Requires `pacman -Sy mokutil` package

### Command: Read EFI Variables
**Command:**
```bash
efi-readvar
```

**Output:**
```
Variable PK, length 1085
PK: List 0, type X509
    Signature 0, size 1057, owner 3cc24e96-22c7-41d8-8863-8e39dcdcc2cf
        Subject:
            C=CN, ST=Beijing, L=Beijing, O=Lenovo(Beijing) Ltd., OU=PSD_CDC, CN=PSD_CDC-KEK, emailAddress=SWQAGENT@LENOVO.COM
        Issuer:
            C=CN, ST=Beijing, L=Beijing, O=Lenovo(Beijing) Ltd., OU=PSD_CDC, CN=PSD_CDC-KEK, emailAddress=SWQAGENT@LENOVO.COM

Variable KEK, length 2648
KEK: List 0, type X509
    Signature 0, size 1060, owner 7facc7b6-127f-4e9c-9c5d-080f98994345
        Subject:
            C=CN, ST=BeiJing, L=BeiJing, O=Lenovo(BeiJing) Ltd., OU=PSD_CDC, CN=PSD_CDC-KEK, emailAddress=SWQAGENT@LENOVO.COM
        Issuer:
            C=CN, ST=Beijing, L=Beijing, O=Lenovo(Beijing) Ltd., OU=PSD_CDC, CN=PSD_CDC-KEK, emailAddress=SWQAGENT@LENOVO.COM
KEK: List 1, type X509
    Signature 0, size 1532, owner 77fa9abd-0359-4d32-bd60-28f4e78f784b
        Subject:
            C=US, ST=Washington, L=Redmond, O=Microsoft Corporation, CN=Microsoft Corporation KEK CA 2011
        Issuer:
            C=US, ST=Washington, L=Redmond, O=Microsoft Corporation, CN=Microsoft Corporation Third Party Marketplace Root

Variable db, length 6167
db: List 0, type X509
    Signature 0, size 962, owner 7facc7b6-127f-4e9c-9c5d-080f98994345
        Subject:
            C=JP, ST=Kanagawa, L=Yokohama, O=Lenovo Ltd., CN=ThinkPad Product CA 2012
        Issuer:
            C=JP, ST=Kanagawa, L=Yokohama, O=Lenovo Ltd., CN=Lenovo Ltd. Root CA 2012
db: List 1, type X509
    Signature 0, size 919, owner 7facc7b6-127f-4e9c-9c5d-080f98994345
        Subject:
            C=US, ST=North Carolina, O=Lenovo, CN=Lenovo UEFI CA 2014
        Issuer:
            C=US, ST=North Carolina, O=Lenovo, CN=Lenovo UEFI CA 2014
db: List 2, type X509
    Signature 0, size 1059, owner 7facc7b6-127f-4e9c-9c5d-080f98994345
        Subject:
            C=CN, ST=BeiJing, L=BeiJing, O=Lenovo(BeiJing) Ltd., OU=PSD_CDC, CN=PSD_CDC-DB, emailAddress=SWQAGENT@LENOVO.COM
        Issuer:
            C=CN, ST=Beijing, L=Beijing, O=Lenovo(Beijing) Ltd., OU=PSD_CDC, CN=PSD_CDC-KEK, emailAddress=SWQAGENT@LENOVO.COM
db: List 3, type X509
    Signature 0, size 1572, owner 77fa9abd-0359-4d32-bd60-28f4e78f784b
        Subject:
            C=US, ST=Washington, L=Redmond, O=Microsoft Corporation, CN=Microsoft Corporation UEFI CA 2011
        Issuer:
            C=US, ST=Washington, L=Redmond, O=Microsoft Corporation, CN=Microsoft Corporation Third Party Marketplace Root
db: List 4, type X509
    Signature 0, size 1515, owner 77fa9abd-0359-4d32-bd60-28f4e78f784b
        Subject:
            C=US, ST=Washington, L=Redmond, O=Microsoft Corporation, CN=Microsoft Windows Production PCA 2011
        Issuer:
            C=US, ST=Washington, L=Redmond, O=Microsoft Corporation, CN=Microsoft Root Certificate Authority 2010

Variable dbx, length 3724
dbx: List 0, type SHA256
    Signature 0, size 48, owner 77fa9abd-0359-4d32-bd60-28f4e78f784b
        Hash:80b4d96931bf0d02fd91a61e19d14f1da452e66db2408ca8604d411f92659f0a
    ...

Variable MokList has no entries
```

### Command: <>
**Command:**
```bash
systemd-cryptenroll --tpm2-device=list
```

**Output:**
```bash
PATH        DEVICE     DRIVER
/dev/tpmrm0 NTC0702:00 tpm_tis
```

### Command: <>
**Command:**
```bash
tpm2_getcap properties-fixed 
```

**Output:**
```bash
tpm2_getcap properties-fixed
TPM2_PT_FAMILY_INDICATOR:
  raw: 0x322E3000
  value: "2.0"
TPM2_PT_LEVEL:
  raw: 0
TPM2_PT_REVISION:
  raw: 0x8A
  value: 1.38
TPM2_PT_DAY_OF_YEAR:
  raw: 0x8
TPM2_PT_YEAR:
  raw: 0x7E2
TPM2_PT_MANUFACTURER:
  raw: 0x4E544300
  value: "NTC"
TPM2_PT_VENDOR_STRING_1:
  raw: 0x4E504354
  value: "NPCT"
TPM2_PT_VENDOR_STRING_2:
  raw: 0x37357800
  value: "75x"
TPM2_PT_VENDOR_STRING_3:
  raw: 0x2010024
  value: ""
TPM2_PT_VENDOR_STRING_4:
  raw: 0x726C7300
  value: "rls"
TPM2_PT_VENDOR_TPM_TYPE:
  raw: 0x0
TPM2_PT_FIRMWARE_VERSION_1:
  raw: 0x70002
TPM2_PT_FIRMWARE_VERSION_2:
  raw: 0x10000
TPM2_PT_INPUT_BUFFER:
  raw: 0x400
TPM2_PT_HR_TRANSIENT_MIN:
  raw: 0x5
TPM2_PT_HR_PERSISTENT_MIN:
  raw: 0x5
TPM2_PT_HR_LOADED_MIN:
  raw: 0x5
TPM2_PT_ACTIVE_SESSIONS_MAX:
  raw: 0x40
TPM2_PT_PCR_COUNT:
  raw: 0x18
TPM2_PT_PCR_SELECT_MIN:
  raw: 0x3
TPM2_PT_CONTEXT_GAP_MAX:
  raw: 0xFF
TPM2_PT_NV_COUNTERS_MAX:
  raw: 0x0
TPM2_PT_NV_INDEX_MAX:
  raw: 0x800
TPM2_PT_MEMORY:
  raw: 0x6
TPM2_PT_CLOCK_UPDATE:
  raw: 0x400000
TPM2_PT_CONTEXT_HASH:
  raw: 0xC
TPM2_PT_CONTEXT_SYM:
  raw: 0x6
TPM2_PT_CONTEXT_SYM_SIZE:
  raw: 0x100
TPM2_PT_ORDERLY_COUNT:
  raw: 0xFF
TPM2_PT_MAX_COMMAND_SIZE:
  raw: 0x800
TPM2_PT_MAX_RESPONSE_SIZE:
  raw: 0x800
TPM2_PT_MAX_DIGEST:
  raw: 0x30
TPM2_PT_MAX_OBJECT_CONTEXT:
  raw: 0x714
TPM2_PT_MAX_SESSION_CONTEXT:
  raw: 0x148
TPM2_PT_PS_FAMILY_INDICATOR:
  raw: 0x1
TPM2_PT_PS_LEVEL:
  raw: 0x0
TPM2_PT_PS_REVISION:
  raw: 0x103
TPM2_PT_PS_DAY_OF_YEAR:
  raw: 0x0
TPM2_PT_PS_YEAR:
  raw: 0x0
TPM2_PT_SPLIT_MAX:
  raw: 0x80
TPM2_PT_TOTAL_COMMANDS:
  raw: 0x71
TPM2_PT_LIBRARY_COMMANDS:
  raw: 0x68
TPM2_PT_VENDOR_COMMANDS:
  raw: 0x9
TPM2_PT_NV_BUFFER_MAX:
  raw: 0x400
TPM2_PT_MODES:
  raw: 0x1
  value: TPMA_MODES_FIPS_140_2
```

### Command: <>
**Command:**
```bash
dmesg | grep -i tpm
```

**Output:**
```bash
```
