#!/usr/bin/env bash
# Arch Linux bootstrap (NVMe|SATA + LUKS2 + Btrfs + systemd-boot)
# Hardened + 11e Gen6 + atomic step IDs + logging alignment

# ===== [0] CORE RUNTIME / ENV =====
set -Eeuo pipefail
set -o errtrace
shopt -s lastpipe
umask 022
export LC_ALL=C LANG=C LC_NUMERIC=C
export PATH=/usr/sbin:/usr/bin:/sbin:/bin

# --- [0A-LOGGING] Streams & structured events ---
# .0A01-LOG-OPEN: open human log + xtrace (DEBUG) + NDJSON
LOG="/var/log/arch-bootstrap.$(date +%F-%H%M%S).log"
install -d -m 0755 "$(dirname "$LOG")"
RUN_JSON="$LOG.ndjson"
exec > >(stdbuf -oL awk '{ printf("[%s] %s\n", strftime("%F %T"), $0) }' | tee -a "$LOG") 2>&1
if [[ ${DEBUG:-0} == 1 ]]; then
  exec 5>>"$LOG.xtrace"
  export BASH_XTRACEFD=5
  export PS4='+ $(date "+%F %T") ${BASH_SOURCE}:${LINENO}:${FUNCNAME[0]}: '
  set -x
fi

# --- [0B-HELPERS] Flow, errors, tools, readiness, locking, data, wrappers ---
# .0B01-HELPERS-LOGFMT: event/timestamp helpers
_ts() { date -u +%FT%TZ; }
_log_event() { local lvl="$1"; shift; printf '{"ts":"%s","level":"%s","msg":%s}\n' "$(_ts)" "$lvl" "$(printf '%s' "$*" | python - <<'PY'
import json,sys
print(json.dumps(sys.stdin.read()))
PY
)" >>"$RUN_JSON" 2>/dev/null || true; }

fatal() { local rc=${1:-1}; shift || true; _log_event "fatal" "$* (rc=$rc)"; printf '[FATAL] (%s) %s\n' "$rc" "$*" >&2; exit "$rc"; }
warn()  { _log_event "warn"  "$*"; printf '[WARN] %s\n' "$*" >&2; }
note()  { _log_event "info"  "$*"; printf '[INFO] %s\n' "$*"; }

# .0B02-HELPERS-FLOW: must/check/retry
must()  { note ".0B02-HELPERS-FLOW: run: $*"; "$@"; local rc=$?; ((rc==0)) || fatal "$rc" ".0B02-HELPERS-FLOW: cmd failed: $*"; }
must_pipe() { note ".0B02-HELPERS-FLOW: pipeline: $*"; set -o pipefail; bash -c "$*"; local rc=$?; set +o pipefail; ((rc==0)) || fatal "$rc" ".0B02-HELPERS-FLOW: pipeline failed: $*"; }
check() { set +e; "$@"; local rc=$?; set -e; return "$rc"; }
retry_rc() { local -i n=$1 d=$2 i rc; shift 2; for ((i=1;i<=n;i++)); do note ".0B02-HELPERS-FLOW: try($i/$n): $*"; "$@"; rc=$?; ((rc==0)) && return 0; ((i<n)) && sleep "$d"; done; return "$rc"; }

# .0B03-HELPERS-MISC: system helpers
require(){ for c in "$@"; do command -v "$c" >/dev/null || fatal 127 ".0B03-HELPERS-MISC: missing: $c"; done; }
wait_udev(){ udevadm settle || true; }
part_rescan(){ partprobe "$1" 2>/dev/null || true; blockdev --rereadpt "$1" 2>/dev/null || true; }
partsuf(){ [[ $1 =~ (nvme|mmcblk) ]] && printf 'p' || printf ''; }
_errtrap(){ local rc=$?; _log_event "error" "ERR rc=$rc at ${BASH_SOURCE[1]}:${BASH_LINENO[0]} while: ${BASH_COMMAND}"; printf '[ERR] rc=%s at %s:%s while: %s\n' "$rc" "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}" "${BASH_COMMAND}" >&2; }
trap _errtrap ERR

# .0B04-HELPERS-DATA: plumbing helpers
join_by() { local IFS="$1"; shift; echo "$*"; }
read0() { local __var="$1"; shift; mapfile -d '' -t "$__var"; }
count_files() { local dir="$1" pat="$2"; local -a _tmp=(); while IFS= read -r -d '' f; do _tmp+=("$f"); done < <(find "$dir" -maxdepth 1 -type f -name "$pat" -print0 2>/dev/null); echo "${#_tmp[@]}"; }

