# fal2proxy

SSH-over-WebSocket proxy server manager for Android DarkTunnel clients.

## Features
- Multi-distro installer (apt/dnf/yum/pacman/zypper/apk)
- Raw TCP bridge (C binary, epoll + TCP_NODELAY, optimized buffers)
- User management (add/delete/modify/list)
- DarkTunnel link generator
- Cloudflare zero-rating support
- Ports: 80, 8443, 38443
- Quota management (unlimited by default)
- fail2ban + UFW security
- Bandwidth monitor
- Log rotation

## Install
Run as root:
```
bash install.sh
```
Then use `fal2proxy` menu.

## Defaults
- Inject host/SNI: saily.flashservice.org
- Proxy: saily.com:80
- Quota: unlimited (enable in advanced menu)

## Options gratuites

Si vous n'avez pas de VPS au Togo, vous pouvez utiliser :
- **Termux** (téléphone Android comme serveur) — voir `docs/TERMUX-SERVER.md`
- **PC/Raspberry Pi** comme serveur SSH local
- **Optimiser v2** (gratuit, améliore l'existant)
- **Forfait minimal** ($1-5/mois)

Voir `docs/FREE-OPTIONS.md` pour les détails.

## Versions
- v1.0.0: Python bridge (select)
- v2.0.0: C bridge (epoll + splice + optimized I/O) + DarkTunnel
- v3.0.0-dev: gost (ws:// + wss://) — replaces DarkTunnel with gost client/server

## v3 (gost) — In Development (deployed in parallel on VPS)

### Throughput (via Cloudflare, zero-rating)
| Mode | Upload | Download |
|------|--------|----------|
| v2 (DarkTunnel) | ~6.3 Mbps | ~1.7 Mbps |
| v3 (gost) | ~6.1 Mbps | ~3.5 Mbps |
v3 replaces DarkTunnel + rawbridge + OpenSSH with **gost** (Go Simple Tunnel).
- Server: gost (ws:// port 80 + wss:// port 443 in parallel)
- Client: gost (Android/PC/Mac/Linux)
- SOCKS5 proxy on port 1080
- See `docs/MIGRATION-GOST.md` for details

Install with gost mode:
```
bash install.sh --mode=gost
```
