#!/usr/bin/env bash
# HugoCirca/tailscale Termux auto-installer for android CLI
# Usage: curl -fsSL https://raw.githubusercontent.com/HugoCirca/tailscale/1.102.3-android-dev/termux.sh | bash
# or: bash termux.sh [--authkey tskey-...] [--ssh] [--hostname my-phone] [--no-sv] [--sv-now]
# Default hostname comes from ro.product.model (e.g. vivo-v2204).
# Default sets up the runit service files but only sv-enables after a Termux
# restart (runsvdir must be running; otherwise `sv up` fails like sshd did).
set -euo pipefail

REPO="HugoCirca/tailscale"
TAG="v1.102.3-android"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
BIN_DIR="$PREFIX/bin"
STATE_DIR="$PREFIX/var/lib/tailscale"
SOCK_DIR="$PREFIX/var/run/tailscale"
SOCK="$SOCK_DIR/tailscaled.sock"
SVDIR="$PREFIX/var/service/tailscaled"
SETUP_SV="defer"

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
    --no-sv) SETUP_SV="no"; shift ;;
    --sv-now) SETUP_SV="now"; shift ;;
    --hostname) HOSTNAME="--hostname=$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

# Default hostname: phone model (e.g. vivo V2204 -> vivo-v2204).
# /tmp does not exist on Termux, logs live under $PREFIX/tmp.
if [ -z "$HOSTNAME" ] && command -v getprop >/dev/null 2>&1; then
  MODEL="$(getprop ro.product.model 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-' | sed 's/^-\+//;s/-\+$//;s/--\+/-/g')"
  if [ -n "$MODEL" ]; then
    HOSTNAME="--hostname=$MODEL"
    echo "  hostname: $MODEL (from ro.product.model)"
  fi
fi
LOG_FILE="$PREFIX/tmp/tailscaled.log"

echo "[1/6] Preparing dirs..."
mkdir -p "$BIN_DIR" "$STATE_DIR" "$SOCK_DIR" "$PREFIX/tmp"
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock || true

echo "[2/6] Downloading $TAG ($GOARCH)..."
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

echo "[3/6] Installing to $BIN_DIR..."
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

echo "[4/6] Setting up runit service (sv)..."
if [ "$SETUP_SV" = "no" ]; then
  echo "  Skipped (--no-sv)."
else
  mkdir -p "$SVDIR/log" "$PREFIX/etc/profile.d"
  cat > "$SVDIR/run" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
exec "$BIN_DIR/tailscaled" --state="$STATE_DIR/tailscaled.state" --socket="$SOCK"
EOF
  cat > "$SVDIR/log/run" <<EOF
#!/data/data/com.termux/files/usr/bin/sh
exec svlogd -tt ./main
EOF
  chmod +x "$SVDIR/run" "$SVDIR/log/run"
  # Keep disabled until Termux restarts (runsvdir not running yet).
  # Same trap as sshd: sv up now would fail with
  # "unable to change to service directory".
  touch "$SVDIR/down"
  # One-shot hook: on next Termux shell restart, hand tailscaled to runsv.
  cat > "$PREFIX/etc/profile.d/zz-tailscaled-sv.sh" <<EOF
# one-shot: enable tailscaled runit service after Termux restart (self-removes flag)
if [ -f "\$HOME/.tailscaled-sv-pending" ]; then
  if command -v sv-enable >/dev/null 2>&1; then
    pkill tailscaled 2>/dev/null || true
    sv-enable tailscaled 2>/dev/null || sv up tailscaled 2>/dev/null || true
    rm -f "\$HOME/.tailscaled-sv-pending"
  fi
fi
EOF
  touch "$HOME/.tailscaled-sv-pending"
  echo "  Service files written to $SVDIR (disabled until restart)."
  if [ "$SETUP_SV" = "now" ]; then
    echo "  --sv-now: trying immediate enable (fails gracefully without runsvdir)..."
    sv-enable tailscaled 2>/dev/null || sv up tailscaled 2>/dev/null || echo "  runsvdir not running yet — will enable on next restart."
  else
    echo "  Restart Termux (swipe away all sessions, reopen) to sv-enable."
  fi
fi

echo "[5/6] Starting tailscaled (nohup, until restart hands it to runsv)..."
pkill tailscaled 2>/dev/null || true
sleep 1
# default is tailscale0,userspace-networking on android - no flag needed, works rooted or not
nohup "$BIN_DIR/tailscaled" --state="$STATE_DIR/tailscaled.state" --socket="$SOCK" > "$LOG_FILE" 2>&1 &
sleep 2
if ! pgrep -f tailscaled >/dev/null 2>&1 && ! pidof tailscaled >/dev/null 2>&1; then
  echo "tailscaled failed to start, log:"
  cat "$LOG_FILE" 2>/dev/null | head -n 50
  exit 1
fi
echo "  tailscaled running (log: $LOG_FILE)"

echo "[6/6] Bringing up tailscale..."
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
echo "  logcat | grep tailscale  # or cat $PREFIX/tmp/tailscaled.log"
echo "  After Termux restart: sv status tailscaled"
