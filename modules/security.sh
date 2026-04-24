#!/usr/bin/env bash
# modules/security.sh — CA certificate installation and download integrity

mod_install_ca_certs() {
    log_step "CA Certificates"

    if is_installed "ca-certificates"; then
        log_ok "ca-certificates already installed"
        return 0
    fi

    if run opkg install ca-certificates; then
        log_ok "ca-certificates installed — HTTPS verification enabled"
        ((INSTALLED++))
    else
        log_warn "ca-certificates could not be installed — HTTPS verification may fail"
    fi
}
