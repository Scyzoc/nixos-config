# vmnet-natd est un exécutable non-PIE : autoPatchelf (interpréteur nix, plus long) le
# laisse avec un PHDR hors segment LOAD → SEGV dans ld.so avant main, vmnet8 (NAT) ne
# démarre pas et vmware-networks échoue. On remet le binaire d'origine (nouvelle
# extraction de l'archive, après autoPatchelf) : son interpréteur /lib64/ld-linux-x86-64.so.2
# est fourni par nix-ld ; les variables NIX_LD* viennent du service (configuration.nix).
# Pas de wrapper : natd se relance via /proc/self/exe.
final: prev: {
  vmware-workstation = prev.vmware-workstation.overrideAttrs (finalAttrs: old: {
    # autoPatchelf manuel : il ne doit pas toucher à bin/vmnet-natd
    dontAutoPatchelf = true;
    postFixup = (old.postFixup or "") + ''
      dirs=()
      for d in $out/*; do dirs+=("$d"); done
      autoPatchelf "''${dirs[@]}"
      ${finalAttrs.vmware-unpack-env}/bin/vmware-unpack-env -c "sh ${finalAttrs.src} --extract natd-orig"
      install -m 555 natd-orig/vmware-vmx/bin/vmnet-natd $out/bin/vmnet-natd
    '';
  });
}
