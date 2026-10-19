#!/usr/bin/env bash
# fal2proxy management menu
set -u
SCRIPT_DIR="/opt/fal2proxy"
source "$SCRIPT_DIR/lib/common.sh"

need_root

USERS_DB="$FAL_DIR/data/users.db"
touch "$USERS_DB"; chmod 600 "$USERS_DB"

pause(){ read -rp "Press Enter to continue..."; }

header(){ clear; echo "=============================="; echo "   fal2proxy - management"; echo "=============================="; echo; }

# ---------- user helpers ----------

db_get(){ grep "^$1:" "$USERS_DB" 2>/dev/null | head -1; }

add_client(){
  read -rp "Username: " u
  [ -z "$u" ] && { echo "Empty username."; pause; return; }
  u="${FAL_PREFIX}${u}"
  if user_exists "$u"; then echo "User already exists."; pause; return; fi
  read -rp "Password (blank = auto): " p
  [ -z "$p" ] && p="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 12)"
  read -rp "Expiry days (default $DEFAULT_EXPIRY_DAYS): " d
  [ -z "$d" ] && d="$DEFAULT_EXPIRY_DAYS"
  exp=$(( $(date +%s) + d*86400 ))
  read -rp "Max sessions (default 2): " ms
  [ -z "$ms" ] && ms="2"
  # create system user
  useradd -m -g "$FAL_GROUP" -s /usr/sbin/nologin "$u" 2>/dev/null || useradd -g "$FAL_GROUP" -s /usr/sbin/nologin "$u"
  echo "$u:$p" | chpasswd
  chage -E "$(date -d "@$exp" +%Y-%m-%d)" "$u" 2>/dev/null || true
  echo "${u}:${p}:${exp}:0:1:${ms}" >> "$USERS_DB"
  echo "Created client: $u"
  echo "Password: $p"
  echo "Expires: $(date -d "@$exp")"
  pause
}

delete_client(){
  read -rp "Username (without prefix): " u
  u="${FAL_PREFIX}${u}"
  if ! user_exists "$u"; then echo "User not found."; pause; return; fi
  userdel -r "$u" 2>/dev/null || userdel "$u"
  grep -v "^${u}:" "$USERS_DB" > "${USERS_DB}.tmp" && mv "${USERS_DB}.tmp" "$USERS_DB"
  echo "Deleted $u"
  pause
}

list_clients(){
  echo "Username            Status   Expires              QuotaMB  MaxSess"
  echo "----------------------------------------------------------------"
  while IFS=: read -r u p exp q en ms; do
    [ -z "$u" ] && continue
    if user_exists "$u"; then
      st="active"
      expd="$(date -d "@$exp" '+%Y-%m-%d %H:%M' 2>/dev/null || echo $exp)"
    else
      st="missing"
      expd="-"
    fi
    qdisp="$q"; [ "$q" = "0" ] && qdisp="unlimited"
    printf "%-18s %-8s %-20s %-8s %s\n" "$u" "$st" "$expd" "$qdisp" "$ms"
  done < "$USERS_DB"
  echo
  pause
}

modify_client(){
  read -rp "Username (without prefix): " u
  u="${FAL_PREFIX}${u}"
  line="$(db_get "$u")"
  [ -z "$line" ] && { echo "Not found."; pause; return; }
  IFS=: read -r _ p exp q en ms <<< "$line"
  echo "1) Change password"
  echo "2) Change expiry days"
  echo "3) Enable/Disable"
  echo "4) Change max sessions"
  echo "5) Change quota (MB, 0=unlimited)"
  read -rp "Choice: " c
  case "$c" in
    1) read -rp "New password: " np; p="$np"; echo "$u:$np" | chpasswd ;;
    2) read -rp "Days from now: " nd; exp=$(( $(date +%s) + nd*86400 )); chage -E "$(date -d "@$exp" +%Y-%m-%d)" "$u" 2>/dev/null || true ;;
    3) if [ "$en" = "1" ]; then en="0"; usermod -L "$u" 2>/dev/null || true; else en="1"; usermod -U "$u" 2>/dev/null || true; fi ;;
    4) read -rp "Max sessions: " nms; ms="$nms" ;;
    5) read -rp "Quota MB (0=unlimited): " nq; q="$nq" ;;
    *) echo "Invalid."; pause; return ;;
  esac
  grep -v "^${u}:" "$USERS_DB" > "${USERS_DB}.tmp" && mv "${USERS_DB}.tmp" "$USERS_DB"
  echo "${u}:${p}:${exp}:${q}:${en}:${ms}" >> "$USERS_DB"
  echo "Updated."
  pause
}

