#!/usr/bin/env bash
# modules/ntp.sh — NTP time synchronization
#
# Enigma2 devices typically have no hardware RTC and reset to epoch on cold boot.
# Incorrect time breaks TLS certificate validation, EPG schedules, and recordings.

mod_configure_ntp() {
    log_step "NTP Time Synchronization"

    local current_year
    current_year="$(date +%Y)"
    if [[ "$current_year" -lt 2020 ]]; then
        log_warn "System time appears wrong (year: $current_year) — NTP sync is critical"
    else
        log_info "Current time: $(date)"
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "ntpdate -b -u pool.ntp.org"
        return 0
    fi

    if ! has_command ntpdate; then
        log_info "ntpdate not found — installing..."
        run opkg install ntpdate || {
            log_warn "ntpdate installation failed — skipping time sync"
            return 0
        }
    fi

    local synced=0
    for server in pool.ntp.org time.google.com time.cloudflare.com; do
        if ntpdate -b -u "$server" >/dev/null 2>&1; then
            log_ok "Time synchronized via $server: $(date)"
            synced=1
            break
        fi
    done

    if [[ $synced -eq 0 ]]; then
        log_warn "NTP sync failed on all servers — check network connectivity"
    fi
}
