#!/usr/bin/env bash
# lib/preflight.sh — Pre-flight environment checks

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script requires root privileges. Run with 'sudo'."
        exit 1
    fi
}

check_enigma2() {
    if ! has_command opkg; then
        log_error "opkg not found. This script must be run on an Enigma2 device."
        exit 1
    fi
    if [[ ! -f "$E2_SETTINGS" ]]; then
        log_warn "$E2_SETTINGS not found. Enigma2 may be freshly installed."
    fi
}

check_network() {
    log_info "Checking internet connectivity..."
    local hosts=("8.8.8.8" "1.1.1.1" "updates.mynonpublic.com")
    for host in "${hosts[@]}"; do
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            log_ok "Connection OK ($host reachable)"
            return 0
        fi
    done
    log_error "No internet connection. Please check your network."
    exit 1
}

check_disk_space() {
    local available_mb
    available_mb="$(df -m / | awk 'NR==2 {print $4}')"
    if [[ "$available_mb" -lt "$MIN_FREE_SPACE_MB" ]]; then
        log_error "Insufficient disk space: ${available_mb}MB (minimum ${MIN_FREE_SPACE_MB}MB required)"
        exit 1
    fi
    log_ok "Disk space OK (${available_mb}MB free)"
}

run_preflight_checks() {
    log_step "Pre-flight Checks"
    check_root
    check_enigma2
    check_network
    check_disk_space
    mkdir -p "$LOG_DIR" "$BACKUP_DIR"
    log_info "Log file: $LOG_FILE"
}
