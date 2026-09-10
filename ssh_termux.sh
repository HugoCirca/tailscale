#!/usr/bin/env bash
# ssh_termux.sh - one-shot Termux SSH + Tailscale bootstrap across one restart
# Usage: curl -fsSL https://raw.githubusercontent.com/HugoCirca/tailscale/1.102.3-android-dev/ssh_termux.sh | bash
# Stage 1 (now): installs openssh + termux-services, arms resume hook.
#   -> force-stop Termux, reopen.
# Stage 2 (auto, background): sv-enable sshd, sv up sshd, then tailscale termux.sh.
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
SELF_URL="https://raw.githubusercontent.com/HugoCirca/tailscale/1.102.3-android-dev/ssh_termux.sh"
SELF_LOCAL="$HOME/.ssh_termux.sh"
FLAG="$HOME/.ssh_termux_stage2"
HOOK="$PREFIX/etc/profile.d/zz-ssh-termux-resume.sh"
TS_URL="https://tinyurl.com/28cmqfk4"

stage2() {
  termux-wake-lock 2>/dev/null || true
  echo "[1/4] Host keys..."
  ssh-keygen -A 2>/dev/null || true
  echo "[2/4] Enabling sshd service..."
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
}

if [ "${1:-}" = "--stage2" ]; then
  stage2
  exit 0
fi

if [ -f "$FLAG" ]; then
  # Re-ran after restart without force-stop: just do stage 2 now.
  rm -f "$FLAG" "$HOOK"
  stage2
  exit 0
fi

echo "[stage 1/2] Installing openssh + termux-services..."
pkg update -y
pkg install -y openssh termux-services iproute2 curl
# Reinstall AFTER termux-services so $PREFIX/var/service/sshd gets created
# (otherwise sv-enable fails: "unable to change to service directory").
pkg reinstall openssh
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock || true

echo "[stage 1/2] Saving self + arming resume hook..."
if command -v curl >/dev/null 2>&1; then
  curl -fsSL -o "$SELF_LOCAL" "$SELF_URL" || cp "$0" "$SELF_LOCAL" 2>/dev/null || true
fi
mkdir -p "$PREFIX/etc/profile.d"
cat > "$HOOK" <<'EOF'
# one-shot: resume ssh_termux.sh stage 2 after Termux restart (backgrounded)
if [ -f "$HOME/.ssh_termux_stage2" ]; then
  rm -f "$HOME/.ssh_termux_stage2"
  P="${PREFIX:-/data/data/com.termux/files/usr}"
  rm -f "$P/etc/profile.d/zz-ssh-termux-resume.sh"
  echo "[ssh_termux] resuming stage 2 in background, log: $P/tmp/ssh_termux_stage2.log"
  nohup bash "$HOME/.ssh_termux.sh" --stage2 > "$P/tmp/ssh_termux_stage2.log" 2>&1 &
fi
EOF
touch "$FLAG"

echo ""
echo "Stage 1 done. Now force-stop Termux (swipe away ALL sessions) and reopen."
echo "Stage 2 (sv-enable sshd + tailscale) resumes automatically in background."
echo "Watch: cat \$PREFIX/tmp/ssh_termux_stage2.log"
