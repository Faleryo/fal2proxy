# fal2proxy — Documentation complète

## Vue d'ensemble

**fal2proxy** est un serveur proxy SSH-over-WebSocket pour clients Android DarkTunnel, avec support du zero-rating via Cloudflare.

### Objectif
Permettre l'accès Internet gratuit (zero-rating) en encapsulant le trafic SSH dans des requêtes HTTP/WebSocket qui transitent par un CDN (Cloudflare) accepté par l'opérateur mobile.

### Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────────┐     ┌──────────┐
│  DarkTunnel │────▶│  Cloudflare  │────▶│  VPS (fal2proxy)     │────▶│ Internet │
│  (Android)  │     │  (zero-rate) │     │  nginx → rawbridge   │     │          │
│             │     │              │     │  → SSH (OpenSSH)     │     │          │
└─────────────┘     └──────────────┘     └─────────────────────┘     └──────────┘
```

### Versions

| Version | Branche | Description |
|---------|---------|-------------|
| v1.0.0 | main | Pont Python (select), install multi-distro |
| v2.0.0 | main | Pont C (epoll + splice), optimisations, monitoring |
| v3.0.0-dev | v3 | gost (ws:// + wss://), non déployé |

---

## Prérequis

### Serveur (VPS)
- OS : Ubuntu 20.04+ / Debian 11+ / CentOS 8+ / Fedora / Arch / Alpine
- Architecture : x86_64 ou aarch64
- Accès root (SSH)
- Ports ouverts : 22 (SSH), 80 (HTTP), 8443, 38443

### Domaine
- Un domaine pointant vers le VPS (ex. `saily.flashservice.org`)
- Domaine proxifié via Cloudflare (orange cloud activé) pour le zero-rating

### Client
- Android avec l'app **DarkTunnel** (v1.0.26+)
- Ou gost client (v3, en développement)

---

## Installation

### Installation standard (v2)
```bash
# Sur le VPS, en tant que root
git clone https://github.com/Faleryo/fal2proxy.git
cd fal2proxy
bash install.sh
```

### Installation avec gost (v3, expérimental)
```bash
bash install.sh --mode=gost
```

### Ce que l'installeur fait
1. Détecte l'OS et le gestionnaire de paquets (apt/dnf/yum/pacman/zypper/apk)
2. Installe les dépendances : OpenSSH, Nginx, fail2ban, UFW, Python3, curl
3. Télécharge et compile le pont C (`rawbridge`)
4. Configure SSH (port 22, comptes tunnel-only, PermitTunnel, AllowTcpForwarding)
5. Configure Nginx (ports 80/8443/38443, proxy WebSocket, anti-buffering)
6. Crée le service systemd `fal2proxy-raw` (auto-restart)
7. Configure UFW (ports 22, 80, 8443, 38443)
8. Configure fail2ban (SSH + Nginx)
9. Installe le menu de gestion (`fal2proxy`)
10. Configure logrotate

---

## Configuration

### Variables (lib/common.sh)
| Variable | Défaut | Description |
|----------|--------|-------------|
| `INJECT_HOST` | `saily.flashservice.org` | Host/SNI d'injection |
| `PROXY_HOST` | `saily.flashservice.org` | Proxy frontal (Cloudflare) |
| `PROXY_PORT` | `80` | Port du proxy |
| `SSH_PORT` | `22` | Port SSH |
| `DEFAULT_QUOTA_MB` | `0` | Quota par défaut (0 = illimité) |
| `DEFAULT_EXPIRY_DAYS` | `30` | Expiration par défaut des comptes |
| `FAL_GROUP` | `fal2proxy` | Groupe système des clients |

### Ports
| Port | Service | Description |
|------|---------|-------------|
| 22 | SSH | Authentification et tunnel |
| 80 | Nginx | HTTP/WebSocket (zero-rating) |
| 8443 | Nginx | HTTP/WebSocket (alternatif) |
| 38443 | Nginx | HTTP/WebSocket (alternatif) |
| 8080 | rawbridge | Pont TCP interne (localhost) |

---

## Menu de gestion

Lancer avec : `fal2proxy`

| Option | Description |
|--------|-------------|
| 1) Add client | Créer un nouveau client (user, pass auto, expiration, max sessions) |
| 2) Delete client | Supprimer un client (user système + DB) |
| 3) List clients | Lister tous les clients (statut, expiration, quota, sessions) |
| 4) Modify client | Modifier pass, expiration, enable/disable, max sessions, quota |
| 5) Generate DarkTunnel link | Générer un lien `darktunnel://` pour l'app Android |
| 13) Generate NPV Tunnel link | Générer un lien `npvt-ssh://` pour l'app NPV Tunnel |
| 6) Domains & injection | Changer le Host/SNI d'injection |
| 7) Advanced security | fail2ban, UFW, ports SSH supplémentaires, quota on/off |
| 8) Monitoring | Statut des services, ports, logs récents |
| 9) Backup / Restore | Sauvegarder/restaurer la config |
| 10) Update components | Mettre à jour les paquets et réinstaller |
| 11) Uninstall | Désinstaller complètement |
| 12) Bandwidth monitor | Connexions actives, requêtes, sessions SSH |
| 0) Exit | Quitter |

