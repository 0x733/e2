#!/usr/bin/env bash
# modules/backup.sh — Configuration backup, listing, and rollback

create_backup() {
    [[ $NO_BACKUP -eq 1 ]] && { log_warn "Backup skipped (--no-backup)"; return 0; }
    [[ $DRY_RUN -eq 1 ]]   && { log_dry "Create backup: $BACKUP_PATH"; return 0; }

    log_step "Configuration Backup"
    mkdir -p "$BACKUP_PATH"

    if [[ -f "$E2_SETTINGS" ]]; then
        cp -a "$E2_SETTINGS" "$BACKUP_PATH/settings"
        log_ok "Backed up: $E2_SETTINGS"
    fi

    if [[ -f "$SYSCTL_CONF" ]]; then
        cp -a "$SYSCTL_CONF" "$BACKUP_PATH/sysctl.conf"
        log_ok "Backed up: $SYSCTL_CONF"
    fi

    opkg list-installed > "$BACKUP_PATH/installed-packages.txt" 2>/dev/null
    log_ok "Backed up: package list"

    if [[ -d /etc/enigma2 ]]; then
        local bouquet_files=()
        while IFS= read -r f; do
            bouquet_files+=("$(basename "$f")")
        done < <(ls /etc/enigma2/bouquets.* /etc/enigma2/userbouquet.* 2>/dev/null)

        if [[ ${#bouquet_files[@]} -gt 0 ]]; then
            tar czf "$BACKUP_PATH/bouquets.tar.gz" -C /etc/enigma2 "${bouquet_files[@]}" \
                2>/dev/null || log_warn "Bouquet backup failed (non-critical)"
        fi
    fi

    ln -sfn "$BACKUP_PATH" "$LATEST_BACKUP_LINK"
    log_ok "Backup directory: $BACKUP_PATH"
}

list_backups() {
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null | grep -v '^latest$')" ]]; then
        log_info "No backups found."
        return
    fi
    log_step "Available Backups"
    for dir in "$BACKUP_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        local name size
        name="$(basename "$dir")"
        [[ "$name" == "latest" ]] && continue
        size="$(du -sh "$dir" 2>/dev/null | cut -f1)"
        printf "  %s  %s\n" "$size" "$name"
    done
    echo
    [[ -L "$LATEST_BACKUP_LINK" ]] && log_info "Latest: $(readlink "$LATEST_BACKUP_LINK")"
}

rollback() {
    local target="${1:-$LATEST_BACKUP_LINK}"
    log_step "Rollback"

    if [[ ! -d "$target" ]]; then
        log_error "Backup not found: $target"
        exit 1
    fi

    log_warn "Restoring from backup: $target"
    confirm "Current configuration will be overwritten. Continue?" \
        || { log_info "Cancelled."; exit 0; }

    [[ -f "$target/settings"    ]] && cp -a "$target/settings"    "$E2_SETTINGS" && log_ok "Restored: $E2_SETTINGS"
    [[ -f "$target/sysctl.conf" ]] && cp -a "$target/sysctl.conf" "$SYSCTL_CONF"  && log_ok "Restored: $SYSCTL_CONF"

    log_warn "To restart Enigma2: init 4 && sleep 3 && init 3"
}
