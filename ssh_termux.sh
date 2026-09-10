#!/usr/bin/env bash
# ssh_termux.sh - one-shot Termux SSH + Tailscale bootstrap across one restart
# Usage: curl -fsSL tinyurl.com/27u9kagf | bash
# Stage 1 (now): installs openssh + termux-services, arms resume hook.
#   -> force-stop Termux, reopen.
# Stage 2 (auto, background): sv-enable sshd, sv up sshd, then tailscale termux.sh.
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
# sv/sv-enable need SVDIR; SSH non-interactive shells don't inherit it.
export SVDIR="$PREFIX/var/service"
SELF_URL="https://raw.githubusercontent.com/HugoCirca/tailscale/1.102.3-android-dev/ssh_termux.sh"
FLAG="$HOME/.ssh_termux_stage2"
LOCK="$HOME/.ssh_termux_lock"
HOOK="$PREFIX/etc/profile.d/zz-ssh-termux-resume.sh"
TS_URL="https://tinyurl.com/28cmqfk4"

stage2() {
  termux-wake-lock 2>/dev/null || true
  echo "[1/4] Ensuring packages + service dirs..."
  pkg install -y openssh termux-services iproute2 curl
  # Service dir must exist or sv-enable fails like before.
  [ -d "$PREFIX/var/service/sshd" ] || pkg reinstall openssh
  echo "[2/4] Host keys + sshd service..."
  ssh-keygen -A 2>/dev/null || true
  sv-enable sshd
  sv up sshd
  sv status sshd
  echo "[3/4] IP + user..."
  whoami
  ip -4 addr 2>/dev/null | grep inet || ifconfig 2>/dev/null || true
  echo "[4/4] Tailscale (termux.sh)..."
  curl -fsSL "$TS_URL" | bash
  echo ""
  echo "Done. Next: run 'passwd', copy your PC key to ~/.ssh/authorized_keys,"
  echo "then: tailscale ssh <user>@<100.x>  (or ssh -p 8022 <user>@<lan-ip>)"
  # Success: disarm (hook removes itself too).
  rm -f "$FLAG" "$HOOK" "$LOCK"
}

if [ "${1:-}" = "--stage2" ]; then
  if ! stage2; then
    echo "STAGE2 FAILED - will retry on next Termux login" >&2
    rm -rf "$LOCK"
    exit 1
  fi
  exit 0
fi

if [ -f "$FLAG" ]; then
  # Re-ran manually ($0 is unreliable when piped): re-download and run stage 2.
  curl -fsSL "$SELF_URL" | bash -s -- --stage2
  exit $?
fi

echo "[stage 1/2] Installing openssh + termux-services..."
pkg update -y
pkg install -y openssh termux-services iproute2 curl
# Reinstall AFTER termux-services so $PREFIX/var/service/sshd gets created
# (otherwise sv-enable fails: "unable to change to service directory").
[ -d "$PREFIX/var/service/sshd" ] || pkg reinstall openssh
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock || true

echo "[stage 1/2] Arming resume hook (re-downloads self, no local copy needed)..."
mkdir -p "$PREFIX/etc/profile.d"
cat > "$HOOK" <<EOF
# one-shot: resume ssh_termux.sh stage 2 after Termux restart (backgrounded).
# Lock makes it retry-safe: failure keeps FLAG so next login retries.
if [ -f "\$HOME/.ssh_termux_stage2" ]; then
  if mkdir "\$HOME/.ssh_termux_lock" 2>/dev/null; then
    P="\${PREFIX:-/data/data/com.termux/files/usr}"
    echo "[ssh_termux] resuming stage 2 in background, log: \$P/tmp/ssh_termux_stage2.log"
    nohup bash -c 'curl -fsSL "$SELF_URL" | bash -s -- --stage2' > "\$P/tmp/ssh_termux_stage2.log" 2>&1 &
  fi
fi
EOF
touch "$FLAG"
rm -rf "$LOCK"

echo ""
echo "Stage 1 done. Now force-stop Termux (swipe away ALL sessions) and reopen."
echo "Stage 2 (sv-enable sshd + tailscale) resumes automatically in background."
echo "Watch: cat \$PREFIX/tmp/ssh_termux_stage2.log"