---

## Clients

### Ajouter un client
```
fal2proxy → 1) Add client
Username: demo
Password: (blank = auto)
Expiry days: 30
Max sessions: 2
```

### Générer un lien DarkTunnel
```
fal2proxy → 5) Generate DarkTunnel link
Username: demo
Inject Host/SNI: (default saily.flashservice.org)
Proxy host: (default saily.flashservice.org)
Proxy port: (default 80)
```
Le lien `darktunnel://...` est affiché. Copiez-le dans l'app DarkTunnel (import config).

### Payload généré
```
GET / HTTP/1.1[crlf]
Host: saily.flashservice.org[crlf]
Connection: Upgrade[crlf]
User-Agent: Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Mobile Safari/537.36[crlf]
Upgrade: websocket[crlf]
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==[crlf]
Sec-WebSocket-Version: 13[crlf]
[crlf]
```

---

## Zero-rating (Cloudflare)

### Comment ça marche
1. Le client DarkTunnel se connecte à `saily.com:80` (Cloudflare edge)
2. Envoie le payload avec `Host: saily.flashservice.org`
3. Cloudflare route la requête vers votre VPS (origin)
4. Votre VPS répond `101 Switching Protocols`
5. DarkTunnel passe en raw TCP (SSH) à travers Cloudflare
6. L'opérateur mobile voit du trafic vers `saily.com` (domaine zero-rated) → pas de facturation

### Configuration Cloudflare requise
- Domaine `saily.flashservice.org` proxifié (orange cloud)
- DNS A record → IP du VPS
- Le zero-rating dépend de l'opérateur (l'app doit être dans la liste zero-rated)

### Paramètres importants
- **SNI** : `admin.saily.com` (trigger zero-rating)
- **Proxy host** : `saily.com` (Cloudflare edge)
- **Host (payload)** : `saily.flashservice.org` (route vers votre VPS)

---

## Sécurité

### Comptes tunnel-only
- Groupe : `fal2proxy`
- Shell : `/bin/bash` (ou `/usr/sbin/nologin`)
- `AllowTcpForwarding yes`, `PermitTunnel yes`
- `X11Forwarding no`, `PermitTTY yes`
- Expiration automatique (`chage`)
- Quota configurable (iptables owner match)

### fail2ban
- Jail SSH : 5 tentatives max, ban 1h
- Jail Nginx : 5 tentatives max, ban 1h
- Logs : `/var/log/auth.log`, `/var/log/nginx/error.log`

### UFW
- Ports autorisés : 22, 80, 8443, 38443
- Activé par défaut

### Masquage des secrets
- Les IP VPS, clés, tokens ne sont jamais loggés en clair
- `users.db` en mode `600`
- Les secrets iodine (v1) sont runtime-only

---

## Performance

### Optimisations appliquées

