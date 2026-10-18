# Guide : Configurer un serveur local sur Termux (Android)

Ce guide détaille comment transformer un téléphone Android en serveur SSH local
pour accéder à Internet via le réseau de l'opérateur (zero-rating ou trafic local).

---

## Prérequis

- Téléphone Android (rooté de préférence, mais pas obligatoire)
- Connexion data mobile active (même sans forfait, le trafic local est gratuit)
- Un autre appareil (PC, tablette, autre téléphone) pour se connecter en SSH
- Connexion WiFi entre les deux appareils (ou USB tethering)

---

## Étape 1 : Installer Termux

1. Téléchargez **Termux** depuis F-Droid (pas le Play Store, version obsolète)
   - F-Droid : https://f-droid.org/packages/com.termux/
   - Ou APK direct : https://github.com/termux/termux-app/releases

2. Installez l'APK sur le téléphone Android

3. Ouvrez Termux et mettez à jour les paquets :
```bash
pkg update && pkg upgrade -y
```

---

## Étape 2 : Installer les outils nécessaires

```bash
# Installer OpenSSH, curl, et autres outils
pkg install openssh curl wget python -y

# Vérifier l'installation
ssh -V
# Output: OpenSSH_9.x, OpenSSL 3.x
```

---

## Étape 3 : Configurer SSH

### 3.1 Définir un mot de passe
```bash
# Définir le mot de passe pour l'utilisateur Termux
passwd
# Entrez un mot de passe fort (ex: T3rmux!Pass2026)
```

### 3.2 Configurer le serveur SSH
```bash
# Éditer la config SSH
nano ~/.ssh/sshd_config
# Ou créer si elle n'existe pas
```

Ajoutez/modifiez ces lignes :
```
Port 8022
PasswordAuthentication yes
PubkeyAuthentication yes
PermitRootLogin no
AllowTcpForwarding yes
X11Forwarding no
```

### 3.3 Générer des clés SSH (optionnel mais recommandé)
```bash
# Générer une clé SSH
ssh-keygen -t ed25519 -C "termux-server"
# Accepter les valeurs par défaut

# Copier la clé publique sur le client (PC)
# Sur le PC : ssh-copy-id -p 8022 user@IP_TELEPHONE
```

### 3.4 Démarrer le serveur SSH
```bash
# Démarrer sshd
sshd

# Vérifier qu'il tourne
pgrep -a sshd
# Output: sshd (process ID)

# Vérifier le port
ss -tlnp | grep 8022
```

### 3.5 Trouver l'IP du téléphone
```bash
# Sur le réseau local (WiFi)
ip -o addr show wlan0 2>/dev/null | grep "inet " | awk '{print $4}' | cut -d/ -f1

# Sur la data mobile
ip -o addr show rmnet_data2 2>/dev/null | grep "inet " | awk '{print $4}' | cut -d/ -f1

# Ou simplement
ifconfig 2>/dev/null | grep "inet " | head -1
```

---

## Étape 4 : Connecter le client

### Depuis un PC (Linux/Mac)
```bash
# Se connecter au téléphone
ssh -p 8022 $(whoami)@IP_TELEPHONE

# Avec clé SSH
ssh -p 8022 -i ~/.ssh/id_ed25519 $(whoami)@IP_TELEPHONE
```

### Depuis un autre téléphone Android
```bash
# Installer Termux sur le client aussi
# Puis se connecter
ssh -p 8022 user@IP_TELEPHONE
```

### Depuis DarkTunnel (si tunnel SSH)
Dans DarkTunnel, configurez :
- Type : SSH
- Host : IP_TELEPHONE
- Port : 8022
- Username : (votre user Termux)
- Password : (votre mot de passe)

---

## Étape 5 : Garder SSH actif en arrière-plan

### Problème : Termux se ferme en arrière-plan
Android peut tuer Termux quand il est en arrière-plan. Solutions :

#### 5.1 Activer le wake lock
```bash
# Dans Termux, activer le wake lock
termux-wake-lock
```
Cela empêche Android de mettre le CPU en veille.

