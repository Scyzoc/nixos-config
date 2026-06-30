# ❄️ Configuration NixOS — Hyprland Desktop

Configuration NixOS personnelle basée sur les **flakes**, pour un environnement de bureau **Wayland** moderne (Hyprland + Waybar). Tout est déclaratif et reproductible, géré par flake + Home Manager.

> ⚠️ **Données anonymisées** : ce dépôt public contient des valeurs masquées — IP (`VPN_HOST_REDACTED`, `VPS_IP_REDACTED`, `HOMELAB_IP_REDACTED`), MAC (`AA:BB:CC:DD:EE:FF`), utilisateur (`user`). Les secrets (clés VPN, certificats, modules privés) ne sont **pas** versionnés. Remplace ces placeholders par tes propres valeurs. Les IP génériques restantes (`192.168.x`, `1.1.1.1`, `8.8.8.8`) sont des exemples/DNS publics fonctionnels, pas des données personnelles.

---

## 🖥️ Machine cible

| | |
|---|---|
| **Hôte** | `pc1` — ThinkPad L14 Gen 4 |
| **GPU** | iGPU AMD (amdgpu) |
| **WM** | Hyprland (Wayland) |
| **Barre** | Waybar (config double écran) |
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
│   ├── waybar.nix         # Barre (modules custom, scripts, style)
│   ├── airpods-monitor.nix
│   ├── bluetooth-menu.nix
│   ├── display-switch.nix
│   ├── gammastep.nix      # Filtre lumière bleue
│   ├── theme-automation.nix
│   ├── voice-transcription.nix
│   └── ...
├── assets/                # Ressources (scripts, images)
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
   - `VPN_HOST_REDACTED`, `HOMELAB_IP_REDACTED` (VPN/homelab) dans `configuration.nix`
   - MAC `AA:BB:CC:DD:EE:FF` (wakeonlan) dans `home.nix`
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
- **Waybar** — barre custom : workspaces, horloge + météo (wttr.in), CPU/RAM, Bluetooth (avec batterie AirPods), Wi-Fi, Ethernet, VPN, batterie, contrôle média MPRIS. Support double écran (workspaces 1-5 sur l'écran principal, 6-10 sur les externes).
- **theme-automation** — bascule de thème automatique.
- **gammastep** — filtre lumière bleue jour/nuit.
- **airpods-monitor** — suivi batterie AirPods (gauche/droite/boîtier).
- **voice-transcription** — transcription vocale.
- **Menus rofi/wofi** — Bluetooth, réseau, Ethernet, presse-papiers, lanceur d'apps, sélecteur de fond d'écran.

La plupart des modules sont des scripts shell générés via `pkgs.writeShellScriptBin`, référençant leurs binaires par chemin Nix (`${pkgs.foo}/bin/foo`).

---

## ⚠️ Avertissements

- **Reproductibilité non garantie out-of-the-box** : config liée à un matériel et un utilisateur précis. Lis et adapte avant tout `switch`.
- **Pas de secrets versionnés** : VPN, certificats et modules privés sont exclus. Les fonctionnalités correspondantes nécessitent ta propre configuration.
- Inspire-toi, copie des bouts, mais ne `switch` pas aveuglément une config tierce sur ta machine.

---

## 📝 Licence

Configuration personnelle fournie telle quelle, à titre d'exemple. Réutilise librement.
