#!/bin/bash
#
# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  Enigma2 Receiver Setup & Optimization Script                             ║
# ║  Version: 2.0.0                                                           ║
# ╠════════════════════════════════════════════════════════════════════════════╣
# ║  Compatible with: OpenATV, OpenPLi, OE-Alliance, OpenVIX, PurE2           ║
# ║                                                                           ║
# ║  Features:                                                                ║
# ║    • Idempotent operations (safe to re-run)                               ║
# ║    • Automatic configuration backup + one-command rollback                ║
# ║    • Color-coded, leveled logging (also written to file)                  ║
# ║    • Selective module execution via CLI arguments                         ║
# ║    • Dry-run mode (preview without making changes)                        ║
# ║    • Network, disk space, root privilege pre-flight checks                ║
# ║    • Lock file (prevents concurrent execution)                            ║
# ║    • Trap-based clean exit (CTRL+C, errors, normal termination)           ║
# ║    • Detailed summary report                                              ║
# ║                                                                           ║
# ║  Usage:                                                                   ║
# ║    ./e2-setup.sh                       # Full setup                       ║
# ║    ./e2-setup.sh --dry-run             # Preview                          ║
# ║    ./e2-setup.sh --only=performance    # Only performance tweaks          ║
# ║    ./e2-setup.sh --skip-emulators      # Setup without emulators          ║
# ║    ./e2-setup.sh --rollback            # Restore latest backup            ║
# ║    ./e2-setup.sh --list-backups        # List available backups           ║
# ║    ./e2-setup.sh --help                # Show help                        ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# -uo pipefail: catch undefined vars + pipe errors
# Avoid -e since opkg returns non-zero on warnings → false positives
set -uo pipefail
IFS=$'\n\t'

# ============================================================================
# CONSTANTS
# ============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="2.0.0"

readonly LOG_DIR="/var/log/e2-setup"
readonly LOG_FILE="${LOG_DIR}/setup-$(date +%Y%m%d-%H%M%S).log"

readonly BACKUP_DIR="/var/backups/e2-setup"
readonly BACKUP_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_PATH="${BACKUP_DIR}/${BACKUP_TIMESTAMP}"
readonly LATEST_BACKUP_LINK="${BACKUP_DIR}/latest"

readonly LOCK_FILE="/var/lock/e2-setup.lock"
readonly MIN_FREE_SPACE_MB=100

# External sources
readonly FEED_OEA_URL="http://updates.mynonpublic.com/oea/feed"
readonly EMULATOR_URL="https://raw.githubusercontent.com/levi-45/Levi45Emulator/refs/heads/main/installer.sh"

# Configuration files
readonly E2_SETTINGS="/etc/enigma2/settings"
readonly SYSCTL_CONF="/etc/sysctl.conf"
readonly SYSCTL_DROPIN="/etc/sysctl.d/99-e2-performance.conf"

# Colors (only when terminal supports them)
if [[ -t 1 ]]; then
    readonly C_RED='\033[0;31m'
    readonly C_GREEN='\033[0;32m'
    readonly C_YELLOW='\033[1;33m'
    readonly C_BLUE='\033[0;34m'
    readonly C_CYAN='\033[0;36m'
    readonly C_BOLD='\033[1m'
    readonly C_RESET='\033[0m'
else
    readonly C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_CYAN='' C_BOLD='' C_RESET=''
fi

# ============================================================================
# RUNTIME STATE
# ============================================================================

DRY_RUN=0
SKIP_UPDATE=0
SKIP_EMULATORS=0
SKIP_BLOATWARE=0
SKIP_PERFORMANCE=0
ONLY_MODULE=""
VERBOSE=0
FORCE=0
NO_BACKUP=0

# Counters
declare -i ERRORS=0
declare -i WARNINGS=0
declare -i INSTALLED=0
declare -i ALREADY_INSTALLED=0
declare -i REMOVED=0
declare -i CONFIG_CHANGES=0

# ============================================================================
# PACKAGE LISTS (kept at top for easy editing)
# ============================================================================

readonly BASE_PLUGINS=(
    "enigma2-plugin-extensions-bouquetmakerxtream"
    "enigma2-plugin-systemplugins-serviceapp"
    "enigma2-plugin-extensions-ajpanel"
)

