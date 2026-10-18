# Analyse de l'app Yas Togo — Jeux (Win Pizz / Spin & Win), FreeData et zero-rating

> Étude réalisée le 18/10/2026 sur le téléphone de l'utilisateur, **sans forfait data**,
> via REA (MCP d'analyse reverse) + ADB + Frida + logcat.
> Cible : `com.yas.selfcare.app` v2.0 (build 152) — application **Flutter**.

---

## 1. Résumé

- L'app Yas est **100 % Flutter** (aucune lib de tunnel/VPN embarquée) — corriger au passage
  la confusion précédente avec DarkTunnel (voir §2).
- L'app contient un **jeu quotidien gratuit** : « **Win Pizz** » (= *Spin & Win*, roue de la chance),
  avec des gains de **data (50/100/150 Mo, jusqu'à 250 Mo selon les règles), crédit d'appel et forfaits**.
- **Toutes les APIs de l'app + son CDN d'images sont zero-rated** : l'app et le jeu fonctionnent
  entièrement **sans forfait** (testé en conditions réelles).
- **Test réel effectué** : 1 tour joué → **gain de 150 Mo valables 24 h**, provisionné par l'API,
  le tout sans forfait data.
- Pistes « data gratuite » pour l'utilisateur : **1 tour de roue/jour**, **parrainage (« Inviter un ami »)**,
  **popup FreeData** — tout étant zero-rated.

---

## 2. Correctif : la confusion avec DarkTunnel

Une analyse précédente avait attribué à l'app Yas des bibliothèques `libdarktunnel` / Xray / DNSTT.
**C'était une erreur** : ces bibliothèques provenaient du **split APK de DarkTunnel**
(`net.darktunnel.app`, fichier `libgojni.so`), pas de Yas.

Vérification — le split arm64 de Yas ne contient que :

| Librairie | Rôle |
|-----------|------|
| `libapp.so` (15,8 Mo) | snapshot Dart AOT (code de l'app) |
| `libflutter.so` | moteur Flutter |
| `libaded25.so` | JNI custom (`MainActivity.myFunction`) |
| `libcc23e6.so` | androidx datastore |
| `libe870.so` | JNI utilitaire |

Aucune trace de tunnel dans l'app Yas.

---

## 3. Méthode d'analyse

- **REA (MCP)** :
  - `identify_flutter_build` → hash du snapshot Dart, libs par ABI ;
  - `inspect_dart_aot` → inventaire des modules Dart (`spin_n_win/`, `quiz/`, `game/`, `freedata/`, `chucker/`…) ;
  - `list_frida_devices` + `instrument_with_frida` → attach Frida réussi sur le téléphone (root, frida-server).
- **Limites locales** : Hopper non licencié, IDA/Ghidra absents, apktool absent →
  pas de décompilation native profonde via REA ; complété par `strings` sur `libapp.so`.
- **Dynamique** : navigation automatisée (ADB input/screencap) + **logcat** — l'app logge en clair
  en version release (voir §9), ce qui a permis de capturer toute la séquence du jeu.
  Les hooks Frida `connect`/`getaddrinfo` n'ont pas pu être posés (résolution d'exports impossible
  dans ce runtime) ; la capture s'est faite via les logs applicatifs.

---

## 4. Identité de l'app

| Élément | Valeur |
|---------|--------|
| Package | `com.yas.selfcare.app` |
| Version | 2.0 (build 152) |
| Type | Flutter AOT — snapshot `97ff04a7…` |
| Activité principale | `com.axian.flutter.project.digitalselfcare.MainActivity` |
| Permissions | 24 déclarées |
| Sécurité | pas de `network_security_config`, **pas de certificate pinning détecté**, inspecteur HTTP Chucker embarqué |

---

## 5. Le jeu : « Win Pizz » (Spin & Win)

### 5.1 Présentation

- Roue à **7 secteurs** :
  - gains (violet) : **« Youpi ! » 50 Mo**, **« Odoou » 100 Mo**, **« Waoouh » 150 Mo** ;
  - perdu (vert, expressions locales) : « Ohoo ! », « Gbatrov a ké », « Désolé ! », « Ogbô ! ».
- Badge **« +N Tours »** en haut à droite = tentatives restantes.
- Boutons : **« Comment ça marche ? »**, **« Inviter un ami »** (parrainage), **« Gagne ta Pizz »** (le tour).
- Événements analytics : `Yas_Spin_And_Win_Landed` / `Selected` / `Spin_Attempt` / `Result`.

### 5.2 Règles officielles (écran « Comment ça marche ? »)

1. **« Jouez 1 fois par jour, sans aucune condition »**
2. Tentatives **réinitialisées toutes les 24 heures** (on peut rejouer chaque jour).
3. Récompenses : **forfaits gratuits**, **bonus internet (jusqu'à 250 Mo)**, **crédit d'appel**.

### 5.3 Mécanique d'un tour (flux complet observé)

1. Tap « Gagne ta Pizz » ;
2. `POST /api/SpinAndWin/IncrementSpinAndWinCount` → consommation/incrément d'un tour + rafraîchissement config ;
3. Le client calcule le secteur gagnant par **tirage pondéré** (poids fournis par la config serveur) ;
4. Animation de la roue (~5 s) vers le secteur tiré ;
5. `POST /api/v2/SpinAndWin/SpinAndWinReward` avec le lot sélectionné (type, valeur, validité, tarifcode) ;
6. Le serveur **provisionne le lot** et renvoie `remainingAttempts` + message officiel.

Secteurs et poids observés en config (`weights: [5,20,10,15,18,20,12]`, somme = 100) :

| # | Secteur | Type | Poids |
|---|---------|------|-------|
| 0 | Ohoo ! | perdu | 5 |
| 1 | Odoou 100 Mo | **gain** | 20 |
| 2 | Gbatrov a ké | perdu | 10 |
| 3 | Waoouh 150 Mo | **gain** | 15 |
| 4 | Désolé ! | perdu | 18 |
| 5 | Youpi ! 50 Mo | **gain** | 20 |
| 6 | Ogbô ! | perdu | 12 |

→ Probabilité de gain observée : **55 %** (20 + 15 + 20), à titre indicatif.

> Observation (documentée, non exploitée) : le secteur est tiré côté client à partir de poids
> configurés côté serveur, puis le serveur provisionne le lot demandé. **Aucun test d'abus n'a
> été effectué** — le jeu est une campagne marketing de l'opérateur.

### 5.4 Test réel (18/10/2026 ~11:04)

| Étape | Résultat |
|-------|----------|
| État initial | +3 tours, solde 4 F, **0 Internet** (aucun forfait) |
| Tour joué | secteur 3 → **150 Mo** |
| Popup | « Félicitations ! Tu viens de bénéficier d'un bonus de 150 Mo val 1j. Profites-en avec Yas ! » |
| Après le tour | badge **+2 Tours** (`remainingAttempts: 2`) |
| Coût data | **0** (tout zero-rated) |

Payload de provisionnement observé (sans les jetons) : `rewardType: Bundle`,
`rewardTypeId: 3`, `validity: 24` (h), `tarifcode: Mega_App`, `rewardDetail : "un bonus de 150 Mo val 1j"`.

---

## 6. Autres jeux / fonctions

| Fonction | Endpoints | Statut |
|----------|-----------|--------|
| **Quiz** | `/api/Quiz/GetQuizLevels`, `/api/Quiz/GetQuizLevelQuestionsDetail`, `/api/Quiz/QuizRedeemReward`, `/api/Quiz/UpdateQuizLastAttempt` | présent dans l'app, non activé dans le menu Togo le 18/10 |
| **FreeData** | `/api/freedata/FreeDataEligibility`, `/api/freedata/ProvideFreeBundle` (flag `isFreeDataRedeemed`) | popup « data gratuite » — non déclenché pendant l'étude |
| **Shake & Win** | config `axian_sc_shakeConfigsAPIVersion`, libellé « Increment Shake And Win Count » | variante du même moteur que Spin & Win |
| **Flash Offers** | `/api/Bundles/SubscribeFlashOffer`, `/api/Bundles/GetDashboardFlashOffer` | offres flash du dashboard |

---

## 7. APIs de l'app (backend Togo)

| Base | Rôle |
|------|------|
| `https://yas-app-mob-web-api.togocom.tg/` | API principale |
| `https://yas-app-ws-apim.togocom.tg/oauth2/` | OAuth2 |
| `https://ws-prp-mob-web-api.togocom.tg/` | API secondaire |
| `https://tmoneytogocom.blob.core.windows.net/` | CDN images (Azure Blob) |

Endpoints du jeu :

| Méthode | Endpoint | Rôle |
|---------|----------|------|
| GET | `/api/spinandwin/SpinAndWinEligibility` | éligibilité |
| GET | `/api/v2/SpinAndWin/GetConfigurations` | config (secteurs, poids, tentatives) |
| POST | `/api/SpinAndWin/IncrementSpinAndWinCount` | consommation/incrément d'un tour |
| POST | `/api/v2/SpinAndWin/SpinAndWinReward` | provisionnement du lot |

Auth : OTP (`/api/otp/RequestOTP`, `/api/otp/VerifyOTP`), refresh (`/api/Account/refreshToken`), Bearer JWT.
Configs dynamiques via **Firebase RTDB** (clés `axian_sc_*`, collection `togo`) :
`spinConfigsAPIVersion 1.0.17`, `preLoginConfigsAPIVersion 1.0.253`, etc.

---

## 8. Zero-rating — mesures réelles (sans forfait, 18/10/2026)

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

Test (depuis le téléphone) :

```bash
adb shell "curl -s -o /dev/null -w '%{http_code}' --max-time 8 https://<hôte>/"
```

**Conclusion** :
- La whitelist opérateur est **par hostname exact** (le blob Azure d'un autre compte est bloqué).
- **L'écosystème complet de l'app est zero-rated** : dashboard, bannières (Azure), APIs, et **les jeux**.
- Démo live : app utilisée **sans forfait** (0 Internet, 4 F de crédit), APIs en HTTP 200 dans les logs,
  **un tour de roue joué et 150 Mo gagnés/provisionnés** — coût data : 0.

**Implication pour fal2proxy** : aucun changement — le Domain Fronting cross-domain (`yas.tg` comme SNI)
reste impossible (cf. `ZERO-RATING-APPROACHES.md`). En revanche, la **voie directe de data gratuite**
passe par l'app elle-même : **1 tour/jour + parrainage + popup FreeData**, tout zero-rated.

---

## 9. Sécurité & vie privée (observations)

- L'app **logge en clair en release** : jetons JWT (`Authorization`, `X-User-Session`), numéro de
  téléphone (masqué ici : `09 22 65 ** **`), `deviceId`, jeton FCM — tous visibles dans logcat.
  → Ne pas partager de logs bruts ; à signaler comme mauvaise pratique côté éditeur.
- Inspecteur HTTP **Chucker** embarqué (outil de débogage).
- **Pas de certificate pinning détecté** (une interception TLS locale serait possible ; non réalisée ici).

---

## 10. Limites & suites possibles

- Quiz non observé activé ; popup FreeData non déclenché (l'endpoint de fourniture n'a pas été appelé hors app).
- Décompilation native limitée par l'outillage local (Hopper non licencié, IDA/Ghidra absents) —
  l'essentiel a été couvert via les métadonnées Flutter + les logs runtime.
- Suites possibles : interception mitmproxy (root présent, pas de pinning) pour capturer les JSON complets ;
  surveillance du popup FreeData en situation d'éligibilité.

---

## 11. Références

- App : `/tmp/yas.apk` (base) + `/tmp/yas_split_arm64.apk` (split arm64)
- Snapshot Dart : `/tmp/yas_libs/lib/arm64-v8a/libapp.so`
- Captures écran : `/tmp/yas_s*.png`, `/tmp/yas_spin_*.png`
- Outils : REA MCP, adb, `strings`, logcat
