#!/bin/bash
# set -uo pipefail: catch undefined variables and pipe errors.
# -e is intentionally omitted: opkg exits non-zero on warnings (false positives).
set -uo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/constants.sh
source "${SCRIPT_DIR}/lib/constants.sh"
# shellcheck source=lib/logging.sh
source "${SCRIPT_DIR}/lib/logging.sh"
# shellcheck source=lib/utils.sh
source "${SCRIPT_DIR}/lib/utils.sh"
# shellcheck source=lib/preflight.sh
source "${SCRIPT_DIR}/lib/preflight.sh"

# shellcheck source=modules/backup.sh
source "${SCRIPT_DIR}/modules/backup.sh"
# shellcheck source=modules/security.sh
source "${SCRIPT_DIR}/modules/security.sh"
# shellcheck source=modules/ntp.sh
source "${SCRIPT_DIR}/modules/ntp.sh"
# shellcheck source=modules/update.sh
source "${SCRIPT_DIR}/modules/update.sh"
# shellcheck source=modules/packages.sh
source "${SCRIPT_DIR}/modules/packages.sh"
# shellcheck source=modules/emulators.sh
source "${SCRIPT_DIR}/modules/emulators.sh"
# shellcheck source=modules/bloatware.sh
source "${SCRIPT_DIR}/modules/bloatware.sh"
# shellcheck source=modules/performance.sh
source "${SCRIPT_DIR}/modules/performance.sh"
# shellcheck source=modules/system.sh
source "${SCRIPT_DIR}/modules/system.sh"
# shellcheck source=modules/health.sh
source "${SCRIPT_DIR}/modules/health.sh"

# ============================================================================
# Runtime State
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

declare -i ERRORS=0
declare -i WARNINGS=0
declare -i INSTALLED=0
declare -i ALREADY_INSTALLED=0
declare -i REMOVED=0
declare -i CONFIG_CHANGES=0

START_TIME=0

# ============================================================================
# Traps
# ============================================================================

cleanup() {
    local exit_code=$?
    rm -f "$LOCK_FILE"
    if [[ $exit_code -ne 0 ]] && [[ $DRY_RUN -eq 0 ]]; then
        log_warn "Script exited with code $exit_code"
        [[ $NO_BACKUP -eq 0 ]] && log_info "To rollback: $0 --rollback"
    fi
    exit "$exit_code"
}

handle_interrupt() {
    echo
    log_warn "Cancelled by user (CTRL+C)"
    exit 130
}

trap cleanup EXIT
trap handle_interrupt INT TERM

# ============================================================================
# Summary
# ============================================================================

print_summary() {
    local elapsed=$(( $(date +%s) - START_TIME ))
    local mins=$(( elapsed / 60 ))
    local secs=$(( elapsed % 60 ))

    echo
    printf "%b╔══════════════════════════════════════════════════╗%b\n" "$C_BOLD" "$C_RESET"
    printf "%b║                SETUP SUMMARY                     ║%b\n" "$C_BOLD" "$C_RESET"
    printf "%b╚══════════════════════════════════════════════════╝%b\n" "$C_BOLD" "$C_RESET"
    printf "  ⏱  Duration            : %dm %ds\n"  "$mins" "$secs"
    printf "  ${C_GREEN}✓${C_RESET}  Packages installed  : %d\n" "$INSTALLED"
    printf "  ${C_BLUE}ℹ${C_RESET}  Already installed   : %d\n" "$ALREADY_INSTALLED"
    printf "  ${C_GREEN}✓${C_RESET}  Packages removed    : %d\n" "$REMOVED"
    printf "  ${C_GREEN}✓${C_RESET}  Config changes      : %d\n" "$CONFIG_CHANGES"
    printf "  ${C_YELLOW}⚠${C_RESET}  Warnings            : %d\n" "$WARNINGS"
    printf "  ${C_RED}✗${C_RESET}  Errors              : %d\n" "$ERRORS"
    echo
    printf "  📄 Log:    %s\n" "$LOG_FILE"
    [[ $NO_BACKUP -eq 0 ]] && [[ $DRY_RUN -eq 0 ]] && printf "  💾 Backup: %s\n" "$BACKUP_PATH"
    echo

    if [[ $ERRORS -gt 0 ]]; then
        log_warn "Some operations encountered errors. Please review the log."
        return 1
    fi
    log_ok "Setup completed successfully!"
}

