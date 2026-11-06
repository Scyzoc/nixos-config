{ config, pkgs, lib, ... }:

{
  # ==========================================================================
  # RÉSEAU ET SÉCURITÉ (Optimisé pour PC Portable)
  # ==========================================================================

  networking.hostName = "nixos";

  # LocalSend : découverte UDP + transfert TCP
  # + UxPlay (AirPlay) : 7000 7001 7100 TCP, 6000 6001 7011 UDP (ports fixés via `uxplay -p`), 5353 mDNS
  networking.firewall.allowedTCPPorts = [ 53317 7000 7001 7100 ];
  networking.firewall.allowedUDPPorts = [ 53317 6000 6001 7011 5353 ];

  # On donne 100% du contrôle à NetworkManager (Ethernet, Wi-Fi, Hotplug)
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = false;
  networking.networkmanager.plugins = [ pkgs.networkmanager-openvpn ];

  # CRUCIAL : On désactive la gestion réseau native de NixOS (dhcpcd) 
  # pour éviter qu'il ne se batte avec NetworkManager et fasse planter la carte.
  networking.useDHCP = false;

  # DNS résilient : le relais DNS d'un partage iPhone (IP_CENSUREE) cale parfois
  # (ex. après mode avion on/off) alors qu'internet passe. Par défaut la libc
  # attend 5 s par serveur → tout semble mort. On raccourcit l'attente et on
  # ajoute des résolveurs publics en fin de liste (utilisés seulement en secours).
  networking.resolvconf.extraOptions = [ "timeout:2" "attempts:2" ];
  networking.resolvconf.extraConfig = ''
    name_servers_append='1.1.1.1 9.9.9.9'
  '';

  # Profil NetworkManager pour l'Ethernet — autoconnect dès que le câble est branché
  networking.networkmanager.ensureProfiles.profiles."ethernet-enp3s0f0" = {
    connection = {
      id = "Ethernet";
      type = "ethernet";
      interface-name = "enp3s0f0";
      autoconnect = "true";
      autoconnect-retries = "-1";
      autoconnect-priority = "10";
    };
    # DHCP court : sans serveur DHCP, NM abandonne vite et bascule sur le profil IP fixe
    ipv4 = {
      method = "auto";
      dhcp-timeout = "5";
      may-fail = "false";
    };
    ipv6 = {
      method = "auto";
      addr-gen-mode = "stable-privacy";
    };
  };

  # Repli : IP fixe quand aucun DHCP ne répond (réseau sans serveur DHCP, lien direct PC↔PC).
  # Adapter l'adresse/le préfixe ici. Pour forcer l'IP fixe sans attendre : `nmcli con up "Ethernet IP fixe"`.
  networking.networkmanager.ensureProfiles.profiles."ethernet-fixe" = {
    connection = {
      id = "Ethernet IP fixe";
      type = "ethernet";
      interface-name = "enp3s0f0";
      autoconnect = "true";
      autoconnect-priority = "0";
    };
    ipv4 = {
      method = "manual";
      address1 = "IP_CENSUREE/24";
    };
    ipv6.method = "link-local";
  };

  systemd.services.wake-ethernet = {
    description = "Force le reveil du port Ethernet (Contournement materiel)";
    
    # CRUCIAL : On exige que la carte existe physiquement avant de lancer le script
    bindsTo = [ "sys-subsystem-net-devices-enp3s0f0.device" ];
    after = [ "sys-subsystem-net-devices-enp3s0f0.device" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Un mini-script qui attend 1 seconde pour éviter les collisions avec le pilote
      ExecStart = pkgs.writeShellScript "wake-eth" ''
        ${pkgs.coreutils}/bin/sleep 1
        ${pkgs.iproute2}/bin/ip link set enp3s0f0 down
        ${pkgs.iproute2}/bin/ip link set enp3s0f0 up
        ${pkgs.ethtool}/bin/ethtool -s enp3s0f0 autoneg on
      '';
    };
  };
}
