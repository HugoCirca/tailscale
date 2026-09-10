#!/usr/bin/env bash
# HugoCirca/tailscale Termux auto-installer for android CLI
# Usage: curl -fsSL https://raw.githubusercontent.com/HugoCirca/tailscale/1.102.3-android-dev/termux.sh | bash
# or: bash termux.sh [--authkey tskey-...] [--ssh] [--hostname my-phone]
set -euo pipefail

REPO="HugoCirca/tailscale"
TAG="v1.102.3-android"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
BIN_DIR="$PREFIX/bin"
STATE_DIR="$PREFIX/var/lib/tailscale"
SOCK_DIR="$PREFIX/var/run/tailscale"
SOCK="$SOCK_DIR/tailscaled.sock"

ARCH="$(uname -m)"
case "$ARCH" in
  aarch64|arm64) GOARCH="arm64" ;;
  armv7*|arm) GOARCH="arm" ;;
  x86_64|amd64) GOARCH="amd64" ;;
  *) echo "Unknown arch: $ARCH (use arm64/arm)"; exit 1 ;;
esac

AUTHKEY=""
SSH="--ssh"
HOSTNAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --authkey) AUTHKEY="$2"; shift 2 ;;
    --no-ssh) SSH=""; shift ;;
    --hostname) HOSTNAME="--hostname=$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

echo "[1/5] Preparing dirs..."
mkdir -p "$BIN_DIR" "$STATE_DIR" "$SOCK_DIR"
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock || true

echo "[2/5] Downloading $TAG ($GOARCH)..."
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
VER="${TAG#v}"
VER="${VER%%-*}"
URL="https://github.com/$REPO/releases/download/$TAG/tailscale_${VER}_${GOARCH}.tgz"
echo "  -> $URL"
if command -v curl >/dev/null 2>&1; then
  curl -fL "$URL" -o "$TMPDIR/ts.tgz"
elif command -v wget >/dev/null 2>&1; then
  wget -O "$TMPDIR/ts.tgz" "$URL"
else
  echo "Need curl or wget"; exit 1
fi

echo "[3/5] Installing to $BIN_DIR..."
tar xzf "$TMPDIR/ts.tgz" -C "$TMPDIR"
# tgz contains ./tailscale and ./tailscaled (or ./tailscaled.arm64)
find "$TMPDIR" -maxdepth 2 -type f -name "tailscale*" -exec chmod +x {} \;
# move both
if ls "$TMPDIR"/tailscale >/dev/null 2>&1; then mv -f "$TMPDIR"/tailscale "$BIN_DIR"/ 2>/dev/null || true; fi
if ls "$TMPDIR"/tailscaled >/dev/null 2>&1; then mv -f "$TMPDIR"/tailscaled "$BIN_DIR"/ 2>/dev/null || true; fi
# handle arm64 named files
for f in "$TMPDIR"/tailscaled.* "$TMPDIR"/tailscale_*; do [ -f "$f" ] && cp -f "$f" "$BIN_DIR"/tailscaled 2>/dev/null || true; [ -f "$f" ] && cp -f "$f" "$BIN_DIR"/tailscale 2>/dev/null || true; done
chmod +x "$BIN_DIR"/tailscale* 2>/dev/null || true
# ensure symlink for combined binary
[ -f "$BIN_DIR/tailscaled" ] && ln -sf tailscaled "$BIN_DIR/tailscale" 2>/dev/null || true

echo "  Installed: $(ls -lh "$BIN_DIR"/tailscale* 2>/dev/null | awk '{print $9, $5}')"

echo "[4/5] Starting tailscaled..."
pkill tailscaled 2>/dev/null || true
sleep 1
# default is tailscale0,userspace-networking on android - no flag needed, works rooted or not
nohup "$BIN_DIR/tailscaled" --state="$STATE_DIR/tailscaled.state" --socket="$SOCK" > /tmp/tailscaled.log 2>&1 &
sleep 2
if ! pgrep -f tailscaled >/dev/null 2>&1 && ! pidof tailscaled >/dev/null 2>&1; then
  echo "tailscaled failed to start, log:"
  cat /tmp/tailscaled.log 2>/dev/null | head -n 50
  exit 1
fi
echo "  tailscaled running (log: /tmp/tailscaled.log)"

echo "[5/5] Bringing up tailscale..."
if [ -n "$AUTHKEY" ]; then
  echo "  Using authkey..."
  "$BIN_DIR/tailscale" --socket="$SOCK" up --authkey="$AUTHKEY" $SSH $HOSTNAME
else
  echo "  No authkey — starting interactive login (device link)..."
  echo "  Visit the URL below on any browser to authenticate:"
  echo ""
  # This will print: To authenticate, visit: https://login.tailscale.com/a/XXXX
  "$BIN_DIR/tailscale" --socket="$SOCK" up $SSH $HOSTNAME
  echo ""
  echo "  Waiting for login... (re-run 'tailscale --socket=$SOCK status' to check)"
fi

echo ""
echo "Done. Useful:"
echo "  tailscale --socket=$SOCK status"
echo "  tailscale --socket=$SOCK ip -4"
echo "  logcat | grep tailscale  # or cat /tmp/tailscaled.log"
