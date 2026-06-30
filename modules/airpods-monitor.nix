{ config, pkgs, lib, ... }:

let
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.bleak ]);

  airpods-monitor = pkgs.writeScriptBin "airpods-monitor" ''
    #!${pythonEnv}/bin/python3

    import asyncio
    import json
    import os
    import subprocess
    import sys
    import time

    from bleak import BleakScanner

    NOTIFY_CMD = "${pkgs.libnotify}/bin/notify-send"
    CACHE_FILE = "/tmp/airpods_battery.json"
    PREV_FILE = "/tmp/airpods_battery_prev"
    CONNECTED_FILE = "/tmp/airpods_connected"
    SCAN_TIMEOUT = 5.0
    SCAN_INTERVAL = 30
    APPLE_ID = 0x004C


    def parse_apple_mfr(data):
        if len(data) < 7 or data[0] != 0x07:
            return None
        flipped = bool(data[4] & 0x20)
        bat_a = (data[5] >> 4) & 0xF
        bat_b = data[5] & 0xF
        bat_case = (data[6] >> 4) & 0xF

        def pct(v):
            return None if v == 0xF else v * 10

        left, right = (bat_b, bat_a) if flipped else (bat_a, bat_b)
        return {
            "left": pct(left),
            "right": pct(right),
            "case": pct(bat_case),
            "timestamp": int(time.time()),
        }


    def is_actually_connected():
        try:
            result = subprocess.run(
                ["bluetoothctl", "info"],
                capture_output=True, text=True, timeout=5
            )
            output = result.stdout
            return "Connected: yes" in output and "Apple" in output
        except Exception:
            return False


    async def scan_once():
        found = [None]

        def cb(device, adv):
            if found[0] is not None:
                return
            mfr = adv.manufacturer_data
            if APPLE_ID not in mfr:
                return
            parsed = parse_apple_mfr(bytes(mfr[APPLE_ID]))
            if parsed is not None:
                found[0] = parsed

        try:
            async with BleakScanner(cb):
                await asyncio.sleep(SCAN_TIMEOUT)
        except Exception:
            pass
        return found[0]


    def notify(title, body, urgency="normal"):
        try:
            subprocess.run(
                [NOTIFY_CMD, title, body, "--urgency=" + urgency, "--icon=bluetooth"],
                timeout=5,
                capture_output=True,
            )
        except Exception:
            pass


    def read_prev():
        try:
            with open(PREV_FILE) as f:
                return int(f.read().strip())
        except Exception:
            return None


    def write_prev(val):
        try:
            with open(PREV_FILE, "w") as f:
                f.write(str(val))
        except Exception:
            pass


    def clear_state():
        for fp in [CACHE_FILE, PREV_FILE, CONNECTED_FILE]:
            try:
                os.remove(fp)
            except Exception:
                pass


    def min_lr(data):
        vals = [v for v in [data.get("left"), data.get("right")] if v is not None]
        return min(vals) if vals else None


    async def main_loop():
        while True:
            connected = is_actually_connected()

            if not connected:
                if os.path.exists(CONNECTED_FILE):
                    clear_state()
                await asyncio.sleep(SCAN_INTERVAL)
                continue

            data = await scan_once()

            if data is None:
                if os.path.exists(CONNECTED_FILE):
                    clear_state()
                await asyncio.sleep(SCAN_INTERVAL)
                continue

            try:
                with open(CACHE_FILE, "w") as f:
                    json.dump(data, f)
            except Exception:
                pass

            lvl = min_lr(data)
            if lvl is None:
                await asyncio.sleep(SCAN_INTERVAL)
                continue

            just_connected = not os.path.exists(CONNECTED_FILE)
            if just_connected:
                try:
                    open(CONNECTED_FILE, "w").close()
                except Exception:
                    pass
                l = data.get("left")
                r = data.get("right")
                c = data.get("case")
                body = "G: " + str(l) + "%  D: " + str(r) + "%  Boitier: " + str(c) + "%"
                notify("AirPods connectés", body, "normal")

            prev = read_prev()
            if prev is not None:
                for threshold in [30, 20, 10]:
                    if prev > threshold >= lvl:
                        urgency = "critical" if threshold <= 10 else "normal"
                        notify("AirPods - Batterie faible", "Niveau: " + str(lvl) + "%", urgency)
                        break

            write_prev(lvl)
            await asyncio.sleep(SCAN_INTERVAL)


    if __name__ == "__main__":
        asyncio.run(main_loop())
  '';

in
{
  home.packages = [ airpods-monitor ];

  systemd.user.services.airpods-battery-monitor = {
    Unit = {
      Description = "AirPods battery monitor";
      After = [ "hyprland-session.target" ];
      PartOf = [ "hyprland-session.target" ];
    };
    Service = {
      ExecStart = "${airpods-monitor}/bin/airpods-monitor";
      Restart = "on-failure";
      RestartSec = "10s";
    };
    Install = {
      WantedBy = [ "hyprland-session.target" ];
    };
  };
}
