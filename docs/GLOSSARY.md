# Glossaire — Termes du freesurf, zero-rating et tunneling

Ce glossaire regroupe tous les termes techniques utilisés dans le projet fal2proxy,
classés par catégorie. Chaque terme est accompagné d'une définition et d'un exemple concret.

---

## 1. Concepts de base

### Zero-rating
**Définition** : Accès gratuit à certains services ou domaines sans consommer le forfait de données mobile.
**Exemple** : L'opérateur Moov Togo ne facture pas le trafic vers `saily.com`. L'utilisateur peut naviguer sur ce domaine sans forfait.

### Freesurf
**Définition** : Surf gratuit sur Internet en exploitant le zero-rating d'un opérateur.
**Exemple** : Utiliser un tunnel via `saily.com` (zero-rated) pour accéder à tout Internet sans forfait.

### Whitelist (liste blanche)
**Définition** : Liste de domaines ou services en accès gratuit définie par l'opérateur.
**Exemple** : `saily.com`, `cloudflare.com`, `facebook.com` sont dans la whitelist de Moov Togo.

### Blacklist (liste noire)
**Définition** : Liste de domaines ou services bloqués ou facturés par l'opérateur.
**Exemple** : Tout domaine non présent dans la whitelist est blacklisté → connexion refusée ou facturée.

### Captive portal (portail captif)
**Définition** : Page d'authentification affichée par l'opérateur quand l'utilisateur n'a pas de forfait actif.
**Exemple** : `http://nodata.togocel.tg` s'affiche quand le SIM Moov n'a pas de forfait data.

### Zero-rated
**Définition** : Domaine ou service bénéficiant du zero-rating (accès gratuit).
**Exemple** : `saily.com` est zero-rated par Moov Togo → trafic non facturé.

---

## 2. Techniques de contournement

### Domain Fronting (frontage de domaine)
**Définition** : Technique qui utilise un CDN (Cloudflare) comme intermédiaire. Le client se connecte à un domaine zero-rated (SNI) mais envoie une requête HTTP vers un autre domaine (Host) hébergé sur le même CDN.
**Exemple** :
```
SNI = saily.com                    → domaine zero-rated → pas de facturation
Host: saily.flashservice.org       → Cloudflare route vers votre VPS
Résultat : trafic gratuit vers votre VPS
```

### SNI Spoofing (usurpation SNI)
**Définition** : Le client envoie un SNI (Server Name Indication) différent du Host réel. Le SNI est visible en clair dans le handshake TLS. En envoyant un SNI zero-rated, on trompe l'opérateur.
**Exemple** :
```
serverNameIndication = "admin.saily.com"   # SNI envoyé au TLS
Host: saily.flashservice.org               # Host réel dans le HTTP
L'opérateur voit : SNI = admin.saily.com → zero-rated → pas de facturation
```

### Host Header Injection
**Définition** : Technique où le client injecte un en-tête `Host` différent du SNI. Le serveur (Cloudflare) utilise cet en-tête pour router la requête vers la bonne origine.
**Exemple** :
```
GET / HTTP/1.1
Host: saily.flashservice.org    ← Cloudflare route vers 164.90.164.227
Connection: Upgrade
Upgrade: websocket
```

### Payload
**Définition** : Charge utile HTTP injectée par le client pour établir le tunnel.
**Exemple** :
```
GET / HTTP/1.1[crlf]
Host: saily.flashservice.org[crlf]
Connection: Upgrade[crlf]
User-Agent: Mozilla/5.0 ...[crlf]
Upgrade: websocket[crlf]
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==[crlf]
Sec-WebSocket-Version: 13[crlf]
[crlf]
```

### Injection
**Définition** : Envoyer le payload au proxy pour établir le tunnel.
**Exemple** : DarkTunnel envoie le payload à `saily.com:80` (Cloudflare edge).

### Obfuscation
**Définition** : Obscurcir le trafic pour éviter la détection par le DPI.
**Exemple** : Encodage Base64 des données, XOR, etc.

### Masquerading (masquage de trafic)
**Définition** : Faire passer le trafic pour un autre type. Le Domain Fronting est une forme de masquerading.
**Exemple** : Faire passer du SSH pour du HTTP/WebSocket.

### Tunneling
**Définition** : Encapsuler un protocole dans un autre pour le faire transiter par un réseau.
**Exemple** : SSH encapsulé dans WebSocket qui transite par Cloudflare.

### Protocol confusion
**Définition** : Confondre le DPI en mélangeant les protocoles HTTP, WebSocket et TLS.
**Exemple** : Envoyer un payload HTTP qui upgrade en WebSocket, puis envoyer du SSH binaire dans le tunnel.

