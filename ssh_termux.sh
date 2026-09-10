#!/usr/bin/env bash
# ssh_termux.sh - one-shot Termux SSH (+optional Tailscale) bootstrap across one restart
# Usage:
#   SSH only (no curl needed after this line):
#     curl -fsSL tinyurl.com/27u9kagf | bash -s -- --ssh-only
#   Full (SSH + Tailscale, needs working curl in stage 2):
#     curl -fsSL tinyurl.com/27u9kagf | bash
# Stage 1 (now): installs openssh + termux-services, arms resume hook.
#   -> force-stop Termux, reopen.
# Stage 2 (auto, background): sv-enable sshd, sv up sshd, then tailscale unless --ssh-only.
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
# sv/sv-enable need SVDIR; SSH non-interactive shells don't inherit it.
export SVDIR="$PREFIX/var/service"
SELF_URL="https://raw.githubusercontent.com/HugoCirca/tailscale/1.102.3-android-dev/ssh_termux.sh"
STAGE2_LOCAL="$HOME/.ssh_termux_stage2.sh"
SSHONLY_FLAG="$HOME/.ssh_termux_sshonly"
FLAG="$HOME/.ssh_termux_stage2"
LOCK="$HOME/.ssh_termux_lock"
HOOK="$PREFIX/etc/profile.d/zz-ssh-termux-resume.sh"
TS_URL="https://tinyurl.com/28cmqfk4"

SSH_ONLY="no"

write_stage2_local() {
  # Saved stage 2: runs from local disk, no curl needed (survives broken curl).
  cat > "$STAGE2_LOCAL" <<'STAGE2_EOF'
#!/usr/bin/env bash
set -euo pipefail
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export SVDIR="$PREFIX/var/service"
SSHONLY_FLAG="$HOME/.ssh_termux_sshonly"
FLAG="$HOME/.ssh_termux_stage2"
HOOK="$PREFIX/etc/profile.d/zz-ssh-termux-resume.sh"
LOCK="$HOME/.ssh_termux_lock"
TS_URL="https://tinyurl.com/28cmqfk4"
trap 'rm -rf "$LOCK"' EXIT

termux-wake-lock 2>/dev/null || true
echo "[1/4] Ensuring packages + service dirs..."
pkg install -y openssh termux-services iproute2 curl
[ -d "$PREFIX/var/service/sshd" ] || pkg reinstall openssh
echo "[2/4] Host keys + sshd service..."
ssh-keygen -A 2>/dev/null || true
sv-enable sshd
sv up sshd
sv status sshd
echo "[3/4] IP + user..."
whoami
ip -4 addr 2>/dev/null | grep inet || ifconfig 2>/dev/null || true
if [ -f "$SSHONLY_FLAG" ]; then
  echo "[4/4] Skipped Tailscale (--ssh-only)."
else
  echo "[4/4] Tailscale (termux.sh, needs working curl)..."
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$TS_URL" | bash
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$TS_URL" | bash
  else
    echo "No curl/wget. Fix with: apt update && apt full-upgrade" >&2
    exit 1
  fi
fi
echo ""
echo "Done. Next: run 'passwd', copy your PC key to ~/.ssh/authorized_keys,"
echo "then: ssh -p 8022 <user>@<lan-ip>  (or tailscale ssh <user>@<100.x>)"
rm -f "$FLAG" "$HOOK" "$LOCK" "$SSHONLY_FLAG"
STAGE2_EOF
  chmod +x "$STAGE2_LOCAL"
}

run_stage2() {
  if ! bash "$STAGE2_LOCAL"; then
    echo "STAGE2 FAILED - will retry on next Termux login" >&2
    rm -rf "$LOCK"
    exit 1
  fi
}

for arg in "$@"; do
  case "$arg" in
    --ssh-only) SSH_ONLY="yes" ;;
    --stage2) RUN_STAGE2="yes" ;;
  esac
done

if [ "${RUN_STAGE2:-no}" = "yes" ]; then
  [ "$SSH_ONLY" = "yes" ] && touch "$SSHONLY_FLAG" || true
  write_stage2_local
  run_stage2
  exit 0
fi

if [ -f "$FLAG" ]; then
  # Re-ran manually: refresh local copy, run stage 2 in foreground.
  [ "$SSH_ONLY" = "yes" ] && touch "$SSHONLY_FLAG" || true
  write_stage2_local
  run_stage2
  exit 0
fi

echo "[stage 1/2] Installing openssh + termux-services..."
pkg update -y
pkg install -y openssh termux-services iproute2 curl
# Reinstall AFTER termux-services so $PREFIX/var/service/sshd gets created
# (otherwise sv-enable fails: "unable to change to service directory").
[ -d "$PREFIX/var/service/sshd" ] || pkg reinstall openssh
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock || true

echo "[stage 1/2] Saving stage 2 locally + arming resume hook (no curl needed)..."
[ "$SSH_ONLY" = "yes" ] && touch "$SSHONLY_FLAG" || true
write_stage2_local
mkdir -p "$PREFIX/etc/profile.d"
cat > "$HOOK" <<EOF
# one-shot: resume ssh_termux stage 2 after Termux restart (backgrounded, local file).
# Lock makes it retry-safe: failure keeps FLAG so next login retries.
if [ -f "\$HOME/.ssh_termux_stage2" ]; then
  if mkdir "\$HOME/.ssh_termux_lock" 2>/dev/null; then
    P="\${PREFIX:-/data/data/com.termux/files/usr}"
    echo "[ssh_termux] resuming stage 2 in background, log: \$P/tmp/ssh_termux_stage2.log"
    nohup bash "\$HOME/.ssh_termux_stage2.sh" > "\$P/tmp/ssh_termux_stage2.log" 2>&1 &
  fi
fi
EOF
touch "$FLAG"
rm -rf "$LOCK"

echo ""
echo "Stage 1 done. Now force-stop Termux (swipe away ALL sessions) and reopen."
echo "Stage 2 (sv-enable sshd$([ "$SSH_ONLY" = "yes" ] || echo " + tailscale")) resumes automatically in background."
echo "Watch: cat \$PREFIX/tmp/ssh_termux_stage2.log"
