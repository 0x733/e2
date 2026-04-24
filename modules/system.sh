#!/usr/bin/env bash
# modules/system.sh — System-level tuning: tmpfs, log rotation, flash optimizations

mod_configure_system() {
    log_step "System Tuning"
    _system_configure_tmpfs
    _system_configure_log_rotation
    _system_check_noatime
}

_system_configure_tmpfs() {
    log_info "Checking /tmp mount..."

    if grep -q "tmpfs /tmp" /proc/mounts 2>/dev/null; then
        log_ok "/tmp is already tmpfs"
        return 0
    fi

    log_warn "/tmp is not tmpfs — temporary file writes go to flash storage"

    local ram_mb tmpfs_size
    ram_mb="$(get_total_ram_mb)"
    tmpfs_size=$(( ram_mb / 4 ))
    [[ $tmpfs_size -lt 32  ]] && tmpfs_size=32
    [[ $tmpfs_size -gt 128 ]] && tmpfs_size=128

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Mount /tmp as tmpfs (${tmpfs_size}M)"
        return 0
    fi

    if ! grep -q "tmpfs /tmp" /etc/fstab 2>/dev/null; then
        echo "tmpfs /tmp tmpfs defaults,nodev,nosuid,size=${tmpfs_size}M 0 0" >> /etc/fstab
        log_ok "Added tmpfs /tmp (${tmpfs_size}M) to /etc/fstab"
        ((CONFIG_CHANGES++))
    fi

    if mount -t tmpfs -o "size=${tmpfs_size}M,nodev,nosuid" tmpfs /tmp 2>/dev/null; then
        log_ok "/tmp mounted as tmpfs immediately (${tmpfs_size}M)"
    else
        log_info "/tmp will be tmpfs after next reboot"
    fi
}

_system_configure_log_rotation() {
    log_info "Configuring log rotation..."

    if ! has_command logrotate; then
        log_warn "logrotate not available — skipping"
        return 0
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Write /etc/logrotate.d/e2-setup"
        return 0
    fi

    mkdir -p /etc/logrotate.d
    cat > /etc/logrotate.d/e2-setup <<'EOF'
/var/log/e2-setup/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
}

/var/log/enigma2.log {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
}
EOF
    log_ok "Log rotation configured (/etc/logrotate.d/e2-setup)"
    ((CONFIG_CHANGES++))
}

_system_check_noatime() {
    log_info "Checking flash mount options..."

    local root_opts
    root_opts="$(grep -E '\s/\s' /proc/mounts 2>/dev/null | awk '{print $4}' | head -1)"

    if echo "$root_opts" | grep -q "noatime"; then
        log_ok "noatime already set on root filesystem"
    else
        log_warn "noatime not set on / — access times are written to flash on every read"
        log_info "Add 'noatime' to the root entry in /etc/fstab to reduce flash wear"
    fi
}