---

## 3. Réseau et opérateur

### DPI (Deep Packet Inspection)
**Définition** : Inspection approfondie des paquets par l'opérateur pour analyser le contenu du trafic.
**Exemple** : L'opérateur analyse le SNI dans le handshake TLS pour vérifier si le domaine est zero-rated.

### DPI bypass
**Définition** : Contournement de l'inspection DPI.
**Exemple** : Utiliser HTTPS/WSS pour chiffrer le payload, empêchant l'opérateur de lire le Host header.

### APN (Access Point Name)
**Définition** : Point d'accès réseau configuré sur le téléphone pour se connecter à l'Internet mobile.
**Exemple** : `internet.moov.tg` pour Moov Togo.

### MCC (Mobile Country Code)
**Définition** : Code pays de l'opérateur mobile (3 chiffres).
**Exemple** : 620 = Togo.

### MNC (Mobile Network Code)
**Définition** : Code réseau de l'opérateur mobile (2-3 chiffres).
**Exemple** : 06 = Moov Africa Togo, 01 = Togocom/Yas.

### IMSI (International Mobile Subscriber Identity)
**Définition** : Identifiant unique de la SIM, composé de MCC + MNC + MSIN.
**Exemple** : 62006XXXXXXXX (masqué après MCC+MNC pour la sécurité).

### eSIM
**Définition** : SIM embarquée (pas de carte physique), téléchargeable via un profil.
**Exemple** : Profil Saily, Moov, Togocom installé sur un téléphone compatible eUICC.

### SIM
**Définition** : Carte SIM physique.
**Exemple** : Moov phone0 (subId 2), Yas phone1 (subId 5).

### SubId (Subscription ID)
**Définition** : ID de souscription Android, identifie la SIM active.
**Exemple** : subId 2 = Moov, subId 5 = Yas (revérifier à chaque fois, ne jamais figer).

### CGNAT (Carrier-Grade NAT)
**Définition** : NAT à grande échelle utilisé par l'opérateur. L'IP source change à chaque connexion.
**Exemple** : L'IP source du téléphone change de 10.95.47.194 à 10.100.59.181 après reconnexion.

### PDN (Packet Data Network)
**Définition** : Réseau de données mobile de l'opérateur.
**Exemple** : Interface `rmnet_data2` sur Android.

---

## 4. Performance et qualité

### Latency (latence)
**Définition** : Temps de réponse d'un paquet (RTT).
**Exemple** : ~450 ms via iodine, ~100 ms via Cloudflare, ~30 ms en direct.

### RTT (Round-Trip Time)
**Définition** : Temps d'aller-retour d'un paquet entre le client et le serveur.
**Exemple** : 450 ms = iodine (DNS tunnel), 50 ms = Cloudflare, 10 ms = réseau local.

### Jitter
**Définition** : Variation de la latence d'un paquet à l'autre.
**Exemple** : ±50 ms = instable, ±5 ms = stable.

### Throughput (débit)
**Définition** : Débit réel mesuré.
**Exemple** : 6.3 Mbps upload via Cloudflare (v2), 3.5 Mbps download via gost (v3).

### Bandwidth (bande passante)
**Définition** : Bande passante maximale théorique.
**Exemple** : 300 Mbps (limite effective gost selon la config).

### Throttling
**Définition** : Limitation de débit appliquée par l'opérateur.
**Exemple** : Réduction à 1 Mbps après 100 Mo de consommation.

### Packet loss (perte de paquets)
**Définition** : Pourcentage de paquets perdus en transit.
**Exemple** : ~30% via iodine (DNS tunnel), ~0% via Cloudflare.

### QoS (Quality of Service)
**Définition** : Priorisation du trafic par l'opérateur.
**Exemple** : Voix prioritaire, data déprioritisée en heures de pointe.

### Traffic shaping
**Définition** : Mise en forme du trafic par l'opérateur pour limiter le débit.
**Exemple** : Limitation à 2 Mbps après 500 Mo de données.

---

## 5. Protocoles et technologies

### SSH (Secure Shell)
**Définition** : Protocole de tunnel chiffré utilisé pour l'accès distant.
**Exemple** : OpenSSH 9.6 sur le VPS, port 22.

### WebSocket
**Définition** : Protocole de communication bidirectionnelle sur HTTP.
**Exemple** : `Upgrade: websocket` dans le payload HTTP.

### TLS/SSL (Transport Layer Security)
**Définition** : Protocole de chiffrement de la connexion entre client et serveur.
**Exemple** : `wss://` = WebSocket over TLS (port 443). Chiffre tout le trafic, y compris le handshake HTTP.

