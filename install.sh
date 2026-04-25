#!/bin/sh
# install.sh — Remote bootstrap for e2-setup
#
# Downloads the latest release tarball from GitHub and runs e2-setup.sh.
# Designed for Enigma2 devices that have wget and tar but no git.
#
# Usage (run directly on the device):
#   wget -qO /tmp/install.sh https://raw.githubusercontent.com/0x733/E2/main/install.sh
#   sh /tmp/install.sh [e2-setup options...]
#
# Or in a single pipeline:
#   wget -qO- https://raw.githubusercontent.com/0x733/E2/main/install.sh | sh

set -eu

REPO_TARBALL="https://github.com/0x733/E2/archive/refs/heads/main.tar.gz"
INSTALL_DIR="/tmp/e2-setup-remote"

# ── helpers ──────────────────────────────────────────────────────────────────

die() { echo "[ERROR] $*" >&2; exit 1; }
info() { echo "[INFO ] $*"; }
ok()   { echo "[ OK  ] $*"; }

# ── sanity checks ────────────────────────────────────────────────────────────

[ "$(id -u)" -eq 0 ] || die "Run as root (e.g. sudo sh install.sh)"
command -v wget >/dev/null 2>&1 || die "wget is required but not found"
command -v tar  >/dev/null 2>&1 || die "tar is required but not found"

# ── download ─────────────────────────────────────────────────────────────────

TARBALL="/tmp/e2-setup-main.tar.gz"

info "Downloading e2-setup from GitHub..."
if ! wget -q --timeout=30 -O "$TARBALL" "$REPO_TARBALL"; then
    die "Download failed: $REPO_TARBALL"
fi
ok "Download complete"

# ── extract ──────────────────────────────────────────────────────────────────

rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

if ! tar -xzf "$TARBALL" -C "$INSTALL_DIR" --strip-components=1; then
    rm -f "$TARBALL"
    die "Extraction failed"
fi
rm -f "$TARBALL"
ok "Extracted to $INSTALL_DIR"

# ── run ──────────────────────────────────────────────────────────────────────

chmod +x "$INSTALL_DIR/e2-setup.sh"
info "Launching e2-setup.sh $*"
exec "$INSTALL_DIR/e2-setup.sh" "$@"
