# ❄️ Configuration NixOS — Hyprland Desktop

Configuration NixOS personnelle basée sur les **flakes**, pour un environnement de bureau **Wayland** moderne (Hyprland + barre Quickshell). Tout est déclaratif et reproductible, géré par flake + Home Manager.

> ⚠️ **Données censurées** : ce dépôt est synchronisé automatiquement à chaque rebuild, avec le contenu confidentiel remplacé par des marqueurs :
> - IP : `VPN_HOST_REDACTED`, `VPS_IP_REDACTED`, `HOMELAB_IP_REDACTED`, `IP_CENSUREE` ; port : `VPN_PORT_REDACTED`
> - MAC : `XX:XX:XX:XX:XX:XX` / `AA:BB:CC:DD:EE:FF` ; identifiants : `ID_CENSURE`, `UUID_CENSURE`
> - clés et certificats (`vpn/`, `*.crt`) : présents, mais leur contenu est remplacé par `[CONTENU CENSURÉ]`
> - utilisateur : `user`
>
> Remplace ces marqueurs par tes propres valeurs. Les IP restantes (`127.0.0.1`, `192.168.1.x`, `1.1.1.1`, `8.8.8.8`, `9.9.9.9`) sont des exemples ou des DNS publics, pas des données personnelles.

---

## 🖥️ Machine cible

| | |
|---|---|
| **Hôte** | `pc1` — ThinkPad L14 Gen 4 |
| **GPU** | iGPU AMD (amdgpu) |
| **WM** | Hyprland (Wayland) |
| **Barre** | Quickshell (QML, popups interactifs) — Waybar gardée en secours |
| **Réseau** | NetworkManager (DHCP désactivé) |
| **Channel** | `nixpkgs/nixos-unstable` |

> L'hostname système réel est `nixos` ; la configuration flake porte le nom `pc1`.

---

## 📂 Structure du dépôt

```
.
├── flake.nix              # Point d'entrée : mkSystem, nixosConfigurations.pc1
├── flake.lock             # Versions verrouillées des inputs
├── configuration.nix      # Config système (boot, services, paquets système)
├── hardware-configuration.nix
├── networking.nix         # Config réseau (NetworkManager)
├── home.nix               # Config Home Manager (utilisateur)
├── hosts/
│   └── pc1/
│       ├── default.nix    # Entrée de l'hôte (importe les fichiers ci-dessus)
│       └── hardware-configuration.nix
├── modules/               # Un module par fonctionnalité desktop
│   ├── quickshell.nix     # Barre Quickshell (+ quickshell/*.qml)
│   ├── app-launcher.nix   # Lanceur d'apps Quickshell (+ quickshell-launcher/*.qml)
│   ├── waybar.nix         # Ancienne barre, gardée en secours
│   ├── airpods-monitor.nix
│   ├── bluetooth-menu.nix
│   ├── display-switch.nix
│   ├── gammastep.nix      # Filtre lumière bleue
│   ├── theme-automation.nix
│   ├── voice-transcription.nix
│   └── ...
├── assets/                # Ressources (scripts, images, générateurs de polices)
├── overlays/ patches/     # Ajustements de paquets
├── vpn/                   # Fichiers VPN (contenu censuré)
└── fonts/
```

### Chaîne d'import
```
flake.nix
  └─ mkSystem "pc1" → hosts/pc1/default.nix
                        ├─ configuration.nix
                        ├─ hardware-configuration.nix
                        ├─ networking.nix
                        └─ home-manager → home.nix → modules/*.nix
```

Home Manager est intégré **comme module NixOS** (pas en standalone) : `useGlobalPkgs = true`, `backupFileExtension = "backup"`.

---

## 🚀 Installation

### Prérequis
- NixOS déjà installé (ISO officielle → installation minimale suffit).
- Flakes activés. Si ce n'est pas le cas, ajoute temporairement dans `/etc/nixos/configuration.nix` :
  ```nix
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  ```
  puis `sudo nixos-rebuild switch`.
- `git` disponible : `nix-shell -p git`.

### 1. Cloner le dépôt
```bash
git clone https://github.com/Scyzoc/nixos-config.git
cd nixos-config
```

### 2. Adapter à ta machine

⚠️ **Étape obligatoire** — cette config est taillée pour un matériel précis.

1. **Hardware** : remplace `hosts/pc1/hardware-configuration.nix` par le **tien** :
   ```bash
   sudo nixos-generate-config --show-hardware-config > hosts/pc1/hardware-configuration.nix
   ```