### WSS (WebSocket Secure)
**Définition** : WebSocket chiffré avec TLS.
**Exemple** : `wss://saily.com:443` — tout le trafic est chiffré de bout en bout.

### DarkTunnel SSL mode
**Définition** : Mode de DarkTunnel qui utilise TLS pour chiffrer le handshake. Non supporté nativement en mode PROXY.
**Exemple** : DarkTunnel envoie le payload HTTP en clair même sur le port 443 → échec si le serveur attend du TLS.

### Zero-copy
**Définition** : Transfert de données entre descripteurs de fichier sans copie en espace utilisateur.
**Exemple** : `splice()` dans rawbridge v2 — les données passent directement du socket client au socket SSH au niveau du noyau.

### TLS/SSL
**Définition** : Chiffrement de la connexion (Transport Layer Security).
**Exemple** : `wss://` = WebSocket over TLS (port 443).

### SOCKS5
**Définition** : Protocole proxy qui transfère les paquets TCP/UDP.
**Exemple** : Gost crée un proxy SOCKS5 sur port 1080.

### HTTP Injector
**Définition** : Catégorie d'apps Android qui injectent des payloads HTTP pour créer des tunnels.
**Exemple** : DarkTunnel, HTTP Injector, SNI Spoofing apps.

### CDN (Content Delivery Network)
**Définition** : Réseau de serveurs distribués géographiquement pour accélérer la livraison de contenu.
**Exemple** : Cloudflare, Fastly, Akamai.

### Proxy
**Définition** : Serveur mandataire qui relaie les requêtes.
**Exemple** : `saily.com` (Cloudflare edge) est le proxy, `saily.flashservice.org` est l'origin.

### Cipher (algorithme de chiffrement)
**Définition** : Algorithme utilisé pour chiffrer les données.
**Exemple** : chacha20-poly1305 (SSH), AES-256-GCM (TLS).

### TCP_NODELAY
**Définition** : Option socket qui désactive l'algorithme de Nagle (envoi immédiat des petits paquets).
**Exemple** : Activé dans rawbridge pour réduire la latence.

### epoll
**Définition** : Mécanisme d'I/O multiplexé sous Linux, plus performant que select().
**Exemple** : Utilisé dans rawbridge v2 pour gérer les connexions.

### splice
**Définition** : Syscall Linux pour transférer des données entre descripteurs de fichier sans copie en espace utilisateur (zero-copy).
**Exemple** : Utilisé dans rawbridge v2 pour transférer les données entre sockets.

---

## 6. Outils et logiciels

### gost
**Définition** : Go Simple Tunnel — binaire Go haute performance pour le tunneling.
**Exemple** : `gost -L ws://:2082` (serveur), `gost -L socks5://:1080 -F ws://server:2082` (client).

### frp
**Définition** : Fast Reverse Proxy — alternative à gost, aussi en Go.
**Exemple** : `frps` (serveur), `frpc` (client).

### DarkTunnel
**Définition** : App Android de tunneling HTTP avec support du zero-rating.
**Exemple** : Utilisée en v2 pour créer le tunnel via Cloudflare.

### HTTP Injector
**Définition** : App Android de tunneling HTTP, similaire à DarkTunnel.
**Exemple** : Alternative à DarkTunnel.

### iodine
**Définition** : Tunnel DNS (bande étroite, toujours ouvert).
**Exemple** : Socle permanent dans FALTUN, ~130 o/s.

### wstunnel
**Définition** : Tunnel WebSocket, alternative à gost.
**Exemple** : `wstunnel server ws://0.0.0.0:8080`, `wstunnel client ws://server:8080`.

### websocat
**Définition** : Pont WebSocket ↔ TCP, utilisé puis remplacé par rawbridge.
**Exemple** : `websocat --binary ws-l:127.0.0.1:8080 tcp:127.0.0.1:22`.

### rawbridge
**Définition** : Pont TCP brut (C) créé pour DarkTunnel (pas de framing WebSocket).
**Exemple** : `/opt/fal2proxy/bin/rawbridge` écoute sur port 8080.

### Cloudflare
**Définition** : CDN/proxy utilisé pour le zero-rating.
**Exemple** : `saily.com`, `saily.flashservice.org` sont sur Cloudflare.

---

## 7. Mesures et métriques

### SLI (Service Level Indicator)
**Définition** : Indicateur de performance mesurable.
**Exemple** : Disponibilité, latence p90, débit moyen.

### Benchmark
**Définition** : Test de performance.
**Exemple** : `dd if=/dev/zero bs=1M count=10 | ssh ... cat > /dev/null`.

