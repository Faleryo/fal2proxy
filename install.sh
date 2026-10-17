#!/usr/bin/env bash
# fal2proxy installer
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

need_root
detect_distro

echo "=== fal2proxy installer ==="
echo "Distro: $DISTRO_ID ($PKG_MGR)"
echo "Installing dependencies..."

# base packages
case "$PKG_MGR" in
  apt) pkg_install openssh-server nginx fail2ban ufw curl wget python3 iptables cron ;;
  dnf|yum) pkg_install openssh-server nginx fail2ban ufw curl wget python3 iptables-services cronie ;;
  pacman) pkg_install openssh nginx fail2ban ufw curl wget python iptables cronie ;;
  zypper) pkg_install openssh nginx fail2ban ufw curl wget python3 iptables cron ;;
  apk) pkg_install openssh nginx fail2ban ufw curl wget python3 iptables cron ;;
esac

# ensure ssh service name
SSH_SVC="ssh"
if ! systemctl list-unit-files 2>/dev/null | grep -q '^ssh\.service'; then
  SSH_SVC="sshd"
fi

ensure_group
ensure_nologin_shell

# install rawbridge (C binary preferred, Python fallback)
mkdir -p "$FAL_DIR/bin" "$FAL_DIR/scripts"
if [ -f "$SCRIPT_DIR/rawbridge.c" ]; then
  cp "$SCRIPT_DIR/rawbridge.c" "$FAL_DIR/rawbridge.c"
fi
if command -v gcc >/dev/null 2>&1 && [ -f "$FAL_DIR/rawbridge.c" ]; then
  gcc -O2 -o "$FAL_DIR/bin/rawbridge" "$FAL_DIR/rawbridge.c" -lpthread 2>/dev/null && \
    log "rawbridge compiled (C)" || {
      log "gcc compile failed, falling back to Python"
      USE_PY=1
    }
else
  USE_PY=1
fi
if [ "${USE_PY:-0}" = "1" ]; then
  cat > "$FAL_DIR/scripts/rawbridge.py" <<'PYEOF'
import socket, select, threading
LISTEN = ("127.0.0.1", 8080)
BACKEND = ("127.0.0.1", 22)
BUF = 65536
def set_opts(s):
    s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 262144)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 262144)
    try: s.setsockopt(socket.IPPROTO_TCP, socket.TCP_QUICKACK, 1)
    except (AttributeError, OSError): pass
def handle(client):
    set_opts(client); buf = b""
    while b"\r\n\r\n" not in buf:
        r,_,_ = select.select([client],[],[],30)
        if not r: client.close(); return
        c = client.recv(4096)
        if not c: client.close(); return
        buf += c
    client.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
    try: backend = socket.create_connection(BACKEND, timeout=10)
    except Exception: client.close(); return
    set_opts(backend); sockets=[client,backend]
    try:
        while True:
            r,_,_ = select.select(sockets,[],[],60)
            if not r: break
            for src in r:
                dst = backend if src is client else client
                try: data = src.recv(BUF)
                except Exception: data = b""
                if not data: raise Exception("closed")
                view = memoryview(data)
                while view:
                    n = dst.send(view); view = view[n:]
    except Exception: pass
    finally:
        try: client.close()
        except: pass
        try: backend.close()
        except: pass
srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
srv.bind(LISTEN); srv.listen(512)
while True:
    c,_ = srv.accept(); set_opts(c)
    threading.Thread(target=handle, args=(c,), daemon=True).start()
PYEOF
  chmod +x "$FAL_DIR/scripts/rawbridge.py"
fi

# sshd hardening snippet
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/fal2proxy.conf <<EOF
# fal2proxy
Port $SSH_PORT
Compression yes
TCPKeepAlive yes
PasswordAuthentication yes
PubkeyAuthentication yes
PermitTunnel yes
AllowTcpForwarding yes
X11Forwarding no
MaxSessions 20
MaxStartups 30:30:60

Match Group $FAL_GROUP
    AllowTcpForwarding yes
    PermitTunnel yes
    X11Forwarding no
    PermitTTY no
    PasswordAuthentication yes
EOF
svc_restart "$SSH_SVC"

# nginx config
cat > "$NGINX_CONF" <<'EOF'
map $http_upgrade $connection_upgrade { default upgrade; '' close; }

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    listen 8443 default_server;
    listen [::]:8443 default_server;
    listen 38443 default_server;
    listen [::]:38443 default_server;
    server_name _;

    location / {
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_buffering off;
        proxy_request_buffering off;
        tcp_nodelay on;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_pass http://127.0.0.1:8080;
    }
}
EOF
ln -sf "$NGINX_CONF" "$NGINX_LINK"
rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
nginx -t && svc_restart nginx

# rawbridge systemd service
if [ -x "$FAL_DIR/bin/rawbridge" ]; then
  EXEC="$FAL_DIR/bin/rawbridge"
else
  EXEC="/usr/bin/python3 $FAL_DIR/scripts/rawbridge.py"
fi
cat > /etc/systemd/system/fal2proxy-raw.service <<EOF
[Unit]
Description=fal2proxy raw TCP bridge (HTTP upgrade to SSH)
After=network.target

[Service]
Type=simple
ExecStart=$EXEC
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
svc_enable_start fal2proxy-raw

# logrotate
if [ -f "$SCRIPT_DIR/logrotate-fal2proxy" ]; then
  cp "$SCRIPT_DIR/logrotate-fal2proxy" /etc/logrotate.d/fal2proxy
fi

# firewall
if cmd_exists ufw; then
  ufw allow $SSH_PORT/tcp >/dev/null 2>&1 || true
  ufw allow $HTTP_PORT/tcp >/dev/null 2>&1 || true
  ufw allow 8443/tcp >/dev/null 2>&1 || true
  ufw allow 38443/tcp >/dev/null 2>&1 || true
  ufw allow $HTTPS_PORT/tcp >/dev/null 2>&1 || true
  ufw --force enable >/dev/null 2>&1 || true
fi

# fail2ban
if cmd_exists fail2ban-client; then
  cat > /etc/fail2ban/jail.d/fal2proxy.conf <<EOF
[sshd]
enabled = true
port = $SSH_PORT
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600

[nginx-http-auth]
enabled = true
port = http,https
filter = nginx-http-auth
logpath = /var/log/nginx/error.log
maxretry = 5
bantime = 3600
EOF
  svc_restart fail2ban
fi

# install management script
mkdir -p "$FAL_DIR"
cp -r "$SCRIPT_DIR"/* "$FAL_DIR"/ 2>/dev/null || true
chmod +x "$FAL_DIR/fal2proxy.sh"
ln -sf "$FAL_DIR/fal2proxy.sh" "$FAL_BIN"

# quota cron (disabled by default)
mkdir -p /etc/cron.d
cat > /etc/cron.d/fal2proxy-quota <<'EOF'
# fal2proxy quota enforcement (disabled by default; enable via menu)
# */5 * * * * root /opt/fal2proxy/scripts/quota-enforce.sh >/dev/null 2>&1
EOF

# state files
mkdir -p "$FAL_DIR/data"
touch "$FAL_DIR/data/users.db"
chmod 600 "$FAL_DIR/data/users.db"

echo "=== Installation complete ==="
echo "Run: fal2proxy"
