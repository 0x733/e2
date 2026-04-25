#!/usr/bin/env bash
# modules/emulators.sh — Levi45 emulator installer

mod_install_emulators() {
    [[ $SKIP_EMULATORS -eq 1 ]] && { log_info "Emulator installation skipped"; return 0; }
    log_step "Emulator Installation (Levi45)"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "opkg install oscam-emu (pre-install attempt)"
        log_dry "download_verified '$EMULATOR_URL' then execute"
        return 0
    fi

    # Pre-install oscam via opkg so the Levi45 installer finds it already
    # present and skips its own download step (which often fails on restricted
    # networks or when the upstream URL is temporarily unavailable).
    _emulators_preinstall_oscam

    local installer
    installer="$(mktemp /tmp/e2-emulator-XXXXXX.sh)"

    if ! download_verified "$EMULATOR_URL" "$installer"; then
        rm -f "$installer"
        return 1
    fi

    log_info "Executing emulator installer..."
    local out rc
    out="$(bash "$installer" 2>&1)"
    rc=$?
    rm -f "$installer"

    if [[ $rc -eq 0 ]]; then
        log_ok "Emulator installed successfully"
    else
        log_error "Emulator installer failed (exit: $rc)"
        # Surface the last lines of installer output for diagnosis
        local line
        while IFS= read -r line; do
            [[ -n "$line" ]] && log_error "  installer: $line"
        done < <(printf '%s\n' "$out" | tail -10)
        return 1
    fi
}

_emulators_preinstall_oscam() {
    if is_installed "oscam-emu"; then
        log_ok "oscam-emu already installed — Levi45 will skip download"
        return 0
    fi

    log_info "Attempting to pre-install oscam-emu via opkg..."
    local out rc
    out="$(opkg install oscam-emu 2>&1)"
    rc=$?

    if [[ $rc -eq 0 ]]; then
        log_ok "oscam-emu pre-installed via opkg — Levi45 will skip download"
        invalidate_pkg_cache
    else
        local reason
        reason="$(printf '%s\n' "$out" | grep -i 'error\|not found\|unknown' | head -1)"
        log_info "oscam-emu not available via opkg${reason:+ (${reason})} — Levi45 installer will download it"
    fi
}
