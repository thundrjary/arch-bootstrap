#!/usr/bin/env bash
# archlib.sh — Bash helpers for reliable system scripting
# Requires: bash 4+, coreutils, awk, grep, sed; optional: curl/wget, rsync, tar, flock, udevadm, python

###############################################################################
# [LOGGING] human log, xtrace (DEBUG), and NDJSON event stream
###############################################################################

# Open a human-readable log and timestamp all stdout/stderr lines.
# Usage: log_open "/var/log/my-script.$(date +%F-%H%M%S).log"
log_open() {
  LOG="$1"; : "${LOG:?log path required}"
  RUN_JSON="$LOG.ndjson"
  install -d -m 0755 -- "$(dirname "$LOG")"
  exec > >(stdbuf -oL awk '{ printf("[%s] %s\n", strftime("%F %T"), $0) }' | tee -a "$LOG") 2>&1
}

# Enable bash xtrace to a separate file when DEBUG=1 (or pass 1 explicitly).
# Usage: log_enable_xtrace "${DEBUG:-0}"
log_enable_xtrace() {
  local dbg="${1:-0}"
  if [[ "$dbg" == 1 ]]; then
    exec 5>>"$LOG.xtrace"
    export BASH_XTRACEFD=5
    export PS4='+ $(date "+%F %T") ${BASH_SOURCE}:${LINENO}:${FUNCNAME[0]}: '
    set -x
  fi
}

# Internal: RFC3339 UTC timestamp
_ts() { date -u +%FT%TZ; }

# Write a structured NDJSON event (if python is available).
# Usage: _log_event info "message"
_log_event() {
  local lvl="$1"; shift
  [[ -n "${RUN_JSON:-}" ]] || return 0
  if command -v python >/dev/null 2>&1; then
    printf '{"ts":"%s","level":"%s","msg":%s}\n' "$(_ts)" "$lvl" \
      "$(printf '%s' "$*" | python - <<'PY'
import json,sys
print(json.dumps(sys.stdin.read()))
PY
)" >>"$RUN_JSON" 2>/dev/null || true
  fi
}

fatal() { local rc=${1:-1}; shift || true; _log_event fatal "$* (rc=$rc)"; printf '[FATAL] (%s) %s\n' "$rc" "$*" >&2; exit "$rc"; }
warn()  { _log_event warn  "$*"; printf '[WARN] %s\n' "$*" >&2; }
note()  { _log_event info  "$*"; printf '[INFO] %s\n' "$*"; }

# Trap helper for noisy error context (opt-in by caller: trap _errtrap ERR)
_errtrap(){ local rc=$?; _log_event error "ERR rc=$rc at ${BASH_SOURCE[1]}:${BASH_LINENO[0]}: ${BASH_COMMAND}"; printf '[ERR] rc=%s at %s:%s: %s\n' "$rc" "${BASH_SOURCE[1]}" "${BASH_LINENO[0]}" "${BASH_COMMAND}" >&2; }

###############################################################################
# [FLOW CONTROL] must/check/retry/require + misc small helpers
###############################################################################

# Run a command or die with context
must() { note "run: $*"; "$@"; local rc=$?; ((rc==0)) || fatal "$rc" "cmd failed: $*"; }

# Run a shell pipeline (string) with pipefail semantics
# Usage: must_pipe 'cmd1 | cmd2 | cmd3'
must_pipe() { note "pipeline: $*"; set -o pipefail; bash -c "$*"; local rc=$?; set +o pipefail; ((rc==0)) || fatal "$rc" "pipeline failed: $*"; }

# Run a command but do not exit on failure; returns command's rc
check() { set +e; "$@"; local rc=$?; set -e; return "$rc"; }

# Retry a command N times with D seconds delay
# Usage: retry_rc 5 2 curl http://example
retry_rc() { local -i n=$1 d=$2 i rc; shift 2; for ((i=1;i<=n;i++)); do note "try($i/$n): $*"; "$@"; rc=$?; ((rc==0)) && return 0; ((i<n)) && sleep "$d"; done; return "$rc"; }