2. **Utilisateur** : la config utilise `user`. Remplace partout par ton nom :
   ```bash
   grep -rl "user" . --include='*.nix'
   ```
   Édite `home.nix` (`home.username`, `home.homeDirectory`) et `configuration.nix` (`users.users.user`).
3. **Placeholders** : remplace les valeurs masquées par les tiennes (ou retire les blocs concernés) :
   - `VPN_HOST_REDACTED`, `VPN_PORT_REDACTED`, `HOMELAB_IP_REDACTED` (VPN/homelab) dans `configuration.nix` et `home.nix`
   - MAC (wakeonlan) dans `home.nix`, identifiants `ID_CENSURE` (Notion) dans les modules concernés
   - VPN : fournis tes propres fichiers dans `vpn/`, ou retire le bloc `services.openvpn` de `configuration.nix`
   - certificat `caddy-root.crt` (CA du homelab) : remplace-le ou retire `security.pki.certificateFiles`
4. **GPU/CPU** : si ton matériel n'est pas un ThinkPad AMD, vérifie `configuration.nix` (`boot.kernelParams`, modules kernel, `services.xserver`/drivers).

### 3. Construire et activer

Vérifier d'abord que ça évalue sans rien activer :
```bash
sudo nixos-rebuild build --flake .#pc1
```

Tester sans persister au boot :
```bash
sudo nixos-rebuild test --flake .#pc1
```

Activer définitivement :
```bash
sudo nixos-rebuild switch --flake .#pc1
```

> Renomme `pc1` si tu changes le nom de l'hôte dans `flake.nix` (`nixosConfigurations`).

### 4. Redémarrer
```bash
sudo reboot
```
Au login, choisis la session **Hyprland**.

---

## 🔧 Commandes utiles

| Action | Commande |
|---|---|
| Rebuild (activer) | `sudo nixos-rebuild switch --flake .#pc1` |
| Test (sans persister au boot) | `sudo nixos-rebuild test --flake .#pc1` |
| Build (vérif sans activer) | `sudo nixos-rebuild build --flake .#pc1` |
| Mettre à jour les inputs | `nix flake update` |
| Vérifier la config | `nix flake check` |
| Rollback | `sudo nixos-rebuild switch --rollback --flake .#pc1` |
| Lister les générations | `sudo nix-env --list-generations --profile /nix/var/nix/profiles/system` |
| Nettoyer le store | `sudo nix-collect-garbage -d` |

---

## ✨ Fonctionnalités

- **Hyprland** — compositeur Wayland tiling.
- **Barre Quickshell** — une barre par écran, avec popups interactifs : workspaces, horloge + météo (wttr.in) et calendrier, média MPRIS (pochette, couleurs extraites), son (sorties/entrées PipeWire), luminosité, CPU/RAM, Bluetooth (batteries, contrôle du bruit des AirPods), Ethernet, Wi-Fi (réseaux, IP statique, mode avion), batterie (profils d'énergie, limite de charge), alimentation (arrêt/veille programmés), minuteurs.
- **Menus Quickshell** — lanceur d'apps (SUPER+R), presse-papiers (SUPER+V), emojis (SUPER+;), fonds d'écran (SUPER+W).
- **Waybar** — ancienne barre, conservée en secours.
- **theme-automation** — bascule de thème automatique.
- **gammastep** — filtre lumière bleue jour/nuit.
- **airpods-monitor** — suivi batterie AirPods (gauche/droite/boîtier).
- **voice-transcription** — transcription vocale.
- **Menus rofi** — réseau et Ethernet avancés (VPN, IP statique, DNS).

La plupart des modules sont des scripts shell générés via `pkgs.writeShellScriptBin`, référençant leurs binaires par chemin Nix (`${pkgs.foo}/bin/foo`).

---

## ⚠️ Avertissements

- **Reproductibilité non garantie out-of-the-box** : config liée à un matériel et un utilisateur précis. Lis et adapte avant tout `switch`.
- **Secrets censurés** : les fichiers VPN, certificats et modules privés sont présents mais leur contenu est remplacé. Les fonctionnalités correspondantes nécessitent ta propre configuration.
- Inspire-toi, copie des bouts, mais ne `switch` pas aveuglément une config tierce sur ta machine.

---

## 📝 Licence

Configuration personnelle fournie telle quelle, à titre d'exemple. Réutilise librement.
