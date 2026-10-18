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
- Ou l'opérateur devrait zero-rater **tout Cloudflare** → à tester

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
| Cloudflare same-domain (actuel) | ✅ Oui | Opérateur zero-rate Cloudflare | ~6 Mbps up / ~3.5 Mbps down |
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
EOF
echo "created"