| Composant | Optimisation |
|-----------|-------------|
| Pont C (rawbridge) | epoll, TCP_NODELAY, TCP_QUICKACK, buffers 256 Ko, splice zero-copy |
| Nginx | proxy_buffering off, proxy_request_buffering off, tcp_nodelay on, timeouts 86400s |
| SSH | Compression yes, TCPKeepAlive yes, chacha20-poly1305 |
| Système | SO_RCVBUF/SO_SNDBUF = 512 Ko, backlog 1024 |

### Mesures de débit (via Cloudflare)

| Direction | Débit |
|-----------|-------|
| Upload (client → serveur) | ~6.3 Mbps |
| Download (serveur → client) | ~1.7 Mbps |
| SSH direct (référence) | ~11.6 Mbps |

### Goulot d'étranglement
Le proxy WebSocket gratuit de Cloudflare limite le débit. Options pour améliorer :
- Cloudflare Argo (~5$/mois) : +20-40% latence
- Cloudflare Pro (20$/mois) : meilleures performances WebSocket
- VPS plus proche géographiquement

---

## Dépannage

### Erreur : `400 Bad Request`
- **Cause** : le payload ne contient pas les en-têtes WebSocket (`Sec-WebSocket-Key`, `Sec-WebSocket-Version`)
- **Solution** : régénérer le lien avec la version à jour du script

### Erreur : `Connection closed` après la bannière SSH
- **Cause** : host key verification ou buffering
- **Solution** : vérifier les paramètres DarkTunnel (accept unknown host keys), utiliser la dernière version du lien

### Le tunnel est lent
- **Cause** : limites Cloudflare (proxy WebSocket gratuit)
- **Solution** : activer Argo, passer en Pro, ou utiliser la connexion directe

### Service ne démarre pas
```bash
# Vérifier les logs
journalctl -u fal2proxy-raw -n 20
# Vérifier le port
ss -tlnp | grep 8080
# Redémarrer
systemctl restart fal2proxy-raw
```

### fail2ban a banni mon IP
```bash
fail2ban-client set sshd unbanip <IP>
```

---

## Structure du projet

```
fal2proxy/
├── README.md
├── install.sh              # Installeur multi-distro
├── fal2proxy.sh            # Menu de gestion
├── rawbridge.c             # Pont C (epoll + splice)
├── rawbridge               # Binaire compilé
├── lib/
│   └── common.sh          # Fonctions communes
├── scripts/
│   ├── quota-enforce.sh   # Enforcement quota (iptables)
│   └── rawbridge.py       # Pont Python (fallback)
├── deploy/
│   ├── gost-server.sh     # Serveur gost (v3)
│   └── gost-client.sh     # Client gost (v3)
├── docs/
│   ├── MIGRATION-GOST.md  # Guide migration v2→v3
│   └── DOCUMENTATION.md   # Ce fichier
├── logrotate-fal2proxy     # Config logrotate
└── .gitignore
```

---

## Améliorations futures possibles

1. **gost v3** — remplacer DarkTunnel par gost client/serveur (plus rapide, moins de couches)
2. **Cloudflare Argo** — routage optimisé (~5$/mois)
3. **Compression adaptative** — activer/désactiver selon le CPU
4. **Multi-VPS** — répartir la charge sur plusieurs serveurs
5. **Web dashboard** — interface web pour gérer les clients
6. **Auto-update** — mise à jour automatique du script
7. **IPv6** — support natif IPv6
8. **Rate limiting** — limiter le débit par client (tc)
9. **Geo-blocking** — bloquer les connexions hors zone
10. **Backup automatique** — sauvegarde quotidienne

---

## Changelog

### v2.0.0 (2026-10-17)
- Pont C optimisé (epoll + splice zero-copy + TCP_NODELAY + buffers 256 Ko)
- Monitoring débit (option 12)
- Logs rotatifs
- SSH compression + TCPKeepAlive
- Nginx anti-buffering
- Multi-distro installer

### v1.0.0 (2026-10-17)
- Pont Python (select)
- Install multi-distro
- Menu de gestion (11 options)
- DarkTunnel link generator
- fail2ban + UFW
- Quota management

### v3.0.0-dev (en développement)
- gost (ws:// + wss://) en parallèle
- Migration guide
- Non déployé
EOF
echo "documentation created"