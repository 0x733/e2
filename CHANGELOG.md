# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [2.4.0] — 2026-04-25

### Added
- `lib/utils.sh`: `invalidate_pkg_cache()` — clears the `is_installed` cache after
  any install or remove operation so subsequent checks reflect the current package
  state; previously the stale cache could cause packages to be reported as installed
  after removal or vice-versa.
- `modules/emulators.sh`: `_emulators_preinstall_oscam()` — attempts `opkg install oscam-emu`
  before running the Levi45 installer. If oscam is available in the OE-Alliance feed
  the Levi45 installer detects it already present and skips its own download step,
  eliminating the most common cause of emulator installation failures.
- `modules/performance.sh`: `_ensure_sysctl_boot_persistence()` — creates
  `/etc/init.d/e2-performance` and registers it via `update-rc.d` or an `/etc/rc5.d`
  symlink so sysctl tweaks survive reboots. Previously the drop-in file was written
  but never loaded at boot because busybox `sysctl` does not process `/etc/sysctl.d/`.

### Fixed
- `modules/emulators.sh`: Levi45 installer output is now captured; on failure the last
  10 lines are surfaced as ERROR log entries so the actual cause (e.g. a failed oscam
  download URL) is visible instead of a generic "execution failed" message.
- `modules/performance.sh`: sysctl settings are now applied one-by-one with
  `sysctl -w key=value` instead of `sysctl -p <file>`. The old approach stopped at
  the first unsupported parameter, leaving all subsequent valid settings unapplied.
  Unsupported parameters are now skipped with a warning and a summary
  (`N applied, M skipped`) is logged.
- `modules/packages.sh`: removed a redundant `((ERRORS++))` in the feed download
  error path — `log_error` already increments the counter, so errors were being
  double-counted in the summary table.
- `modules/packages.sh`: `invalidate_pkg_cache` called after each successful
  `opkg install` so subsequent `is_installed` checks reflect reality.
- `modules/bloatware.sh`: `invalidate_pkg_cache` called after each successful
  `opkg remove` for the same reason.
- `modules/update.sh`: `opkg list-upgradable` is no longer called in dry-run mode.
  Previously this executed a real system command even when `--dry-run` was active.
- `e2-setup.sh`: `print_summary` return value is now checked (`print_summary || exit 1`).
  Previously the script always exited with code 0 even when errors were recorded.
- `modules/backup.sh`: `list_backups` now skips the `latest` symlink. The `*/` glob
  followed the symlink and listed the target directory a second time.
- `modules/health.sh`: `/proc/$pid/stat` paths now properly quoted.
- `lib/preflight.sh`: network check now tries HTTP (`wget`) before falling back to
  ICMP ping, which is blocked on some networks and Enigma2 firmware configurations.

---

## [2.3.0] — 2026-04-25

### Added
- `install.sh` — single-file POSIX bootstrap script; allows downloading and running
  the project on Enigma2 devices (which have no `git`) with a single `wget` command.
  Downloads the GitHub tarball (`/archive/refs/heads/main.tar.gz`) to
  `/tmp/e2-setup-remote/` and launches `e2-setup.sh`, forwarding all arguments.
- `lib/constants.sh`: `REPO_BASE`, `REPO_TARBALL`, `REPO_INSTALLER` — single-source
  constants for all repository URLs.
- `README.md`: "Installation" section — one-liner wget command with usage examples.

### Fixed
- `lib/utils.sh`: `download_verified()` now logs the actual URL instead of the
  temp filename (`Downloading: http://…`).
- `modules/packages.sh`: feed download failures now increment the `ERRORS` counter;
  previously the error was logged but not reflected in the summary table.
- `modules/performance.sh`: `sysctl -p` errors are no longer silenced; the first
  `sysctl: …` line is appended to the warning. Also fixed a return-code masking issue
  caused by combining `local` with assignment (`sysctl_rc=$?` moved to its own line).

---

## [2.2.0] — 2026-04-24

### Added
- `modules/security.sh` — installs `ca-certificates` to enable proper HTTPS verification
- `modules/ntp.sh` — forces immediate clock sync via `ntpdate`; tries pool.ntp.org,
  time.google.com, and time.cloudflare.com in sequence; warns if year < 2020
- `modules/system.sh` — mounts `/tmp` as RAM-proportional `tmpfs`, configures `logrotate`
  for e2-setup and enigma2 logs, audits `noatime` on root filesystem
