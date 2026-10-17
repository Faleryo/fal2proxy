#!/usr/bin/env bash
# fal2proxy quota enforcement (best-effort, iptables owner match)
set -u
FAL_DIR="/opt/fal2proxy"
source "$FAL_DIR/lib/common.sh"
[ -f "$FAL_DIR/lib/common.sh" ] || exit 0

USERS_DB="$FAL_DIR/data/users.db"
[ -f "$USERS_DB" ] || exit 0

# Only run if enabled marker exists
[ -f "$FAL_DIR/data/quota_enabled" ] || exit 0

DEFAULT_CAP_MB="$(grep '^DEFAULT_QUOTA_MB=' "$FAL_DIR/lib/common.sh" | cut -d= -f2 | tr -d '"')"
[ -z "$DEFAULT_CAP_MB" ] && DEFAULT_CAP_MB=0
[ "$DEFAULT_CAP_MB" = "0" ] && exit 0

CAP_BYTES=$(( DEFAULT_CAP_MB * 1024 * 1024 ))

# Reset quota chain
iptables -F FAL2PROXY_QUOTA 2>/dev/null || iptables -N FAL2PROXY_QUOTA 2>/dev/null
iptables -F FAL2PROXY_QUOTA 2>/dev/null
# ensure jump
iptables -C OUTPUT -j FAL2PROXY_QUOTA 2>/dev/null || iptables -A OUTPUT -j FAL2PROXY_QUOTA

while IFS=: read -r u p exp q en ms; do
  [ -z "$u" ] && continue
  [ "$en" = "1" ] || continue
  uid="$(id -u "$u" 2>/dev/null)" || continue
  cap="$q"; [ "$cap" = "0" ] && cap="$DEFAULT_CAP_MB"
  [ "$cap" = "0" ] && continue
  bytes=$(( cap * 1024 * 1024 ))
  # accept up to quota, then drop
  iptables -A FAL2PROXY_QUOTA -m owner --uid-owner "$uid" -m quota --quota "$bytes" -j ACCEPT 2>/dev/null
  iptables -A FAL2PROXY_QUOTA -m owner --uid-owner "$uid" -j DROP 2>/dev/null
done < "$USERS_DB"