# .0B05-HELPERS-WRAPPERS: defensive tool wrappers
http_get() { # .0B05-HELPERS-WRAPPERS: http_get
  local url="$1" out="${2:-}"
  if command -v curl >/dev/null; then
    local args=(--fail-with-body --location --retry 5 --retry-delay 2 --retry-connrefused --max-time 60 --silent --show-error)
    [[ -n $out ]] && curl "${args[@]}" --output "$out" -- "$url" || curl "${args[@]}" -- "$url"
  elif command -v wget >/dev/null; then
    local args=(--retry-connrefused --tries=10 --waitretry=2 --timeout=30 --quiet)
    [[ -n $out ]] && wget "${args[@]}" -O "$out" -- "$url" || wget "${args[@]}" -O - -- "$url"
  else fatal 127 ".0B05-HELPERS-WRAPPERS: neither curl nor wget"; fi
}
rsync_safe() { local src="$1" dst="$2"; shift 2; rsync -a --partial --inplace --checksum --delete-delay --mkpath --info=stats2 "$src" "$dst" "$@"; }
tar_repro() { local out="$1" dir="$2"; tar --numeric-owner --owner=0 --group=0 --mtime=@0 --sort=name -cf "$out" -C "$dir" .; }

# .0B06-HELPERS-READY: readiness checks
wait_for_dev(){ local dev="$1" t="${2:-30}" d=$((SECONDS+t)); while [[ ! -e "$dev" ]]; do ((SECONDS<d))||return 1; udevadm settle||true; sleep 1; done; }
assert_mount(){ local mp="$1" src="$2" sub="${3:-}"; findmnt -no SOURCE,TARGET,OPTIONS --target "$mp" | awk -v s="$src" -v sv="$sub" 'BEGIN{ok=0}{if($1==s&&$2=="'"$mp"'"){if(sv=="")ok=1;else if(index($3,"subvol="sv))ok=1}}END{exit ok?0:1}'; }
net_ready(){ local host="${1:-archlinux.org}" t="${2:-20}" d=$((SECONDS+t)); while ! getent hosts "$host" >/dev/null 2>&1; do ((SECONDS<d))||return 1; sleep 1; done; }
bootfiles_ready(){ [[ -f "$1/EFI/systemd/systemd-bootx64.efi" && -f "$1/loader/loader.conf" ]]; }
snapper_ready(){ [[ -f "$1/etc/snapper/configs/root" && -d "$1/.snapshots" ]]; }

# .0B07-HELPERS-LOCKS: concurrency & pacman lock
LOCK_DIR=/run/lock/arch-bootstrap
install -d -m 0755 "$LOCK_DIR"
with_lock() { local name="$1" timeout="${2:-60}"; shift 2; local path="$LOCK_DIR/${name//\//_}.lock"; exec {__lfd__}> "$path" || fatal 98 ".0B07-HELPERS-LOCKS: cannot open lock: $path"; if ! flock -x -w "$timeout" "$__lfd__"; then fatal 99 ".0B07-HELPERS-LOCKS: lock timeout: $name"; fi; "$@"; local rc=$?; flock -u "$__lfd__"; eval "exec $__lfd__>&-"; return "$rc"; }
mount_locked()  { local target="${@: -1}"; with_lock "mnt:$target" 120 mount "$@"; }
umount_locked() { local mp="$1";            with_lock "mnt:$mp"    120 umount -R -- "$mp"; }
wait_pacman_lock() { local deadline=$((SECONDS+600)); while [[ -e /var/lib/pacman/db.lck ]]; do (( SECONDS < deadline )) || fatal 97 ".0B07-HELPERS-LOCKS: pacman lock held too long"; sleep 2; done; }

# .0B08-CLEANUP: tmpdir + global single-instance
tmpdir="$(mktemp -d)"
cleanup(){ set +e; sync; umount -R /mnt/stage 2>/dev/null || true; rm -rf "$tmpdir"; }
trap cleanup EXIT INT TERM

# .0B09-LOCK-GLOBAL: ensure single instance
exec 9>"/var/lock/arch-bootstrap.lock"
flock -n 9 || fatal 99 ".0B09-LOCK-GLOBAL: another instance is running"

note ".0B10-START: arch-bootstrap start"

# ===== [A] PRE-INSTALLATION =====
# .A01-UEFI-VERIFY: UEFI boot mode required
[[ -d /sys/firmware/efi/efivars ]] && note ".A01-UEFI-VERIFY: UEFI mode confirmed" || fatal 1 ".A01-UEFI-VERIFY: BIOS/CSM detected"

# .A02-REQS-CHECK: required tools present
require ping curl pacman sgdisk cryptsetup lsblk wipefs awk sed grep blkid rsync tar

# .A03-NET-TEST: basic connectivity
if ! retry_rc 5 2 timeout 5s ping -c1 archlinux.org >/dev/null; then
  rc=$?; ((rc==124)) && fatal 124 ".A03-NET-TEST: ping timed out"; fatal "$rc" ".A03-NET-TEST: ping failed (rc=$rc)"
fi
note ".A03-NET-TEST: Internet OK"

# .A04-TIME-NTP: enable NTP (best-effort)
check timedatectl set-ntp true || warn ".A04-TIME-NTP: set-ntp failed"
check timedatectl status || warn ".A04-TIME-NTP: status failed"