readonly POST_FEED_PLUGINS=(
    "enigma2-plugin-systemplugins-ciplushelper"
)

readonly BLOATWARE=(
    "enigma2-plugin-extensions-hbbtv"
    "enigma2-plugin-extensions-browser"
    "enigma2-plugin-extensions-chromium"
    "enigma2-plugin-systemplugins-minidlna"
    "enigma2-plugin-systemplugins-bluetoothsetup"
    "enigma2-plugin-systemplugins-upnp"
    "enigma2-plugin-systemplugins-nfsserver"
    "enigma2-plugin-systemplugins-softwaremanager"
    "enigma2-plugin-systemplugins-networkwizard"
    "enigma2-plugin-extensions-modem"
)

# Enigma2 settings as key=value pairs
# Format: "key|value"
readonly E2_SETTING_OVERRIDES=(
    "config.plugins.serviceapp.servicemp3|5002"
    "config.plugins.serviceapp.service5002|exteplayer3"
    "config.plugins.serviceapp.service4097|exteplayer3"
    "config.usage.infobar_timeout|2"
    "config.usage.show_infobar_on_zap|false"
    "config.usage.show_spinner|false"
    "config.plugins.configurationbackup.backup_location|/tmp/"
)

# Sysctl performance tweaks
readonly SYSCTL_TWEAKS=(
    "vm.swappiness=10"
    "vm.vfs_cache_pressure=200"
    "vm.dirty_ratio=15"
    "vm.dirty_background_ratio=5"
    "net.core.rmem_max=2097152"
    "net.core.wmem_max=2097152"
)

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

_log() {
    local level="$1"; shift
    local color="$1"; shift
    local msg="$*"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"

    # Print to console with color
    printf "%b[%s] [%s]%b %s\n" "$color" "$ts" "$level" "$C_RESET" "$msg"

    # Write to log file without color
    if [[ -d "$LOG_DIR" ]]; then
        printf "[%s] [%s] %s\n" "$ts" "$level" "$msg" >> "$LOG_FILE"
    fi
}

log_info()    { _log "INFO " "$C_BLUE"   "$@"; }
log_ok()      { _log " OK  " "$C_GREEN"  "$@"; }
log_warn()    { _log "WARN " "$C_YELLOW" "$@"; ((WARNINGS++)); }
log_error()   { _log "ERROR" "$C_RED"    "$@"; ((ERRORS++)); }
log_step()    {
    echo
    printf "%b━━━ %s ━━━%b\n" "$C_CYAN$C_BOLD" "$*" "$C_RESET"
    [[ -d "$LOG_DIR" ]] && printf "\n=== %s ===\n" "$*" >> "$LOG_FILE"
}
log_debug()   { [[ $VERBOSE -eq 1 ]] && _log "DEBUG" "$C_CYAN" "$@" || true; }
log_dry()     { _log " DRY " "$C_YELLOW" "$@"; }

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

usage() {
    cat <<EOF
${C_BOLD}${SCRIPT_NAME}${C_RESET} v${SCRIPT_VERSION} - Enigma2 setup & optimization script

${C_BOLD}USAGE:${C_RESET}
    $SCRIPT_NAME [OPTIONS]

${C_BOLD}OPTIONS:${C_RESET}
    --dry-run            Preview commands without executing them
    --skip-update        Skip system update step
    --skip-emulators     Skip emulator installation
    --skip-bloatware     Skip bloatware removal step
    --skip-performance   Skip performance tweaks
    --no-backup          Run without creating a backup (not recommended)
    --only=MODULE        Run only the specified module
                         (update|base|feeds|emulators|bloatware|performance)
    --rollback           Restore the latest backup and exit
    --list-backups       List available backups and exit
    --force              Skip confirmation prompts
    --verbose            Show debug-level logs
    --help               Show this help

${C_BOLD}EXAMPLES:${C_RESET}
    $SCRIPT_NAME --dry-run
    $SCRIPT_NAME --only=performance
    $SCRIPT_NAME --skip-emulators --skip-bloatware
    $SCRIPT_NAME --rollback

${C_BOLD}LOG:${C_RESET}     $LOG_FILE
${C_BOLD}BACKUP:${C_RESET}  $BACKUP_DIR/
EOF
}

