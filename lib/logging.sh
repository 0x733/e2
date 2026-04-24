#!/usr/bin/env bash
# lib/logging.sh — Leveled, color-coded logging with optional file output

_log() {
    local level="$1"; shift
    local color="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    printf "%b[%s] [%s]%b %s\n" "$color" "$ts" "$level" "$C_RESET" "$msg"
    if [[ -d "$LOG_DIR" ]]; then
        printf "[%s] [%s] %s\n" "$ts" "$level" "$msg" >> "$LOG_FILE"
    fi
}

log_info()  { _log "INFO " "$C_BLUE"   "$@"; }
log_ok()    { _log " OK  " "$C_GREEN"  "$@"; }
log_warn()  { _log "WARN " "$C_YELLOW" "$@"; ((WARNINGS++)); }
log_error() { _log "ERROR" "$C_RED"    "$@"; ((ERRORS++)); }
log_debug() { [[ $VERBOSE -eq 1 ]] && _log "DEBUG" "$C_CYAN" "$@" || true; }
log_dry()   { _log " DRY " "$C_YELLOW" "$@"; }

log_step() {
    echo
    printf "%b━━━ %s ━━━%b\n" "$C_CYAN$C_BOLD" "$*" "$C_RESET"
    [[ -d "$LOG_DIR" ]] && printf "\n=== %s ===\n" "$*" >> "$LOG_FILE"
}