# .A05-PKGMGR-SETUP: pacman tooling & reflector
if ! retry_rc 5 3 pacman -Sy --noconfirm --needed sgdisk cryptsetup btrfs-progs dosfstools util-linux gptfdisk reflector git; then
  fatal $? ".A05-PKGMGR-SETUP: pacman prep failed after retries"
fi
check pacman-key --init || warn ".A05-PKGMGR-SETUP: pacman-key --init failed"
check pacman-key --populate archlinux || warn ".A05-PKGMGR-SETUP: pacman-key --populate failed"

# .A06-TPM-DETECT: detect TPM2 availability
if [[ -d /sys/class/tpm && -c /dev/tpm0 ]]; then TPM2_AVAILABLE=true; note ".A06-TPM-DETECT: TPM2 detected"; else TPM2_AVAILABLE=false; note ".A06-TPM-DETECT: no TPM2"; fi

# .A07-DISK-AUTOPICK: choose target disk if not set
if [[ -z "${TARGET_DISK:-}" ]]; then
  TARGET_DISK="$(lsblk -dnpo NAME,TYPE,RM,SIZE | awk '$2=="disk" && $3==0 {print $1, $4}' | sort -hk2 | tail -1 | awk '{print $1}')"
  [[ -n "$TARGET_DISK" ]] || fatal 2 ".A07-DISK-AUTOPICK: auto-detect failed"
fi
PSUF="$(partsuf "$TARGET_DISK")"
note ".A07-DISK-AUTOPICK: TARGET_DISK=$TARGET_DISK"

# .A08-DISK-SANITY: basic device sanity & capacity
[[ -b $TARGET_DISK ]] || fatal 2 ".A08-DISK-SANITY: not a block device: $TARGET_DISK"
lsblk -ndo TYPE "$TARGET_DISK" | grep -qx disk || fatal 2 ".A08-DISK-SANITY: not TYPE=disk"
lsblk -ndo NAME "$TARGET_DISK" | grep -q '^loop' && fatal 2 ".A08-DISK-SANITY: refusing loop device"
: "${ESP_GIB:=1}" "${SWAP_GIB:=10}" "${OP_GIB:=20}"
DISK_SIZE_G=$(( $(blockdev --getsize64 "$TARGET_DISK") / 1024 / 1024 / 1024 ))
NEEDED=$(( ESP_GIB + SWAP_GIB + OP_GIB + 2 ))
(( DISK_SIZE_G > NEEDED )) || fatal 2 ".A08-DISK-SANITY: ${DISK_SIZE_G}GiB < ${NEEDED}GiB"

# ===== [B] DISK PREPARATION =====
# .B01-DISK-PROMPT: show/warn/confirm destructive action
disk_prep_prompt() {
  lsblk -o NAME,SIZE,TYPE,MOUNTPOINT "$TARGET_DISK" || true
  note ".B01-DISK-PROMPT: Will destroy ALL data on $TARGET_DISK"
  check sgdisk --print "$TARGET_DISK" || note ".B01-DISK-PROMPT: no existing GPT found"
  if (( ${AUTO_CONFIRM:-0} != 1 )); then
    IFS= read -r -p ".B01-DISK-PROMPT: type device name ($(basename "$TARGET_DISK")) to continue: " confirm
    [[ $confirm == "$(basename "$TARGET_DISK")" ]] || fatal 1 ".B01-DISK-PROMPT: aborted"
  fi
}
# .B02-DISK-UNMOUNT: ensure nothing mounted; swap off
disk_umount_safety() {
  if lsblk -nrpo MOUNTPOINT "$TARGET_DISK" | grep -q .; then fatal 1 ".B02-DISK-UNMOUNT: some partitions are mounted"; fi
  check swapoff -a || warn ".B02-DISK-UNMOUNT: swapoff returned nonzero"
}
# .B03-GPT-WIPE: wipe and create aligned GPT
disk_create_gpt() {
  must wipefs -a "$TARGET_DISK"
  must sgdisk -Z "$TARGET_DISK"
  must sgdisk -a 2048 -o "$TARGET_DISK"
  wait_udev
}
# .B04-GPT-PARTS: create partitions ESP/cryptroot/cryptswap
disk_make_parts() {
  must sgdisk -n 1:2048:+${ESP_GIB}G -t 1:EF00 -c 1:"ESP" "$TARGET_DISK"
  local END_FOR_P2=$((SWAP_GIB+OP_GIB))
  must sgdisk -n 2:0:-${END_FOR_P2}G -t 2:8309 -c 2:"cryptroot" "$TARGET_DISK"
  must sgdisk -n 3:0:-${OP_GIB}G -t 3:8309 -c 3:"cryptswap" "$TARGET_DISK"
  must sgdisk -p "$TARGET_DISK"
  part_rescan "$TARGET_DISK"; wait_udev
  wait_for_dev "${TARGET_DISK}${PSUF}1" 15 || fatal 1 ".B04-GPT-PARTS: ESP node missing"
  wait_for_dev "${TARGET_DISK}${PSUF}2" 15 || fatal 1 ".B04-GPT-PARTS: cryptroot node missing"
  wait_for_dev "${TARGET_DISK}${PSUF}3" 15 || fatal 1 ".B04-GPT-PARTS: cryptswap node missing"
}
# .B05-GPT-BACKUP: backup GPT to /tmp
disk_gpt_backup() {
  local BACKUP="gpt-$(basename "$TARGET_DISK")-$(date +%Y%m%d-%H%M%S).bin"
  local tmpbk; tmpbk="$(mktemp -p "$tmpdir" gpt.XXXXXX)"
  must sgdisk --backup="$tmpbk" "$TARGET_DISK"
  must mv -f -- "$tmpbk" "/tmp/$BACKUP"
  note ".B05-GPT-BACKUP: saved /tmp/$BACKUP"
}
with_lock "disk:$TARGET_DISK" 300 bash -c '
  disk_prep_prompt
  disk_umount_safety
  disk_create_gpt
  disk_make_parts
  disk_gpt_backup