# Ensure commands exist
# Usage: require awk sed grep
require(){ for c in "$@"; do command -v "$c" >/dev/null || fatal 127 "missing: $c"; done; }

# udev settle / partition table rescan
wait_udev(){ udevadm settle || true; }
part_rescan(){ partprobe "$1" 2>/dev/null || true; blockdev --rereadpt "$1" 2>/dev/null || true; }

# Append 'p' to disk name for nvme/mmcblk
partsuf(){ [[ $1 =~ (nvme|mmcblk) ]] && printf 'p' || printf ''; }

###############################################################################
# [DATA PLUMBING] safe string/list/stream helpers
###############################################################################

# Join arguments by a delimiter
# Usage: join_by , a b c   -> a,b,c
join_by() { local IFS="$1"; shift; echo "$*"; }

# Read NUL-delimited lines into an array
# Usage: read0 arr < <(find . -print0)
read0() { local __var="$1"; shift; mapfile -d '' -t "$__var"; }

# Count files matching pattern in a dir (safe)
# Usage: count_files /etc '*.conf'
count_files() { local dir="$1" pat="$2"; local -a _tmp=(); while IFS= read -r -d '' f; do _tmp+=("$f"); done < <(find "$dir" -maxdepth 1 -type f -name "$pat" -print0 2>/dev/null); echo "${#_tmp[@]}"; }

###############################################################################
# [LOCKING] single-instance & resource-scoped locks
###############################################################################

# Global single-instance lock (call once near start)
# Usage: single_instance_lock "/var/lock/my-script.lock"
single_instance_lock() { local path="$1"; exec 9>"$path" || fatal 98 "lock open failed: $path"; flock -n 9 || fatal 99 "another instance is running"; }

# Folder for fine-grained locks (ensure exists)
# Usage: lock_root_init "/run/lock/my-script"
lock_root_init(){ LOCK_ROOT="$1"; install -d -m 0755 -- "$LOCK_ROOT"; }

# Run a command under a named lock with timeout
# Usage: with_lock "disk:/dev/nvme0n1" 120 sgdisk -p /dev/nvme0n1
with_lock() {
  local name="$1" timeout="${2:-60}"; shift 2
  local path="${LOCK_ROOT:-/run/lock}/$(echo "$name" | tr '/ ' '__').lock"
  exec {__lfd__}> "$path" || fatal 98 "cannot open lock: $path"
  flock -x -w "$timeout" "$__lfd__" || fatal 99 "lock timeout: $name"
  "$@"; local rc=$?
  flock -u "$__lfd__"; eval "exec $__lfd__>&-"
  return "$rc"
}

# Locking wrappers for mount/umount (serialize by mountpoint)
mount_locked()  { local target="${@: -1}"; with_lock "mnt:$target" 120 mount "$@"; }
umount_locked() { local mp="$1";            with_lock "mnt:$mp"    120 umount -R -- "$mp"; }

# Wait for pacman db lock to clear (up to 10 min)
wait_pacman_lock(){ local deadline=$((SECONDS+600)); while [[ -e /var/lib/pacman/db.lck ]]; do ((SECONDS<deadline)) || fatal 97 "pacman lock held too long"; sleep 2; done; }

###############################################################################
# [READINESS CHECKS] “don’t proceed until it’s actually ready”
###############################################################################

# Wait until a path exists (device/file), with timeout seconds
# Usage: wait_for_dev /dev/mapper/cryptroot 30
wait_for_dev(){ local dev="$1" t="${2:-30}" d=$((SECONDS+t)); while [[ ! -e "$dev" ]]; do ((SECONDS<d))||return 1; udevadm settle||true; sleep 1; done; }

