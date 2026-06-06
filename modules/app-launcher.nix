{ pkgs, ... }:

let
  app-launcher = pkgs.writeShellScriptBin "app-launcher" ''
    PIDFILE="/tmp/wofi-launcher.pid"

    if [ -f "$PIDFILE" ]; then
      PID=$(cat "$PIDFILE")
      if kill -0 "$PID" 2>/dev/null; then
        kill "$PID"
        rm -f "$PIDFILE"
        exit 0
      fi
      rm -f "$PIDFILE"
    fi

    ${pkgs.wofi}/bin/wofi --show drun --style ${./wofi-style.css} --conf ${./wofi-config} &
    echo $! > "$PIDFILE"
    wait
    rm -f "$PIDFILE"
  '';
in
{
  home.packages = [ app-launcher ];

}
