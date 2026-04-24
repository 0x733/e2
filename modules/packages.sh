#!/usr/bin/env bash
# modules/packages.sh — Base plugin installation and feed configuration

# Installs a list of packages; skips already-installed ones (idempotent).
install_packages() {
    local label="$1"; shift
    local packages=("$@")

    log_info "Installing $label (${#packages[@]} packages)..."
    for pkg in "${packages[@]}"; do
        if is_installed "$pkg"; then
            log_ok "Already installed: $pkg"
            ((ALREADY_INSTALLED++))
            continue
        fi
        if run opkg install "$pkg"; then
            log_ok "Installed: $pkg"
            ((INSTALLED++))
        else
            log_error "Failed to install: $pkg"
        fi
    done
}

mod_install_base_plugins() {
    log_step "Base Plugins"
    install_packages "base plugins" "${BASE_PLUGINS[@]}"
}

mod_configure_feeds() {
    log_step "OE-Alliance Feed"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "download_verified '$FEED_OEA_URL' then execute"
    else
        local installer
        installer="$(mktemp /tmp/e2-feed-XXXXXX.sh)"

        if download_verified "$FEED_OEA_URL" "$installer"; then
            log_info "Executing feed installer..."
            if bash "$installer"; then
                log_ok "Feed added"
            else
                log_error "Feed installer execution failed"
                rm -f "$installer"
                return 1
            fi
        else
            return 1
        fi
        rm -f "$installer"
    fi

    run opkg update
    install_packages "post-feed plugins" "${POST_FEED_PLUGINS[@]}"
}
