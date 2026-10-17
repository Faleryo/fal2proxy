#!/usr/bin/env bash
# gost-server.sh — Install and configure gost server (ws:// + wss://)
# Usage: bash gost-server.sh [install|start|stop|restart|status|uninstall]
set -euo pipefail

GOST_VERSION="2.12.0"
GOST_DIR="/opt/gost"
GOST_BIN="/usr/local/bin/gost"
GOST_USER="gost"
GOST_GROUP="gost"
WS_PORT=8080
WSS_PORT=8443
SSH_BACKEND=""  # not needed for gost server (proxy mode)
DOMAIN="${DOMAIN:-saily.flashservice.org}"
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"

log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die(){ echo "[ERROR] $*" >&2; exit 1; }
need_root(){ [ "$(id -u)" -eq 0 ] || die "Run as root."; }

detect_arch(){
  case "$(uname -m)" in
    x86_64) echo "amd64" ;;
    aarch64) echo "arm64" ;;
    armv7l) echo "armv7" ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
  esac
}

install_gost(){
  need_root
  ARCH=$(detect_arch)
  if [ -x "$GOST_BIN" ]; then
    log "gost already installed: $($GOST_BIN -V 2>&1 | head -1)"
    return
  fi
  log "Downloading gost v$GOST_VERSION ($ARCH)..."
  TMPDIR=$(mktemp -d)
  URL="https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/gost_${GOST_VERSION}_linux_${ARCH}.tar.gz"
  curl -fsSL "$URL" -o "$TMPDIR/gost.tar.gz"
  tar xzf "$TMPDIR/gost.tar.gz" -C "$TMPDIR"
  install -m 755 "$TMPDIR/gost" "$GOST_BIN"
  rm -rf "$TMPDIR"
  log "gost installed: $($GOST_BIN -V 2>&1 | head -1)"
}

create_user(){
  need_root
  getent group "$GOST_GROUP" >/dev/null || groupadd "$GOST_GROUP"
  id "$GOST_USER" >/dev/null 2>&1 || useradd -r -g "$GOST_GROUP" -s /usr/sbin/nologin -d "$GOST_DIR" "$GOST_USER"
  mkdir -p "$GOST_DIR"
  chown "$GOST_USER:$GOST_GROUP" "$GOST_DIR"
}

# ws:// server (port 80 via nginx)
create_ws_config(){
  mkdir -p "$GOST_DIR"
  cat > "$GOST_DIR/start-ws.sh" <<EOF
#!/usr/bin/env bash
# ws:// mode: gost proxy server on port $WS_PORT
exec $GOST_BIN -L "ws://:$WS_PORT"
EOF
  chmod +x "$GOST_DIR/start-ws.sh"
}

# wss:// server (port 443 via nginx)
create_wss_config(){
  mkdir -p "$GOST_DIR"
  cat > "$GOST_DIR/start-wss.sh" <<EOF
#!/usr/bin/env bash
# wss:// mode: gost proxy server (TLS) on port $WSS_PORT
# Requires TLS cert for $DOMAIN
exec $GOST_BIN -L "wss://:$WSS_PORT?cert=$CERT_DIR/fullchain.pem\&key=$CERT_DIR/privkey.pem"
EOF
  chmod +x "$GOST_DIR/start-wss.sh"
}

# systemd services
create_services(){
  need_root
  # ws service
  cat > /etc/systemd/system/gost-ws.service <<EOF
[Unit]
Description=gost WebSocket server (ws:// port $WS_PORT)
After=network.target

[Service]
Type=simple
User=$GOST_USER
Group=$GOST_GROUP
ExecStart=$GOST_DIR/start-ws.sh
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  # wss service
  cat > /etc/systemd/system/gost-wss.service <<EOF
[Unit]
Description=gost WebSocket+TLS server (wss:// port $WSS_PORT)
After=network.target

[Service]
Type=simple
User=$GOST_USER
Group=$GOST_GROUP
ExecStart=$GOST_DIR/start-wss.sh
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

install_cert(){
  need_root
  if [ -d "$CERT_DIR" ]; then
    log "TLS cert already exists for $DOMAIN"
    return
  fi
  log "Installing certbot for Let's Encrypt..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y >/dev/null 2>&1
    apt-get install -y certbot >/dev/null 2>&1
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y certbot >/dev/null 2>&1
  elif command -v yum >/dev/null 2>&1; then
    yum install -y certbot >/dev/null 2>&1
  fi
  log "Obtaining TLS cert for $DOMAIN..."
  certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" 2>&1 | tail -5
  if [ -d "$CERT_DIR" ]; then
    log "TLS cert obtained"
  else
    log "WARNING: TLS cert not obtained. wss:// mode will not work."
    log "Run manually: certbot certonly --standalone -d $DOMAIN"
  fi
}

start_services(){
  need_root
  systemctl enable --now gost-ws >/dev/null 2>&1
  if [ -d "$CERT_DIR" ]; then
    systemctl enable --now gost-wss >/dev/null 2>&1
  else
    log "Skipping gost-wss (no TLS cert)"
  fi
  log "gost services started"
}

stop_services(){
  need_root
  systemctl stop gost-ws gost-wss 2>/dev/null || true
  log "gost services stopped"
}

status(){
  echo "=== gost server status ==="
  for svc in gost-ws gost-wss; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${svc}.service"; then
      echo "  $svc: $(systemctl is-active $svc 2>/dev/null)"
    fi
  done
  echo
  echo "Listening ports:"
  ss -tlnp | grep -E ":(80|443|8080|8443)" 2>/dev/null
  echo
  echo "gost version: $($GOST_BIN -V 2>&1 | head -1)"
}

uninstall(){
  need_root
  systemctl disable --now gost-ws gost-wss 2>/dev/null || true
  rm -f /etc/systemd/system/gost-ws.service /etc/systemd/system/gost-wss.service
  systemctl daemon-reload
  rm -rf "$GOST_DIR"
  rm -f "$GOST_BIN"
  log "gost uninstalled"
}

# Main
case "${1:-install}" in
  install)
    install_gost
    create_user
    create_ws_config
    create_wss_config
    create_services
    install_cert
    start_services
    echo
    echo "=== gost server installed ==="
    echo "ws://  : port $WS_PORT (via nginx 80)"
    echo "wss:// : port $WSS_PORT (via nginx 443, if cert available)"
    echo "Mode: proxy server (no backend needed)"
    echo
    status
    ;;
  start)   start_services ;;
  stop)    stop_services ;;
  restart) stop_services; start_services ;;
  status)  status ;;
  uninstall) uninstall ;;
  *) die "Usage: $0 [install|start|stop|restart|status|uninstall]" ;;
esac
EOF
chmod +x /home/pierre/fal2proxy/deploy/gost-server.sh 2>/dev/null || { mkdir -p /home/pierre/fal2proxy/deploy; chmod +x /home/pierre/fal2proxy/deploy/gost-server.sh; }
echo "created"