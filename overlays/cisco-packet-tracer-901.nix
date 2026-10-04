final: prev: {
  # nixpkgs ne fournit que Packet Tracer 9.0.0, mais NetAcad ne distribue
  # plus que le .deb 9.0.1. On redéfinit le paquet pour cette version
  # (le nom du .deb et les noms des fichiers .desktop embarqués changent).
  cisco-packet-tracer_9 =
    let
      version = "9.0.1";
      pname = "cisco-packet-tracer";

      appimage = prev.stdenvNoCC.mkDerivation {
        pname = "cisco-packet-tracer-appimage";
        inherit version;

        src = prev.requireFile {
          name = "CiscoPacketTracer_901_Ubuntu_64bit.deb";
          hash = "sha256-NoPdh+d5iFNyrpo1wabllNEvST5knnxpdAhynBRZR5s=";
          url = "https://www.netacad.com/resources/lab-downloads";
        };

        nativeBuildInputs = [ prev.dpkg ];

        installPhase = ''
          runHook preInstall

          cp opt/pt/packettracer.AppImage $out

          runHook postInstall
        '';
      };
    in
    prev.appimageTools.wrapType2 {
      inherit pname version;

      src = appimage;

      extraPkgs = _: [
        prev.libpng
        prev.libxkbfile
      ];

      extraBwrapArgs = [
        # corrige le lancement sous wayland quand QT_QPA_PLATFORM=wayland :
        # "Fatal: This application failed to start because no Qt platform plugin could be initialized."
        "--setenv QT_QPA_PLATFORM xcb"
      ];

      extraInstallCommands =
        let
          contents = prev.appimageTools.extract { inherit pname version; src = appimage; };
        in
        ''
          mv $out/bin/${pname} $out/bin/packettracer9

          install -Dm444 ${contents}/CiscoPacketTracer-${version}.desktop $out/share/applications/cisco-packet-tracer-9.desktop
          install -Dm444 ${contents}/CiscoPacketTracerPtsa-${version}.desktop $out/share/applications/cisco-packet-tracer-ptsa-9.desktop
          substituteInPlace $out/share/applications/* \
            --replace-fail "Exec=@EXEC_PATH@" "Exec=packettracer9" \
            --replace-fail "Icon=app" "Icon=cisco-packet-tracer-9"

          install -Dm444 ${contents}/usr/share/icons/hicolor/48x48/apps/app.png $out/share/icons/hicolor/48x48/apps/cisco-packet-tracer-9.png
          cp -r ${contents}/usr/share/icons/gnome/48x48/mimetypes $out/share/icons/hicolor/48x48/

          for desktop in $out/share/applications/*.desktop; do
            sed -i '/^\[Desktop Entry\]/a StartupWMClass=PacketTracer' "$desktop"
          done
        '';

      meta = {
        description = "Network simulation tool from Cisco";
        homepage = "https://www.netacad.com/courses/packet-tracer";
        license = prev.lib.licenses.unfree;
        mainProgram = "packettracer9";
        platforms = [ "x86_64-linux" ];
        sourceProvenance = with prev.lib.sourceTypes; [ binaryNativeCode ];
      };
    };
}