'
note ".B99-DISK-DONE: disk preparation complete"

# ===== [C] ENCRYPTION =====
ESP=${TARGET_DISK}${PSUF}1
PROOT=${TARGET_DISK}${PSUF}2
PSWAP=${TARGET_DISK}${PSUF}3

# .C01-LUKS-FMT: format LUKS containers
with_lock "luks:$PROOT" 120 must cryptsetup luksFormat "$PROOT" --type luks2 --batch-mode --pbkdf argon2id --iter-time 1500 --cipher aes-xts-plain64 --key-size 512 --hash sha256 --label cryptroot
with_lock "luks:$PSWAP" 120 must cryptsetup luksFormat "$PSWAP" --type luks2 --batch-mode --pbkdf argon2id --iter-time 800  --cipher aes-xts-plain64 --key-size 512 --hash sha256 --label cryptswap

# .C02-LUKS-ENROLL: optional TPM2 enrollment
if $TPM2_AVAILABLE && systemd-cryptenroll --tpm2-device=list >/dev/null 2>&1; then
  check systemd-cryptenroll --tpm2-device=auto "$PROOT" || warn ".C02-LUKS-ENROLL: tpm enroll root failed"
  check systemd-cryptenroll --tpm2-device=auto "$PSWAP" || warn ".C02-LUKS-ENROLL: tpm enroll swap failed"
  OPEN_OPTS=(--tpm2-device=auto); CRYPTOPT="luks,tpm2-device=auto"
else
  OPEN_OPTS=(); CRYPTOPT="luks"
fi

# .C03-LUKS-OPEN: open LUKS and wait for mappers
with_lock "luks-open:$PROOT" 60 must cryptsetup open "$PROOT"  cryptroot "${OPEN_OPTS[@]}"
with_lock "luks-open:$PSWAP" 60 must cryptsetup open "$PSWAP"  cryptswap "${OPEN_OPTS[@]}"
wait_udev
wait_for_dev /dev/mapper/cryptroot 15 || fatal 1 ".C03-LUKS-OPEN: cryptroot mapper missing"
wait_for_dev /dev/mapper/cryptswap 15 || fatal 1 ".C03-LUKS-OPEN: cryptswap mapper missing"
note ".C99-LUKS-DONE: encryption opened"

# ===== [D] FILESYSTEMS & MOUNTS =====
# .D01-ESP-MKFS: FAT32 on ESP
must mkfs.fat -F32 -n ESP -- "$ESP"
must fsck.fat -v -- "$ESP"

# .D02-BTRFS-MKFS: Btrfs on root; swap label
must mkfs.btrfs -L archroot -m dup /dev/mapper/cryptroot
must mkswap -L swap -- /dev/mapper/cryptswap

# .D03-BTRFS-SUBVOLS: create subvolumes
must mount /dev/mapper/cryptroot /mnt/stage
for sv in @main @sandbox @home @bulk; do must btrfs subvolume create "/mnt/stage/$sv"; done
must umount /mnt/stage

# .D04-MOUNTS: mount subvols + ESP with locked mount helpers
declare -a _mnt_main_opts=(subvol=@main noatime compress=zstd:3 ssd space_cache=v2)
declare -a _mnt_home_opts=(subvol=@home noatime compress=zstd:3 ssd space_cache=v2)
declare -a _mnt_bulk_opts=(subvol=@bulk noatime compress=zstd:3 ssd space_cache=v2)
mount_locked -o "$(join_by , "${_mnt_main_opts[@]}")" /dev/mapper/cryptroot /mnt/stage
install -d -m 0755 /mnt/stage/{boot,home,bulk}
mount_locked -o "$(join_by , "${_mnt_home_opts[@]}")" /dev/mapper/cryptroot /mnt/stage/home
mount_locked -o "$(join_by , "${_mnt_bulk_opts[@]}")" /dev/mapper/cryptroot /mnt/stage/bulk
must mount -- "$ESP" /mnt/stage/boot
assert_mount /mnt/stage      /dev/mapper/cryptroot @main || fatal 1 ".D04-MOUNTS: @main mount unexpected"
assert_mount /mnt/stage/home /dev/mapper/cryptroot @home || fatal 1 ".D04-MOUNTS: @home mount unexpected"
assert_mount /mnt/stage/bulk /dev/mapper/cryptroot @bulk || fatal 1 ".D04-MOUNTS: @bulk mount unexpected"

