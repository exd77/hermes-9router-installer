#!/usr/bin/env bash
set -Eeuo pipefail

# Auto installer for Hermes Agent + Hermes gateway config + 9Router dashboard.
# Sources:
#   - https://hermes-agent.nousresearch.com/
#   - https://github.com/decolua/9router

HERMES_INSTALL_URL="${HERMES_INSTALL_URL:-https://hermes-agent.nousresearch.com/install.sh}"
NINE_ROUTER_REPO="${NINE_ROUTER_REPO:-https://github.com/decolua/9router.git}"
NINE_ROUTER_PORT="${NINE_ROUTER_PORT:-20128}"
NINE_ROUTER_HOST="${NINE_ROUTER_HOST:-0.0.0.0}"
NINE_ROUTER_BASE_URL="${NINE_ROUTER_BASE_URL:-http://localhost:${NINE_ROUTER_PORT}}"
INSTALL_ROOT="${INSTALL_ROOT:-$HOME/.local/share/hermes-9router}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
SERVICE_DIR="$HOME/.config/systemd/user"
DESKTOP_AUTOSTART_DIR="$HOME/.config/autostart"
TRAY_NAME="9router-background"
SKILLS_SRC_DIR="${SKILLS_SRC_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/skills}"
HERMES_SKILLS_DIR="${HERMES_SKILLS_DIR:-$HERMES_HOME/skills}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { printf "${BLUE}==>${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}WARN:${NC} %s\n" "$*"; }
ok() { printf "${GREEN}OK:${NC} %s\n" "$*"; }
fail() { printf "${RED}ERROR:${NC} %s\n" "$*" >&2; exit 1; }
has() { command -v "$1" >/dev/null 2>&1; }

usage() {
  cat <<EOF
Usage: $0 [command]

Commands:
  install          Install Hermes + 9Router, setup service, setup tray launcher (default)
  start            Start 9Router background service
  stop             Stop 9Router background service
  restart          Restart 9Router background service
  status           Show 9Router service status
  dashboard        Open or print 9Router dashboard URL
  logs            Follow 9Router logs
  skills          Install Hermes skills from ${SKILLS_SRC_DIR}
  uninstall       Remove 9Router service/tray files only; keep Hermes and npm package

Environment overrides:
  NINE_ROUTER_PORT=20128
  NINE_ROUTER_HOST=0.0.0.0
  NINE_ROUTER_BASE_URL=http://localhost:20128
  HERMES_HOME=$HOME/.hermes
  INSTALL_ROOT=$HOME/.local/share/hermes-9router
EOF
}

ensure_path() {
  mkdir -p "$BIN_DIR"
  case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) export PATH="$BIN_DIR:$PATH" ;;
  esac
}

