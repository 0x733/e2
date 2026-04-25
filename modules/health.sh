#!/usr/bin/env bash
# modules/health.sh — Read-only system health diagnostics (invoked via --health)

mod_health_report() {
    log_step "System Health Report"
    _health_system_info
    _health_memory
    _health_disk
    _health_temperature
    _health_time
    _health_enigma2
    _health_network
    echo
}

_health_section() { printf "\n%b  %s%b\n" "$C_BOLD" "$*" "$C_RESET"; }
_health_row()     { printf "  %-24s %s\n" "$1" "$2"; }

_health_system_info() {
    _health_section "System"
    _health_row "Hostname:"   "$(hostname 2>/dev/null || echo unknown)"
    _health_row "Kernel:"     "$(uname -r)"
    _health_row "Uptime:"     "$(uptime 2>/dev/null | sed 's/.*up //;s/,.*//')"
    _health_row "Load (1/5/15):" "$(cut -d' ' -f1-3 /proc/loadavg)"
    _health_row "RAM total:"  "$(get_total_ram_mb)MB"
    [[ -f /etc/image-version ]] && _health_row "Image:" "$(cat /etc/image-version)"
}

_health_memory() {
    _health_section "Memory"
    local total avail used swap_total swap_free swap_used
    total="$(awk '/^MemTotal/    {print int($2/1024)}' /proc/meminfo)"
    avail="$(awk '/^MemAvailable/{print int($2/1024)}' /proc/meminfo)"
    used=$(( total - avail ))
    swap_total="$(awk '/^SwapTotal/{print int($2/1024)}' /proc/meminfo)"
    swap_free="$( awk '/^SwapFree/ {print int($2/1024)}' /proc/meminfo)"
    swap_used=$(( swap_total - swap_free ))

    local pct=$(( used * 100 / total ))
    local color="$C_GREEN"
    [[ $pct -gt 70 ]] && color="$C_YELLOW"
    [[ $pct -gt 90 ]] && color="$C_RED"

    printf "  %-24s %b%d%%%b (%dMB used / %dMB total)\n" \
        "RAM:" "$color" "$pct" "$C_RESET" "$used" "$total"
    _health_row "Available:" "${avail}MB"

    if [[ $swap_total -gt 0 ]]; then
        _health_row "Swap:" "${swap_used}MB / ${swap_total}MB"
        [[ $swap_used -gt 0 ]] && log_warn "Swap in use — degrades flash lifespan"
    else
        _health_row "Swap:" "disabled"
    fi

    [[ $avail -lt 30 ]] && log_warn "Low available memory (${avail}MB)"
}

_health_disk() {
    _health_section "Disk"
    df -m 2>/dev/null | awk 'NR>1 && $2>0 {
        pct = int($3*100/$2)
        printf "  %-24s %d%% (%dMB / %dMB)\n", $6":", pct, $3, $2
    }'

    local tmp_type
    tmp_type="$(grep -E '\s/tmp\s' /proc/mounts 2>/dev/null | awk '{print $3}' | head -1)"
    _health_row "/tmp type:" "${tmp_type:-unknown}"
    [[ "$tmp_type" != "tmpfs" ]] && log_warn "/tmp is not tmpfs — writes go to flash"

    local root_pct
    root_pct="$(df -m / 2>/dev/null | awk 'NR==2 {print int($3*100/$2)}')"
    [[ "$root_pct" -gt 80 ]] && log_warn "Root filesystem is ${root_pct}% full"
}

_health_temperature() {
    _health_section "Temperature"
    local found=0
    for f in /sys/class/thermal/thermal_zone*/temp; do
        [[ -r "$f" ]] || continue
        local zone temp_c
        zone="$(basename "$(dirname "$f")")"
        temp_c=$(( $(cat "$f") / 1000 ))
        _health_row "${zone}:" "${temp_c}°C"
        [[ $temp_c -gt 80 ]] && log_warn "High temperature on ${zone}: ${temp_c}°C"
        found=1
    done
    [[ $found -eq 0 ]] && _health_row "Sensors:" "not available"
}

_health_time() {
    _health_section "Time"
    _health_row "System time:" "$(date)"
    local year
    year="$(date +%Y)"
    if [[ "$year" -lt 2020 ]]; then
        log_warn "System clock looks wrong (year: $year) — TLS, EPG, and recordings may fail"
    fi
    if has_command ntpq; then
        printf "  NTP peers:\n"
        ntpq -p 2>/dev/null | head -6 | while IFS= read -r line; do
            printf "    %s\n" "$line"
        done
    fi
}

_health_enigma2() {
    _health_section "Enigma2"
    if pgrep -x enigma2 >/dev/null 2>&1; then
        local pid
        pid="$(pgrep -x enigma2 | head -1)"
        log_ok "enigma2 running (PID: $pid)"

        if [[ -r "/proc/$pid/stat" ]]; then
            local ticks hz uptime_s start
            ticks="$(awk '{print $22}' "/proc/$pid/stat" 2>/dev/null)"
            hz="$(getconf CLK_TCK 2>/dev/null || echo 100)"
            uptime_s="$(cut -d. -f1 /proc/uptime)"
            start=$(( uptime_s - ticks / hz ))
            _health_row "Process uptime:" "${start}s"
        fi
    else
        log_warn "enigma2 is NOT running"
    fi

    [[ -f "$E2_SETTINGS" ]] && \
        _health_row "Settings entries:" "$(wc -l < "$E2_SETTINGS")"

    if [[ -f /var/log/enigma2.log ]]; then
        local crashes
        crashes="$(grep -c -i "crash\|segfault\|killed" /var/log/enigma2.log 2>/dev/null || echo 0)"
        _health_row "Crash indicators:" "$crashes in enigma2.log"
    fi
}

_health_network() {
    _health_section "Network"
    for iface_path in /sys/class/net/*/; do
        local iface state ip
        iface="$(basename "$iface_path")"
        [[ "$iface" == "lo" ]] && continue
        state="$(cat "${iface_path}operstate" 2>/dev/null || echo unknown)"
        ip="$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet /{print $2}' | head -1)"
        _health_row "${iface}:" "$state ${ip:+(${ip})}"
    done

    if has_command ss; then
        printf "\n  %bListening ports:%b\n" "$C_BOLD" "$C_RESET"
        ss -tlnp 2>/dev/null | awk 'NR>1 {printf "    %s\n", $0}'
    fi
}