#### 5.2 Démarrer sshd au boot (avec Termux:Boot)
1. Installez **Termux:Boot** depuis F-Droid
2. Créez le script de démarrage :
```bash
mkdir -p ~/.termux/boot
cat > ~/.termux/boot/start-sshd.sh <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
termux-wake-lock
sshd
EOF
chmod +x ~/.termux/boot/start-sshd.sh
```
3. Redémarrez le téléphone → sshd démarre automatiquement

#### 5.3 Garder Termux ouvert
- Ne fermez pas Termux
- Désactivez l'optimisation batterie pour Termux dans les paramètres Android

---

## Étape 6 : Optimisations

### 6.1 Réduire la consommation batterie
```bash
# Désactiver le WiFi si vous utilisez la data mobile
# Réduire la luminosité de l'écran
# Activer le mode économie d'énergie
```

### 6.2 Optimiser la connexion
```bash
# Dans ~/.ssh/sshd_config, ajouter :
ClientAliveInterval 60
ClientAliveCountMax 3
TCPKeepAlive yes
```

### 6.3 Utiliser USB tethering (recommandé)
Au lieu du WiFi, connectez le téléphone au PC via USB et activez le tethering :
1. Connectez le téléphone au PC via USB
2. Sur le téléphone : Paramètres → Connexions → Partage de connexion → USB
3. Le PC obtient une IP sur le réseau du téléphone
4. SSH vers l'IP du téléphone (généralement 192.168.42.129 ou similaire)

**Avantage** : plus stable que WiFi, pas de déconnexion

### 6.4 Compression SSH
```bash
# Sur le client, se connecter avec compression
ssh -p 8022 -C user@IP_TELEPHONE
# -C active la compression
```

---

## Étape 7 : Tester la connexion

### Depuis le PC
```bash
# Test de connexion
ssh -p 8022 user@IP_TELEPHONE "echo 'Connexion OK'"

# Test de débit
dd if=/dev/zero bs=1M count=10 2>/dev/null | ssh -p 8022 -C user@IP_TELEPHONE 'cat > /dev/null'
```

### Depuis DarkTunnel
1. Ouvrez DarkTunnel
2. Créez une config SSH :
   - Type : SSH
   - Host : IP_TELEPHONE
   - Port : 8022
   - Username : (votre user Termux)
   - Password : (votre mot de passe)
3. Connectez-vous
4. Le tunnel devrait s'établir

---

## Étape 8 : Utiliser le zero-rating

### Si l'opérateur zero-rate un domaine (ex. yas.tg)
1. Configurez le téléphone pour utiliser la data mobile (pas WiFi)
2. Assurez-vous que le téléphone n'a **pas de forfait** (pour tester le zero-rating)
3. Connectez le client au téléphone via SSH (sur le réseau local ou USB)
4. Le trafic passe par le réseau de l'opérateur → zero-rated si le domaine est dans la liste

### Note importante
Avec Termux comme serveur, il n'y a **pas de zero-rating bypass** :
- Le trafic est déjà sur le réseau de l'opérateur
- Pas besoin de Domain Fronting, pas de Cloudflare, pas de payload
- La connexion SSH est directe → débit maximal

---

## Dépannage

### SSH ne démarre pas
```bash
# Vérifier les logs
cat ~/.ssh/sshd_config
# Vérifier le port
ss -tlnp | grep 8022
# Redémarrer sshd
pkill sshd; sshd
```

### Connexion refusée
```bash
# Vérifier le firewall Android
# Désactiver le firewall ou autoriser le port 8022
# Vérifier que le téléphone et le client sont sur le même réseau
```

### Termux se ferme en arrière-plan
```bash
# Activer le wake lock
termux-wake-lock
# Installer Termux:Boot
# Désactiver l'optimisation batterie pour Termux
```

### Débit lent
```bash
# Utiliser USB tethering au lieu de WiFi
# Activer la compression SSH (-C)
# Vérifier le signal 4G/3G
```

---

## Voir aussi
- `docs/FREE-OPTIONS.md` — Options gratuites pour le zero-rating
- `docs/DOCUMENTATION.md` — Documentation complète du projet
- `docs/ZERO-RATING-APPROACHES.md` — Approches de zero-rating
EOF
echo "TERMUX-SERVER.md created"