# .D05-CRYPTTAB: write early crypttab for sd-encrypt
ROOT_UUID=$(blkid -s UUID -o value "$PROOT")
SWAP_UUID=$(blkid -s UUID -o value "$PSWAP")
install -d -m 0755 /mnt/stage/etc
cat > "$tmpdir/crypttab.initramfs" <<EOF
cryptroot UUID=$ROOT_UUID none $CRYPTOPT
cryptswap UUID=$SWAP_UUID none $CRYPTOPT
EOF
install -m 0644 "$tmpdir/crypttab.initramfs" /mnt/stage/etc/crypttab.initramfs

# .D06-FSTAB: generate fstab and validate (no subvolid)
must genfstab -U /mnt/stage >> /mnt/stage/etc/fstab
if check grep -q -- 'subvolid=' /mnt/stage/etc/fstab; then fatal 1 ".D06-FSTAB: fstab contains subvolid"; fi
note ".D99-FS-DONE: filesystems/subvols mounted"

# ===== [E] BASE INSTALL =====
# .E01-REFLECTOR: DNS readiness then mirror refresh (best-effort)
if ! net_ready archlinux.org 20; then
  warn ".E01-REFLECTOR: DNS not ready; skipping reflector"
else
  with_lock "file:/etc/pacman.d/mirrorlist" 120 \
    timeout 120s reflector --country US --latest 30 --protocol https --sort rate --save /etc/pacman.d/mirrorlist || \
    warn ".E01-REFLECTOR: reflector failed; continue"
fi

# .E02-PACSTRAP: install base packages
BASE_PKGS=( base base-devel btrfs-progs linux linux-headers linux-lts linux-lts-headers
  linux-firmware mkinitcpio cryptsetup networkmanager dosfstools util-linux gptfdisk
  vim nano sudo man-db man-pages texinfo tpm2-tss tpm2-tools git wget curl rsync tar )
wait_pacman_lock
if ! retry_rc 5 3 pacstrap -K /mnt/stage "${BASE_PKGS[@]}"; then
  fatal $? ".E02-PACSTRAP: pacstrap failed after retries"
fi
note ".E99-INSTALL-DONE: base installed"

# ===== [G] SYSTEM CONFIG (CHROOT) =====
# .G01-CHROOT-CONFIG: configure system inside target
if ! arch-chroot /mnt/stage /bin/bash <<'CHROOT_EOF'
set -Eeuo pipefail
set -o errtrace
trap 'rc=$?; echo "[G-ERR] rc=$rc at ${BASH_SOURCE[1]}:${BASH_LINENO[0]} while: ${BASH_COMMAND}" >&2' ERR

# .G01-LOCALE-TZ: timezone/locale/vconsole/hostname/hosts
ln -sf /usr/share/zoneinfo/US/Mountain /etc/localtime
hwclock --systohc
sed -i 's/^#\s*en_US\.UTF-8/en_US.UTF-8/' /etc/locale.gen
locale-gen
printf 'LANG=en_US.UTF-8\n' > /etc/locale.conf
printf 'KEYMAP=us\n' > /etc/vconsole.conf
printf 'lollypop\n' > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   lollypop.localdomain lollypop
EOF

# .G02-SERVICES: enable core services
systemctl enable NetworkManager
systemctl enable --now fstrim.timer || echo "[G02-SERVICES] warn: fstrim.timer not enabled"
systemctl enable systemd-timesyncd  || echo "[G02-SERVICES] warn: timesyncd not enabled"

# .G03-UCODE: install microcode and stash initrd line
if grep -qi intel /proc/cpuinfo; then
  pacman -Sy --noconfirm intel-ucode
  UCODE_LINE="initrd  /intel-ucode.img"
elif grep -qi amd /proc/cpuinfo; then
  pacman -Sy --noconfirm amd-ucode
  UCODE_LINE="initrd  /amd-ucode.img"
else
  UCODE_LINE=""
fi
printf '%s\n' "$UCODE_LINE" > /etc/.ucode_line

# .G04-MKINIT-HOOKS: sd-encrypt + resume hooks
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect modconf kms keyboard sd-vconsole block sd-encrypt resume filesystems fsck)/' /etc/mkinitcpio.conf
[ -s /etc/crypttab.initramfs ] || { echo "[G04-MKINIT-HOOKS] ERROR: crypttab.initramfs missing"; exit 1; }

