#!/usr/bin/env bash

# archlib.sh — Enhanced Bash helpers for reliable system scripting

# Requires: bash 4+, coreutils, awk, grep, sed; optional: curl/wget, rsync, tar, flock, udevadm, python

# Version: 2.0.0 - Enhanced with comprehensive improvements

###############################################################################

# [CONFIGURATION] Global settings with defaults

###############################################################################

# Default configuration - can be overridden via config file or environment

declare -A ARCHLIB_CONFIG=(
[DEFAULT_TIMEOUT]=60
[HTTP_TIMEOUT]=60
[LOCK_TIMEOUT]=120
[RETRY_COUNT]=5
[RETRY_BASE_DELAY]=2
[RETRY_MAX_DELAY]=30
[PACMAN_LOCK_TIMEOUT]=600
[LOG_LEVEL]=info
[LOG_MAX_SIZE]=100M
[BATCH_LOG_INTERVAL]=5
[MIN_DISK_SPACE]=100M
[MAX_LOCK_AGE]=3600
)

# Load configuration from file if it exists

_load_config() {
local config_file=”${ARCHLIB_CONFIG_FILE:-/etc/archlib.conf}”
if [[ -r “$config_file” ]]; then
# shellcheck source=/dev/null
source “$config_file” 2>/dev/null || warn “Failed to load config: $config_file”
fi
}

# Get configuration value with fallback

_config() {
local key=”$1” default=”$2”
echo “${ARCHLIB_CONFIG[$key]:-$default}”
}

###############################################################################

# [COMPATIBILITY & PLATFORM DETECTION]

###############################################################################

# Detect platform and set compatibility flags

declare -g ARCHLIB_PLATFORM ARCHLIB_HAS_GNU_UTILS=0 ARCHLIB_HAS_SYSTEMD=0
_detect_platform() {
case “$(uname -s)” in
Linux)   ARCHLIB_PLATFORM=linux; ARCHLIB_HAS_GNU_UTILS=1 ;;
Darwin)  ARCHLIB_PLATFORM=macos ;;
FreeBSD) ARCHLIB_PLATFORM=freebsd ;;
*)       ARCHLIB_PLATFORM=unknown ;;
esac

```
# Check for systemd
[[ -d /run/systemd/system ]] && ARCHLIB_HAS_SYSTEMD=1

# Verify core utilities support required features
if ! date --version >/dev/null 2>&1; then
    warn "GNU coreutils not detected - some features may not work"
fi
```

}

# Check bash version compatibility

_check_bash_version() {
if (( BASH_VERSINFO[0] < 4 )); then
fatal 126 “bash 4+ required (found ${BASH_VERSION})”
fi
}

###############################################################################

# [CACHED COMMAND CHECKS] Performance optimization

###############################################################################

declare -A _COMMAND_CACHE=()

# Cached command existence check

_has_command() {
local cmd=”$1”
if [[ -z “${_COMMAND_CACHE[$cmd]:-}” ]]; then
if command -v “$cmd” >/dev/null 2>&1; then
_COMMAND_CACHE[$cmd]=1
else
_COMMAND_CACHE[$cmd]=0
fi
fi
return “${_COMMAND_CACHE[$cmd]}”
}

###############################################################################

# [SECURITY & VALIDATION] Input sanitization and safety

###############################################################################

# Sanitize file path to prevent directory traversal

_sanitize_path() {
local path=”$1”
# Remove .. components and normalize
readlink -f “$path” 2>/dev/null || {
# Fallback for non-existent paths
printf ‘%s’ “$path” | sed ‘s|/+|/|g; s|/../|/|g; s|^../||; s|/..$||’
}
}

# Validate numeric input with optional range

_validate_numeric() {
local value=”$1” min=”${2:-0}” max=”${3:-999999}” name=”${4:-value}”
if ! [[ “$value” =~ ^[0-9]+$ ]] || (( value < min || value > max )); then
fatal 2 “Invalid $name: ‘$value’ (must be $min-$max)”
fi
}

# Validate timeout parameter

_validate_timeout() {
local timeout=”$1” name=”${2:-timeout}”
_validate_numeric “$timeout” 1 86400 “$name”
}

# Check if running with appropriate privileges for operation

_check_privileges() {
local operation=”$1”
case “$operation” in
mount|partition|device)
(( EUID == 0 )) || fatal 77 “$operation requires root privileges” ;;
network)
# Most network operations don’t need root, but some do
;;
esac
}

# Validate lock file permissions and ownership

_validate_lock_file() {
local lock_file=”$1”
if [[ -e “$lock_file” ]]; then
local perms owner age
perms=$(stat -c %a “$lock_file” 2>/dev/null)
owner=$(stat -c %u “$lock_file” 2>/dev/null)
age=$(( $(date +%s) - $(stat -c %Y “$lock_file” 2>/dev/null || echo 0) ))

```
    # Check permissions (should be 644 or 600)
    if [[ "$perms" != "644" && "$perms" != "600" ]]; then
        warn "Lock file has unusual permissions: $lock_file ($perms)"
    fi
    
    # Check if lock is stale
    if (( age > $(_config MAX_LOCK_AGE) )); then
        warn "Stale lock file detected: $lock_file (age: ${age}s)"
        return 1
    fi
fi
return 0
```

}

###############################################################################

# [DISK SPACE & RESOURCE CHECKS]

###############################################################################

# Check available disk space at path

_check_disk_space() {
local path=”$1” required=”${2:-$(_config MIN_DISK_SPACE)}”
local available

```
if _has_command df; then
    available=$(df -B1 "$path" 2>/dev/null | awk 'NR==2 {print $4}')
    local required_bytes
    required_bytes=$(_parse_size "$required")
    
    if (( available < required_bytes )); then
        fatal 28 "Insufficient disk space at $path: ${available}B available, ${required_bytes}B required"
    fi
else
    warn "Cannot check disk space - df command not available"
fi
```

}

# Parse size with units (K, M, G) to bytes

_parse_size() {
local size=”$1”
case “$size” in
*K|*k) echo $(( ${size%[Kk]} * 1024 )) ;;
*M|*m) echo $(( ${size%[Mm]} * 1024 * 1024 )) ;;
*G|*g) echo $(( ${size%[Gg]} * 1024 * 1024 * 1024 )) ;;
*[0-9]) echo “$size” ;;
*) echo 1048576 ;; # Default 1MB
esac
}

###############################################################################

# [ENHANCED LOGGING] Batched writes, levels, and structured events

###############################################################################

