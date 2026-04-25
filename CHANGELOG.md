# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [2.3.0] — 2026-04-25

### Added
- `install.sh` — tek dosya POSIX bootstrap betiği; Enigma2 cihazlarında
  `git` olmadan tek bir `wget` komutuyla projeyi indirip çalıştırmayı sağlar.
  GitHub tarball'ını (`/archive/refs/heads/main.tar.gz`) `/tmp/e2-setup-remote/`
  altına indirir ve `e2-setup.sh`'ı tüm argümanları geçirerek başlatır.
- `lib/constants.sh`: `REPO_BASE`, `REPO_TARBALL`, `REPO_INSTALLER` — repo URL'leri
  için tek kaynak sabitleri.
- `README.md`: "Installation" bölümü — tek satır wget komutu ve argüman örnekleri.

### Fixed
- `lib/utils.sh`: `download_verified()` artık geçici dosya adı yerine gerçek URL'yi
  logluyor (`Downloading: http://…`).
- `modules/packages.sh`: feed indirme hatası artık `ERRORS` sayacını artırıyor;
  önceden `[ERROR]` log'lanmasına rağmen özet tabloya yansımıyordu.
- `modules/performance.sh`: `sysctl -p` hatası artık susturulmuyor; başarısız olduğunda
  ilk `sysctl: …` satırı uyarıya ekleniyor. Ayrıca `local` atamasının dönüş kodunu
  maskeleme sorunu düzeltildi (`sysctl_rc=$?` ayrı satıra alındı).

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