gen_link(){
  read -rp "Username (without prefix): " u
  u="${FAL_PREFIX}${u}"
  line="$(db_get "$u")"
  [ -z "$line" ] && { echo "Not found."; pause; return; }
  IFS=: read -r _ p exp q en ms <<< "$line"
  base_user="${u#${FAL_PREFIX}}"
  read -rp "Inject Host/SNI (default $INJECT_HOST): " h
  [ -z "$h" ] && h="$INJECT_HOST"
  read -rp "Proxy host (default $PROXY_HOST): " ph
  [ -z "$ph" ] && ph="$PROXY_HOST"
  read -rp "Proxy port (default $PROXY_PORT): " pp
  [ -z "$pp" ] && pp="$PROXY_PORT"
  payload="GET / HTTP/1.1[crlf]Host: ${h}[crlf]Connection: Upgrade[crlf]User-Agent: Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Mobile Safari/537.36[crlf]Upgrade: websocket[crlf]Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==[crlf]Sec-WebSocket-Version: 13[crlf][crlf]"
  python3 - "$base_user" "$p" "$h" "$ph" "$pp" "$payload" <<'PY'
import sys,json,base64
u,p,h,ph,pp,payload = sys.argv[1:7]
cfg={"type":"SSH","name":"fal2proxy",
  "sshTunnelConfig":{"sshConfig":{"username":u,"password":p},
  "injectConfig":{"mode":"PROXY","serverNameIndication":h,"proxyHost":ph,"proxyPort":int(pp),"payload":payload}}}
s=json.dumps(cfg,separators=(',',':'))
print("darktunnel://"+base64.b64encode(s.encode()).decode())
PY
  echo
  pause
}

gen_npv_link(){
  read -rp "Username (without prefix): " u
  u="${FAL_PREFIX}${u}"
  line="$(db_get "$u")"
  [ -z "$line" ] && { echo "Not found."; pause; return; }
  IFS=: read -r _ p exp q en ms <<< "$line"
  base_user="${u#${FAL_PREFIX}}"
  read -rp "Inject Host/SNI (default $INJECT_HOST): " h
  [ -z "$h" ] && h="$INJECT_HOST"
  read -rp "Proxy host (default $PROXY_HOST): " ph
  [ -z "$ph" ] && ph="$PROXY_HOST"
  read -rp "Proxy port (default $PROXY_PORT): " pp
  [ -z "$pp" ] && pp="$PROXY_PORT"
  read -rp "SSH host (default $ph): " sh
  [ -z "$sh" ] && sh="$ph"
  read -rp "SSH port (default $SSH_PORT): " sp
  [ -z "$sp" ] && sp="$SSH_PORT"
  payload="GET / HTTP/1.1[crlf]Host: ${h}[crlf]Connection: Upgrade[crlf]User-Agent: Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Mobile Safari/537.36[crlf]Upgrade: websocket[crlf]Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==[crlf]Sec-WebSocket-Version: 13[crlf][crlf]"
  python3 - "$base_user" "$p" "$h" "$ph" "$pp" "$sh" "$sp" "$payload" <<'PY'
import sys,json,base64
u,p,h,ph,pp,sh,sp,payload = sys.argv[1:9]
cfg={
  "sshConfigType":"SSH-Direct",
  "remarks":"fal2proxy",
  "sshHost":sh,
  "sshPort":int(sp),
  "sshUsername":u,
  "sshPassword":p,
  "sni":h,
  "httpProxy":f"{ph}:{pp}",
  "payload":payload,
  "dnsTTMode":"UDP",
  "udpgwTransparentDNS":True
}
s=json.dumps(cfg,separators=(',',':'))
print("npvt-ssh://"+base64.b64encode(s.encode()).decode())
PY
  echo
  pause
}