# .G05-MKINIT-BUILD: build initramfs for all kernels
mkinitcpio -P

# .G06-BOOTCTL: install systemd-boot + loader.conf
bootctl install
cat > /boot/loader/loader.conf <<'EOF'
default  arch-main.conf
timeout  3
editor   no
EOF

# .G07-LOADER-ENTRIES: write loader entries under lock
LOCK_DIR=/boot/loader/.locks; install -d -m 0755 "$LOCK_DIR"
exec {bootlfd}> "$LOCK_DIR/entries.lock" || true
flock -x -w 60 "$bootlfd" || echo "[G07-LOADER-ENTRIES] warn: could not lock entries"

SWAP_UUID=$(blkid -s UUID -o value /dev/mapper/cryptswap || true)
RESUME_OPT=""
[ -n "$SWAP_UUID" ] && RESUME_OPT="resume=UUID=${SWAP_UUID}"
ROOT_MAIN="root=/dev/mapper/cryptroot rootflags=subvol=@main rw"
ROOT_SBOX="root=/dev/mapper/cryptroot rootflags=subvol=@sandbox rw"
UCODE_LINE=$(cat /etc/.ucode_line 2>/dev/null || true)

make_entry () {
  local name="$1" kernel="$2" rootopts="$3" fallback="$4" entry="/boot/loader/entries/${name}.conf"
  {
    echo "title   ${name}"
    echo "linux   /vmlinuz-${kernel}"
    [ -n "$UCODE_LINE" ] && echo "$UCODE_LINE"
    if [ "$fallback" = "yes" ]; then
      echo "initrd  /initramfs-${kernel}-fallback.img"
    else
      echo "initrd  /initramfs-${kernel}.img"
    fi
    echo "options ${rootopts} ${RESUME_OPT} loglevel=3"
  } > "$entry"
  sync -f "$entry" 2>/dev/null || true
}
make_entry "arch-main"           "linux"     "$ROOT_MAIN"  "no"
make_entry "arch-lts"            "linux-lts" "$ROOT_MAIN"  "no"
make_entry "arch-main-fallback"  "linux"     "$ROOT_MAIN"  "yes"
make_entry "arch-lts-fallback"   "linux-lts" "$ROOT_MAIN"  "yes"
make_entry "arch-sandbox"        "linux"     "$ROOT_SBOX"  "no"
make_entry "arch-sandbox-lts"    "linux-lts" "$ROOT_SBOX"  "no"

flock -u "$bootlfd" 2>/dev/null || true; exec {bootlfd}>&- 2>/dev/null || true

# .G08-BOOTFILES-READY: verify boot files exist on ESP
if [[ ! -f /boot/EFI/systemd/systemd-bootx64.efi || ! -f /boot/loader/loader.conf ]]; then
  echo "[G08-BOOTFILES-READY] ERROR: systemd-boot files missing on ESP"; exit 1
fi

# .G09-ROOT-PASSWD: prompt root password (optional)
if [[ ${SKIP_ROOT_PW:-0} -ne 1 ]]; then
  echo "Set root password:"; passwd
fi
CHROOT_EOF
then
  fatal $? ".G01-CHROOT-CONFIG: chroot configuration failed"
fi
note ".G99-CONFIG-DONE: chroot configuration complete"

# ===== [I] SECURITY (POST-CHROOT) =====
# .I01-TPM-OUTSIDE: enroll TPM2 tokens with PCRs (best-effort)
if $TPM2_AVAILABLE && systemd-cryptenroll --tpm2-device=list >/dev/null 2>&1; then
  check systemd-cryptenroll "$PROOT" --tpm2-device=auto --tpm2-pcrs=0+7 || warn ".I01-TPM-OUTSIDE: enroll root failed"
  check systemd-cryptenroll "$PSWAP" --tpm2-device=auto --tpm2-pcrs=0+7 || warn ".I01-TPM-OUTSIDE: enroll swap failed"
  check cryptsetup luksDump "$PROOT" | grep -qi tpm2 && note ".I01-TPM-OUTSIDE: tpm2 token present (root)" || true
  check cryptsetup luksDump "$PSWAP" | grep -qi tpm2 && note ".I01-TPM-OUTSIDE: tpm2 token present (swap)" || true
fi

# ===== [J] OPTIONALS =====
# .J01-OPTIONAL-SVCS: power/bluetooth (best-effort)
check arch-chroot /mnt/stage systemctl enable tlp tlp-sleep || warn ".J01-OPTIONAL-SVCS: tlp not enabled"
check arch-chroot /mnt/stage systemctl enable bluetooth     || warn ".J01-OPTIONAL-SVCS: bluetooth not enabled"
echo "options i915 enable_psr=0" > /mnt/stage/etc/modprobe.d/i915.conf