### Zero-rating probe
**Définition** : Outil qui vérifie si le zero-rating fonctionne.
**Exemple** : `zero_rating_probe.py --duree 1800` (mesure sur 30 minutes).

### Direct measurement
**Définition** : Mesure avec forfait actif (pas zero-rated).
**Exemple** : 98 tests directe = tous DISPONIBLE (le téléphone avait du forfait).

### Non concluant
**Définition** : Test qui ne donne pas de réponse claire.
**Exemple** : rc 2 = non concluant (ni confirmé ni infirmé).

---

## Historique du Domain Fronting

| Année | Événement |
|-------|-----------|
| 2015 | Tor propose le Domain Fronting pour contourner la censure |
| 2018 | Cloudflare, Google, AWS bloquent le Domain Fronting cross-domain |
| 2020+ | Le Domain Fronting same-domain (sous-domaines) fonctionne toujours |
| 2024+ | Les apps Android (DarkTunnel, HTTP Injector) automatisent la technique |

### Cross-domain vs Same-domain

**Cross-domain (BLOQUÉ par Cloudflare depuis 2018)** :
```
SNI = google.com          (domaine A)
Host = monsite.com        (domaine B, compte différent)
→ Cloudflare détecte la différence → bloque (403)
```

**Same-domain (FONCTIONNE)** :
```
SNI = saily.com           (domaine A, compte Cloudflare)
Host = saily.flashservice.org  (sous-domaine A, même compte)
→ Cloudflare accepte → route vers l'origin
```

### Limitations
- Le domaine de l'origin doit être sur le **même compte Cloudflare** que le domaine zero-rated
- L'opérateur doit **zero-rater le CDN** (Cloudflare) ou le domaine utilisé comme façade
- Cloudflare peut changer ses règles à tout moment
- Certains opérateurs utilisent le **DPI** pour détecter le masquage

---

## Index alphabétique

| Terme | Catégorie | Page |
|-------|-----------|------|
| APN | Réseau | §3 |
| Bandwidth | Performance | §4 |
| Blacklist | Concepts | §1 |
| Captive portal | Concepts | §1 |
| CDN | Protocoles | §5 |
| CDN Fronting | Contournement | §2 |
| CGNAT | Réseau | §3 |
| Cipher | Protocoles | §5 |
| DarkTunnel | Outils | §6 |
| DarkTunnel SSL mode | Protocoles | §5 |
| Zero-copy | Protocoles | §5 |
| DPI | Réseau | §3 |
| DPI bypass | Réseau | §3 |
| Domain Fronting | Contournement | §2 |
| epoll | Protocoles | §5 |
| eSIM | Réseau | §3 |
| Freesurf | Concepts | §1 |
| gost | Outils | §6 |
| Host Header Injection | Contournement | §2 |
| HTTP Injector | Protocoles | §5 |
| IMSI | Réseau | §3 |
| Injection | Contournement | §2 |
| iodine | Outils | §6 |
| Jitter | Performance | §4 |
| Latency | Performance | §4 |
| Masquerading | Contournement | §2 |
| MCC | Réseau | §3 |
| MNC | Réseau | §3 |
| Obfuscation | Contournement | §2 |
| Packet loss | Performance | §4 |
| Payload | Contournement | §2 |
| PDN | Réseau | §3 |
| Protocol confusion | Contournement | §2 |
| Proxy | Protocoles | §5 |
| QoS | Performance | §4 |
| rawbridge | Outils | §6 |
| RTT | Performance | §4 |
| SIM | Réseau | §3 |
| SLI | Mesures | §7 |
| SNI Spoofing | Contournement | §2 |
| SOCKS5 | Protocoles | §5 |
| splice | Protocoles | §5 |
| SSH | Protocoles | §5 |
| SubId | Réseau | §3 |
| TCP_NODELAY | Protocoles | §5 |
| Throttling | Performance | §4 |
| Throughput | Performance | §4 |
| TLS/SSL | Protocoles | §5 |
| Traffic shaping | Performance | §4 |
| Tunneling | Contournement | §2 |
| WebSocket | Protocoles | §5 |
| websocat | Outils | §6 |
| wstunnel | Outils | §6 |
| Whitelist | Concepts | §1 |
| Zero-rating | Concepts | §1 |
| Zero-rated | Concepts | §1 |
| Zero-rating bypass | Contournement | §2 |
| Zero-rating probe | Mesures | §7 |

---

## Références

- Tor Project : "Domain Fronting" (2015)
- Cloudflare Blog : "Blocking Domain Fronting" (2018)
- FALTUN AGENTS.md : règles de travail et erreurs
- fal2proxy DOCUMENTATION.md : documentation complète du projet
EOF
echo "glossary created"