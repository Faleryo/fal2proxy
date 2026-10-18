# Approches de zero-rating — Documentation

## Vue d'ensemble

Le zero-rating (freesurf) permet d'accéder à Internet sans consommer son forfait
en exploitant les domaines ou services que l'opérateur mobile ne facture pas.
Ce document présente toutes les approches possibles, leur faisabilité et leurs
limitations.

---

## 1. Approche actuelle : Cloudflare same-domain

### Principe
Utiliser Cloudflare comme façade. Le client se connecte à un domaine zero-rated
sur Cloudflare, et Cloudflare route vers votre VPS (même compte Cloudflare).

### Fonctionnement
```
Client → saily.com:80 (Cloudflare edge) → saily.flashservice.org → VPS (164.90.164.227)
         SNI = saily.com (zero-rated)     Host = saily.flashservice.org (route vers VPS)
```

### Conditions
- Le domaine de l'origin (`saily.flashservice.org`) doit être sur le **même compte Cloudflare**
- L'opérateur doit **zero-rater Cloudflare** en général (pas juste un domaine spécifique)

### Avantages
- ✅ Fonctionne avec DarkTunnel et gost
- ✅ Pas de serveur supplémentaire
- ✅ Ports Cloudflare standard (80, 443, 2082, 2083)

### Limitations
- L'opérateur peut zero-rater spécifiquement `yas.tg` et pas tout Cloudflare
- Cloudflare peut changer ses règles

### ⚠️ Mesuré le 18/10/2026 (SIM 2 sans forfait) — prérequis non validé
- `saily.com` est **bloqué** par l'opérateur (ports 80/443, IPv4+IPv6), y compris en le
  forçant sur l'IP d'un edge Cloudflare zero-rated (`104.18.3.27`) : la même requête
  répond depuis internet normal (403 Cloudflare) → le blocage vient bien de l'opérateur.
- L'opérateur ne zero-rate **pas Cloudflare en général** ; la whitelist porte sur des
  paires (hostname ↔ IP) de l'écosystème Yas. ⇒ **Cette approche n'est pas validée**
  (détails et tests croisés : §8).

### Ports Cloudflare supportés
| Protocole | Ports |
|-----------|-------|
| HTTP | 80, 8080, 8880, 2052, 2082, 2086, 2095 |
| HTTPS | 443, 2053, 2083, 2087, 2096, 8443 |

---

## 2. Approche yas.tg

