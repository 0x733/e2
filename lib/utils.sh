#!/usr/bin/env bash
# lib/utils.sh — run wrapper, user prompts, opkg helpers, and lock management

# Executes arguments directly; logs only in dry-run mode.
run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "$*"
        return 0
    fi
    log_debug "Executing: $*"
    "$@"
}

# Prompts for confirmation; skipped when --force is active.
confirm() {
    local prompt="${1:-Continue?}"
    [[ $FORCE -eq 1 ]] && return 0
    read -r -p "$(printf "%b%s [y/e/N]: %b" "$C_YELLOW" "$prompt" "$C_RESET")" reply
    [[ "$reply" =~ ^[YyEe]$ ]]
}

has_command() { command -v "$1" >/dev/null 2>&1; }

# Returns total RAM in megabytes.
get_total_ram_mb() {
    awk '/^MemTotal/ {print int($2/1024)}' /proc/meminfo
}

# Package list is cached on first call to avoid repeated opkg invocations.
# Call invalidate_pkg_cache after install/remove operations.
_INSTALLED_CACHE=""
is_installed() {
    if [[ -z "$_INSTALLED_CACHE" ]]; then
        _INSTALLED_CACHE="$(opkg list-installed 2>/dev/null)"
    fi
    echo "$_INSTALLED_CACHE" | grep -q "^$1 "
}

invalidate_pkg_cache() { _INSTALLED_CACHE=""; }

# Downloads a file and optionally verifies its SHA-256 checksum.
# If no expected checksum is supplied, shows the actual hash and prompts
# the user before proceeding — never silently executes unverified content.
download_verified() {
    local url="$1" dest="$2" expected_sha256="${3:-}"

    log_info "Downloading: $url"
    if ! wget -q --timeout=30 -O "$dest" "$url"; then
        log_error "Download failed: $url"
        rm -f "$dest"
        return 1
    fi

    local actual
    actual="$(sha256sum "$dest" | cut -d' ' -f1)"

    if [[ -n "$expected_sha256" ]]; then
        if [[ "$actual" != "$expected_sha256" ]]; then
            log_error "Checksum mismatch for $(basename "$dest")"
            log_error "  Expected: $expected_sha256"
            log_error "  Actual:   $actual"
            rm -f "$dest"
            return 1
        fi
        log_ok "Checksum verified: $(basename "$dest")"
    else
        log_warn "No expected checksum — SHA-256: $actual"
        confirm "Proceed with unverified script?" || { rm -f "$dest"; return 1; }
    fi
}

acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid
        pid="$(cat "$LOCK_FILE" 2>/dev/null || echo "")"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_error "Another setup process is running (PID: $pid). If stale: rm $LOCK_FILE"
            exit 1
        fi
        log_warn "Stale lock file found, removing"
        rm -f "$LOCK_FILE"
    fi
    echo "$$" > "$LOCK_FILE"
}