# Command execution wrapper (with dry-run support)
run() {
    local cmd="$*"
    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "$cmd"
        return 0
    fi
    log_debug "Executing: $cmd"
    eval "$cmd"
}

# Ask for confirmation (skipped if --force)
confirm() {
    local prompt="${1:-Continue?}"
    [[ $FORCE -eq 1 ]] && return 0
    read -r -p "$(printf "%b%s [y/N]: %b" "$C_YELLOW" "$prompt" "$C_RESET")" reply
    [[ "$reply" =~ ^[YyEe]$ ]]
}

# Check if a command exists
has_command() {
    command -v "$1" >/dev/null 2>&1
}

# Check if a package is installed
is_installed() {
    opkg list-installed 2>/dev/null | grep -q "^$1 "
}

# Acquire lock file and release via trap
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid
        pid="$(cat "$LOCK_FILE" 2>/dev/null || echo "")"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_error "Another setup process is running (PID: $pid)"
            log_error "If this is incorrect: rm $LOCK_FILE"
            exit 1
        else
            log_warn "Stale lock file found, removing"
            rm -f "$LOCK_FILE"
        fi
    fi
    echo "$$" > "$LOCK_FILE"
}

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script requires root privileges. Run with 'sudo'."
        exit 1
    fi
}

check_enigma2() {
    if ! has_command opkg; then
        log_error "opkg not found. This script must be run on an Enigma2 device."
        exit 1
    fi
    if [[ ! -f "$E2_SETTINGS" ]]; then
        log_warn "$E2_SETTINGS not found. Enigma2 may be freshly installed."
    fi
}

check_network() {
    log_info "Checking internet connectivity..."
    local hosts=("8.8.8.8" "1.1.1.1" "updates.mynonpublic.com")
    for host in "${hosts[@]}"; do
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            log_ok "Connection OK ($host reachable)"
            return 0
        fi
    done
    log_error "No internet connection. Please check your network."
    exit 1
}

check_disk_space() {
    local available_mb
    available_mb="$(df -m / | awk 'NR==2 {print $4}')"
    if [[ "$available_mb" -lt "$MIN_FREE_SPACE_MB" ]]; then
        log_error "Insufficient disk space: ${available_mb}MB (at least ${MIN_FREE_SPACE_MB}MB required)"
        exit 1
    fi
    log_ok "Disk space OK (${available_mb}MB free)"
}

run_preflight_checks() {
    log_step "Pre-flight Checks"
    check_root
    check_enigma2
    check_network
    check_disk_space

    # Create log directory
    mkdir -p "$LOG_DIR" "$BACKUP_DIR"
    log_info "Log file: $LOG_FILE"
}

# ============================================================================
# BACKUP / ROLLBACK
# ============================================================================

create_backup() {
    [[ $NO_BACKUP -eq 1 ]] && { log_warn "Backup skipped (--no-backup)"; return 0; }
    [[ $DRY_RUN -eq 1 ]] && { log_dry "Create backup: $BACKUP_PATH"; return 0; }

    log_step "Configuration Backup"
    mkdir -p "$BACKUP_PATH"

    # Enigma2 settings
    if [[ -f "$E2_SETTINGS" ]]; then
        cp -a "$E2_SETTINGS" "$BACKUP_PATH/settings"
        log_ok "Backed up: $E2_SETTINGS"
    fi

    # Sysctl
    if [[ -f "$SYSCTL_CONF" ]]; then
        cp -a "$SYSCTL_CONF" "$BACKUP_PATH/sysctl.conf"
        log_ok "Backed up: $SYSCTL_CONF"
    fi

    # Installed package list (reference for rollback)
    opkg list-installed > "$BACKUP_PATH/installed-packages.txt" 2>/dev/null
    log_ok "Backed up: package list"

    # Bouquets
    if [[ -d /etc/enigma2 ]]; then
        tar czf "$BACKUP_PATH/bouquets.tar.gz" -C /etc/enigma2 \
            $(ls /etc/enigma2/bouquets.* /etc/enigma2/userbouquet.* 2>/dev/null | xargs -n1 basename) \
            2>/dev/null || log_warn "Bouquet backup failed (non-critical)"
    fi

    # Symlink to latest
    ln -sfn "$BACKUP_PATH" "$LATEST_BACKUP_LINK"
    log_ok "Backup directory: $BACKUP_PATH"
}