# .J02-OPTIONAL-USER: create interactive user (optional)
MAKEUSER=${MAKEUSER:-0}
if (( MAKEUSER == 1 )) || { IFS= read -r -p ".J02-OPTIONAL-USER: Create user now? (y/N): " ans && [[ $ans =~ ^[Yy]$ ]]; }; then
  if [[ -z ${USERNAME:-} ]]; then IFS= read -r -p ".J02-OPTIONAL-USER: Enter username: " USERNAME; fi
  if ! [[ $USERNAME =~ ^[a-z_][a-z0-9_-]*$ ]]; then fatal 2 ".J02-OPTIONAL-USER: invalid username '$USERNAME'"; fi
  must arch-chroot /mnt/stage useradd -mG wheel "$USERNAME"
  if [[ ${SKIP_USER_PW:-0} -ne 1 ]]; then
    note ".J02-OPTIONAL-USER: set password for $USERNAME"; must arch-chroot /mnt/stage passwd "$USERNAME"
  fi
  install -d -m 0755 /mnt/stage/etc/systemd/system/getty@tty1.service.d
  cat > /mnt/stage/etc/systemd/system/getty@tty1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USERNAME --noclear %I \$TERM
EOF
  tmpf="$(mktemp -p "$tmpdir" sudoers.XXXXXX)"; printf '%%wheel ALL=(ALL:ALL) ALL\n' > "$tmpf"
  install -m 0440 "$tmpf" /mnt/stage/etc/sudoers.d/wheel
  cat > /mnt/stage/home/$USERNAME/.bash_profile <<'EOF'
if [ -z "$DISPLAY" ] && [ "${XDG_VTNR:-0}" -eq 1 ]; then
  exec uwsm start
fi
EOF
  check arch-chroot /mnt/stage chown "$USERNAME:$USERNAME" "/home/$USERNAME/.bash_profile" || warn ".J02-OPTIONAL-USER: chown profile failed"
  check arch-chroot /mnt/stage systemctl enable getty@tty1 || warn ".J02-OPTIONAL-USER: getty enable failed"
fi

# .J03-SNAPPER: configure snapper & snapshots (best-effort)
check pacman -Sy --noconfirm --needed snapper snapper-support snap-pac || warn ".J03-SNAPPER: pkgs failed"
install -d -m 0755 /mnt/.btrfs
mount_locked -o subvolid=5 /dev/mapper/cryptroot /mnt/.btrfs
if [[ ! -d /mnt/.btrfs/@sandbox ]]; then
  must btrfs subvolume snapshot /mnt/.btrfs/@main /mnt/.btrfs/@sandbox
  [[ -d /mnt/.btrfs/@home ]] && check btrfs subvolume snapshot /mnt/.btrfs/@home /mnt/.btrfs/@sandbox-home || true
fi
umount_locked /mnt/.btrfs
arch-chroot /mnt/stage snapper -c root create-config /           || true
arch-chroot /mnt/stage snapper -c home create-config /home       || true
arch-chroot /mnt/stage snapper -c root create --description "Baseline Root" || true
arch-chroot /mnt/stage snapper -c home create --description "Baseline Home" || true
if ! snapper_ready /mnt/stage; then warn ".J03-SNAPPER: not fully initialized"; fi

# .J04-SANDBOX-FSTAB: wire sandbox fstab
install -d -m 0755 /mnt/sbx
mount_locked -o subvol=@sandbox /dev/mapper/cryptroot /mnt/sbx
assert_mount /mnt/sbx /dev/mapper/cryptroot @sandbox || fatal 1 ".J04-SANDBOX-FSTAB: /mnt/sbx not @sandbox"
BTRFS_UUID=$(blkid -s UUID -o value /dev/mapper/cryptroot)
if ! check grep -qE -- '\s/home\s' /mnt/sbx/etc/fstab 2>/dev/null; then
  printf 'UUID=%s /home btrfs %s 0 0\n' "$BTRFS_UUID" "noatime,compress=zstd:3,subvol=@sandbox-home" >> /mnt/sbx/etc/fstab
else
  must sed -i 's#subvol=@home#subvol=@sandbox-home#' /mnt/sbx/etc/fstab
fi
umount_locked /mnt/sbx

# ===== [K] PRE-REBOOT VERIFICATION =====
# .K01-LOADER-ENTRIES: ensure loader entries exist
if [[ $(count_files /mnt/stage/boot/loader/entries '*.conf') -eq 0 ]]; then
  fatal 1 ".K01-LOADER-ENTRIES: none found"
fi

# .K02-UCODE-REFS: warn if microcode not referenced
if grep -qi intel /proc/cpuinfo; then
  check grep -rI -- "intel-ucode" /mnt/stage/boot/loader/entries || warn ".K02-UCODE-REFS: intel-ucode not referenced"
elif grep -qi amd /proc/cpuinfo; then
  check grep -rI -- "amd-ucode"   /mnt/stage/boot/loader/entries || warn ".K02-UCODE-REFS: amd-ucode not referenced"
fi