### Principe
Utiliser `yas.tg` (site de l'opérateur Yas Togo, zero-rated) comme façade.
L'opérateur voit `yas.tg` → zero-rated → pas de facturation.

### Ports ouverts sur yas.tg (via Cloudflare)
| Port | Protocole | État |
|------|-----------|------|
| 80 | HTTP | ✅ ouvert |
| 443 | HTTPS | ✅ ouvert |
| 8080 | HTTP proxy | ✅ ouvert |
| 8443 | HTTPS alt | ✅ ouvert |
| 8880 | HTTP alt | ✅ ouvert |
| 2052 | HTTP | ✅ ouvert |
| 2053 | HTTPS | ✅ ouvert |
| 2082 | HTTP | ✅ ouvert |
| 2083 | HTTPS | ✅ ouvert |
| 2086 | HTTP | ✅ ouvert |
| 2087 | HTTPS | ✅ ouvert |
| 2095 | HTTP | ✅ ouvert |
| 2096 | HTTPS | ✅ ouvert |
| 3000 | — | ❌ filtré |
| 8000 | — | ❌ filtré |
| 9000 | — | ❌ filtré |

### Pourquoi ça ne marche pas
```
# Ce qu'on voudrait faire :
SNI = yas.tg                  → opérateur voit yas.tg → zero-rated ✅
Host = saily.flashservice.org  → Cloudflare route vers notre VPS

# Ce qui se passe réellement :
SNI (yas.tg) ≠ Host (saily.flashservice.org) → comptes Cloudflare différents
→ Cloudflare détecte le cross-domain → 403 Forbidden ❌
```

Cloudflare a bloqué le **Domain Fronting cross-domain** en 2018. Seul le **same-domain** (même compte) fonctionne.

### Conditions pour que ça marche
- `yas.tg` devrait être sur le **même compte Cloudflare** que notre domaine → impossible (on ne contrôle pas `yas.tg`)
- Ou l'opérateur devrait zero-rater **tout Cloudflare** → testé le 18/10/2026 : **non** (voir §8)

---

## 3. Approches alternatives

### 3.1 VPS au Togo (réseau de l'opérateur)
**Principe** : Héberger le serveur directement sur le réseau de l'opérateur (Moov/Yas). Le trafic est "local" → pas de zero-rating bypass nécessaire.

| Aspect | Détail |
|--------|--------|
| Faisabilité | ⚠️ Possible mais difficile |
| Coût | VPS Togo rares et chers |
| Avantage | Pas de zero-rating bypass, débit maximal |
| Inconvénient | Pas de Cloudflare, pas de CDN |

**Fournisseurs possibles** : TOGOCOM (Yas), Moov Africa Togo, hébergeurs locaux (Lomé)

### 3.2 DPI bypass (stunnel / obfs4)
**Principe** : Au lieu de masquer le domaine (Domain Fronting), masquer le **protocole**. Encapsuler SSH dans du TLS standard pour que l'opérateur voie du HTTPS normal.

| Aspect | Détail |
|--------|--------|
| Faisabilité | ⚠️ Partiel |
| Avantage | L'opérateur voit du HTTPS standard → difficile à détecter |
| Inconvénient | Nécessite un serveur avec un SNI zero-rated (impossible sans contrôler `yas.tg`) |

**Outils** : stunnel, obfs4, shadowsocks

### 3.3 Héberger sur le domaine zero-rated
**Principe** : Héberger notre origine directement sur un domaine zero-rated.

| Aspect | Détail |
|--------|--------|
| Faisabilité | ❌ Non |
| Raison | On ne contrôle pas `yas.tg` ni aucun domaine zero-rated |

### 3.4 Proxy non-Cloudflare
**Principe** : Utiliser un reverse proxy sur un serveur que vous contrôlez, avec une IP zero-rated.

| Aspect | Détail |
|--------|--------|
| Faisabilité | ⚠️ Partiel |
| Avantage | Pas de dépendance à Cloudflare |
| Inconvénient | Nécessite une IP zero-rated (rare) |

### 3.5 Utiliser un autre CDN zero-rated
**Principe** : Si l'opérateur zero-rate Fastly ou Akamai, utiliser ces CDN comme façade.

| Aspect | Détail |
|--------|--------|
| Faisabilité | ⚠️ À tester |
| Avantage | Même technique que Cloudflare |
| Inconvénient | Cross-domain toujours bloqué (depuis 2018) |

---

## 4. Tableau comparatif

| Approche | Faisable ? | Conditions | Débit estimé |
|----------|-----------|------------|-------------|
| Cloudflare same-domain (actuel) | ⚠️ Non validé (§8) | Opérateur zero-rate Cloudflare | ~6 Mbps up / ~3.5 Mbps down |
| Cross-domain fronting (yas.tg) | ❌ Non | Bloqué par Cloudflare | — |
| Héberger sur yas.tg | ❌ Non | Pas d'accès au domaine | — |
| VPS au Togo | ⚠️ Possible | Rare et cher | Maximal (pas de tunnel) |
| DPI bypass (stunnel/obfs4) | ⚠️ Partiel | Serveur avec SNI zero-rated | Variable |
| Proxy non-Cloudflare | ⚠️ Partiel | IP zero-rated | Variable |
| Autre CDN (Fastly/Akamai) | ⚠️ À tester | Opérateur zero-rate ce CDN | Variable |

---

## 5. Recommandation

### Étape 1 : Tester si Cloudflare est zero-rated en général
Au lieu de `yas.tg`, testez si l'opérateur zero-rate **tout le trafic Cloudflare**.

**Test** : Connectez-vous au tunnel (v2 ou v3) et vérifiez si le trafic est facturé.
- Si oui → Cloudflare est zero-rated → notre config actuelle fonctionne
- Si non → l'opérateur zero-rate spécifiquement `yas.tg`

**Résultat (18/10/2026, SIM 2 sans forfait)** : Cloudflare **n'est pas** zero-rated en
général (`saily.com` bloqué, cf. §8) → branche « Si non ».

### Étape 2 : Si Cloudflare n'est pas zero-rated en général
- **Option A** : Chercher un VPS au Togo (réseau de l'opérateur)
- **Option B** : Tester d'autres CDN (Fastly, Akamai) si l'opérateur les zero-rate
- **Option C** : Utiliser un proxy HTTP sur un serveur avec IP zero-rated

### Étape 3 : Si rien ne fonctionne
- Le zero-rating est spécifique à `yas.tg` et ne peut pas être exploité via Domain Fronting
- Alternative : utiliser un forfait data minimal et optimiser la consommation (compression, cache)

---

## 6. Termes associés

| Terme | Définition | Exemple |
|-------|-----------|---------|
| **Zero-rating** | Accès gratuit à certains services/domains | Trafic vers `saily.com` non facturé |
| **Freesurf** | Surf gratuit via zero-rating | Naviguer sans forfait via un domaine zero-rated |
| **Domain Fronting** | Masquer la destination derrière un domaine zero-rated | SNI = `saily.com`, Host = `saily.flashservice.org` |
| **Cross-domain** | SNI et Host sur des domaines différents (bloqué) | SNI = `yas.tg`, Host = `saily.flashservice.org` |
| **Same-domain** | SNI et Host sur le même compte Cloudflare (fonctionne) | SNI = `saily.com`, Host = `saily.flashservice.org` |
| **DPI bypass** | Contournement de l'inspection DPI | Chiffrer le trafic en TLS |
| **VPS local** | Serveur dans le réseau de l'opérateur | VPS au Togo sur le réseau Moov/Yas |
| **stunnel** | Outil de tunnel TLS | Encapsule SSH dans du TLS |
| **obfs4** | Protocole d'obfuscation | Masque le trafic SSH en HTTPS |

---

## 7. Mesures réelles de zero-rating (18/10/2026)

Tests effectués **sans forfait data** depuis un téléphone Yas Togo (curl sur l'appareil) :

| Hôte testé | HTTP | Statut |
|------------|------|--------|
| `yas.tg` | 200 | ✅ zero-rated |
| `yas-app-mob-web-api.togocom.tg` | 200 | ✅ zero-rated |
| `yas-app-ws-apim.togocom.tg` | 302 | ✅ zero-rated |
| `ws-prp-mob-web-api.togocom.tg` | 200 | ✅ zero-rated |
| `tmoneytogocom.blob.core.windows.net` | 400 (réponse Azure) | ✅ zero-rated |
| `www.togocom.tg` | 000 | ❌ bloqué |
| `blob.core.windows.net` (générique) | 000 | ❌ bloqué |
| `azureopendatastorage.blob.core.windows.net` (autre compte) | 000 | ❌ bloqué |
| `firebaseremoteconfig.googleapis.com` | 000 | ❌ bloqué |

Constats :

- La whitelist opérateur est **par hostname exact** (blob Azure d'un autre compte = bloqué).
- **Tout l'écosystème de l'app Yas est zero-rated** : APIs (`*.togocom.tg`), CDN images
  (`tmoneytogocom.blob.core.windows.net`), site (`yas.tg`). L'app et ses jeux fonctionnent
  **entièrement sans forfait** (démo : un tour du jeu « Win Pizz » joué sans forfait, 150 Mo gagnés).
- Pour fal2proxy : **aucun gain côté Domain Fronting** (pas de domaine contrôlé dans la whitelist ;
  cross-domain impossible). La voie « data gratuite » la plus directe reste l'app elle-même
  (jeu quotidien, parrainage, popup FreeData) — voir `YAS-APP-ANALYSIS.md`.

Mesures complémentaires du même jour (verrouillage hôte ↔ IP, test `saily.com` sur edge
Cloudflare, spoofing SNI/Host, interception port 80) : voir §8.

---

## 8. Affinage du modèle : verrouillage hôte ↔ IP et Cloudflare (18/10/2026, SIM 2 sans forfait)

Batterie complémentaire depuis le téléphone (2ᵉ ligne Yas, `subId 3`, **aucun forfait**),
avec **contre-vérification de chaque requête depuis une connexion internet normale**
(workstation) pour distinguer ce qui vient de l'opérateur de ce qui vient du site.

### 8.1 Verrouillage hôte ↔ IP (mesures croisées)

| Requête | Sans forfait (SIM 2) | Internet normal (contrôle) |
|---------|----------------------|----------------------------|
| `yas.tg` via `104.18.2.27` / `104.18.3.27` (IP renvoyées par le DNS opérateur) | ✅ 200 | ✅ 200 |
| `yas.tg` via `104.18.12.124` (autre edge Cloudflare) | ❌ 000 (timeout/RST) | ✅ 200 |
| `saily.com` via `104.18.3.27` (edge zero-rated de `yas.tg`) | ❌ 000 | ✅ 403 (Cloudflare répond) |
| `saily.com` (résolution normale `104.18.12.124`) | ❌ 000 | ✅ 403 |

Lecture :
- l'IP autorisée ne suffit pas → il faut **aussi le bon hostname** ;
- le bon hostname ne suffit pas → il faut **aussi l'IP attendue** (celle du DNS opérateur) ;
- **Cloudflare n'est pas zero-rated en général** : l'approche §1 n'est pas validée.

### 8.2 Spoofing SNI / Host vers notre VPS : aucun passage

Variantes testées : SNI `yas.tg` / `saily.com` / `admin.saily.com` / hôtes app → VPS:443 ;
Host `yas.tg` / `admin.saily.com` / `saily.flashservice.org` → VPS:80.
- port 443 → timeout ou RST pendant le handshake TLS ;
- port 80 → HTTP **302** vers `http://nodata.togocel.tg` (portail « pas de data » de
  l'opérateur) ou timeout.

### 8.3 Comportement de l'interception (sans forfait)

- HTTP (80) vers un hôte non whitelisté → redirection **302** vers `http://nodata.togocel.tg`.
- HTTPS (443) vers un hôte non whitelisté → **RST** pendant le ClientHello (SNI lisible)
  ou timeout.
- Résultats **flaky** (RST/timeouts aléatoires selon les instants) : toujours re-tester
  avant de conclure sur un hôte donné.

### 8.4 Hôtes bloqués constatés (en plus de §7)

`www.cloudflare.com`, `discord.com`, `www.fastly.com`, `www.akamai.com`, `aws.amazon.com`,
`github.com`, `www.microsoft.com`, `www.google.com`, `saily.com`,
`azureopendatastorage.blob.core.windows.net`.

Nuances : `tmoneytogocom.blob.core.windows.net` reste ✅ mais **intermittent** (parfois 400,
parfois RST/timeout) ; `www.togocom.tg` jamais 200 (handshakes TLS partiels intermittents).

Config fal2proxy testée telle quelle (2ᵉ passage) : **SNI `admin.saily.com`** vers edge normal
(`104.18.12.124`) → timeout ; vers l'edge autorisé de `yas.tg` (`104.18.3.27`) → RST ;
**Host `saily.flashservice.org`** vers Cloudflare:80 → bloqué. Aucune variante de la config
ne passe sans forfait.

### 8.5 Conclusion

- Modèle opérateur : whitelist = **écosystème Yas uniquement**, verrouillée en
  **paires hostname ↔ IP** → aucun domaine tiers contrôlable, pas de bypass trouvé.
- Le prérequis de §1 (« l'opérateur zero-rate Cloudflare en général ») est contredit par
  ces mesures sur SIM 2. Reste à confirmer sur **SIM 1 sans forfait** (bonus actif
  jusqu'au ~19/10 11h04).
- **Reproduit** lors d'un 2ᵉ passage le même jour : mêmes résultats (yas verrouillé aux IP
  `104.18.2.27`/`104.18.3.27` ; `saily.com` et `admin.saily.com` bloqués sur tous les chemins
  testés ; portail port 80 opérateur), avec les intermittences habituelles (`blob-yas`,
  timeouts/RST aléatoires).
- Pistes restantes : récompenses de l'app (§7), VPS au Togo (§3.1), forfait minimal.