list_backups() {
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null | grep -v '^latest$')" ]]; then
        log_info "No backups found yet."
        return
    fi
    log_step "Available Backups"
    for dir in "$BACKUP_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        local name size
        name="$(basename "$dir")"
        size="$(du -sh "$dir" 2>/dev/null | cut -f1)"
        printf "  %s  %s\n" "$size" "$name"
    done
    echo
    [[ -L "$LATEST_BACKUP_LINK" ]] && \
        log_info "Latest: $(readlink "$LATEST_BACKUP_LINK")"
}

rollback() {
    local target="${1:-$LATEST_BACKUP_LINK}"
    log_step "Rollback"

    if [[ ! -d "$target" ]]; then
        log_error "Backup not found: $target"
        exit 1
    fi

    log_warn "Restoring from backup: $target"
    confirm "Current configuration will be overwritten. Continue?" || { log_info "Cancelled."; exit 0; }

    [[ -f "$target/settings"    ]] && cp -a "$target/settings"    "$E2_SETTINGS"  && log_ok "Restored: $E2_SETTINGS"
    [[ -f "$target/sysctl.conf" ]] && cp -a "$target/sysctl.conf" "$SYSCTL_CONF"  && log_ok "Restored: $SYSCTL_CONF"

    log_warn "To restart Enigma2: init 4 && sleep 3 && init 3"
}

# ============================================================================
# MODULE: SYSTEM UPDATE
# ============================================================================

mod_update_system() {
    [[ $SKIP_UPDATE -eq 1 ]] && { log_info "System update skipped"; return 0; }
    log_step "System Update"

    run "opkg update" || { log_error "opkg update failed"; return 1; }
    log_ok "Package list updated"

    # Number of upgradable packages
    local upgradable
    upgradable="$(opkg list-upgradable 2>/dev/null | wc -l)"
    log_info "Upgradable package count: $upgradable"

    if [[ $upgradable -gt 0 ]]; then
        run "opkg upgrade" && log_ok "System upgraded" || log_warn "Some packages could not be upgraded"
    else
        log_ok "System is already up to date"
    fi
}

# ============================================================================
# MODULE: PACKAGE INSTALLATION (idempotent)
# ============================================================================

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
        if run "opkg install '$pkg'"; then
            log_ok "Installed: $pkg"
            ((INSTALLED++))
        else
            log_error "Failed to install: $pkg"
        fi
    done
}

mod_install_base_plugins() {
    log_step "Base Plugins Installation"
    install_packages "base plugins" "${BASE_PLUGINS[@]}"
}

# ============================================================================
# MODULE: EXTERNAL FEED CONFIGURATION
# ============================================================================

mod_configure_feeds() {
    log_step "OE-Alliance Feed Configuration"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "wget '$FEED_OEA_URL' | bash"
    else
        log_info "Downloading feed installer script..."
        if wget --no-check-certificate -O - -q "$FEED_OEA_URL" | bash; then
            log_ok "Feed added"
        else
            log_error "Failed to add feed"
            return 1
        fi
    fi

    run "opkg update"
    install_packages "post-feed plugins" "${POST_FEED_PLUGINS[@]}"
}

# ============================================================================
# MODULE: EMULATOR INSTALLATION
# ============================================================================

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

# ============================================================================
# MODULE: BLOATWARE REMOVAL
# ============================================================================

mod_remove_bloatware() {
    [[ $SKIP_BLOATWARE -eq 1 ]] && { log_info "Bloatware removal skipped"; return 0; }
    log_step "Bloatware Removal"

    for pkg in "${BLOATWARE[@]}"; do
        if ! is_installed "$pkg"; then
            log_debug "Not installed: $pkg"
            continue
        fi
        if run "opkg remove --force-depends '$pkg'"; then
            log_ok "Removed: $pkg"
            ((REMOVED++))
        else
            log_warn "Could not remove: $pkg"
        fi
    done
    log_info "Total packages removed: $REMOVED"
}

