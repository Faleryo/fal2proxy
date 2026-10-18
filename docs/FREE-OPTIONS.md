# Options gratuites pour le zero-rating

Ce document présente toutes les options **gratuites** pour obtenir un accès Internet
via zero-rating, sans payer de VPS ni d'abonnement Cloudflare Argo.

---

## Option A : Téléphone Android comme serveur (Termux)

### Principe
Utiliser un téléphone Android existant au Togo comme serveur SSH. Le téléphone est
sur le réseau de l'opérateur (Moov/Yas) → le trafic est "local" → pas de zero-rating
bypass nécessaire, pas de facturation.

### Architecture
```
Client (PC/autre téléphone) ──SSH direct──▶ Téléphone Android (Termux + SSH) ──▶ Internet
                                              (sur le réseau de l'opérateur)
```

### Avantages
- ✅ **Gratuit** : utilise un téléphone existant
- ✅ **Pas de tunnel** : connexion SSH directe, débit maximal
- ✅ **Pas de Cloudflare** : pas de zero-rating bypass, pas de Domain Fronting
- ✅ **Pas de complexité** : pas de payload, pas de SNI, pas de Host header
- ✅ **Fiable** : pas de dépendance à un CDN tiers

### Inconvénients
- ❌ Le téléphone doit rester allumé et connecté
- ❌ Débit limité par le WiFi/4G du téléphone
- ❌ Consommation batterie
- ❌ Le téléphone ne peut pas être utilisé normalement pendant le tunnel
- ❌ Pas d'IP fixe (l'IP change à chaque reconnexion)

### Matériel nécessaire
- 1 téléphone Android (rooté de préférence, mais pas obligatoire)
- Connexion data mobile active (même sans forfait, le trafic local est gratuit)
- Un autre appareil (PC, tablette) pour se connecter en SSH

### Coût
- **$0** (utilise du matériel existant)

### Débit attendu
- WiFi : 10-50 Mbps (selon le réseau local)
- 4G : 5-20 Mbps (selon le signal)
- 3G : 1-5 Mbps

---

## Option B : PC / Raspberry Pi comme serveur

### Principe
Utiliser un PC ou un Raspberry Pi au Togo comme serveur SSH. Même principe que
Termux mais avec un ordinateur.

### Architecture
```
Client (téléphone/PC) ──SSH direct──▶ PC/Raspberry Pi (OpenSSH) ──▶ Internet
                                        (sur le réseau de l'opérateur)
```

### Avantages
- ✅ **Gratuit** : utilise un PC/Raspberry Pi existant
- ✅ **Débit meilleur** que Termux (Ethernet, WiFi)
- ✅ **Plus stable** (pas de gestion de batterie)
- ✅ **IP fixe possible** (si IP statique de l'opérateur)

### Inconvénients
- ❌ Le PC/Raspberry Pi doit rester allumé
- ❌ Consommation électrique
- ❌ Nécessite un port forwarding sur le routeur (si accès depuis l'extérieur)

### Matériel nécessaire
- 1 PC ou Raspberry Pi
- Connexion Internet au Togo (même sans forfait, le trafic local est gratuit)
- Un autre appareil pour se connecter en SSH

### Coût
- **$0** (utilise du matériel existant)
- Électricité : ~$1-2/mois pour un Raspberry Pi

### Débit attendu
- Ethernet : 10-100 Mbps (selon le réseau)
- WiFi : 10-50 Mbps

---

## Option C : Optimiser v2 actuelle (gratuit)

### Principe
Améliorer la configuration existante (v2) sans changer d'infrastructure. Le serveur
reste sur le VPS actuel (164.90.164.227) via Cloudflare.

### Optimisations possibles
1. **Compression SSH** : déjà activée (`Compression yes`)
2. **Ports alternatifs Cloudflare** : tester 8080, 8443, 2082, 2083, 2095, 2096
3. **Réduire la taille des paquets** : `ServerAliveInterval`, `TCPKeepAlive`
4. **Utiliser les ports les moins bloqués** : certains ports Cloudflare peuvent être moins surveillés
5. **Cacher le trafic** : utiliser des User-Agent réalistes, des headers HTTP normaux

### Avantages
- ✅ **Gratuit** : pas de nouveau matériel
- ✅ **Pas de changement** : garde la config actuelle

### Inconvénients
- ❌ Le zero-rating dépend de l'opérateur (peut ne pas fonctionner)
- ❌ Débit limité par Cloudflare
- ❌ Peut être détecté par le DPI

### Coût
- **$0**

### Débit attendu
- Via Cloudflare : ~6 Mbps upload / ~1.7 Mbps download (mesuré)

---

## Option D : Forfait minimal + optimisation

### Principe
Acheter le forfait le moins cher possible et optimiser la consommation.

### Avantages
- ✅ **Fiable** : pas de zero-rating bypass, pas de risque de blocage
- ✅ **Débit maximal** : pas de limitation Cloudflare
- ✅ **Simple** : pas de tunnel, pas de configuration complexe

### Inconvénients
- ❌ Coût récurrent (~$1-5/mois selon l'opérateur)
- ❌ Consommation de données (mais optimisée avec compression)

### Coût
- **$1-5/mois** (forfait minimal Togo)

### Débit attendu
- Maximal (pas de tunnel, pas de Cloudflare)

---

## Tableau comparatif

| Option | Coût | Débit | Complexité | Fiabilité | Zero-rating |
|--------|------|-------|------------|-----------|-------------|
| A. Termux (téléphone) | $0 | 5-20 Mbps | Moyenne | ⚠️ Moyenne | N/A (local) |
| B. PC/Raspberry Pi | $0 | 10-100 Mbps | Faible | ✅ Haute | N/A (local) |
| C. Optimiser v2 | $0 | ~6 Mbps | Faible | ⚠️ Moyenne | ⚠️ Incertain |
| D. Forfait minimal | $1-5/mois | Maximal | Très faible | ✅ Haute | N/A |

---

## Recommandation

1. **Si vous avez un PC ou Raspberry Pi au Togo** → Option B (meilleur débit, plus stable)
2. **Si vous avez seulement un téléphone Android** → Option A (Termux)
3. **Si vous voulez garder l'infra actuelle** → Option C (optimiser v2)
4. **Si vous avez un petit budget** → Option D (forfait minimal + compression)

### Ordre de priorité
1. **Termux/PC comme serveur** (gratuit, fiable, débit local)
2. **Optimiser v2** (gratuit, améliore l'existant)
3. **Forfait minimal** (si le budget le permet)

---

## Voir aussi
- `docs/TERMUX-SERVER.md` — Guide détaillé pour configurer Termux comme serveur
- `docs/DOCUMENTATION.md` — Documentation complète du projet
- `docs/ZERO-RATING-APPROACHES.md` — Approches de zero-rating
EOF
echo "FREE-OPTIONS.md created"