ensure_base_tools() {
  log "Checking required tools"
  local missing=()
  has curl || missing+=(curl)
  has git || missing+=(git)
  has python3 || missing+=(python3)

  if ((${#missing[@]})); then
    warn "Missing: ${missing[*]}"
    if has apt-get; then
      log "Installing missing packages via apt-get"
      sudo apt-get update
      sudo apt-get install -y curl git python3 python3-venv python3-pip xdg-utils ca-certificates gnupg
    else
      fail "Install missing tools manually first: ${missing[*]}"
    fi
  fi

  ensure_node_22
  ensure_native_build_toolchain
}

ensure_node_22() {
  local node_major=0
  if has node; then
    node_major="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
  fi
  if [ "${node_major:-0}" -ge 22 ]; then
    ok "Node $(node -v) is OK (≥22 required for 9Router node:sqlite fallback)"
    return 0
  fi

  warn "Node ${node_major:-missing} < 22 detected. 9Router needs Node ≥22.5 for the built-in node:sqlite driver."
  if ! has apt-get; then
    fail "Please install Node.js ≥22 manually, then rerun the installer."
  fi

  log "Installing Node.js 22 from NodeSource"
  if has node && has apt-get; then
    sudo apt-get remove -y nodejs npm 2>/dev/null || true
  fi
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
  sudo apt-get install -y nodejs

  if ! has node; then
    fail "Node.js install via NodeSource failed"
  fi
  ok "Node $(node -v) installed"
}

ensure_native_build_toolchain() {
  # better-sqlite3 native build needs python3 + make + g++ + build-essential.
  # If the toolchain is missing, npm silently skips the optional dep and
  # 9Router falls back to node:sqlite (or sql.js — which often fails too).
  if has make && has g++ && has python3; then
    ok "Native build toolchain present (make, g++, python3)"
    return 0
  fi
  if ! has apt-get; then
    warn "Native build toolchain incomplete and apt-get not available."
    warn "better-sqlite3 will likely be skipped; install build-essential + python3 manually."
    return 0
  fi
  log "Installing native build toolchain (build-essential, python3, make, g++)"
  sudo apt-get install -y build-essential python3 make g++ pkg-config libsqlite3-dev
}

install_hermes() {
  log "Installing Hermes Agent from ${HERMES_INSTALL_URL}"
  mkdir -p "$HERMES_HOME"
  curl -fsSL "$HERMES_INSTALL_URL" | HERMES_HOME="$HERMES_HOME" bash -s -- --skip-setup

  if has hermes; then
    ok "Hermes CLI installed: $(command -v hermes)"
  elif [ -x "$HERMES_HOME/hermes-agent/venv/bin/hermes" ]; then
    ln -sf "$HERMES_HOME/hermes-agent/venv/bin/hermes" "$BIN_DIR/hermes"
    ok "Hermes CLI linked to $BIN_DIR/hermes"
  else
    warn "Hermes installed, but CLI was not found in PATH. Open a new shell or inspect $HERMES_HOME/hermes-agent."
  fi

  install_hermes_gateway
}

install_hermes_gateway() {
  log "Installing Hermes gateway via 'hermes gateway install'"
  local hermes_bin=""
  if has hermes; then
    hermes_bin="$(command -v hermes)"
  elif [ -x "$BIN_DIR/hermes" ]; then
    hermes_bin="$BIN_DIR/hermes"
  elif [ -x "$HERMES_HOME/hermes-agent/venv/bin/hermes" ]; then
    hermes_bin="$HERMES_HOME/hermes-agent/venv/bin/hermes"
  else
    warn "hermes CLI not found, skipping 'hermes gateway install'"
    return 0
  fi

  if "$hermes_bin" gateway install </dev/null; then
    ok "Hermes gateway installed"
  else
    warn "'hermes gateway install' returned non-zero. Re-run manually after install: $hermes_bin gateway install"
  fi

  setup_hermes_gateway "$hermes_bin"
}

setup_hermes_gateway() {
  local hermes_bin="$1"

  echo
  printf "${GREEN}========================================${NC}\n"
  printf "${GREEN} Hermes Gateway Setup (Telegram)${NC}\n"
  printf "${GREEN}========================================${NC}\n"
  echo "Sebentar lagi 'hermes gateway setup' jalan dan minta:"
  echo "  - Telegram bot token (dari @BotFather)"
  echo "  - Chat ID / username yang boleh chat dengan bot"
  echo
  echo "Cara dapat bot token:"
  echo "  1. Telegram -> cari @BotFather"
  echo "  2. Kirim /newbot, ikutin instruksinya"
  echo "  3. Copy token (format: 12345:ABCDEF...) dan paste pas diminta"
  echo

  if [ ! -t 0 ]; then
    warn "Stdin bukan TTY (kemungkinan dijalankan via 'curl | bash')."
    warn "Setup gateway butuh input interaktif. Jalanin manual setelah install:"
    echo "  $hermes_bin gateway setup"
    return 0
  fi

  if "$hermes_bin" gateway setup; then
    ok "Hermes gateway setup selesai"
  else
    warn "'hermes gateway setup' selesai dengan error/cancel. Bisa diulang manual:"
    echo "  $hermes_bin gateway setup"
    return 0
  fi

  log "Restart gateway service supaya token Telegram dipakai"
  "$hermes_bin" gateway restart </dev/null || warn "Gagal restart gateway, coba manual: $hermes_bin gateway restart"
  "$hermes_bin" gateway status </dev/null || true
}

install_9router() {
  log "Installing 9Router CLI globally via 'sudo npm i -g 9router'"
  if has sudo; then
    sudo npm i -g --foreground-scripts 9router
  else
    npm i -g --foreground-scripts 9router
  fi

  if ! has 9router; then
    fail "9Router CLI not found after npm install. Pastikan global npm bin ada di PATH."
  fi
  ok "9Router CLI installed: $(command -v 9router)"

  ensure_9router_sqlite_driver
}

ensure_9router_sqlite_driver() {
  # Make sure 9Router has a working SQLite driver. Without one, the dashboard
  # crashes with: "[DB] No SQLite driver available (bun/better/node/sql.js all failed)".
  # better-sqlite3 is an optionalDependency in 9router, so it gets skipped
  # silently when the native toolchain is missing or the npm registry
  # downloads a non-matching prebuilt for the host CPU.
  log "Ensuring 9Router has a working SQLite driver (better-sqlite3 native build)"

  local nine_dir=""
  if has 9router; then
    local bin
    bin="$(readlink -f "$(command -v 9router)" 2>/dev/null || command -v 9router)"
    nine_dir="$(dirname "$(dirname "$bin")")/lib/node_modules/9router"
  fi
  [ -d "$nine_dir" ] || nine_dir="$(npm root -g 2>/dev/null)/9router"

  if [ ! -d "$nine_dir" ]; then
    warn "Could not locate 9router install dir; skipping driver hardening."
    return 0
  fi

  if [ -d "$nine_dir/node_modules/better-sqlite3/build/Release" ] && \
     ls "$nine_dir/node_modules/better-sqlite3/build/Release"/*.node >/dev/null 2>&1; then
    ok "better-sqlite3 native binding already present"
    return 0
  fi

  log "Building better-sqlite3 inside ${nine_dir}"
  local NPM_RUN="npm i better-sqlite3 --foreground-scripts --build-from-source --no-save"
  if has sudo; then
    if sudo bash -c "cd '$nine_dir' && $NPM_RUN"; then
      ok "better-sqlite3 built from source for 9Router"
      return 0
    fi
  else
    if (cd "$nine_dir" && eval "$NPM_RUN"); then
      ok "better-sqlite3 built from source for 9Router"
      return 0
    fi
  fi

  warn "better-sqlite3 build failed. 9Router will try node:sqlite (Node ≥22.5) or sql.js."
  if has node; then
    local nv
    nv="$(node -p 'process.versions.node' 2>/dev/null || echo unknown)"
    warn "Current Node version: $nv. Need ≥22.5 for the node:sqlite fallback."
  fi
}

write_helpers() {
  log "Writing helper commands"
  mkdir -p "$BIN_DIR"

  cat > "$BIN_DIR/9router-bg" <<EOF
#!/usr/bin/env bash
set -euo pipefail
export PORT="${NINE_ROUTER_PORT}"
export HOSTNAME="${NINE_ROUTER_HOST}"
export NEXT_PUBLIC_BASE_URL="${NINE_ROUTER_BASE_URL}"
exec 9router
EOF
  chmod +x "$BIN_DIR/9router-bg"

  cat > "$BIN_DIR/9router-dashboard" <<EOF
#!/usr/bin/env bash
set -euo pipefail
url="${NINE_ROUTER_BASE_URL}/dashboard"
if command -v xdg-open >/dev/null 2>&1 && [ -n "\${DISPLAY:-}\${WAYLAND_DISPLAY:-}" ]; then
  nohup xdg-open "\$url" >/dev/null 2>&1 &
else
  echo "Dashboard: \$url"
fi
EOF
  chmod +x "$BIN_DIR/9router-dashboard"
}

write_systemd_service() {
  log "Creating user systemd service for hidden/background 9Router"
  mkdir -p "$SERVICE_DIR"
  cat > "$SERVICE_DIR/9router.service" <<EOF
[Unit]
Description=9Router AI Gateway Dashboard
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=PORT=${NINE_ROUTER_PORT}
Environment=HOSTNAME=${NINE_ROUTER_HOST}
Environment=NEXT_PUBLIC_BASE_URL=${NINE_ROUTER_BASE_URL}
Environment=PATH=${BIN_DIR}:${HOME}/.npm-global/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=${BIN_DIR}/9router-bg
Restart=always
RestartSec=5
WorkingDirectory=${HOME}

[Install]
WantedBy=default.target
EOF

  if has systemctl; then
    systemctl --user daemon-reload || warn "systemctl --user daemon-reload failed"
    systemctl --user enable 9router.service || warn "Could not enable user service"
    loginctl enable-linger "$USER" >/dev/null 2>&1 || true
    ok "User service ready: 9router.service"
  else
    warn "systemd not found; use '9router-bg &' to run manually"
  fi
}

write_tray_launcher() {
  log "Creating desktop autostart entry for tray/background behavior"
  mkdir -p "$DESKTOP_AUTOSTART_DIR"
  cat > "$DESKTOP_AUTOSTART_DIR/${TRAY_NAME}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=9Router Background
Comment=Start 9Router dashboard/gateway in background
Exec=${BIN_DIR}/9router-bg
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

  cat > "$BIN_DIR/9router-tray" <<'EOF'
#!/usr/bin/env bash
# Run `9router` and immediately Hide to tray (Background).
# Priority:
#   1. Real desktop tray via kdocker / alltray (only with $DISPLAY/$WAYLAND_DISPLAY).
#   2. systemd --user service (recommended for VPS/headless).
#   3. nohup background fallback.
set -euo pipefail

PORT="${PORT:-20128}"
HOSTNAME="${HOSTNAME:-0.0.0.0}"
NEXT_PUBLIC_BASE_URL="${NEXT_PUBLIC_BASE_URL:-http://localhost:${PORT}}"
export PORT HOSTNAME NEXT_PUBLIC_BASE_URL

if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
  if command -v kdocker >/dev/null 2>&1; then
    exec kdocker -q -i /usr/share/icons/hicolor/48x48/apps/9router.png -n "9Router" 9router
  fi
  if command -v alltray >/dev/null 2>&1; then
    exec alltray 9router
  fi
fi

if command -v systemctl >/dev/null 2>&1 && systemctl --user list-unit-files 9router.service >/dev/null 2>&1; then
  systemctl --user restart 9router.service
  sleep 1
  systemctl --user --no-pager status 9router.service || true
  echo
  echo "9Router is hidden to background (systemd user service)."
  echo "Dashboard: ${NEXT_PUBLIC_BASE_URL}/dashboard"
  exit 0
fi

LOG="${HOME}/.9router-bg.log"
nohup 9router >"$LOG" 2>&1 &
disown || true
echo "9Router started in background (PID $!). Log: $LOG"
echo "Dashboard: ${NEXT_PUBLIC_BASE_URL}/dashboard"
EOF
  chmod +x "$BIN_DIR/9router-tray"

  ok "Tray/autostart file created: $DESKTOP_AUTOSTART_DIR/${TRAY_NAME}.desktop"
  warn "Real tray icon needs a desktop session plus kdocker/alltray. On headless Ubuntu, systemd background mode is used."
}

write_hermes_gateway_note() {
  log "Writing Hermes + 9Router gateway notes"
  mkdir -p "$HERMES_HOME"
  cat > "$HERMES_HOME/9router-gateway.env" <<EOF
# Use this gateway endpoint for OpenAI-compatible clients/providers.
OPENAI_BASE_URL=${NINE_ROUTER_BASE_URL}/v1
OPENAI_API_BASE=${NINE_ROUTER_BASE_URL}/v1
NINE_ROUTER_DASHBOARD=${NINE_ROUTER_BASE_URL}/dashboard

# Copy the API key from the 9Router dashboard after adding a provider/account.
# Example:
# OPENAI_API_KEY=your-9router-api-key
EOF
  ok "Gateway note: $HERMES_HOME/9router-gateway.env"
}

install_skills() {
  if [ ! -d "$SKILLS_SRC_DIR" ]; then
    warn "No skills folder at $SKILLS_SRC_DIR, skipping skill install"
    return 0
  fi

  shopt -s nullglob
  local files=("$SKILLS_SRC_DIR"/*.md "$SKILLS_SRC_DIR"/*.MD)
  shopt -u nullglob

  if [ "${#files[@]}" -eq 0 ]; then
    warn "No .md skills in $SKILLS_SRC_DIR, skipping"
    return 0
  fi

  log "Installing ${#files[@]} skill(s) into ${HERMES_SKILLS_DIR}"
  mkdir -p "$HERMES_SKILLS_DIR"

  local f name slug target
  for f in "${files[@]}"; do
    name="$(awk '
      /^---[[:space:]]*$/ { fm = !fm; next }
      fm && /^name:[[:space:]]*/ {
        sub(/^name:[[:space:]]*/, "")
        gsub(/^["'\'']|["'\'']$/, "")
        print
        exit
      }
    ' "$f")"

    if [ -z "$name" ]; then
      name="$(basename "$f")"
      name="${name%.md}"
      name="${name%.MD}"
      name="${name%.SKILL}"
      name="${name%.skill}"
    fi

    slug="$(echo "$name" | tr '[:upper:] ' '[:lower:]-' | sed 's/[^a-z0-9._-]//g; s/--*/-/g; s/^-//; s/-$//')"
    [ -z "$slug" ] && slug="skill-$(date +%s)"

    target="$HERMES_SKILLS_DIR/$slug"
    mkdir -p "$target"
    cp -f "$f" "$target/SKILL.md"
    ok "Skill installed: $slug ($target/SKILL.md)"
  done
}

start_service() {
  if [ -x "$BIN_DIR/9router-tray" ]; then
    log "Starting 9Router and Hiding to tray (Background)"
    "$BIN_DIR/9router-tray" || warn "9router-tray exited non-zero"
    return 0
  fi

  if has systemctl; then
    systemctl --user daemon-reload || true
    systemctl --user restart 9router.service
    sleep 2
    systemctl --user --no-pager status 9router.service || true
  else
    nohup "$BIN_DIR/9router-bg" > "$INSTALL_ROOT/9router.log" 2>&1 &
    ok "9Router started with PID $!"
  fi
}

detect_public_ip() {
  local ip=""
  for url in https://api.ipify.org https://ifconfig.me https://ipinfo.io/ip https://icanhazip.com; do
    ip="$(curl -fsS --max-time 4 "$url" 2>/dev/null | tr -d '[:space:]')" || ip=""
    if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "$ip"
      return 0
    fi
  done
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [ -n "$ip" ] && echo "$ip" && return 0
  echo "localhost"
}

show_dashboard() {
  local public_ip
  public_ip="$(detect_public_ip)"
  local public_url="http://${public_ip}:${NINE_ROUTER_PORT}/dashboard"
  local local_url="${NINE_ROUTER_BASE_URL}/dashboard"
  if has xdg-open && [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    xdg-open "$public_url" >/dev/null 2>&1 &
  fi
  echo
  printf "${GREEN}========================================${NC}\n"
  printf "${GREEN} 9Router Dashboard${NC}\n"
  printf "${GREEN}========================================${NC}\n"
  printf "  Public:  %s\n" "$public_url"
  printf "  Local:   %s\n" "$local_url"
  printf "  API:     http://%s:%s/v1\n" "$public_ip" "$NINE_ROUTER_PORT"
  printf "${GREEN}========================================${NC}\n"
  echo
  warn "Pastikan port ${NINE_ROUTER_PORT} dibuka di security group/firewall VPS supaya URL public bisa diakses."
}

install_all() {
  ensure_path
  ensure_base_tools
  install_hermes
  install_9router
  write_helpers
  write_systemd_service
  write_tray_launcher
  write_hermes_gateway_note
  install_skills
  start_service
  show_dashboard
  ok "Install complete"
}

cmd="${1:-install}"
case "$cmd" in
  install) install_all ;;
  start) start_service ;;
  stop) systemctl --user stop 9router.service ;;
  restart) start_service ;;
  status) systemctl --user --no-pager status 9router.service ;;
  dashboard) show_dashboard ;;
  logs) journalctl --user -u 9router.service -f ;;
  skills) install_skills ;;
  uninstall)
    systemctl --user disable --now 9router.service 2>/dev/null || true
    rm -f "$SERVICE_DIR/9router.service" "$DESKTOP_AUTOSTART_DIR/${TRAY_NAME}.desktop" "$BIN_DIR/9router-bg" "$BIN_DIR/9router-dashboard" "$BIN_DIR/9router-tray"
    systemctl --user daemon-reload 2>/dev/null || true
    ok "Removed 9Router service/tray helper files"
    ;;
  -h|--help|help) usage ;;
  *) usage; fail "Unknown command: $cmd" ;;
esac