domains_menu(){
  echo "Current inject host: $INJECT_HOST"
  read -rp "New inject host (blank to keep): " nh
  [ -n "$nh" ] && INJECT_HOST="$nh"
  # persist
  sed -i "s/^INJECT_HOST=.*/INJECT_HOST=\"$INJECT_HOST\"/" "$SCRIPT_DIR/lib/common.sh"
  echo "Updated to $INJECT_HOST"
  pause
}

advanced_menu(){
  while true; do
    header
    echo "Advanced security"
    echo "1) Toggle fail2ban (restart)"
    echo "2) Toggle UFW status"
    echo "3) Add extra SSH port"
    echo "4) Enable/Disable quota enforcement"
    echo "5) Set quota default MB (0=unlimited)"
    echo "6) Show active sessions"
    echo "0) Back"
    read -rp "Choice: " c
    case "$c" in
      1) svc_restart fail2ban; echo "fail2ban restarted."; pause ;;
      2) ufw status; pause ;;
      3) read -rp "Port: " prt; 
         if ! grep -q "Port $prt" /etc/ssh/sshd_config.d/fal2proxy.conf; then
           sed -i "s/^Port .*/Port $SSH_PORT\nPort $prt/" /etc/ssh/sshd_config.d/fal2proxy.conf
           svc_restart ssh 2>/dev/null || svc_restart sshd
           ufw allow "$prt/tcp" >/dev/null 2>&1 || true
           echo "Added port $prt"
         else echo "Already present."; fi
         pause ;;
      4) if grep -q '^# \*/5' /etc/cron.d/fal2proxy-quota; then
           sed -i 's/^# \*\/5/*\/5/' /etc/cron.d/fal2proxy-quota
           echo "Quota enforcement ENABLED"
         else
           sed -i 's/^\*\/5/# *\/5/' /etc/cron.d/fal2proxy-quota
           echo "Quota enforcement DISABLED"
         fi
         pause ;;
      5) read -rp "Default quota MB (0=unlimited): " qm
         [ -z "$qm" ] && qm="0"
         sed -i "s/^DEFAULT_QUOTA_MB=.*/DEFAULT_QUOTA_MB=\"$qm\"/" "$SCRIPT_DIR/lib/common.sh"
         echo "Set to $qm"
         pause ;;
      6) echo "Active SSH sessions:"; who; echo; ss -tnp | grep ":$SSH_PORT" | head -20; pause ;;
      0) break ;;
      *) ;;
    esac
  done
}

monitoring(){
  header
  echo "Services:"
  for s in ssh sshd nginx fal2proxy-raw fail2ban; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${s}.service"; then
      echo "  $s: $(svc_status $s)"
    fi
  done
  echo
  echo "Listening ports:"
  ss -tlnp | grep -E ":($SSH_PORT|$HTTP_PORT|$WS_PORT)" 
  echo
  echo "Recent auth log:"
  tail -n 15 /var/log/auth.log 2>/dev/null || journalctl -u ssh -n 15 --no-pager 2>/dev/null
  pause
}