declare -g LOG RUN_JSON LOG_BATCH_BUFFER=() LOG_BATCH_TIMER=0
declare -g LOG_LEVELS=([debug]=0 [info]=1 [warn]=2 [error]=3 [fatal]=4)
declare -g CURRENT_LOG_LEVEL=1

# Initialize logging system with lazy loading

log_init() {
local log_path=”${1:-}”
local log_level=”${2:-$(_config LOG_LEVEL)}”

```
if [[ -n "$log_path" ]]; then
    LOG="$log_path"
    RUN_JSON="$LOG.ndjson"
    
    # Validate log directory and disk space
    local log_dir
    log_dir=$(dirname "$LOG")
    _check_disk_space "$log_dir"
    install -d -m 0755 -- "$log_dir"
    
    # Set up log rotation if file exists and is too large
    _rotate_log_if_needed
    
    # Redirect stdout/stderr with timestamps
    exec > >(stdbuf -oL awk '{ printf("[%s] %s\n", strftime("%F %T"), $0) }' | tee -a "$LOG") 2>&1
fi

# Set log level
CURRENT_LOG_LEVEL=${LOG_LEVELS[$log_level]:-1}

# Set up signal traps for cleanup
trap '_cleanup_on_exit' EXIT
trap '_cleanup_on_signal' INT TERM
```

}

# Alias for backward compatibility

log_open() { log_init “$@”; }

# Log rotation based on size

_rotate_log_if_needed() {
if [[ -f “$LOG” ]]; then
local max_size_bytes
max_size_bytes=$(_parse_size “$(_config LOG_MAX_SIZE)”)
local current_size
current_size=$(stat -c%s “$LOG” 2>/dev/null || echo 0)

```
    if (( current_size > max_size_bytes )); then
        local timestamp
        timestamp=$(date +%Y%m%d-%H%M%S)
        mv "$LOG" "${LOG}.${timestamp}"
        note "Rotated log file: ${LOG}.${timestamp}"
    fi
fi
```

}

# Enhanced xtrace with better formatting

log_enable_xtrace() {
local dbg=”${1:-${DEBUG:-0}}”
_validate_numeric “$dbg” 0 1 “debug flag”

```
if (( dbg == 1 )); then
    local xtrace_file="${LOG}.xtrace"
    exec 5>>"$xtrace_file"
    export BASH_XTRACEFD=5
    export PS4='+ $(date "+%F %T") [$$:${BASH_SUBSHELL}] ${BASH_SOURCE}:${LINENO}:${FUNCNAME[0]}: '
    set -x
    note "Debug tracing enabled: $xtrace_file"
fi
```

}

# Internal: RFC3339 UTC timestamp with microseconds

_ts() {
if _has_command python3; then
python3 -c “import datetime; print(datetime.datetime.now(datetime.timezone.utc).isoformat())”
else
date -u +%FT%TZ
fi
}

# Batched JSON event logging for performance