# Assert that a mountpoint is mounted from SOURCE and (optionally) with subvol=NAME
# Usage: assert_mount /mnt /dev/mapper/cryptroot @main
assert_mount(){
  local mp="$1" src="$2" sub="${3:-}"
  findmnt -no SOURCE,TARGET,OPTIONS --target "$mp" | awk -v s="$src" -v sv="$sub" '
    BEGIN{ok=0}
    { if ($1==s && $2=="'"$mp"'") { if (sv=="") ok=1; else if (index($3,"subvol="sv)) ok=1 } }
    END{exit ok?0:1}
  '
}

# DNS/network readiness (beyond ICMP)
# Usage: net_ready archlinux.org 20
net_ready(){ local host="${1:-archlinux.org}" t="${2:-20}" d=$((SECONDS+t)); while ! getent hosts "$host" >/dev/null 2>&1; do ((SECONDS<d))||return 1; sleep 1; done; }

# Boot files presence on ESP
# Usage: bootfiles_ready /boot
bootfiles_ready(){ [[ -f "$1/EFI/systemd/systemd-bootx64.efi" && -f "$1/loader/loader.conf" ]]; }

# Snapper materialized (config + .snapshots)
# Usage: snapper_ready /mnt
snapper_ready(){ [[ -f "$1/etc/snapper/configs/root" && -d "$1/.snapshots" ]]; }

###############################################################################
# [SAFE WRAPPERS] network fetch, rsync, reproducible tar
###############################################################################

# HTTP GET with strict failures and retries (curl preferred; falls back to wget).
# Usage: http_get URL [OUTFILE]
http_get() {
  local url="$1" out="${2:-}"
  if command -v curl >/dev/null 2>&1; then
    local args=(--fail-with-body --location --retry 5 --retry-delay 2 --retry-connrefused --max-time 60 --silent --show-error)
    [[ -n $out ]] && curl "${args[@]}" --output "$out" -- "$url" || curl "${args[@]}" -- "$url"
  elif command -v wget >/dev/null 2>&1; then
    local args=(--retry-connrefused --tries=10 --waitretry=2 --timeout=30 --quiet)
    [[ -n $out ]] && wget "${args[@]}" -O "$out" -- "$url" || wget "${args[@]}" -O - -- "$url"
  else
    fatal 127 "neither curl nor wget available"
  fi
}

# Rsync with restartability, checksum correctness, safe deletes, and auto-mkdirs.
# Usage: rsync_safe SRC/ DEST/ [extra rsync args...]
rsync_safe(){ local src="$1" dst="$2"; shift 2; rsync -a --partial --inplace --checksum --delete-delay --mkpath --info=stats2 "$src" "$dst" "$@"; }

# Reproducible tar (stable owners, mtime, sort, and content)
# Usage: tar_repro out.tar /dir
tar_repro(){ local out="$1" dir="$2"; tar --numeric-owner --owner=0 --group=0 --mtime=@0 --sort=name -cf "$out" -C "$dir" .; }

###############################################################################
# [SYSTEMD HELPERS] optional: machine-readable readiness
###############################################################################

# Wait until a systemd unit reaches a “running/active” substate (or fail)
# Usage: systemctl_up nginx.service 60
systemctl_up(){
  local unit="$1" t="${2:-60}" deadline=$((SECONDS+t))
  systemctl start "$unit"
  while (( SECONDS < deadline )); do
    local ss; ss=$(systemctl show -p SubState --value "$unit" 2>/dev/null || true)
    case "$ss" in running|listening|active) return 0 ;; failed) journalctl -u "$unit" --no-pager -n 50; return 1 ;; esac
    sleep 1
  done
  journalctl -u "$unit" --no-pager -n 50 || true
  return 1
}

# Is a systemd unit enabled? (quiet boolean)
# Usage: systemctl_enabled NetworkManager.service && echo yes
systemctl_enabled(){ systemctl is-enabled --quiet "$1"; }