# ============================================================================
# CLI
# ============================================================================

usage() {
    cat <<EOF
${C_BOLD}${SCRIPT_NAME}${C_RESET} v${SCRIPT_VERSION} — Enigma2 setup & optimization script

${C_BOLD}USAGE:${C_RESET}
    $SCRIPT_NAME [OPTIONS]

${C_BOLD}OPTIONS:${C_RESET}
    --dry-run            Preview commands without executing them
    --skip-update        Skip system update
    --skip-emulators     Skip emulator installation
    --skip-bloatware     Skip bloatware removal
    --skip-performance   Skip performance tweaks
    --no-backup          Skip backup (not recommended)
    --only=MODULE        Run a single module:
                         security | ntp | update | base | feeds | emulators |
                         bloatware | performance | system | health
    --health             Run system health diagnostics (read-only) and exit
    --rollback           Restore the latest backup and exit
    --list-backups       List available backups and exit
    --force              Skip confirmation prompts
    --verbose, -v        Show debug output
    --help, -h           Show this help

${C_BOLD}EXAMPLES:${C_RESET}
    $SCRIPT_NAME --dry-run
    $SCRIPT_NAME --only=performance
    $SCRIPT_NAME --only=health
    $SCRIPT_NAME --skip-emulators --skip-bloatware
    $SCRIPT_NAME --rollback

${C_BOLD}LOG:${C_RESET}     $LOG_FILE
${C_BOLD}BACKUP:${C_RESET}  $BACKUP_DIR/
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)          DRY_RUN=1 ;;
            --skip-update)      SKIP_UPDATE=1 ;;
            --skip-emulators)   SKIP_EMULATORS=1 ;;
            --skip-bloatware)   SKIP_BLOATWARE=1 ;;
            --skip-performance) SKIP_PERFORMANCE=1 ;;
            --no-backup)        NO_BACKUP=1 ;;
            --force)            FORCE=1 ;;
            --verbose|-v)       VERBOSE=1 ;;
            --only=*)           ONLY_MODULE="${1#*=}" ;;
            --health)           ONLY_MODULE="health" ;;
            --rollback)
                check_root
                mkdir -p "$LOG_DIR"
                rollback
                exit 0 ;;
            --list-backups)
                list_backups
                exit 0 ;;
            --help|-h)          usage; exit 0 ;;
            *)
                log_error "Unknown argument: $1"
                usage
                exit 1 ;;
        esac
        shift
    done
}

# ============================================================================
# Main
# ============================================================================

main() {
    START_TIME=$(date +%s)
    parse_args "$@"

    echo
    printf "%b╔══════════════════════════════════════════════════╗%b\n" "$C_BOLD$C_CYAN" "$C_RESET"
    printf "%b║   Enigma2 Setup Script v%-6s                  ║%b\n" "$C_BOLD$C_CYAN" "$SCRIPT_VERSION" "$C_RESET"
    printf "%b╚══════════════════════════════════════════════════╝%b\n" "$C_BOLD$C_CYAN" "$C_RESET"
    [[ $DRY_RUN -eq 1 ]] && log_warn "DRY-RUN MODE: No changes will be made"

    # Health is read-only — skip preflight, backup, and lock
    if [[ "$ONLY_MODULE" == "health" ]]; then
        mod_health_report
        exit 0
    fi

    run_preflight_checks
    acquire_lock
    create_backup

    if [[ -n "$ONLY_MODULE" ]]; then
        case "$ONLY_MODULE" in
            security)     mod_install_ca_certs ;;
            ntp)          mod_configure_ntp ;;
            update)       mod_update_system ;;
            base)         mod_install_base_plugins ;;
            feeds)        mod_configure_feeds ;;
            emulators)    mod_install_emulators ;;
            bloatware)    mod_remove_bloatware ;;
            performance)  mod_apply_performance_tweaks ;;
            system)       mod_configure_system ;;
            *)            log_error "Invalid module: $ONLY_MODULE"; exit 1 ;;
        esac
    else
        mod_install_ca_certs
        mod_configure_ntp
        mod_update_system
        mod_install_base_plugins
        mod_configure_feeds
        mod_install_emulators
        mod_remove_bloatware
        mod_apply_performance_tweaks
        mod_configure_system
    fi

    print_summary || exit 1
}

main "$@"