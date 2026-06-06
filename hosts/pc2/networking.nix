{ ... }:

{
  networking.hostName = "pc2";

  # LocalSend : découverte UDP + transfert TCP
  networking.firewall.allowedTCPPorts = [ 53317 ];
  networking.firewall.allowedUDPPorts = [ 53317 ];

  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.powersave = false;
  networking.useDHCP = false;
}