# ============================================================================
# MODULE: PERFORMANCE TWEAKS
# ============================================================================

# Idempotent settings updater
# - If key exists, updates its value
# - If not, appends to file
# - Unlike the old sed approach, does not require knowing the previous value
update_setting() {
    local file="$1"
    local key="$2"
    local value="$3"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_dry "Set: $key=$value (in $file)"
        return 0
    fi

    if [[ ! -f "$file" ]]; then
        log_warn "File missing, creating: $file"
        mkdir -p "$(dirname "$file")"
        touch "$file"
    fi

    # Check current value
    local current
    current="$(grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2- || true)"

    if [[ "$current" == "$value" ]]; then
        log_debug "$key already correct ($value)"
        return 0
    fi

    if grep -qE "^${key}=" "$file"; then
        # Escape dots in key for sed
        local escaped_key
        escaped_key="$(echo "$key" | sed 's/\./\\./g')"
        sed -i "s|^${escaped_key}=.*|${key}=${value}|" "$file"
        log_ok "Updated: $key=$value (was: $current)"
    else
        echo "${key}=${value}" >> "$file"
        log_ok "Added: $key=$value"
    fi
    ((CONFIG_CHANGES++))
}

mod_apply_performance_tweaks() {
    [[ $SKIP_PERFORMANCE -eq 1 ]] && { log_info "Performance tweaks skipped"; return 0; }
    log_step "Performance Optimizations"

    # Stop Enigma2 to safely edit settings
    if [[ $DRY_RUN -eq 0 ]] && [[ -f "$E2_SETTINGS" ]]; then
        log_info "Stopping Enigma2 (init 4)..."
        init 4
        sleep 5
    fi

    # Update E2 settings
    log_info "Applying Enigma2 settings..."
    for entry in "${E2_SETTING_OVERRIDES[@]}"; do
        local key="${entry%%|*}"
        local value="${entry#*|}"
        update_setting "$E2_SETTINGS" "$key" "$value"
    done

    # Sysctl tweaks — old script appended to /etc/sysctl.conf with >>
    # which created duplicate lines on every run. We use a drop-in file instead.
    log_info "Applying sysctl performance settings..."
    if [[ $DRY_RUN -eq 0 ]]; then
        {
            echo "# Generated by e2-setup.sh"
            echo "# Date: $(date)"
            for tweak in "${SYSCTL_TWEAKS[@]}"; do
                echo "$tweak"
            done
        } > "$SYSCTL_DROPIN"

        # Apply immediately
        if has_command sysctl; then
            sysctl -p "$SYSCTL_DROPIN" >/dev/null 2>&1 && \
                log_ok "Sysctl settings active" || \
                log_warn "Sysctl could not be applied at runtime (will activate on reboot)"
        fi
        log_ok "Sysctl drop-in: $SYSCTL_DROPIN"
        ((CONFIG_CHANGES++))
    else
        log_dry "Sysctl drop-in file: $SYSCTL_DROPIN"
    fi

    # Restart Enigma2
    if [[ $DRY_RUN -eq 0 ]] && [[ -f "$E2_SETTINGS" ]]; then
        log_info "Starting Enigma2 (init 3)..."
        init 3
    fi
}

# ============================================================================
# SUMMARY REPORT
# ============================================================================