- `modules/health.sh` — read-only diagnostic report covering RAM, disk, temperature,
  time, Enigma2 process status, and network listeners
- `--health` CLI flag (alias for `--only=health`); bypasses preflight and backup since
  it makes no changes
- `--only=security|ntp|system|health` module selectors
- `lib/utils.sh`: `get_total_ram_mb()` — reads `/proc/meminfo` for runtime RAM detection
- `lib/utils.sh`: `download_verified()` — downloads to a temp file, shows SHA-256,
  requires user confirmation when no expected checksum is provided; never silently
  executes unverified content
- `modules/performance.sh`: `_compute_net_buf()` — scales `rmem_max`/`wmem_max` to
  `RAM / 32`, clamped to [256 KB, 1 MB]
- New sysctl parameters: `vm.overcommit_memory=1`, `fs.inotify.max_user_watches=8192`,
  `net.ipv4.tcp_window_scaling=1`, `net.ipv4.tcp_fastopen=3`, `kernel.dmesg_restrict=1`

### Changed
- `vm.vfs_cache_pressure` corrected from `200` → `50`: 200 aggressively evicts VFS cache
  on embedded devices, causing repeated flash re-reads and increased latency
- `vm.dirty_ratio` corrected from `15` → `10`: on 256 MB RAM, 15% means 38 MB of
  unwritten data can accumulate before blocking I/O, causing GUI freezes during recording
- `net.core.rmem_max` and `net.core.wmem_max` removed from the static `SYSCTL_TWEAKS`
  array; values are now computed at runtime based on available RAM
- `modules/packages.sh`: removed `--no-check-certificate` from the feed wget call;
  installer is now downloaded via `download_verified()` before execution
- `modules/emulators.sh`: emulator installer now uses `download_verified()` pattern
- `e2-setup.sh`: new modules sourced in pipeline order (security → ntp → … → system)
- `e2-setup.sh`: full pipeline now runs `mod_install_ca_certs` and `mod_configure_ntp`
  before `mod_update_system` to ensure certificates and time are correct first
- `README.md`: complete rewrite — added module descriptions, sysctl rationale table,
  health section breakdown, updated options reference

### Security
- Feed and emulator installers no longer piped directly to bash from a URL;
  they are downloaded first, SHA-256 is shown, and user confirmation is required
- `ca-certificates` installed as the first pipeline step so all subsequent HTTPS
  requests benefit from proper certificate validation

---

## [2.1.0] — 2026-04-24

### Changed
- Refactored monolithic script into a modular structure (`lib/` + `modules/`)
- `e2-setup.sh` is now a thin orchestrator that sources all components
- `run()` no longer uses `eval` — arguments passed directly, eliminating shell injection
- `is_installed()` caches `opkg list-installed` output to avoid repeated invocations
- Bouquet backup rewritten with an array to safely handle filenames with spaces
- `sed` value substitution now escapes `|` and `\` to prevent delimiter collisions
- `confirm()` prompt updated to `[y/e/N]` to match accepted inputs
- `START_TIME` initialized to `0` in runtime state to prevent `set -u` crash

### Fixed
- `print_summary()` crash when `START_TIME` was unset and `set -u` was active

---

## [2.0.0] — 2026-04-23

### Added
- Idempotent package installation and settings updates
- Automatic configuration backup with timestamped directories and `latest` symlink
- `--rollback` to restore any backup in one command
- `--list-backups` to enumerate available snapshots
- `--dry-run` mode — previews all commands without executing
- `--only=MODULE` to run a single pipeline step
- `--skip-*` flags for each module
- Color-coded, leveled logging (INFO / OK / WARN / ERROR / DEBUG / DRY)
- Log written to `/var/log/e2-setup/setup-<timestamp>.log`
- Lock file at `/var/lock/e2-setup.lock` to prevent concurrent runs
- Trap-based cleanup on EXIT, INT, and TERM signals
- Pre-flight checks: root, opkg, network, disk space
- Sysctl drop-in file (`/etc/sysctl.d/99-e2-performance.conf`) instead of
  appending to `/etc/sysctl.conf`
- Summary report with counters and elapsed time

---

## [1.0.0] — Initial release

- Basic setup script: update, plugin install, feed configuration, emulator install,
  bloatware removal, sysctl tweaks
