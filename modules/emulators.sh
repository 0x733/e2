#!/usr/bin/env bash
# modules/emulators.sh — Levi45 emulator installer

mod_install_emulators() {
    [[ $SKIP_EMULATORS -eq 1 ]] && { log_info "Emulator installation skipped"; return 0; }
    log_step "Emulator Installation (Levi45)"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "wget '$EMULATOR_URL' | bash"
        return 0
    fi

    if wget -qO- "$EMULATOR_URL" | bash; then
        log_ok "Emulator installed successfully"
    else
        log_error "Emulator installation failed"
    fi
}