print_summary() {
    local elapsed=$(($(date +%s) - START_TIME))
    local mins=$((elapsed / 60))
    local secs=$((elapsed % 60))

    echo
    printf "%b╔══════════════════════════════════════════════════╗%b\n" "$C_BOLD" "$C_RESET"
    printf "%b║                SETUP SUMMARY                     ║%b\n" "$C_BOLD" "$C_RESET"
    printf "%b╚══════════════════════════════════════════════════╝%b\n" "$C_BOLD" "$C_RESET"
    printf "  ⏱  Duration            : %dm %ds\n" "$mins" "$secs"
    printf "  ${C_GREEN}✓${C_RESET}  Packages installed  : %d\n" "$INSTALLED"
    printf "  ${C_BLUE}ℹ${C_RESET}  Already installed   : %d\n" "$ALREADY_INSTALLED"
    printf "  ${C_GREEN}✓${C_RESET}  Packages removed    : %d\n" "$REMOVED"
    printf "  ${C_GREEN}✓${C_RESET}  Config changes      : %d\n" "$CONFIG_CHANGES"
    printf "  ${C_YELLOW}⚠${C_RESET}  Warnings            : %d\n" "$WARNINGS"
    printf "  ${C_RED}✗${C_RESET}  Errors              : %d\n" "$ERRORS"
    echo
    printf "  📄 Log:    %s\n" "$LOG_FILE"
    [[ $NO_BACKUP -eq 0 ]] && [[ $DRY_RUN -eq 0 ]] && \
        printf "  💾 Backup: %s\n" "$BACKUP_PATH"
    echo

    if [[ $ERRORS -gt 0 ]]; then
        log_warn "Some operations encountered errors. Please review the log."
        return 1
    fi
    log_ok "Setup completed successfully!"
    return 0
}

# ============================================================================
# CLEANUP / TRAPS
# ============================================================================

cleanup() {
    local exit_code=$?
    rm -f "$LOCK_FILE"
    if [[ $exit_code -ne 0 ]] && [[ $DRY_RUN -eq 0 ]]; then
        log_warn "Script exited with code $exit_code"
        [[ $NO_BACKUP -eq 0 ]] && \
            log_info "To rollback: $0 --rollback"
    fi
    exit $exit_code
}

handle_interrupt() {
    echo
    log_warn "Cancelled by user (CTRL+C)"
    exit 130
}

trap cleanup EXIT
trap handle_interrupt INT TERM

# ============================================================================
# ARGUMENT PARSING
# ============================================================================

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)            DRY_RUN=1 ;;
            --skip-update)        SKIP_UPDATE=1 ;;
            --skip-emulators)     SKIP_EMULATORS=1 ;;
            --skip-bloatware)     SKIP_BLOATWARE=1 ;;
            --skip-performance)   SKIP_PERFORMANCE=1 ;;
            --no-backup)          NO_BACKUP=1 ;;
            --force)              FORCE=1 ;;
            --verbose|-v)         VERBOSE=1 ;;
            --only=*)             ONLY_MODULE="${1#*=}" ;;
            --rollback)
                check_root
                mkdir -p "$LOG_DIR"
                rollback
                exit 0 ;;
            --list-backups)
                list_backups
                exit 0 ;;
            --help|-h)            usage; exit 0 ;;
            *)
                log_error "Unknown argument: $1"
                usage
                exit 1 ;;
        esac
        shift
    done
}

# ============================================================================
# MAIN FLOW
# ============================================================================

main() {
    START_TIME=$(date +%s)

    parse_args "$@"

    echo
    printf "%b╔══════════════════════════════════════════════════╗%b\n" "$C_BOLD$C_CYAN" "$C_RESET"
    printf "%b║   Enigma2 Setup Script v%s                    ║%b\n" "$C_BOLD$C_CYAN" "$SCRIPT_VERSION" "$C_RESET"
    printf "%b╚══════════════════════════════════════════════════╝%b\n" "$C_BOLD$C_CYAN" "$C_RESET"
    [[ $DRY_RUN -eq 1 ]] && log_warn "DRY-RUN MODE: No changes will be made"

    run_preflight_checks
    acquire_lock
    create_backup

    # If --only is given, run only that module
    if [[ -n "$ONLY_MODULE" ]]; then
        case "$ONLY_MODULE" in
            update)       mod_update_system ;;
            base)         mod_install_base_plugins ;;
            feeds)        mod_configure_feeds ;;
            emulators)    mod_install_emulators ;;
            bloatware)    mod_remove_bloatware ;;
            performance)  mod_apply_performance_tweaks ;;
            *)            log_error "Invalid module: $ONLY_MODULE"; exit 1 ;;
        esac
    else
        # Full pipeline
        mod_update_system
        mod_install_base_plugins
        mod_configure_feeds
        mod_install_emulators
        mod_remove_bloatware
        mod_apply_performance_tweaks
    fi

    print_summary
}

main "$@"