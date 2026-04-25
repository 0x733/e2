#!/usr/bin/env bash
# modules/bloatware.sh — Removal of unused pre-installed packages

mod_remove_bloatware() {
    [[ $SKIP_BLOATWARE -eq 1 ]] && { log_info "Bloatware removal skipped"; return 0; }
    log_step "Bloatware Removal"

    for pkg in "${BLOATWARE[@]}"; do
        if ! is_installed "$pkg"; then
            log_debug "Not installed: $pkg"
            continue
        fi
        if run opkg remove --force-depends "$pkg"; then
            log_ok "Removed: $pkg"
            ((REMOVED++))
            invalidate_pkg_cache
        else
            log_warn "Could not remove: $pkg"
        fi
    done
    log_info "Total packages removed: $REMOVED"
}
