#!/usr/bin/env bash
# gost-client.sh — Install and configure gost client (ws:// or wss://)
# Usage: bash gost-client.sh [install|ws|wss|start|stop|status]
set -euo pipefail

GOST_VERSION="2.12.0"
GOST_DIR="${HOME}/.gost"
GOST_BIN="${HOME}/.local/bin/gost"
PROXY_PORT=1080
SERVER="${SERVER:-saily.flashservice.org}"
SERVER_PORT_WS=2082
SERVER_PORT_WSS=2083
SNI="${SNI:-saily.flashservice.org}"
HOST="${HOST:-saily.flashservice.org}"

log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die(){ echo "[ERROR] $*" >&2; exit 1; }

detect_arch(){
  case "$(uname -m)" in
    x86_64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l) echo "armv7" ;;
    i386|i686) echo "386" ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
  esac
}

# Detect OS for download URL
detect_os(){
  case "$(uname -s)" in
    Linux) echo "linux" ;;
    Darwin) echo "darwin" ;;
    *) die "Unsupported OS: $(uname -s)" ;;
  esac
}

install_gost(){
  OS=$(detect_os)
  ARCH=$(detect_arch)
  if [ -x "$GOST_BIN" ]; then
    log "gost already installed: $($GOST_BIN -V 2>&1 | head -1)"
    return
  fi
  mkdir -p "$(dirname "$GOST_BIN")" "$GOST_DIR"
  log "Downloading gost v$GOST_VERSION ($OS/$ARCH)..."
  TMPDIR=$(mktemp -d)
  URL="https://github.com/ginuerzh/gost/releases/download/v${GOST_VERSION}/gost_${GOST_VERSION}_${OS}_${ARCH}.tar.gz"
  curl -fsSL "$URL" -o "$TMPDIR/gost.tar.gz"
  tar xzf "$TMPDIR/gost.tar.gz" -C "$TMPDIR"
  install -m 755 "$TMPDIR/gost" "$GOST_BIN"
  rm -rf "$TMPDIR"
  log "gost installed: $($GOST_BIN -V 2>&1 | head -1)"
  echo "Add to PATH: export PATH=\"\$HOME/.local/bin:\$PATH\""
}

# Mode ws:// (port 80, zero-rating)
config_ws(){
  mkdir -p "$GOST_DIR"
  cat > "$GOST_DIR/ws.sh" <<EOF
#!/usr/bin/env bash
# gost client: ws:// mode (zero-rating via Cloudflare port 2082)
# Creates SOCKS5 proxy on port $PROXY_PORT
exec $GOST_BIN -L "socks5://:$PROXY_PORT" -F "ws://$SERVER:$SERVER_PORT_WS?host=$HOST"
EOF
  chmod +x "$GOST_DIR/ws.sh"
  log "Configured ws:// mode → SOCKS5 on port $PROXY_PORT"
  log "  Server: $SERVER:$SERVER_PORT_WS"
  log "  SNI: $SNI"
  log "  Host: $HOST"
}

# Mode wss:// (port 2083, TLS)
config_wss(){
  mkdir -p "$GOST_DIR"
  cat > "$GOST_DIR/wss.sh" <<EOF
#!/usr/bin/env bash
# gost client: wss:// mode (TLS on port 2083)
# Creates SOCKS5 proxy on port $PROXY_PORT
exec $GOST_BIN -L "socks5://:$PROXY_PORT" -F "wss://$SERVER:$SERVER_PORT_WSS?host=$HOST&sni=$HOST"
EOF
  chmod +x "$GOST_DIR/wss.sh"
  log "Configured wss:// mode → SOCKS5 on port $PROXY_PORT"
  log "  Server: $SERVER:$SERVER_PORT_WSS"
  log "  SNI: $SNI"
  log "  Host: $HOST"
}

start_ws(){
  config_ws
  log "Starting gost client (ws:// mode)..."
  nohup "$GOST_DIR/ws.sh" > "$GOST_DIR/ws.log" 2>&1 &
  echo $! > "$GOST_DIR/ws.pid"
  sleep 1
  if kill -0 "$(cat "$GOST_DIR/ws.pid")" 2>/dev/null; then
    log "gost ws client started (PID $(cat "$GOST_DIR/ws.pid"))"
    log "SOCKS5 proxy available on 127.0.0.1:$PROXY_PORT"
  else
    log "Failed to start. Check $GOST_DIR/ws.log"
    cat "$GOST_DIR/ws.log"
  fi
}

start_wss(){
  config_wss
  log "Starting gost client (wss:// mode)..."
  nohup "$GOST_DIR/wss.sh" > "$GOST_DIR/wss.log" 2>&1 &
  echo $! > "$GOST_DIR/wss.pid"
  sleep 1
  if kill -0 "$(cat "$GOST_DIR/wss.pid")" 2>/dev/null; then
    log "gost wss client started (PID $(cat "$GOST_DIR/wss.pid"))"
    log "SOCKS5 proxy available on 127.0.0.1:$PROXY_PORT"
  else
    log "Failed to start. Check $GOST_DIR/wss.log"
    cat "$GOST_DIR/wss.log"
  fi
}

stop(){
  for mode in ws wss; do
    if [ -f "$GOST_DIR/$mode.pid" ]; then
      PID=$(cat "$GOST_DIR/$mode.pid")
      kill "$PID" 2>/dev/null || true
      rm -f "$GOST_DIR/$mode.pid"
      log "Stopped $mode client (PID $PID)"
    fi
  done
}

status(){
  echo "=== gost client status ==="
  for mode in ws wss; do
    if [ -f "$GOST_DIR/$mode.pid" ]; then
      PID=$(cat "$GOST_DIR/$mode.pid")
      if kill -0 "$PID" 2>/dev/null; then
        echo "  $mode: running (PID $PID)"
      else
        echo "  $mode: dead (stale PID)"
      fi
    else
      echo "  $mode: not running"
    fi
  done
  echo
  echo "SOCKS5 proxy: 127.0.0.1:$PROXY_PORT"
  echo "gost binary: $GOST_BIN"
  echo "gost version: $($GOST_BIN -V 2>&1 | head -1)"
}

case "${1:-install}" in
  install)
    install_gost
    config_ws
    config_wss
    echo
    echo "=== gost client installed ==="
    echo "Usage:"
    echo "  bash gost-client.sh ws     # start ws:// mode (zero-rating)"
    echo "  bash gost-client.sh wss    # start wss:// mode (TLS)"
    echo "  bash gost-client.sh stop   # stop all"
    echo "  bash gost-client.sh status # show status"
    echo
    echo "SOCKS5 proxy will be available on 127.0.0.1:$PROXY_PORT"
    echo "Configure your browser/apps to use SOCKS5 127.0.0.1:$PROXY_PORT"
    ;;
  ws)     start_ws ;;
  wss)    start_wss ;;
  start)  start_ws ;;
  stop)   stop ;;
  status) status ;;
  *) die "Usage: $0 [install|ws|wss|start|stop|status]" ;;
esac
EOF
echo "created"