backup_restore(){
  echo "1) Backup"
  echo "2) Restore"
  read -rp "Choice: " c
  case "$c" in
    1) ts="$(date +%Y%m%d_%H%M%S)"; out="/root/fal2proxy-backup-$ts.tar.gz"
       tar czf "$out" "$FAL_DIR" /etc/ssh/sshd_config.d/fal2proxy.conf /etc/nginx/sites-available/fal2proxy 2>/dev/null
       echo "Backup: $out";;
    2) read -rp "Backup file path: " bf
       [ -f "$bf" ] && tar xzf "$bf" -C / && echo "Restored." || echo "File not found.";;
  esac
  pause
}

update_components(){
  echo "Updating packages..."
  detect_distro
  case "$PKG_MGR" in
    apt) apt-get update -y && apt-get upgrade -y openssh-server nginx fail2ban ;;
    dnf|yum) yum update -y openssh-server nginx fail2ban ;;
    pacman) pacman -Syu --noconfirm openssh nginx fail2ban ;;
    *) echo "Manual update required for $PKG_MGR" ;;
  esac
  # reinstall websocat
  rm -f "$WEBSCAT_BIN"
  bash "$FAL_DIR/install.sh" >/dev/null 2>&1 && echo "Reinstalled." || echo "Reinstall failed."
  pause
}

uninstall(){
  read -rp "Are you sure? (yes/no): " yn
  [ "$yn" != "yes" ] && { echo "Aborted."; pause; return; }
  systemctl disable --now fal2proxy-raw 2>/dev/null || true
  rm -f /etc/systemd/system/fal2proxy-raw.service
  rm -f /etc/ssh/sshd_config.d/fal2proxy.conf
  rm -f "$NGINX_LINK" "$NGINX_CONF"
  systemctl daemon-reload
  # remove users
  while IFS=: read -r u _; do
    [ -z "$u" ] && continue
    userdel -r "$u" 2>/dev/null || userdel "$u" 2>/dev/null || true
  done < "$USERS_DB"
  rm -rf "$FAL_DIR"
  rm -f "$FAL_BIN"
  rm -f /etc/cron.d/fal2proxy-quota
  svc_restart ssh 2>/dev/null || svc_restart sshd
  svc_restart nginx 2>/dev/null || true
  echo "Uninstalled."
  pause
}

# ---------- bandwidth monitor ----------
bandwidth_monitor(){
  header
  echo "Active connections:"
  ss -tn state established '( dport = :80 or dport = :8443 or dport = :38443 )' 2>/dev/null | tail -n +2 | head -20
  echo
  echo "Nginx requests (last 5 min):"
  awk -v d="$(date -d '5 min ago' '+%d/%b/%Y:%H:%M')" '$4 > "["d {print}' /var/log/nginx/access.log 2>/dev/null | wc -l
  echo
  echo "SSH sessions:"
  who | grep -c pts || echo 0
  echo
  echo "Service status:"
  for svc in nginx fal2proxy-raw ssh fail2ban; do
    echo "  $svc: $(systemctl is-active $svc 2>/dev/null)"
  done
  echo
  pause
}

# ---------- main loop ----------
while true; do
  header
  echo "1) Add client"
  echo "2) Delete client"
  echo "3) List clients"
  echo "4) Modify client"
  echo "5) Generate DarkTunnel link"
  echo "6) Domains & injection"
  echo "7) Advanced security"
  echo "8) Monitoring"
  echo "9) Backup / Restore"
  echo "10) Update components"
  echo "11) Uninstall"
  echo "12) Bandwidth monitor"
  echo "13) Generate NPV Tunnel link"
  echo "0) Exit"
  echo
  read -rp "Choice: " ch
  case "$ch" in
    1) add_client ;;
    2) delete_client ;;
    3) list_clients ;;
    4) modify_client ;;
    5) gen_link ;;
    6) domains_menu ;;
    7) advanced_menu ;;
    8) monitoring ;;
    9) backup_restore ;;
    10) update_components ;;
    11) uninstall; break ;;
    12) bandwidth_monitor ;;
    13) gen_npv_link ;;
    0) break ;;
    *) ;;
  esac
done
echo "Bye."
