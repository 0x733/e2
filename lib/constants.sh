#!/usr/bin/env bash
# lib/constants.sh — Global constants, colors, and configuration arrays

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="2.2.0"

readonly LOG_DIR="/var/log/e2-setup"
readonly LOG_FILE="${LOG_DIR}/setup-$(date +%Y%m%d-%H%M%S).log"

readonly BACKUP_DIR="/var/backups/e2-setup"
readonly BACKUP_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_PATH="${BACKUP_DIR}/${BACKUP_TIMESTAMP}"
readonly LATEST_BACKUP_LINK="${BACKUP_DIR}/latest"

readonly LOCK_FILE="/var/lock/e2-setup.lock"
readonly MIN_FREE_SPACE_MB=100

readonly FEED_OEA_URL="http://updates.mynonpublic.com/oea/feed"
readonly EMULATOR_URL="https://raw.githubusercontent.com/levi-45/Levi45Emulator/refs/heads/main/installer.sh"

readonly E2_SETTINGS="/etc/enigma2/settings"
readonly SYSCTL_CONF="/etc/sysctl.conf"
readonly SYSCTL_DROPIN="/etc/sysctl.d/99-e2-performance.conf"

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

# Static sysctl tweaks. Network buffer sizes are computed dynamically in
# modules/performance.sh based on available RAM and appended to this list.
readonly SYSCTL_TWEAKS=(
    "vm.swappiness=10"
    "vm.vfs_cache_pressure=50"
    "vm.dirty_ratio=10"
    "vm.dirty_background_ratio=5"
    "vm.overcommit_memory=1"
    "fs.inotify.max_user_watches=8192"
    "net.ipv4.tcp_window_scaling=1"
    "net.ipv4.tcp_fastopen=3"
    "kernel.dmesg_restrict=1"
)