# .K03-RESUME-UUID: ensure resume=UUID matches cryptswap
SWAP_UUID_MAP=$(blkid -s UUID -o value /dev/mapper/cryptswap)
if ! check grep -rI -- "resume=UUID=${SWAP_UUID_MAP}" /mnt/stage/boot/loader/entries >/dev/null; then
  case $? in
    1) fatal 1 ".K03-RESUME-UUID: resume=UUID missing/wrong" ;;
    *) fatal $? ".K03-RESUME-UUID: grep error" ;;
  esac
fi

# .K04-ESP-USAGE: warn if ESP nearly full
ESP_USAGE=$(LC_ALL=C df /mnt/stage/boot | awk 'NR==2 {print $5}' | tr -d '%')
(( ESP_USAGE > 85 )) && warn ".K04-ESP-USAGE: ${ESP_USAGE}% used"

# .K05-SVCS-ENABLED: confirm critical services enabled
for svc in NetworkManager fstrim.timer systemd-timesyncd; do
  if arch-chroot /mnt/stage systemctl is-enabled "$svc" >/dev/null 2>&1; then
    note ".K05-SVCS-ENABLED: ✓ $svc enabled"
  else
    warn ".K05-SVCS-ENABLED: ✗ $svc NOT enabled"
  fi
done

# .K06-BOOTFILES-READY: ensure ESP has boot files
if ! bootfiles_ready /mnt/stage/boot; then
  fatal 1 ".K06-BOOTFILES-READY: missing systemd-boot files"
fi

note ".K99-VERIFY-DONE: pre-reboot verification complete"

# ===== [K7] ARTIFACT COLLECTION =====
# .K7A-ART-DIR: prepare artifact dirs
ART_DIR_SRC="$tmpdir/artifacts"
ART_DIR_TGT="/mnt/stage/var/log/installer"
ART_TARBALL="/tmp/arch-bootstrap-artifacts.tar"
install -d -m 0755 "$ART_DIR_SRC" "$ART_DIR_TGT"

# .K7B-ART-COLLECT: gather configs, state, logs
check rsync_safe "/mnt/stage/etc/fstab"                 "$ART_DIR_SRC/"        || true
check rsync_safe "/mnt/stage/etc/crypttab.initramfs"    "$ART_DIR_SRC/"        || true
check rsync_safe "/mnt/stage/etc/mkinitcpio.conf"       "$ART_DIR_SRC/"        || true
check rsync_safe "/mnt/stage/boot/loader/loader.conf"   "$ART_DIR_SRC/boot/"   || true
check rsync_safe "/mnt/stage/boot/loader/entries/"      "$ART_DIR_SRC/boot/entries/" || true
LC_ALL=C lsblk -f > "$ART_DIR_SRC/lsblk.txt" 2>&1 || true
blkid        > "$ART_DIR_SRC/blkid.txt"      2>&1 || true
sgdisk -p "$TARGET_DISK"   > "$ART_DIR_SRC/sgdisk-print.txt" 2>&1 || true
check rsync_safe "$LOG" "$ART_DIR_SRC/" || true
[[ -f "$LOG.xtrace" ]] && check rsync_safe "$LOG.xtrace" "$ART_DIR_SRC/" || true
[[ -f "$RUN_JSON"   ]] && check rsync_safe "$RUN_JSON"   "$ART_DIR_SRC/" || true

# .K7C-ART-TAR: reproducible tar + copy into target
tar_repro "$ART_TARBALL" "$ART_DIR_SRC" || warn ".K7C-ART-TAR: bundle failed"
check rsync_safe "$ART_DIR_SRC/" "$ART_DIR_TGT/" || warn ".K7C-ART-TAR: rsync into target failed"
check rsync_safe "$ART_TARBALL"  "$ART_DIR_TGT/" || true
note ".K7Z-ART-DONE: artifacts at $ART_DIR_TGT / $(basename "$ART_TARBALL")"

# ===== [L] REBOOT PHASE =====
# .L01-UMOUNT: sync & unmount stage
sync
umount_locked /mnt/stage || warn ".L01-UMOUNT: some filesystems couldn't be unmounted cleanly"

# .L02-LUKS-CLOSE: close mappers
with_lock "luks-open:$PSWAP" 30  check cryptsetup close cryptswap || warn ".L02-LUKS-CLOSE: cannot close cryptswap"
with_lock "luks-open:$PROOT" 30  check cryptsetup close cryptroot || warn ".L02-LUKS-CLOSE: cannot close cryptroot"

# .L03-REBOOT: done (optional reboot)
note ".L03-REBOOT: installation complete"
if (( ${REBOOT_AFTER:-1} == 1 )); then
  echo "Rebooting in 10s… remove installation media."
  if (( ${AUTO_CONFIRM:-0} != 1 )); then IFS= read -r -t 10 -p "Press Enter to reboot now, or wait 10 seconds... " _ || true; fi
  _log_event "info" ".L03-REBOOT: rebooting"
  reboot
else
  _log_event "info" ".L03-REBOOT: completed without reboot"
fi
