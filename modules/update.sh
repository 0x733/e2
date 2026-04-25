#!/usr/bin/env bash
# modules/update.sh — System package list update and upgrade

mod_update_system() {
    [[ $SKIP_UPDATE -eq 1 ]] && { log_info "System update skipped"; return 0; }
    log_step "System Update"

    run opkg update || { log_error "opkg update failed"; return 1; }
    log_ok "Package list updated"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "opkg list-upgradable | opkg upgrade"
        return 0
    fi

    local upgradable
    upgradable="$(opkg list-upgradable 2>/dev/null | wc -l)"
    log_info "Upgradable packages: $upgradable"

    if [[ $upgradable -gt 0 ]]; then
        run opkg upgrade && log_ok "System upgraded" \
            || log_warn "Some packages could not be upgraded"
    else
        log_ok "System is already up to date"
    fi
}
