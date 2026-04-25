# Enigma2 Setup & Optimization Script

A modular Bash script for setting up and optimizing **Enigma2** satellite receivers.  
Compatible with OpenATV, OpenPLi, OE-Alliance, OpenVIX, and PurE2.

## Features

| Feature | Description |
|---|---|
| **Idempotent** | Safe to re-run — already-correct settings and installed packages are skipped |
| **Dry-run mode** | Preview every change before applying |
| **Backup & rollback** | Timestamped config backup with one-command restore |
| **Modular** | Run any single module via `--only=<module>` |
| **Preflight checks** | Root, network, disk space, and Enigma2 verified before any change |
| **Download integrity** | Remote scripts downloaded to a temp file with SHA-256 display and user confirmation |
| **RAM-aware tuning** | Network buffers sized proportionally to device RAM (min 256 KB, max 1 MB) |
| **Health diagnostics** | Read-only `--health` report: RAM, disk, temperature, time, ports |
| **Lock file** | Prevents concurrent execution |
| **Colored logging** | INFO / OK / WARN / ERROR levels, also written to `/var/log/e2-setup/` |

## Project Structure

```
e2-setup.sh              Entry point & orchestrator
lib/
  constants.sh           Constants, colors, package/settings arrays
  logging.sh             Leveled log functions
  utils.sh               run(), confirm(), is_installed(), download_verified(), get_total_ram_mb()
  preflight.sh           Root, network, disk, Enigma2 checks
modules/
  security.sh            CA certificate installation
  ntp.sh                 NTP force-sync and time validation
  backup.sh              create_backup, list_backups, rollback
  update.sh              mod_update_system
  packages.sh            install_packages, mod_install_base_plugins, mod_configure_feeds
  emulators.sh           mod_install_emulators (Levi45)
  bloatware.sh           mod_remove_bloatware
  performance.sh         update_setting, mod_apply_performance_tweaks (RAM-aware)
  system.sh              tmpfs /tmp, log rotation, noatime audit
  health.sh              mod_health_report (read-only diagnostics)
```

## Installation

Enigma2 devices do not have `git`. Use the single **wget** command below to
download and run the script directly:

```sh
wget -qO /tmp/e2-install.sh \
  https://raw.githubusercontent.com/0x733/E2/main/install.sh \
  && sh /tmp/e2-install.sh
```

All `e2-setup.sh` options can be passed directly to the installer:

```sh
# Dry-run — preview all changes without applying anything
sh /tmp/e2-install.sh --dry-run

# Run only the performance module
sh /tmp/e2-install.sh --only=performance

# Skip the emulator and bloatware steps
sh /tmp/e2-install.sh --skip-emulators --skip-bloatware
```

**What does `install.sh` do?**

1. Downloads the project tar.gz archive from GitHub to `/tmp` via `wget`
2. Extracts it to `/tmp/e2-setup-remote/` using `tar`
3. Executes `e2-setup.sh`, forwarding all arguments

> **Note:** If the download fails, the script exits with a non-zero code
> and no changes are made.

---

## Usage

```bash
# Full setup
./e2-setup.sh

# Preview without making any changes
./e2-setup.sh --dry-run

# System health report (read-only, no root required for most checks)
./e2-setup.sh --health

# Run only one module
./e2-setup.sh --only=performance
./e2-setup.sh --only=ntp
./e2-setup.sh --only=system

# Skip specific steps
./e2-setup.sh --skip-emulators --skip-bloatware

# Restore the latest backup
./e2-setup.sh --rollback

# List available backups
./e2-setup.sh --list-backups
```

## Options

```
--dry-run            Preview commands without executing them
--skip-update        Skip system update
--skip-emulators     Skip emulator installation
--skip-bloatware     Skip bloatware removal
--skip-performance   Skip performance tweaks
--no-backup          Skip backup (not recommended)
--only=MODULE        Run a single module:
                     security | ntp | update | base | feeds | emulators |
                     bloatware | performance | system | health
--health             Run health diagnostics and exit (alias for --only=health)
--rollback           Restore the latest backup and exit
--list-backups       List available backups and exit
--force              Skip confirmation prompts
--verbose, -v        Show debug output
--help, -h           Show this help
```

