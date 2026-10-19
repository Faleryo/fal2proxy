#!/usr/bin/env bash
# fal2proxy - common helpers
set -u

FAL_DIR="/opt/fal2proxy"
FAL_BIN="/usr/local/bin/fal2proxy"
FAL_GROUP="fal2proxy"
FAL_PREFIX="fp_"
SSH_PORT="22"
WS_PORT="8080"
HTTP_PORT="80"
HTTPS_PORT="443"
INJECT_HOST="saily.flashservice.org"
PROXY_HOST="saily.flashservice.org"
PROXY_PORT="80"
INJECT_PORT="38443"   # rawbridge direct (sans Cloudflare)
# IP publique du serveur (pour SSH direct : le domaine orange-cloud ne porte pas le 22)
SSH_HOST="${SSH_HOST:-$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[\d.]+' | head -1)}"
[ -n "${SSH_HOST:-}" ] || SSH_HOST="$(hostname -I 2>/dev/null | awk '{print $1}')"
DEFAULT_QUOTA_MB="0"   # 0 = unlimited
DEFAULT_EXPIRY_DAYS="30"
NGINX_CONF="/etc/nginx/sites-available/fal2proxy"
NGINX_LINK="/etc/nginx/sites-enabled/fal2proxy"

log(){ echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
err(){ echo "[ERROR] $*" >&2; }
die(){ err "$*"; exit 1; }

need_root(){ [ "$(id -u)" -eq 0 ] || die "Run as root."; }

cmd_exists(){ command -v "$1" >/dev/null 2>&1; }

# distro detection
detect_distro(){
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
    DISTRO_LIKE="${ID_LIKE:-}"
  else
    DISTRO_ID="unknown"; DISTRO_LIKE=""
  fi
  PKG_MGR=""
  if cmd_exists apt-get; then PKG_MGR="apt"
  elif cmd_exists dnf; then PKG_MGR="dnf"
  elif cmd_exists yum; then PKG_MGR="yum"
  elif cmd_exists pacman; then PKG_MGR="pacman"
  elif cmd_exists zypper; then PKG_MGR="zypper"
  elif cmd_exists apk; then PKG_MGR="apk"
  fi
  [ -n "$PKG_MGR" ] || die "Unsupported package manager."
}

pkg_install(){
  # $@ packages
  detect_distro
  case "$PKG_MGR" in
    apt) apt-get update -y >/dev/null 2>&1; DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
    dnf) dnf install -y "$@" ;;
    yum) yum install -y "$@" ;;
    pacman) pacman -Sy --noconfirm "$@" ;;
    zypper) zypper install -y "$@" ;;
    apk) apk add --no-cache "$@" ;;
  esac
}

svc_enable_start(){
  # $1 service name
  if cmd_exists systemctl; then
    systemctl enable --now "$1" >/dev/null 2>&1
  elif cmd_exists service; then
    service "$1" start >/dev/null 2>&1
    update-rc.d "$1" defaults >/dev/null 2>&1 || chkconfig "$1" on >/dev/null 2>&1 || true
  fi
}

svc_restart(){
  if cmd_exists systemctl; then systemctl restart "$1"
  elif cmd_exists service; then service "$1" restart
  fi
}

svc_status(){
  if cmd_exists systemctl; then systemctl is-active "$1" 2>/dev/null
  elif cmd_exists service; then service "$1" status >/dev/null 2>&1 && echo active || echo inactive
  fi
}

ensure_group(){
  getent group "$FAL_GROUP" >/dev/null || groupadd "$FAL_GROUP"
}

user_exists(){ id "$1" >/dev/null 2>&1; }

ensure_nologin_shell(){
  if ! grep -qxF /usr/sbin/nologin /etc/shells 2>/dev/null; then
    echo /usr/sbin/nologin >> /etc/shells
  fi
}