declare -A _LOG_BATCH_BUFFER=()
_flush_log_batch() {
if [[ -n “${RUN_JSON:-}” && ${#_LOG_BATCH_BUFFER[@]} -gt 0 ]]; then
{
for event in “${_LOG_BATCH_BUFFER[@]}”; do
echo “$event”
done
} >> “$RUN_JSON” 2>/dev/null || true
_LOG_BATCH_BUFFER=()
fi
}

# Enhanced structured logging with levels and batching

_log_event() {
local level=”$1”; shift
local msg=”$*”
local level_num=${LOG_LEVELS[$level]:-1}

```
# Check if this level should be logged
(( level_num >= CURRENT_LOG_LEVEL )) || return 0

if [[ -n "${RUN_JSON:-}" ]]; then
    local json_msg
    if _has_command python3; then
        json_msg=$(printf '%s' "$msg" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read().strip()))")
    else
        # Fallback JSON escaping
        json_msg=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$//')
        json_msg="\"$json_msg\""
    fi
    
    local event
    printf -v event '{"ts":"%s","level":"%s","pid":%d,"msg":%s}' "$(_ts)" "$level" "$$" "$json_msg"
    _LOG_BATCH_BUFFER+=("$event")
    
    # Flush batch periodically or on high-priority events
    if [[ "$level" == "fatal" || "$level" == "error" ]] || (( ${#_LOG_BATCH_BUFFER[@]} >= 10 )); then
        _flush_log_batch
    fi
fi
```

}

# Enhanced logging functions with levels

debug() { (( ${LOG_LEVELS[debug]} >= CURRENT_LOG_LEVEL )) && { _log_event debug “$*”; printf ‘[DEBUG] %s\n’ “$*” >&2; } }
note()  { _log_event info  “$*”; printf ‘[INFO] %s\n’ “$*”; }
info()  { note “$@”; } # Alias
warn()  { _log_event warn  “$*”; printf ‘[WARN] %s\n’ “$*” >&2; }
error() { _log_event error “$*”; printf ‘[ERROR] %s\n’ “$*” >&2; }
fatal() {
local rc=${1:-1}; shift || true
_log_event fatal “$* (rc=$rc)”
printf ‘[FATAL] (%s) %s\n’ “$rc” “$*” >&2
_flush_log_batch  # Ensure fatal events are written immediately
exit “$rc”
}

# Enhanced error trap with more context

_errtrap() {
local rc=$? line_no=${BASH_LINENO[0]} source_file=${BASH_SOURCE[1]} cmd=${BASH_COMMAND}
local func_name=${FUNCNAME[1]:-main}

```
_log_event error "Command failed: rc=$rc, file=$source_file, line=$line_no, func=$func_name, cmd=$cmd"
printf '[ERROR] Command failed (rc=%s) at %s:%s in %s(): %s\n' "$rc" "$source_file" "$line_no" "$func_name" "$cmd" >&2

# Add stack trace for fatal errors
if (( rc > 100 )); then
    printf '[ERROR] Stack trace:\n' >&2
    local i=1
    while [[ ${BASH_SOURCE[i]:-} ]]; do
        printf '  [%d] %s:%s in %s()\n' "$i" "${BASH_SOURCE[i]}" "${BASH_LINENO[i-1]}" "${FUNCNAME[i]:-main}" >&2
        ((i++))
    done
fi
```

}

# Cleanup functions for graceful shutdown

_cleanup_on_exit() {
_flush_log_batch
_cleanup_locks
}

_cleanup_on_signal() {
warn “Received signal, cleaning up…”
_flush_log_batch
_cleanup_locks
exit 130
}

# Timer-based batch flushing

_start_log_batch_timer() {
local interval=$(_config BATCH_LOG_INTERVAL)
(
while sleep “$interval”; do
_flush_log_batch
done
) &
LOG_BATCH_TIMER=$!
}

_stop_log_batch_timer() {
if (( LOG_BATCH_TIMER > 0 )); then
kill “$LOG_BATCH_TIMER” 2>/dev/null || true
LOG_BATCH_TIMER=0
fi
}

###############################################################################

# [ENHANCED FLOW CONTROL] Better error handling and validation

###############################################################################

# Enhanced command execution with validation and context

must() {
local cmd_desc=”$*”
[[ $# -gt 0 ]] || fatal 2 “must: no command specified”

```
debug "run: $cmd_desc"

# Validate command exists
local cmd_name="$1"
_has_command "$cmd_name" || fatal 127 "command not found: $cmd_name"

# Execute with timing
local start_time=$SECONDS
"$@"
local rc=$?
local duration=$((SECONDS - start_time))

if (( rc == 0 )); then
    debug "success: $cmd_desc (${duration}s)"
else
    error "command failed: $cmd_desc (rc=$rc, ${duration}s)"
    fatal "$rc" "cmd failed: $cmd_desc"
fi
```

}

# Enhanced pipeline execution with better error reporting

must_pipe() {
local pipeline=”$1”
[[ -n “$pipeline” ]] || fatal 2 “must_pipe: empty pipeline”

```
debug "pipeline: $pipeline"

local start_time=$SECONDS
set -o pipefail
bash -c "$pipeline"
local rc=$?
set +o pipefail
local duration=$((SECONDS - start_time))

if (( rc == 0 )); then
    debug "pipeline success: $pipeline (${duration}s)"
else
    error "pipeline failed: $pipeline (rc=$rc, ${duration}s)"
    fatal "$rc" "pipeline failed: $pipeline"
fi
```

}

# Safe command execution with error handling

check() {
set +e
“$@”
local rc=$?
set -e
return “$rc”
}

# Enhanced retry with exponential backoff and jitter

retry_rc() {
local max_attempts=”$1” base_delay=”$2”
shift 2
[[ $# -gt 0 ]] || fatal 2 “retry_rc: no command specified”

```
_validate_numeric "$max_attempts" 1 100 "max_attempts"
_validate_numeric "$base_delay" 1 3600 "base_delay"

local attempt=1 delay="$base_delay" max_delay=$(_config RETRY_MAX_DELAY)

while (( attempt <= max_attempts )); do
    debug "attempt $attempt/$max_attempts: $*"
    
    if "$@"; then
        debug "retry_rc: success on attempt $attempt"
        return 0
    fi
    
    local rc=$?
    
    if (( attempt < max_attempts )); then
        # Add jitter (±25% of delay)
        local jitter=$(( (RANDOM % (delay / 2)) - (delay / 4) ))
        local actual_delay=$(( delay + jitter ))
        (( actual_delay < 1 )) && actual_delay=1
        
        warn "attempt $attempt failed (rc=$rc), retrying in ${actual_delay}s..."
        sleep "$actual_delay"
        
        # Exponential backoff with maximum
        delay=$(( delay * 2 ))
        (( delay > max_delay )) && delay=$max_delay
    else
        error "all $max_attempts attempts failed (final rc=$rc): $*"
    fi
    
    ((attempt++))
done

return "$rc"
```

}

# Retry with default parameters

retry() {
retry_rc “$(_config RETRY_COUNT)” “$(_config RETRY_BASE_DELAY)” “$@”
}

# Enhanced dependency checking with versions

require() {
local missing=() cmd
for cmd in “$@”; do
if ! _has_command “$cmd”; then
missing+=(”$cmd”)
fi
done

```
if (( ${#missing[@]} > 0 )); then
    error "Missing required commands: ${missing[*]}"
    fatal 127 "install missing dependencies: ${missing[*]}"
fi

note "All required commands available: $*"
```

}

# Enhanced require with version checking

require_version() {
local cmd=”$1” required_version=”$2”
require “$cmd”

```
# Basic version checking for common tools
local actual_version
case "$cmd" in
    curl)
        actual_version=$(curl --version 2>/dev/null | head -n1 | awk '{print $2}') ;;
    rsync)
        actual_version=$(rsync --version 2>/dev/null | head -n1 | awk '{print $3}') ;;
    *)
        warn "Version checking not implemented for: $cmd"
        return 0 ;;
esac

if [[ -n "$actual_version" ]]; then
    debug "$cmd version: $actual_version (required: $required_version)"
    # Note: Full semantic version comparison would require more complex logic
fi
```

}

# Device and partition utilities with enhanced error handling

wait_udev() {
if _has_command udevadm; then
debug “waiting for udev to settle…”
udevadm settle –timeout=30 || warn “udev settle timeout”
else
warn “udevadm not available, skipping udev settle”
sleep 2  # Fallback delay
fi
}

part_rescan() {
local device=”$1”
[[ -b “$device” ]] || fatal 6 “not a block device: $device”

```
_check_privileges device
debug "rescanning partition table: $device"

if _has_command partprobe; then
    partprobe "$device" 2>/dev/null || warn "partprobe failed for $device"
fi

if _has_command blockdev; then
    blockdev --rereadpt "$device" 2>/dev/null || warn "blockdev rereadpt failed for $device"
fi

wait_udev
```

}

# Enhanced partition suffix detection

partsuf() {
local device=”$1”
[[ “$device” =~ (nvme|mmcblk|loop) ]] && printf ‘p’ || printf ‘’
}

###############################################################################

# [ENHANCED DATA PLUMBING] Memory-efficient and safe operations

###############################################################################

# Memory-efficient join with large datasets

join_by() {
local delimiter=”$1”; shift
local first=1
for arg in “$@”; do
if (( first )); then
printf ‘%s’ “$arg”
first=0
else
printf ‘%s%s’ “$delimiter” “$arg”
fi
done
echo
}

# Enhanced NUL-delimited reading with size limits

read0() {
local var_name=”$1” max_items=”${2:-10000}”
shift
_validate_numeric “$max_items” 1 100000 “max_items”

```
local -a items=()
local count=0

while IFS= read -r -d '' item && (( count < max_items )); do
    items+=("$item")
    ((count++))
done

if (( count >= max_items )); then
    warn "read0: hit maximum item limit ($max_items), data may be truncated"
fi

# Assign to the named variable
declare -n target_array="$var_name"
target_array=("${items[@]}")
```

}

# Enhanced file counting with pattern validation

count_files() {
local dir=”$1” pattern=”${2:-*}”
[[ -d “$dir” ]] || { warn “not a directory: $dir”; echo 0; return; }

```
local -a files=()
while IFS= read -r -d '' file; do
    files+=("$file")
done < <(find "$dir" -maxdepth 1 -type f -name "$pattern" -print0 2>/dev/null)

echo "${#files[@]}"
```

}

# Safe array operations with bounds checking

array_get() {
local -n arr_ref=”$1”
local index=”$2” default=”${3:-}”

```
if (( index >= 0 && index < ${#arr_ref[@]} )); then
    echo "${arr_ref[$index]}"
else
    echo "$default"
fi
```

}

array_push() {
local -n arr_ref=”$1”
shift
arr_ref+=(”$@”)
}

array_pop() {
local -n arr_ref=”$1”
local last_index=$(( ${#arr_ref[@]} - 1 ))
if (( last_index >= 0 )); then
echo “${arr_ref[$last_index]}”
unset “arr_ref[$last_index]”
fi
}

###############################################################################

# [ENHANCED LOCKING] Read/write locks, cleanup, and monitoring

###############################################################################

declare -A _ACTIVE_LOCKS=()

# Initialize locking subsystem

lock_init() {
local lock_root=”${1:-/run/lock/archlib}”
LOCK_ROOT=”$lock_root”
install -d -m 0755 – “$LOCK_ROOT”

```
# Clean up stale locks on init
_cleanup_stale_locks

note "Lock system initialized: $LOCK_ROOT"
```

}

# Alias for backward compatibility

lock_root_init() { lock_init “$@”; }

# Clean up stale locks

_cleanup_stale_locks() {
local max_age=$(_config MAX_LOCK_AGE)
local now=$(date +%s)

```
while IFS= read -r -d '' lock_file; do
    local age=$(( now - $(stat -c %Y "$lock_file" 2>/dev/null || echo "$now") ))
    if (( age > max_age )); then
        warn "Removing stale lock: $lock_file (age: ${age}s)"
        rm -f "$lock_file" 2>/dev/null || true
    fi
done < <(find "${LOCK_ROOT:-/run/lock}" -name "*.lock" -print0 2>/dev/null)
```

}

# Global single-instance lock with enhanced error handling

single_instance_lock() {
local lock_path=”$1” timeout=”${2:-$(_config LOCK_TIMEOUT)}”
[[ -n “$lock_path” ]] || fatal 2 “single_instance_lock: lock path required”

```
lock_path=$(_sanitize_path "$lock_path")
_validate_timeout "$timeout"

local lock_dir
lock_dir=$(dirname "$lock_path")
install -d -m 0755 -- "$lock_dir"

exec 9>"$lock_path" || fatal 98 "cannot create lock file: $lock_path"

if ! flock -n 9; then
    if (( timeout > 0 )); then
        note "waiting for lock: $lock_path (timeout: ${timeout}s)"
        flock -w "$timeout" 9 || fatal 99 "lock timeout: $lock_path"
    else
        fatal 99 "another instance is running: $lock_path"
    fi
fi

# Write PID and timestamp to lock file
printf 'pid=%d\nstart=%s\nhost=%s\n' "$$" "$(date -u +%FT%TZ)" "${HOSTNAME:-unknown}" >&9

_ACTIVE_LOCKS["$lock_path"]=9
note "acquired global lock: $lock_path"
```

}

# Enhanced lock acquisition with read/write differentiation

with_lock() {
local lock_name=”$1” timeout=”${2:-$(_config LOCK_TIMEOUT)}” lock_type=”${3:-exclusive}”
shift 3
[[ $# -gt 0 ]] || fatal 2 “with_lock: no command specified”

```
_validate_timeout "$timeout"
[[ "$lock_type" =~ ^(exclusive|shared)$ ]] || fatal 2 "invalid lock type: $lock_type"

local lock_path="${LOCK_ROOT:-/run/lock}/$(echo "$lock_name" | tr '/:' '__').lock"
lock_path=$(_sanitize_path "$lock_path")

debug "acquiring $lock_type lock: $lock_name"

# Open lock file
exec {lock_fd}> "$lock_path" || fatal 98 "cannot open lock: $lock_path"

# Acquire lock with appropriate type
local flock_opts=()
if [[ "$lock_type" == "shared" ]]; then
    flock_opts+=(-s)  # Shared lock
else
    flock_opts+=(-x)  # Exclusive lock (default)
fi

if ! flock "${flock_opts[@]}" -w "$timeout" "$lock_fd"; then
    eval "exec $lock_fd>&-"
    fatal 99 "lock timeout: $lock_name"
fi

# Write lock info
printf 'pid=%d\nstart=%s\ntype=%s\nname=%s\n' "$$" "$(date -u +%FT%TZ)" "$lock_type" "$lock_name" >&"$lock_fd"

_ACTIVE_LOCKS["$lock_name"]=$lock_fd

# Execute command with error handling
local start_time=$SECONDS rc=0
"$@" || rc=$?
local duration=$((SECONDS - start_time))

# Release lock
flock -u "$lock_fd"
eval "exec $lock_fd>&-"
unset "_ACTIVE_LOCKS[$lock_name]"

debug "released $lock_type lock: $lock_name (held for ${duration}s)"
return "$rc"
```

}

# Shared lock wrapper

with_shared_lock() {
local lock_name=”$1” timeout=”${2:-$(_config LOCK_TIMEOUT)}”
shift 2
with_lock “$lock_name” “$timeout” shared “$@”
}

# Clean up all active locks

_cleanup_locks() {
local lock_name fd
for lock_name in “${!_ACTIVE_LOCKS[@]}”; do
fd=${_ACTIVE_LOCKS[$lock_name]}
debug “cleaning up lock: $lock_name (fd=$fd)”
flock -u “$fd” 2>/dev/null || true
eval “exec $fd>&-” 2>/dev/null || true
unset “_ACTIVE_LOCKS[$lock_name]”
done
}

# Enhanced mount/umount with better error handling

mount_locked() {
local -a mount_args=(”$@”)
local target=”${mount_args[-1]}”

```
_check_privileges mount
[[ -n "$target" ]] || fatal 2 "mount_locked: no target specified"

target=$(_sanitize_path "$target")

# Ensure mount point exists
install -d -m 0755 -- "$target"

with_lock "mnt:$target" "$(_config LOCK_TIMEOUT)" mount "${mount_args[@]}"

# Verify mount succeeded
if ! mountpoint -q "$target"; then
    fatal 32 "mount verification failed: $target"
fi

note "mounted: $target"
```

}

umount_locked() {
local mp=”$1” force=”${2:-false}”
[[ -n “$mp” ]] || fatal 2 “umount_locked: no mountpoint specified”

```
_check_privileges mount
mp=$(_sanitize_path "$mp")

if ! mountpoint -q "$mp"; then
    warn "not a mountpoint: $mp"
    return 0
fi

local umount_cmd=(umount)
[[ "$force" == "true" ]] && umount_cmd+=(-f)
umount_cmd+=(-R -- "$mp")

with_lock "mnt:$mp" "$(_config LOCK_TIMEOUT)" "${umount_cmd[@]}"

# Verify umount succeeded
if mountpoint -q "$mp"; then
    fatal 32 "umount verification failed: $mp"
fi

note "unmounted: $mp"
```

}

# Enhanced pacman lock handling with better timeout

wait_pacman_lock() {
local timeout=”${1:-$(_config PACMAN_LOCK_TIMEOUT)}”
_validate_timeout “$timeout”

```
local deadline=$((SECONDS + timeout))
local lock_file="/var/lib/pacman/db.lck"

while [[ -e "$lock_file" ]]; do
    if (( SECONDS >= deadline )); then
        error "pacman lock held too long, checking for stale lock..."
        
        # Check if the locking process still exists
        if [[ -r "$lock_file" ]]; then
            local lock_pid
            lock_pid=$(cat "$lock_file" 2>/dev/null || echo "")
            if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
                warn "removing stale pacman lock (pid $lock_pid not running)"
                rm -f "$lock_file" 2>/dev/null || true
                break
            fi
        fi
        
        fatal 97 "pacman lock timeout after ${timeout}s"
    fi
    
    debug "waiting for pacman lock to clear..."
    sleep 2
done

note "pacman lock cleared"
```

}

###############################################################################

# [ENHANCED READINESS CHECKS] More robust waiting and validation

###############################################################################

# Enhanced device waiting with udev integration

wait_for_dev() {
local device=”$1” timeout=”${2:-$(_config DEFAULT_TIMEOUT)}” check_type=”${3:-existence}”
[[ -n “$device” ]] || fatal 2 “wait_for_dev: device path required”

```
_validate_timeout "$timeout"
device=$(_sanitize_path "$device")

local deadline=$((SECONDS + timeout))
local check_interval=1

debug "waiting for device: $device (timeout: ${timeout}s, check: $check_type)"

while (( SECONDS < deadline )); do
    case "$check_type" in
        existence)
            [[ -e "$device" ]] && { note "device ready: $device"; return 0; } ;;
        block)
            [[ -b "$device" ]] && { note "block device ready: $device"; return 0; } ;;
        readable)
            [[ -r "$device" ]] && { note "device readable: $device"; return 0; } ;;
        writable)
            [[ -w "$device" ]] && { note "device writable: $device"; return 0; } ;;
        *)
            fatal 2 "invalid check type: $check_type" ;;
    esac
    
    # Trigger udev and wait progressively longer
    wait_udev
    sleep "$check_interval"
    (( check_interval < 5 )) && ((check_interval++))
done

error "device not ready: $device (timeout after ${timeout}s)"
return 1
```

}

# Enhanced mount assertion with detailed validation

assert_mount() {
local mountpoint=”$1” expected_source=”${2:-}” expected_subvol=”${3:-}”
[[ -n “$mountpoint” ]] || fatal 2 “assert_mount: mountpoint required”

```
mountpoint=$(_sanitize_path "$mountpoint")

if ! mountpoint -q "$mountpoint"; then
    fatal 32 "not mounted: $mountpoint"
fi

# Get mount information
local mount_info
mount_info=$(findmnt -no SOURCE,TARGET,FSTYPE,OPTIONS --target "$mountpoint" 2>/dev/null) || {
    fatal 32 "cannot get mount info: $mountpoint"
}

local actual_source actual_target actual_fstype actual_options
read -r actual_source actual_target actual_fstype actual_options <<< "$mount_info"

# Validate source if specified
if [[ -n "$expected_source" ]]; then
    if [[ "$actual_source" != "$expected_source" ]]; then
        fatal 32 "mount source mismatch: expected '$expected_source', got '$actual_source'"
    fi
fi

# Validate subvolume if specified
if [[ -n "$expected_subvol" ]]; then
    if [[ "$actual_options" != *"subvol=$expected_subvol"* ]]; then
        fatal 32 "subvolume mismatch: expected '$expected_subvol', options: $actual_options"
    fi
fi

debug "mount assertion passed: $mountpoint ($actual_source, $actual_fstype)"
note "verified mount: $mountpoint"
```

}

# Enhanced network readiness with multiple validation methods

net_ready() {
local host=”${1:-archlinux.org}” timeout=”${2:-$(_config DEFAULT_TIMEOUT)}” method=”${3:-dns}”
_validate_timeout “$timeout”

```
local deadline=$((SECONDS + timeout))

debug "checking network readiness: $host (method: $method, timeout: ${timeout}s)"

while (( SECONDS < deadline )); do
    case "$method" in
        dns)
            if getent hosts "$host" >/dev/null 2>&1; then
                note "network ready (DNS): $host"
                return 0
            fi ;;
        ping)
            if _has_command ping && ping -c1 -W2 "$host" >/dev/null 2>&1; then
                note "network ready (ping): $host"
                return 0
            fi ;;
        http)
            if _has_command curl && curl -s --connect-timeout 5 --max-time 10 "http://$host" >/dev/null 2>&1; then
                note "network ready (HTTP): $host"
                return 0
            fi ;;
        https)
            if _has_command curl && curl -s --connect-timeout 5 --max-time 10 "https://$host" >/dev/null 2>&1; then
                note "network ready (HTTPS): $host"
                return 0
            fi ;;
        *)
            fatal 2 "invalid network check method: $method" ;;
    esac
    
    sleep 2
done

error "network not ready: $host (method: $method, timeout after ${timeout}s)"
return 1
```

}

# Enhanced boot files check with detailed validation

bootfiles_ready() {
local boot_path=”$1”
[[ -d “$boot_path” ]] || { error “boot path not found: $boot_path”; return 1; }

```
boot_path=$(_sanitize_path "$boot_path")

local required_files=(
    "$boot_path/EFI/systemd/systemd-bootx64.efi"
    "$boot_path/loader/loader.conf"
)

local missing=()
for file in "${required_files[@]}"; do
    if [[ ! -f "$file" ]]; then
        missing+=("$file")
    fi
done

if (( ${#missing[@]} > 0 )); then
    error "missing boot files: ${missing[*]}"
    return 1
fi

# Additional validation
if [[ -f "$boot_path/loader/loader.conf" ]]; then
    if ! grep -q "^default\|^timeout\|^console-mode" "$boot_path/loader/loader.conf"; then
        warn "loader.conf appears incomplete"
    fi
fi

note "boot files ready: $boot_path"
return 0
```

}

# Enhanced snapper readiness check

snapper_ready() {
local root_path=”$1”
[[ -d “$root_path” ]] || { error “root path not found: $root_path”; return 1; }

```
root_path=$(_sanitize_path "$root_path")

local config_file="$root_path/etc/snapper/configs/root"
local snapshots_dir="$root_path/.snapshots"

if [[ ! -f "$config_file" ]]; then
    error "snapper config not found: $config_file"
    return 1
fi

if [[ ! -d "$snapshots_dir" ]]; then
    error "snapshots directory not found: $snapshots_dir"
    return 1
fi

# Check if snapper config is valid
if ! grep -q "^SUBVOLUME=" "$config_file"; then
    error "invalid snapper config: $config_file"
    return 1
fi

note "snapper ready: $root_path"
return 0
```

}

###############################################################################

# [ENHANCED NETWORK & FILE OPERATIONS] Better error handling and features

###############################################################################

# Enhanced HTTP GET with comprehensive error handling and validation

http_get() {
local url=”$1” output_file=”${2:-}” timeout=”${3:-$(_config HTTP_TIMEOUT)}”
[[ -n “$url” ]] || fatal 2 “http_get: URL required”

```
# Basic URL validation
if [[ ! "$url" =~ ^https?:// ]]; then
    fatal 2 "invalid URL: $url"
fi

_validate_timeout "$timeout"

local temp_file=""
if [[ -n "$output_file" ]]; then
    output_file=$(_sanitize_path "$output_file")
    local output_dir
    output_dir=$(dirname "$output_file")
    _check_disk_space "$output_dir"
    
    # Use temporary file for atomic writes
    temp_file=$(mktemp "${output_file}.tmp.XXXXXX")
    trap "rm -f '$temp_file'" RETURN
fi

debug "downloading: $url${output_file:+ -> $output_file}"

local start_time=$SECONDS rc=0

if _has_command curl; then
    local curl_args=(
        --fail-with-body
        --location
        --retry 3
        --retry-delay 2
        --retry-connrefused
        --max-time "$timeout"
        --connect-timeout 10
        --silent
        --show-error
        --user-agent "archlib/2.0"
        --proto "=http,https"
        --tlsv1.2
    )
    
    if [[ -n "$temp_file" ]]; then
        curl "${curl_args[@]}" --output "$temp_file" -- "$url" || rc=$?
    else
        curl "${curl_args[@]}" -- "$url" || rc=$?
    fi
    
elif _has_command wget; then
    local wget_args=(
        --retry-connrefused
        --tries=5
        --waitretry=2
        --timeout="$timeout"
        --connect-timeout=10
        --quiet
        --show-progress
        --user-agent="archlib/2.0"
        --secure-protocol=TLSv1_2
    )
    
    if [[ -n "$temp_file" ]]; then
        wget "${wget_args[@]}" -O "$temp_file" -- "$url" || rc=$?
    else
        wget "${wget_args[@]}" -O - -- "$url" || rc=$?
    fi
    
else
    fatal 127 "neither curl nor wget available"
fi

local duration=$((SECONDS - start_time))

if (( rc == 0 )); then
    if [[ -n "$temp_file" ]]; then
        # Validate downloaded file
        if [[ ! -s "$temp_file" ]]; then
            fatal 25 "downloaded file is empty: $url"
        fi
        
        # Atomic move
        mv "$temp_file" "$output_file"
        note "downloaded: $url -> $output_file (${duration}s)"
    else
        debug "downloaded: $url (${duration}s)"
    fi
else
    error "download failed: $url (rc=$rc, ${duration}s)"
    return "$rc"
fi
```

}

# Enhanced HTTP GET with checksum verification

http_get_verified() {
local url=”$1” output_file=”$2” expected_checksum=”${3:-}” checksum_type=”${4:-sha256}”

```
http_get "$url" "$output_file"

if [[ -n "$expected_checksum" ]]; then
    verify_checksum "$output_file" "$expected_checksum" "$checksum_type"
fi
```

}

# Checksum verification

verify_checksum() {
local file=”$1” expected=”$2” type=”${3:-sha256}”
[[ -f “$file” ]] || fatal 2 “file not found: $file”
[[ -n “$expected” ]] || fatal 2 “expected checksum required”

```
local actual_checksum
case "$type" in
    md5)    actual_checksum=$(md5sum "$file" | cut -d' ' -f1) ;;
    sha1)   actual_checksum=$(sha1sum "$file" | cut -d' ' -f1) ;;
    sha256) actual_checksum=$(sha256sum "$file" | cut -d' ' -f1) ;;
    sha512) actual_checksum=$(sha512sum "$file" | cut -d' ' -f1) ;;
    *) fatal 2 "unsupported checksum type: $type" ;;
esac

if [[ "$actual_checksum" != "$expected" ]]; then
    fatal 26 "checksum mismatch: expected $expected, got $actual_checksum"
fi

note "checksum verified: $file ($type)"
```

}

# Enhanced rsync with better progress and error handling

rsync_safe() {
local source=”$1” destination=”$2”
shift 2
[[ -n “$source” && -n “$destination” ]] || fatal 2 “rsync_safe: source and destination required”

```
source=$(_sanitize_path "$source")
destination=$(_sanitize_path "$destination")

# Check disk space at destination
local dest_dir
dest_dir=$(dirname "$destination")
_check_disk_space "$dest_dir"

local rsync_args=(
    --archive
    --partial
    --inplace
    --checksum
    --delete-delay
    --mkpath
    --human-readable
    --info=progress2,stats2
    --timeout=300
    --contimeout=60
)

# Add bandwidth limiting if available
if [[ -n "${RSYNC_BWLIMIT:-}" ]]; then
    rsync_args+=(--bwlimit="$RSYNC_BWLIMIT")
fi

debug "rsync: $source -> $destination"

local start_time=$SECONDS
rsync "${rsync_args[@]}" "$source" "$destination" "$@"
local duration=$((SECONDS - start_time))

note "rsync completed: $source -> $destination (${duration}s)"
```

}

# Enhanced tar with reproducible builds and compression

tar_repro() {
local output=”$1” source_dir=”$2” compression=”${3:-none}”
[[ -n “$output” && -d “$source_dir” ]] || fatal 2 “tar_repro: output file and source directory required”

```
output=$(_sanitize_path "$output")
source_dir=$(_sanitize_path "$source_dir")

local tar_args=(
    --create
    --file="$output"
    --numeric-owner
    --owner=0
    --group=0
    --mtime='@0'
    --sort=name
    --format=posix
    -C "$source_dir"
)

# Add compression if specified
case "$compression" in
    gzip|gz)   tar_args+=(--gzip) ;;
    bzip2|bz2) tar_args+=(--bzip2) ;;
    xz)        tar_args+=(--xz) ;;
    zstd)      tar_args+=(--zstd) ;;
    none)      ;;
    *) fatal 2 "unsupported compression: $compression" ;;
esac

debug "creating reproducible tar: $output (compression: $compression)"

tar "${tar_args[@]}" .

note "created reproducible tar: $output"
```

}

###############################################################################

# [ENHANCED SYSTEMD HELPERS] Better integration and error handling

###############################################################################

# Check if systemd is available

_require_systemd() {
(( ARCHLIB_HAS_SYSTEMD )) || fatal 95 “systemd not available on this system”
}

# Enhanced systemd unit status checking

systemctl_up() {
local unit=”$1” timeout=”${2:-$(_config DEFAULT_TIMEOUT)}” check_ports=”${3:-}”
[[ -n “$unit” ]] || fatal 2 “systemctl_up: unit name required”

```
_require_systemd
_validate_timeout "$timeout"

debug "starting systemd unit: $unit (timeout: ${timeout}s)"

# Start the unit
systemctl start "$unit" || {
    error "failed to start unit: $unit"
    _show_unit_logs "$unit"
    return 1
}

local deadline=$((SECONDS + timeout))
local check_interval=1

while (( SECONDS < deadline )); do
    local state substate
    state=$(systemctl show -p ActiveState --value "$unit" 2>/dev/null || echo "unknown")
    substate=$(systemctl show -p SubState --value "$unit" 2>/dev/null || echo "unknown")
    
    debug "unit $unit: state=$state, substate=$substate"
    
    case "$state" in
        active)
            case "$substate" in
                running|listening|exited)
                    # Additional port checking if specified
                    if [[ -n "$check_ports" ]]; then
                        _check_unit_ports "$unit" "$check_ports" || {
                            sleep "$check_interval"
                            continue
                        }
                    fi
                    note "unit ready: $unit ($state/$substate)"
                    return 0 ;;
            esac ;;
        failed)
            error "unit failed: $unit"
            _show_unit_logs "$unit"
            return 1 ;;
    esac
    
    sleep "$check_interval"
    (( check_interval < 5 )) && ((check_interval++))
done

error "unit start timeout: $unit (${timeout}s)"
_show_unit_logs "$unit"
return 1
```

}

# Show recent logs for a unit

_show_unit_logs() {
local unit=”$1” lines=”${2:-50}”
error “Recent logs for $unit:”
journalctl -u “$unit” –no-pager –lines=”$lines” –output=short-iso >&2 || true
}

# Check if unit is listening on expected ports

_check_unit_ports() {
local unit=”$1” ports=”$2”

```
# Get the main PID of the unit
local main_pid
main_pid=$(systemctl show -p MainPID --value "$unit" 2>/dev/null)
[[ "$main_pid" != "0" ]] || return 1

# Check each port
local port
for port in ${ports//,/ }; do
    if ! ss -ln | grep -q ":$port "; then
        debug "port $port not yet listening for unit $unit"
        return 1
    fi
done

debug "all ports listening for unit $unit: $ports"
return 0
```

}

# Enhanced systemd unit status checks

systemctl_enabled() {
local unit=”$1”
[[ -n “$unit” ]] || fatal 2 “systemctl_enabled: unit name required”

```
_require_systemd
systemctl is-enabled --quiet "$unit"
```

}

systemctl_active() {
local unit=”$1”
[[ -n “$unit” ]] || fatal 2 “systemctl_active: unit name required”

```
_require_systemd
systemctl is-active --quiet "$unit"
```

}

systemctl_running() {
local unit=”$1”
[[ -n “$unit” ]] || fatal 2 “systemctl_running: unit name required”

```
_require_systemd
[[ "$(systemctl show -p SubState --value "$unit" 2>/dev/null)" == "running" ]]
```

}

# Wait for systemd unit to stop

systemctl_down() {
local unit=”$1” timeout=”${2:-$(_config DEFAULT_TIMEOUT)}”
[[ -n “$unit” ]] || fatal 2 “systemctl_down: unit name required”

```
_require_systemd
_validate_timeout "$timeout"

debug "stopping systemd unit: $unit (timeout: ${timeout}s)"

systemctl stop "$unit" || warn "failed to stop unit: $unit"

local deadline=$((SECONDS + timeout))

while (( SECONDS < deadline )); do
    local state
    state=$(systemctl show -p ActiveState --value "$unit" 2>/dev/null || echo "unknown")
    
    if [[ "$state" == "inactive" ]]; then
        note "unit stopped: $unit"
        return 0
    fi
    
    sleep 1
done

error "unit stop timeout: $unit (${timeout}s)"
return 1
```

}

# Restart unit with proper waiting

systemctl_restart() {
local unit=”$1” timeout=”${2:-$(_config DEFAULT_TIMEOUT)}”

```
debug "restarting systemd unit: $unit"
systemctl_down "$unit" "$timeout"
systemctl_up "$unit" "$timeout"
```

}

###############################################################################

# [MONITORING & METRICS] Performance and health monitoring

###############################################################################

declare -A _METRICS=()

# Record a metric

metric_record() {
local name=”$1” value=”$2” timestamp=”${3:-$(date +%s)}”
[[ -n “$name” && -n “$value” ]] || return 1

```
_METRICS["${name}_${timestamp}"]="$value"
debug "metric: $name=$value @$timestamp"
```

}

# Get metric history

metric_get() {
local name=”$1” limit=”${2:-10}”
local pattern=”${name}_”

```
for key in "${!_METRICS[@]}"; do
    if [[ "$key" =~ ^${pattern}([0-9]+)$ ]]; then
        local timestamp="${BASH_REMATCH[1]}"
        echo "$timestamp ${_METRICS[$key]}"
    fi
done | sort -n | tail -n "$limit"
```

}

# Performance timing wrapper

time_command() {
local name=”$1”; shift
[[ -n “$name” ]] || fatal 2 “time_command: metric name required”

```
local start_time=$SECONDS
"$@"
local rc=$?
local duration=$((SECONDS - start_time))

metric_record "duration_$name" "$duration"
debug "timed command '$name': ${duration}s (rc=$rc)"

return "$rc"
```

}

# System resource monitoring

monitor_resources() {
local interval=”${1:-60}” duration=”${2:-3600}”

```
debug "starting resource monitoring (interval: ${interval}s, duration: ${duration}s)"

local end_time=$((SECONDS + duration))

while (( SECONDS < end_time )); do
    # CPU usage
    if _has_command top; then
        local cpu_usage
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
        metric_record "cpu_usage" "$cpu_usage"
    fi
    
    # Memory usage
    if [[ -r /proc/meminfo ]]; then
        local mem_total mem_available mem_used_pct
        mem_total=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
        mem_available=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
        mem_used_pct=$(( (mem_total - mem_available) * 100 / mem_total ))
        metric_record "memory_usage_pct" "$mem_used_pct"
    fi
    
    # Disk usage for important paths
    if _has_command df; then
        local path usage
        for path in / /tmp /var; do
            if [[ -d "$path" ]]; then
                usage=$(df "$path" | awk 'NR==2 {print $5}' | tr -d '%')
                metric_record "disk_usage_${path//\//_}" "$usage"
            fi
        done
    fi
    
    # Load average
    if [[ -r /proc/loadavg ]]; then
        local load1
        load1=$(cut -d' ' -f1 /proc/loadavg)
        metric_record "load_avg_1min" "$load1"
    fi
    
    sleep "$interval"
done
```

}

# Health check function

health_check() {
local checks=(”${@:-disk memory load}”)
local overall_status=0

```
note "running health checks: ${checks[*]}"

for check in "${checks[@]}"; do
    case "$check" in
        disk)
            local usage
            usage=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
            if (( usage > 90 )); then
                error "disk usage critical: ${usage}%"
                overall_status=1
            elif (( usage > 80 )); then
                warn "disk usage high: ${usage}%"
            else
                debug "disk usage ok: ${usage}%"
            fi ;;
        memory)
            if [[ -r /proc/meminfo ]]; then
                local mem_total mem_available mem_used_pct
                mem_total=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
                mem_available=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
                mem_used_pct=$(( (mem_total - mem_available) * 100 / mem_total ))
                
                if (( mem_used_pct > 95 )); then
                    error "memory usage critical: ${mem_used_pct}%"
                    overall_status=1
                elif (( mem_used_pct > 85 )); then
                    warn "memory usage high: ${mem_used_pct}%"
                else
                    debug "memory usage ok: ${mem_used_pct}%"
                fi
            fi ;;
        load)
            if [[ -r /proc/loadavg ]]; then
                local load1 cpu_count
                load1=$(cut -d' ' -f1 /proc/loadavg)
                cpu_count=$(nproc 2>/dev/null || echo 1)
                
                # Convert to integer comparison (multiply by 100)
                local load_int=$(printf '%.0f' "$(echo "$load1 * 100" | bc 2>/dev/null || echo "0")")
                local threshold_int=$((cpu_count * 200)) # 2.0 * CPU count
                
                if (( load_int > threshold_int )); then
                    error "load average high: $load1 (cpus: $cpu_count)"
                    overall_status=1
                else
                    debug "load average ok: $load1"
                fi
            fi ;;
        *)
            warn "unknown health check: $check" ;;
    esac
done

if (( overall_status == 0 )); then
    note "all health checks passed"
else
    error "some health checks failed"
fi

return "$overall_status"
```

}

###############################################################################

# [INITIALIZATION] Library setup and compatibility checks

###############################################################################

# Initialize the library

_archlib_init() {
# Prevent multiple initialization
[[ -z “${_ARCHLIB_INITIALIZED:-}” ]] || return 0

```
# Basic compatibility checks
_check_bash_version
_detect_platform

# Load configuration
_load_config

# Set up error handling
set -euo pipefail
# Note: ERR trap is opt-in via: trap _errtrap ERR

# Initialize subsystems with defaults
lock_init "${LOCK_ROOT:-/run/lock/archlib}"

# Start background timers if logging is enabled
if [[ -n "${LOG:-}" ]]; then
    _start_log_batch_timer
fi

# Mark as initialized
declare -g _ARCHLIB_INITIALIZED=1

debug "archlib initialized (platform: $ARCHLIB_PLATFORM, bash: $BASH_VERSION)"
```

}

# Auto-initialize when sourced

_archlib_init

# Export key functions for subshells

export -f note warn error fatal debug
export -f must check retry require
export -f http_get rsync_safe
export -f with_lock mount_locked umount_locked
export -f wait_for_dev net_ready
export -f systemctl_up systemctl_enabled

###############################################################################

# [LIBRARY METADATA] Version and feature information

###############################################################################

archlib_version() { echo “2.0.0”; }
archlib_features() {
echo “Enhanced bash scripting library with:”
echo “  - Comprehensive error handling and logging”
echo “  - Advanced locking with read/write support”
echo “  - Performance monitoring and health checks”
echo “  - Secure file operations and input validation”
echo “  - Enhanced network and system utilities”
echo “  - Platform compatibility and graceful degradation”
echo “  - Structured logging with NDJSON events”
echo “  - Resource management and cleanup”
}

# Show current configuration

archlib_config() {
echo “Current configuration:”
local key
for key in “${!ARCHLIB_CONFIG[@]}”; do
printf “  %-20s = %s\n” “$key” “${ARCHLIB_CONFIG[$key]}”
done
echo “Platform: $ARCHLIB_PLATFORM”
echo “Systemd: $(_has_command systemctl && echo “available” || echo “not available”)”
echo “Lock root: ${LOCK_ROOT:-not set}”
echo “Log file: ${LOG:-not set}”
}

# Library self-test

archlib_selftest() {
note “running archlib self-test…”

```
local tests_passed=0 tests_total=0

# Test basic functions
((tests_total++))
if join_by "," a b c | grep -q "a,b,c"; then
    ((tests_passed++))
    debug "✓ join_by function works"
else
    error "✗ join_by function failed"
fi

# Test validation functions
((tests_total++))
if _validate_numeric 42 1 100 "test" 2>/dev/null; then
    ((tests_passed++))
    debug "✓ numeric validation works"
else
    error "✗ numeric validation failed"
fi

# Test command caching
((tests_total++))
if _has_command bash; then
    ((tests_passed++))
    debug "✓ command caching works"
else
    error "✗ command caching failed"
fi

# Test path sanitization
((tests_total++))
local sanitized
sanitized=$(_sanitize_path "/tmp/../tmp/test")
if [[ "$sanitized" == "/tmp/test" ]]; then
    ((tests_passed++))
    debug "✓ path sanitization works"
else
    error "✗ path sanitization failed: got '$sanitized'"
fi

# Results
note "self-test completed: $tests_passed/$tests_total tests passed"

if (( tests_passed == tests_total )); then
    note "✓ All tests passed"
    return 0
else
    error "✗ Some tests failed"
    return 1
fi
```

}