## Modules

### `security`
Installs the `ca-certificates` package to enable proper HTTPS certificate verification
for all subsequent `wget` operations.

### `ntp`
Forces an immediate clock sync via `ntpdate` (tries pool.ntp.org, time.google.com,
time.cloudflare.com). Enigma2 devices have no hardware RTC — an incorrect clock
breaks TLS validation, EPG schedules, and recordings.

### `update`
Runs `opkg update` and upgrades all outdated packages.

### `base`
Installs core plugins: BouquetMakerXtream, ServiceApp, AJPanel.

### `feeds`
Adds the OE-Alliance feed. The installer script is downloaded to a temp file,
its SHA-256 is displayed, and user confirmation is required before execution.

### `emulators`
Installs the Levi45 emulator package via its upstream installer (same
download-verify-confirm flow as feeds).

### `bloatware`
Removes unused pre-installed packages: HbbTV, built-in browser, Chromium, miniDLNA,
Bluetooth, UPnP, NFS server, Software Manager, Network Wizard, modem plugins.

### `performance`
- Applies Enigma2 settings (ServiceApp player, infobar timeout, spinner)
- Writes `/etc/sysctl.d/99-e2-performance.conf` with embedded-hardware-tuned values
- Network buffer sizes (`rmem_max`, `wmem_max`) are computed from available RAM:
  `RAM / 32`, clamped to [256 KB, 1 MB]

**Sysctl values applied:**

| Parameter | Value | Rationale |
|---|---|---|
| `vm.swappiness` | 10 | Keeps Enigma2 in RAM, avoids slow flash swapping |
| `vm.vfs_cache_pressure` | 50 | Retains VFS cache longer; reduces flash re-reads |
| `vm.dirty_ratio` | 10 | Prevents GUI freeze during recording on low-RAM devices |
| `vm.dirty_background_ratio` | 5 | Starts background flush early |
| `vm.overcommit_memory` | 1 | Prevents OOM-killer from terminating Enigma2 mid-recording |
| `fs.inotify.max_user_watches` | 8192 | Prevents plugin file watchers from silently failing |
| `net.ipv4.tcp_window_scaling` | 1 | Enables large TCP windows for streaming |
| `net.ipv4.tcp_fastopen` | 3 | Reduces TCP handshake latency |
| `kernel.dmesg_restrict` | 1 | Restricts kernel log to root |
| `net.core.rmem_max` | RAM-aware | Receive buffer, scaled to device memory |
| `net.core.wmem_max` | RAM-aware | Send buffer, scaled to device memory |

### `system`
- Mounts `/tmp` as `tmpfs` (size = RAM / 4, clamped to [32 MB, 128 MB]) to reduce
  flash wear and improve temp file I/O
- Configures `logrotate` for e2-setup logs (daily, 7 days) and enigma2.log (weekly, 4 weeks)
- Audits root filesystem mount options and warns if `noatime` is not set

### `health`
Read-only diagnostic report — safe to run at any time, does not modify the system.

| Section | Checks |
|---|---|
| System | Hostname, kernel, uptime, load average, image version |
| Memory | RAM used/available, swap status |
| Disk | Usage per mount point, `/tmp` type, root fullness |
| Temperature | All thermal zones in `/sys/class/thermal/` |
| Time | System clock, year sanity check, NTP peer status |
| Enigma2 | Process status, uptime, crash indicators in log |
| Network | Interface states, IP addresses, listening ports |

## Backup & Rollback

Every run creates a timestamped backup under `/var/backups/e2-setup/` containing:
- Enigma2 settings file
- `sysctl.conf`
- Installed package list
- Bouquet files (`.tar.gz`)

A `latest` symlink always points to the most recent backup.

```bash
./e2-setup.sh --rollback       # Restore latest backup
./e2-setup.sh --list-backups   # Show available snapshots
```

## Requirements

- Root access
- `opkg` package manager (Enigma2 device)
- Internet connectivity
- Minimum 100 MB free disk space

## Compatibility

Tested on: **OpenATV**, **OpenPLi**, **OE-Alliance**, **OpenVIX**, **PurE2**

## License

MIT — see [LICENSE](LICENSE).